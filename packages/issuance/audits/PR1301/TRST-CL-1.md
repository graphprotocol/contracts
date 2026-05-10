# TRST-CL-1: RecurringCollector may underreport required claim causing under-reservation in the RAM

- **Category:** Logical flaws
- **Source:** RecurringCollector.sol
- **Status:** Fixed

## Description

In the refactored codebase, `_getMaxNextClaimScoped()` returns the next worst-case collection as a `max()` of PENDING and ACTIVE scopes. In the PENDING calculation, the collection time window always starts at `block.timestamp`. However, new agreements after `update()` take effect retroactively, so the time window may be larger (since last collection date).

The end impact is an understated next claim, which may cause the RAM to under-reserve for the particular allocation. No loss of funds is possible, although a delay in payment may arise.

## Mitigation Review

Issue has been addressed surgically. The function now accounts for the last collection time in case the agreement has already been accepted.

---
