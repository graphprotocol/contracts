#!/usr/bin/env bash
#
# tag-deployment.sh - Create annotated git tag for a contract deployment
#
# Produces tags in the format `deploy/<env>/YYYY-MM-DD/<name>` as defined by
# DEPLOYMENT.md (the bare-date form `deploy/<env>/YYYY-MM-DD` is permitted as a
# fallback when --name is omitted, but a descriptive name is recommended). The
# tag body records the deployer, network, commit, and a list of changed
# contracts per address book (detected by diffing address-book JSON against a
# base ref).
#
# Usage:
#   ./scripts/tag-deployment.sh --deployer <desc> --network <network> [--name <short-name>] [options]
#
# Options:
#   --deployer <desc>   What performed the deployment (free-form, e.g., "packages/deployment --tags RewardsManager")
#   --network <name>    Network: arbitrumOne (→ mainnet) or arbitrumSepolia (→ testnet)
#   --name <short-name> Recommended release/upgrade short name appended to the tag as a further path segment
#                       (e.g. "reward-manager-and-subgraph-service" → deploy/<env>/YYYY-MM-DD/<name>).
#                       If omitted, the tag is the bare-date form deploy/<env>/YYYY-MM-DD — permitted as a
#                       fallback but exceptional; prefer a name that describes the deploy.
#   --base <ref>        Git ref to diff address books against. Defaults to the latest `deploy/<env>/*`
#                       tag for the target environment. If none exists (initial deploy), pass --base
#                       explicitly (e.g. --base HEAD~1 or the empty-tree sentinel).
#   --dry-run           Print the preview and exit without creating the tag.
#   --yes, -y           Skip the interactive confirmation prompt (required for non-interactive use).
#   --no-sign           Create an unsigned annotated tag. Default is signed (-s).
#   --help              Show this help
#
# By default the script prints a preview (tag name, commit, annotation body) and
# then asks for confirmation before creating the tag. Use --yes to skip the
# prompt, or --dry-run to stop after the preview.
#
set -euo pipefail

# --- Dependencies ---
for cmd in git jq; do
  if ! command -v "$cmd" >/dev/null 2>&1; then
    echo "Error: $cmd is required but not found"
    exit 1
  fi
done

REPO_ROOT="$(git rev-parse --show-toplevel)"

# --- Defaults ---
DEPLOYER=""
NETWORK=""
UPGRADE_NAME=""
BASE_REF=""   # Empty means "auto: use latest deploy/<env>/* tag". Overridden by --base.
DRY_RUN=false
ASSUME_YES=false
SIGN_FLAG="-s"   # Signed by default. --no-sign switches to -a (annotated, unsigned).

# --- Address books managed by packages/deployment ---
ADDRESS_BOOKS=(
  "packages/horizon/addresses.json:horizon"
  "packages/subgraph-service/addresses.json:subgraph-service"
  "packages/issuance/addresses.json:issuance"
)

# --- Network to chain ID / label mapping ---
network_to_chain_id() {
  case "$1" in
    arbitrumOne)     echo "42161" ;;
    arbitrumSepolia) echo "421614" ;;
    *) echo "unknown" ;;
  esac
}

network_to_label() {
  case "$1" in
    arbitrumOne)     echo "mainnet" ;;
    arbitrumSepolia) echo "testnet" ;;
    *) echo "unknown" ;;
  esac
}

network_to_display() {
  case "$1" in
    arbitrumOne)     echo "arbitrum-one" ;;
    arbitrumSepolia) echo "arbitrum-sepolia" ;;
    *) echo "$1" ;;
  esac
}

# --- Parse arguments ---
usage() {
  sed -n '3,32p' "$0" | sed 's/^# \?//'
  exit "${1:-0}"
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --deployer) DEPLOYER="$2"; shift 2 ;;
    --network)  NETWORK="$2"; shift 2 ;;
    --name)     UPGRADE_NAME="$2"; shift 2 ;;
    --base)     BASE_REF="$2"; shift 2 ;;
    --dry-run)  DRY_RUN=true; shift ;;
    --yes|-y)   ASSUME_YES=true; shift ;;
    --no-sign)  SIGN_FLAG="-a"; shift ;;
    --help)     usage 0 ;;
    *) echo "Unknown option: $1"; usage 1 ;;
  esac
done

if [[ -z "$DEPLOYER" ]]; then
  echo "Error: --deployer is required"
  usage 1
fi

if [[ -z "$NETWORK" ]]; then
  echo "Error: --network is required"
  usage 1
fi

# --name is recommended but not required. When provided, validate format: lowercase, digits, hyphens only.
if [[ -n "$UPGRADE_NAME" ]]; then
  if [[ ! "$UPGRADE_NAME" =~ ^[a-z0-9]([a-z0-9-]*[a-z0-9])?$ ]]; then
    echo "Error: --name must be lowercase alphanumeric with hyphens (e.g., 'reward-manager-and-subgraph-service')"
    exit 1
  fi
else
  echo "Warning: --name not provided; creating bare-date tag (fallback form)."
  echo "         Prefer a descriptive --name (e.g. 'reward-manager', 'fix-activation') for self-describing tags."
fi

CHAIN_ID="$(network_to_chain_id "$NETWORK")"
LABEL="$(network_to_label "$NETWORK")"
DISPLAY="$(network_to_display "$NETWORK")"

if [[ "$CHAIN_ID" == "unknown" ]]; then
  echo "Error: unknown network '$NETWORK' (expected arbitrumOne or arbitrumSepolia)"
  exit 1
fi

# --- Resolve --base default ---
# If --base was not provided, use the latest deploy/<label>/* tag as the diff base.
# This is the common case: every deploy's "contracts changed" section is the diff
# against the previous deploy on the same environment.
if [[ -z "$BASE_REF" ]]; then
  BASE_REF="$(git tag -l "deploy/${LABEL}/*" | sort | tail -1)"
  if [[ -z "$BASE_REF" ]]; then
    echo "Error: no previous deploy/${LABEL}/* tag found to use as --base default."
    echo "  For an initial deploy on ${LABEL}, pass --base explicitly"
    echo "  (e.g. --base HEAD~1, or --base \$(git hash-object -t tree /dev/null) for an empty-tree diff)."
    exit 1
  fi
  echo "Using latest deploy/${LABEL}/* tag as --base: ${BASE_REF}"
fi

# --- Preconditions ---
if [[ -n "$(git status --porcelain)" ]]; then
  echo "Error: working tree is not clean. Commit or stash changes first."
  echo "  (Tag must point to a finalized commit)"
  exit 1
fi

COMMIT_SHA="$(git rev-parse HEAD)"
COMMIT_SHORT="$(git rev-parse --short HEAD)"

# Check if commit is signed (informational)
if ! git log -1 --format='%G?' HEAD | grep -q '[GU]'; then
  echo "Warning: HEAD commit ($COMMIT_SHORT) is not signed"
fi

# Verify base ref exists
if ! git rev-parse --verify "$BASE_REF" >/dev/null 2>&1; then
  echo "Error: base ref '$BASE_REF' does not exist"
  exit 1
fi

# --- Detect changed contracts per address book ---
collect_changes() {
  local book_path="$1"
  local chain_id="$2"
  local base_ref="$3"
  # Get the file at base ref and at HEAD (both via git, not filesystem)
  local base_json head_json
  base_json="$(git show "$base_ref:$book_path" 2>/dev/null || echo '{}')"
  head_json="$(git show "HEAD:$book_path" 2>/dev/null || echo '{}')"

  if [[ "$head_json" == '{}' ]]; then
    return
  fi

  # Extract contract names for this chain at base and head
  local base_contracts head_contracts
  base_contracts="$(echo "$base_json" | jq -r --arg cid "$chain_id" '.[$cid] // {} | keys[]' 2>/dev/null || true)"
  head_contracts="$(echo "$head_json" | jq -r --arg cid "$chain_id" '.[$cid] // {} | keys[]' 2>/dev/null || true)"

  # Find contracts that are new or changed
  local all_contracts
  all_contracts="$(echo -e "${base_contracts}\n${head_contracts}" | sort -u | grep -v '^$' || true)"

  for contract in $all_contracts; do
    local base_entry head_entry
    base_entry="$(echo "$base_json" | jq -c --arg cid "$chain_id" --arg c "$contract" '.[$cid][$c] // empty' 2>/dev/null || true)"
    head_entry="$(echo "$head_json" | jq -c --arg cid "$chain_id" --arg c "$contract" '.[$cid][$c] // empty' 2>/dev/null || true)"

    if [[ "$base_entry" != "$head_entry" ]]; then
      # Contract changed - extract key details
      local impl addr change_type
      addr="$(echo "$head_json" | jq -r --arg cid "$chain_id" --arg c "$contract" '.[$cid][$c].address // empty' 2>/dev/null || true)"
      impl="$(echo "$head_json" | jq -r --arg cid "$chain_id" --arg c "$contract" '.[$cid][$c].implementation // empty' 2>/dev/null || true)"

      if [[ -z "$base_entry" ]]; then
        change_type="new"
      elif [[ -z "$head_entry" ]]; then
        change_type="removed"
      else
        change_type="updated"
      fi

      local detail=""
      if [[ -n "$impl" ]]; then
        detail="implementation: ${impl}"
      elif [[ -n "$addr" ]]; then
        detail="address: ${addr}"
      fi

      echo "${change_type}|${contract}|${detail}"
    fi
  done
}

# Collect all changes grouped by address book
declare -A BOOK_CHANGES
has_changes=false

for entry in "${ADDRESS_BOOKS[@]}"; do
  book_path="${entry%%:*}"
  book_name="${entry##*:}"

  changes="$(collect_changes "$book_path" "$CHAIN_ID" "$BASE_REF")"
  if [[ -n "$changes" ]]; then
    BOOK_CHANGES["$book_name"]="$changes"
    has_changes=true
  fi
done

if [[ "$has_changes" == false ]]; then
  echo "No address book changes detected for chain $CHAIN_ID between $BASE_REF and HEAD"
  echo "  Checked:"
  for entry in "${ADDRESS_BOOKS[@]}"; do
    echo "    ${entry%%:*}"
  done
  exit 1
fi

# --- Generate tag name ---
# Format matches DEPLOYMENT.md: deploy/<env>/YYYY-MM-DD[/<name>]
TAG_DATE="$(date +%Y-%m-%d)"
if [[ -n "$UPGRADE_NAME" ]]; then
  TAG_BASE="deploy/${LABEL}/${TAG_DATE}/${UPGRADE_NAME}"
else
  TAG_BASE="deploy/${LABEL}/${TAG_DATE}"
fi
TAG_NAME="$TAG_BASE"

# Collisions are resolved by choosing a more specific --name, not by automatic suffixes.
if git tag -l "$TAG_NAME" | grep -q .; then
  echo "Error: tag '${TAG_NAME}' already exists."
  if [[ -n "$UPGRADE_NAME" ]]; then
    echo "  Choose a more specific --name (e.g. 'fix-...', 'retry-...') to disambiguate."
  else
    echo "  Provide a --name to disambiguate (the name is the only disambiguator; letter suffixes are not used)."
  fi
  exit 1
fi

# --- Build annotation ---
ANNOTATION="network: ${DISPLAY} (${CHAIN_ID})
deployed-by: ${DEPLOYER}
commit: ${COMMIT_SHA}"
if [[ -n "$UPGRADE_NAME" ]]; then
  ANNOTATION="upgrade: ${UPGRADE_NAME}
${ANNOTATION}"
fi

for book_name in $(echo "${!BOOK_CHANGES[@]}" | tr ' ' '\n' | sort); do
  changes="${BOOK_CHANGES[$book_name]}"
  ANNOTATION="${ANNOTATION}

contracts (${book_name}):"

  while IFS='|' read -r change_type contract detail; do
    local_line="  - ${contract}"
    if [[ -n "$detail" ]]; then
      local_line="${local_line} (${detail})"
    fi
    if [[ "$change_type" == "new" ]]; then
      local_line="${local_line} [new]"
    elif [[ "$change_type" == "removed" ]]; then
      local_line="${local_line} [removed]"
    fi
    ANNOTATION="${ANNOTATION}
${local_line}"
  done <<< "$changes"
done

# --- Create or preview tag ---
echo ""
echo "--- Deployment Tag ---"
echo "Tag:    ${TAG_NAME}"
echo "Commit: ${COMMIT_SHORT} ($(git log -1 --format='%s' HEAD))"
echo ""
echo "$ANNOTATION"
echo "----------------------"
echo ""

if [[ "$DRY_RUN" == true ]]; then
  echo "[dry-run] Tag not created"
  exit 0
fi

# Confirm before creating the tag (unless --yes was given).
if [[ "$ASSUME_YES" == false ]]; then
  if [[ ! -t 0 ]]; then
    echo "Error: stdin is not a TTY; re-run with --yes to confirm non-interactively, or from a terminal."
    exit 1
  fi
  read -r -p "Create this tag? [y/N] " answer
  case "$answer" in
    y|Y|yes|YES) ;;
    *) echo "Aborted."; exit 1 ;;
  esac
fi

MSG_FILE="$(mktemp)"
trap 'rm -f "$MSG_FILE"' EXIT
printf '%s\n' "$ANNOTATION" > "$MSG_FILE"
git tag "$SIGN_FLAG" "$TAG_NAME" -F "$MSG_FILE"

echo "Tag created: ${TAG_NAME}"
echo ""
echo "To push:  git push origin ${TAG_NAME}"
echo "To view:  git show ${TAG_NAME}"
