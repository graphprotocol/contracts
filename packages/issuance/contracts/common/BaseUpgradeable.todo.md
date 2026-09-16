# BaseUpgradeable.sol — pending updates

Tracking pending edits noted but deferred to avoid touching contract source until the next maintenance window. When picking up, drop the corresponding entry below as part of the same commit.

## Unused `MILLION` constant

`uint256 public constant MILLION = 1_000_000;` (around L37) has no in-repo references. The only mentions of `MILLION` anywhere under `packages/` are this declaration and its own docstring example.

It's `public`, so removing it is technically an ABI change on every `BaseUpgradeable` descendant (each currently exposes a `MILLION()` getter).

- **Delete.** Drop the constant and its docstring. Confirm no external caller depends on the getter — a quick GitHub code search across consumers (indexer-rs, eligibility-oracle-node, etc.) should be enough; ABI hash will change on any contract inheriting BaseUpgradeable.
