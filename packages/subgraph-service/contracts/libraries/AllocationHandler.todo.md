# AllocationHandler.sol — pending updates

Tracking pending edits noted but deferred to avoid touching contract source until the next maintenance window. When picking up, drop the corresponding entry below as part of the same commit.

## Legacy-allo migration cleanup

The legacy-allocation-id migration block around L170 is unused. It was added during horizon work to migrate legacy allocation IDs from `HorizonStaking` to `SubgraphService`, never executed, and intentionally deferred.

**Confirmation:**

- Maikol on PR #1331 (2026-05-06, `AllocationHandler.sol:170`): "I believe this is no longer being used so we could delete. Maybe leave for a post-post-horizon cleanup 😅"
- tmigone on PR #1331 (2026-05-08): "this was never used indeed. added with horizon to migrate legacy allo ids from staking to subgraph service but we never executed on it and have since decided to remove with clean up. its likely it got re-added with matias' commit but we don't need it."

**Trigger:** Post-horizon cleanup pass, or any adjacent edit to `AllocationHandler.sol` that makes the removal cheap to fold in. Scope is the specific block tmigone identified — not a broader audit of horizon-era dead code.
