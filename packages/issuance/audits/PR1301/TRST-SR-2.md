# TRST-SR-2: Escrow thawing period creates prolonged fund immobility

- **Severity:** Systemic Risk

## Description

The PaymentsEscrow thawing period (configurable up to `MAX_WAIT_PERIOD`, 90 days) creates a window during which escrowed funds are immobile. When the RAM needs to rebalance escrow across providers - for example, after an agreement ends and funds should be redirected to a new agreement - the thawing delay prevents immediate reallocation. During this window, the RAM effectively has reduced capacity.

If multiple agreements end in a short period or the escrow mode degrades from Full to OnDemand, the RAM may enter a state where substantial funds are locked in thawing and unavailable for either existing or new obligations. This is compounded by the micro-thaw griefing vector (TRST-M-1), which can extend the immobility period by blocking thaw increases.

The thawing period is a protocol-level parameter set on PaymentsEscrow and is outside the RAM's control. Changes to this parameter affect all users of the escrow system, not just the RAM.
