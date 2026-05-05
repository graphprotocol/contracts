# TRST-SR-4: Try/catch callback pattern silently degrades state consistency

- **Severity:** Systemic Risk

## Description

The RecurringCollector wraps all payer callbacks (`beforeCollection()`, `afterCollection()`) in try/catch blocks. While this design prevents malicious or buggy payer contracts from blocking collection, it means that any revert in these callbacks is silently discarded. The collection proceeds as if the callback succeeded, but the payer's internal state (escrow snapshots, deficit tracking, reconciliation) may not have been updated.

This creates a systemic tension: the try/catch is necessary for liveness (ensuring providers can collect), but it trades state consistency for availability. Over time, if callbacks fail repeatedly (due to gas issues, contract bugs, or the stale snapshot issue in TRST-H-3), the divergence between the RAM's internal accounting and the actual escrow state can compound silently with no on-chain signal.

There is no event emitted when a callback fails, making it difficult for off-chain monitoring to detect and respond to these silent failures.
