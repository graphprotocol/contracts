#!/usr/bin/env bash
#
# tag-deployment.sh - Create annotated git tag for a contract deployment
#
# Usage:
#   ./scripts/tag-deployment.sh --deployer <description> --network <network> --name <short-name> [options]
#
# Options:
#   --deployer <desc>   What performed the deployment (free-form, e.g., "packages/deployment --tags RewardsManager")
#   --network <name>    Network: arbitrumOne or arbitrumSepolia
#   --name <short-name> Upgrade short name for the tag (e.g., "reward-manager-and-subgraph-service")
#   --base <ref>        Git ref to diff against (default: HEAD~1)
#   --dry-run           Preview tag without creating it
#   --sign              Force-sign the tag with -s
#   --help              Show this help
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
BASE_REF="HEAD~1"
DRY_RUN=false
SIGN_FLAG="-a"

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
  sed -n '3,14p' "$0" | sed 's/^# \?//'
  exit "${1:-0}"
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --deployer) DEPLOYER="$2"; shift 2 ;;
    --network)  NETWORK="$2"; shift 2 ;;
    --name)     UPGRADE_NAME="$2"; shift 2 ;;
    --base)     BASE_REF="$2"; shift 2 ;;
    --dry-run)  DRY_RUN=true; shift ;;
    --sign)     SIGN_FLAG="-s"; shift ;;
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

if [[ -z "$UPGRADE_NAME" ]]; then
  echo "Error: --name is required"
  usage 1
fi

# Validate upgrade name: lowercase, digits, hyphens only
if [[ ! "$UPGRADE_NAME" =~ ^[a-z0-9]([a-z0-9-]*[a-z0-9])?$ ]]; then
  echo "Error: --name must be lowercase alphanumeric with hyphens (e.g., 'reward-manager-and-subgraph-service')"
  exit 1
fi

CHAIN_ID="$(network_to_chain_id "$NETWORK")"
LABEL="$(network_to_label "$NETWORK")"
DISPLAY="$(network_to_display "$NETWORK")"

if [[ "$CHAIN_ID" == "unknown" ]]; then
  echo "Error: unknown network '$NETWORK' (expected arbitrumOne or arbitrumSepolia)"
  exit 1
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
TAG_DATE="$(date +%Y-%m-%d)"
TAG_BASE="deploy/${LABEL}/${TAG_DATE}/${UPGRADE_NAME}"
TAG_NAME="$TAG_BASE"

# Handle suffix for multiple deploys with the same name on the same day
if git tag -l "$TAG_NAME" | grep -q .; then
  for suffix in b c d e f; do
    candidate="${TAG_BASE}-${suffix}"
    if ! git tag -l "$candidate" | grep -q .; then
      TAG_NAME="$candidate"
      break
    fi
  done
  if [[ "$TAG_NAME" == "$TAG_BASE" ]]; then
    echo "Error: too many deployment tags for ${TAG_DATE}/${UPGRADE_NAME}"
    exit 1
  fi
fi

# --- Build annotation ---
ANNOTATION="upgrade: ${UPGRADE_NAME}
network: ${DISPLAY} (${CHAIN_ID})
deployed-by: ${DEPLOYER}
commit: ${COMMIT_SHA}"

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

MSG_FILE="$(mktemp)"
trap 'rm -f "$MSG_FILE"' EXIT
printf '%s\n' "$ANNOTATION" > "$MSG_FILE"
git tag "$SIGN_FLAG" "$TAG_NAME" -F "$MSG_FILE"

echo "Tag created: ${TAG_NAME}"
echo ""
echo "To push:  git push origin ${TAG_NAME}"
echo "To view:  git show ${TAG_NAME}"
