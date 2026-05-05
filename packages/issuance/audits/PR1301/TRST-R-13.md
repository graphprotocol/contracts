# TRST-R-13: Document reclaim reason change for stale allocation force-close

- **Severity:** Recommendation

## Description

Before the PR's refactor, `forceCloseStaleAllocation()` closed the allocation via `_closeAllocation()` and caused a reclaim with reason `CLOSE_ALLOCATION`. Post refactor, the force close path goes through `_resizeAllocation(allocationId, 0, ...)`, which triggers a reclaim with reason `STALE_POI` instead. The reclaim still occurs, but the reason code exposed to reclaim address configuration changes. Document this change so that operators are able to prepare accordingly and have funding paths line up with intention.
