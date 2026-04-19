# Deployment Strategy

This document outlines the branching and deployment strategy for Solidity contracts in this repository.

## Overview

We use a **per-cycle deployment branch** model: each deployment cycle creates a fresh, short-lived branch from `main`, runs testnet then mainnet from that branch, and merges back to `main` when the cycle closes. Tags on the branch capture each deploy as a self-contained snapshot — deployed code, deployment scripts, and artifacts together.

```
feature/* ──PR──► main (audited, deployment-ready)
                   │
                   ▼ branch at cycle start
           deployment/YYYY-MM-DD
                   │
                   ├─► deploy to testnet ──► tag: deploy/testnet/YYYY-MM-DD
                   │
                   ├─► deploy to mainnet ──► tag: deploy/mainnet/YYYY-MM-DD
                   │
                   └──PR──► merge back to main
```

For hotfixes, branch from the tag in production instead of from `main`:

```
deploy/mainnet/YYYY-MM-DD (tag) ──branch──► deployment/YYYY-MM-DD-hotfix
                                                   │
                                                   ├─► fix + audit
                                                   ├─► deploy ──► tag: deploy/mainnet/YYYY-MM-DD
                                                   └──PR──► merge back to main
```

## Key Principles

1. **Work in feature branches.** All development happens in `feature/*` branches. Merge to `main` only when the work is complete.

2. **`main` is always deployable and always audited.** If code isn't ready, it stays in a feature branch. PRs modifying production Solidity contracts require an `audited` label before merging.

3. **Deployment branches are short-lived and branched fresh.** Each cycle starts a new `deployment/YYYY-MM-DD` branch from `main`. The branch accumulates deployment script changes, artifacts, and any cycle-specific fixes, then merges back to `main` and is deleted when the cycle closes. No long-lived deployment branches exist; the presence or absence of a `deployment/*` branch is itself the signal for "is a cycle in progress?"

4. **At most one active deployment cycle at a time.** Avoid starting a new cycle while another is in flight. The exception is an emergency hotfix, which runs on its own parallel branch. Keeping to a single active cycle makes "what's being deployed next" unambiguous and avoids the merge-ordering hazards of two concurrent deployment branches diverging from the same `main`. If testnet validation of a cycle is pending, wait for it to conclude (or be abandoned) before starting the next cycle.

5. **Hotfix branches are branched from the tag they patch.** A hotfix branches from the `deploy/mainnet/YYYY-MM-DD` tag currently in production, not from `main`. This keeps the hotfix diff minimal (against running code only) and avoids shipping accumulated but undeployed work on `main`.

6. **Tag every deployment.** Each deploy creates an immutable `deploy/<env>/YYYY-MM-DD` tag. The tag points at the deployment branch tip at the moment of deploy, so `git checkout <tag>` reproduces the full state: source code, deployment scripts, and artifacts.

7. **Merge back to `main` closes every cycle.** At the end of every cycle (regular or hotfix) the deployment branch is merged back to `main` via a PR. This backports artifacts, pins deployment script changes, and ensures `main` reflects the currently-deployed state.

8. **Prefer fast-forward, especially for audited changes.** Each non-FF merge creates a tree state no reviewer read before it existed. For audited PRs this weakens the link between the audit's pinned commit hash and the bytes that end up on `main`, reducing the audit proof from trivial SHA equality to a diff-based check. Rebase audited feature branches onto current `main` before merging whenever feasible, and deploy often enough that cycle merge-backs stay small.

## Branches

| Branch                  | Purpose                               | Lifetime                              |
| ----------------------- | ------------------------------------- | ------------------------------------- |
| `feature/*`             | Active development                    | Until merged to `main`                |
| `main`                  | Audited, deployment-ready code        | Permanent                             |
| `deployment/YYYY-MM-DD` | A single deployment cycle's workspace | Short-lived; deleted after merge-back |

## Tags

For each deployment create an immutable annotated tag:

- `deploy/testnet/YYYY-MM-DD/<name>` — testnet deployment snapshot (Arbitrum Sepolia)
- `deploy/mainnet/YYYY-MM-DD/<name>` — mainnet deployment snapshot (Arbitrum One)

Including a descriptive `<name>` is recommended. A short hyphenated identifier (e.g. `reward-manager-and-subgraph-service`, `fix-activation`, `retry-subgraph-service`) makes tags self-describing, gives operators something meaningful to search on, and naturally prevents collisions when multiple deploys happen on the same day. The date segment ensures chronological sort regardless.

Each tag is self-contained: its tree includes the deployed `.sol` sources, the deployment scripts used, and the resulting artifacts (`addresses.json`, etc.). The annotated tag body additionally records deployer identity and the list of changed contracts. Reproducing a past deploy is `git checkout <tag>` and nothing else.

### Finding and working with deployed code

Check out what's currently on mainnet:

```bash
git checkout "$(git tag -l 'deploy/mainnet/*' | sort | tail -1)"
```

Check out what's currently on testnet:

```bash
git checkout "$(git tag -l 'deploy/testnet/*' | sort | tail -1)"
```

List all deployment tags:

```bash
git tag -l "deploy/*"
```

Diff between last mainnet deploy and current main:

```bash
git diff "$(git tag -l 'deploy/mainnet/*' | sort | tail -1)"..main
```

Check whether a deployment cycle is in progress:

```bash
git branch -a --list 'deployment/*'
```

## Workflows

### Feature Development

Features are developed in feature branches and merged to `main` when complete. PRs modifying Solidity contracts require the `audited` label.

```
feature/new-stuff ──PR (audited)──► main
```

### Deployment Cycle

When ready to start a deployment:

1. Branch `deployment/YYYY-MM-DD` from current `main` and push it. Check that there are no other deployment branches.
2. Run the deployment scripts against testnet. Commit the updated artifacts (e.g. `addresses.json`) and any deployment script changes to the branch, and push. Open a PR from the branch back to `main` once this first commit lands — it stays open for the whole cycle as the review/tracking thread and becomes the merge-back PR at the end.
3. Run `tag-deployment.sh --network arbitrumSepolia --name <name> ...` (see [Tagging](#tagging)) to create an annotated `deploy/testnet/YYYY-MM-DD/<name>` tag pointing at the artifact commit. Push the tag.
4. After testnet validation, run the scripts against mainnet from the same branch tip. Commit updated artifacts and push.
5. Run `tag-deployment.sh --network arbitrumOne --name <name> ...` to create the `deploy/mainnet/YYYY-MM-DD/<name>` tag. Push the tag.
6. Review and merge the open PR back into `main`.
7. Delete the deployment branch. The tags remain as the permanent record, and the absence of any `deployment/*` branch correctly signals "no cycle in progress."

Because both testnet and mainnet deploy from the same branch, testnet previews mainnet by construction.

### Emergency Hotfix

For critical mainnet issues:

1. Branch `deployment/YYYY-MM-DD-hotfix` from the current `deploy/mainnet/YYYY-MM-DD` tag and push it.
2. Apply the fix. If it touches contract source, it must be audited before deploy. Commit and push; open a PR back to `main` at this point — it stays open for the duration of the hotfix as the review/tracking thread and becomes the merge-back PR.
3. Run the deployment scripts against mainnet (ideally testnet first as a dry run). Commit artifacts and push.
4. Run `tag-deployment.sh --network arbitrumOne --name <name> ...` to create the `deploy/mainnet/YYYY-MM-DD/<name>` tag. Push the tag.
5. Review and merge the open PR back into `main`. The `audited` label applies to any contract changes in this PR.
6. Delete the hotfix branch.
7. If another deployment cycle is already in flight on a separate `deployment/*` branch, rebase or merge that branch onto the hotfix before its deploy — otherwise it will silently revert the fix.

## Audit Integrity

Audits certify that specific files have specific content. The operational question is always:

> For every file in the audit scope, do its current bytes match the audited version's bytes?

This scheme preserves that property by construction. Deployment branches are branched from `main` (or from a deploy tag for hotfixes) and only move forward; the audited bytes on `main` flow into the deployment branch unchanged unless a cycle-specific fix explicitly modifies them, in which case the fix is gated by the `audited` label on its merge-back PR.

The audit scope is a transitive closure — a reviewed contract's imports are implicitly in scope even if the PR didn't touch them — and the audit reference is a pinned commit SHA, not a PR number or label. A CI check can be added to provide a mechanical floor under the cultural FF-preference: diff the audited paths between the last audit tag and `HEAD`, and either require the diff to be empty or require a fresh audit. See [Appendix A: Audit Integrity CI Check](#appendix-a-audit-integrity-ci-check) for the sketch and the design decisions it depends on.

## Automation

### Tagging

Tag creation is a **scripted operator step**, not a GitHub Action. Deployments are infrequent enough that full automation offers little benefit, and the tagging script can capture context a CI workflow cannot: which deploy script was actually invoked, with what flags, by whom, and which contracts changed in which address books — baked into an annotated tag body, optionally signed.

Implementation: [`packages/deployment/scripts/tag-deployment.sh`](packages/deployment/scripts/tag-deployment.sh). It takes `--deployer`, `--network`, `--name` (recommended), and `--base`; diffs each address book (`packages/horizon/addresses.json`, `packages/subgraph-service/addresses.json`, `packages/issuance/addresses.json`) against the base ref to enumerate new / updated / removed contracts; and creates the annotated tag in the `deploy/<env>/YYYY-MM-DD/<name>` format defined above (or the bare-date fallback when no name is given). Network names map `arbitrumOne` → `mainnet` and `arbitrumSepolia` → `testnet`.

Typical invocation after the artifact commit is pushed, first create tag:

```bash
packages/deployment/scripts/tag-deployment.sh \
  --deployer "packages/deployment --tags RewardsManager,SubgraphService" \
  --network arbitrumSepolia \
  --name reward-manager-and-subgraph-service
```

The script prints a preview (tag name, commit, annotation body), asks for confirmation, and creates a signed annotated tag. Run `tag-deployment.sh --help` for the full option list (`--dry-run`, `--yes`, `--no-sign`, `--base`, …).

Then push:

```bash
git push origin <tag>
```

The diff against `--base` is what populates the tag body's "contracts" section. The default of the previous deploy tag for the same environment should normally be correct. For an initial deploy on an environment (no prior tag exists), pass `--base` explicitly.

### Audit Label Requirement

PRs to `main` modifying Solidity contract files require an `audited` label before merging (`.github/workflows/require-audit-label.yml`).

- **Applies to:** `.sol` files outside of test directories
- **Excludes:** Files in `/test/`, `/tests/`, or ending in `.t.sol`
- **Label:** `audited`

This enforces principle #2: code in `main` must be audited.

### Cycle merge-back

Merging a deployment branch back to `main` is a standard PR. In the common case the branch only added artifacts and scripts, so the audit gate is a no-op. If the cycle included any contract changes (e.g. a hotfix), those require the `audited` label before merge-back lands.

## Appendix A: Audit Integrity CI Check

A future workflow to enforce the byte-equality property at CI level rather than relying on the cultural FF-preference. Sketched here; design decisions still to make before implementation.

### Approach

1. **Audit tags.** Each completed audit produces an annotated tag of the form `audit/YYYY-MM-DD/<scope-name>` pointing at the commit the auditors signed off on. The tag body records the auditor, the scope (which files/paths), and a link to the audit report.
2. **Scope definition.** The "audit scope" is the set of file paths the auditors reviewed, together with the transitive closure of their Solidity imports. Stored as a path list (or glob) in the audit tag's annotation body so it can be parsed programmatically.
3. **CI check.** On every PR to `main` (or every push to `deployment/*`), resolve the most recent `audit/*` tag that covers each in-scope file and compute `git diff <audit-tag> HEAD -- <scoped-paths>`. If non-empty for any in-scope file, require either:
   - The PR to carry the `audited` label (operator asserts the diff has been re-reviewed), or
   - A new `audit/*` tag to land that covers the current `HEAD` for those paths.
4. **Empty diff ⇒ automatic pass.** When the audited bytes on `HEAD` match the audit tag's bytes exactly for all in-scope files, no human intervention is needed — the CI proves trivially that `HEAD` still matches what was audited.

### Open design decisions

- **Where does "audit scope" live?** Most robust: in the `audit/*` tag body as a path list. Alternative: a checked-in `audits/manifest.json`. The tag-body approach keeps the scope immutable alongside the reference commit; the file approach is easier to edit when scopes overlap or evolve.
- **Multi-audit composition.** Different contracts may be covered by different audits. The CI needs a deterministic "most recent audit covering file X" lookup. Overlapping scopes require conflict resolution (most specific wins? most recent?).
- **Transitive closure computation.** For `.sol` files, the importer graph is machine-derivable. A pre-commit or CI step should expand a human-declared scope (e.g. "the `IssuanceAllocator` contract") into the full transitive closure, so scope drift (an import added after audit) is caught automatically.
- **Path inclusion/exclusion rules.** The current `require-audit-label.yml` excludes `/test/`, `/tests/`, and `*.t.sol`, but there are other helper, mock, and internal-only contracts that aren't audit targets (migration scaffolding, local fixtures, temporary scripts). A robust check needs either an explicit in-scope list or a clearer directory convention.

### Prerequisite: reorganize non-production Solidity

The current tree mixes production contracts with helpers, mocks, and internal tooling in the same directories. Before the CI check is meaningful:

- Move non-production Solidity into clearly-named directories outside any plausible audit scope (e.g. `mocks/`, `helpers/`, `scripts/`, a top-level `non-audit/` tree per package).
- Make audit scope a directory-level property wherever possible ("everything under `packages/<pkg>/contracts/` is audit scope; nothing else is") so that inclusion is inferrable from path rather than requiring a bespoke filter.
- Update `require-audit-label.yml`'s filter in the same pass so its exclusions match the new layout.

Until this reorganization lands, an audit-integrity CI check is possible but would rely on hand-maintained path lists — fragile and easy to drift from reality. The reorganization is low-risk refactoring but should be done in its own PR (itself audited for scope equivalence), separately from adopting this deployment proposal.
