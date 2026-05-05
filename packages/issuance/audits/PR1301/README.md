# Trust Security Audit - PR #1301

**Auditor:** Trust Security
**Period:** 2026-03-03 to 2026-03-19
**Commit:** 7405c9d5f73bce04734efb3f609b76d95ffb520e
**Report:** [Graph_PR1301_v01.pdf](Graph_PR1301_v01.pdf)

## Findings Summary

| ID                      | Title                                                    | Severity |
| ----------------------- | -------------------------------------------------------- | -------- |
| [TRST-H-1](TRST-H-1.md) | Malicious payer gas siphoning via 63/64 rule             | High     |
| [TRST-H-2](TRST-H-2.md) | Invalid supportsInterface() returndata escapes try/catch | High     |
| [TRST-H-3](TRST-H-3.md) | Stale escrow snapshot causes perpetual revert loop       | High     |
| [TRST-H-4](TRST-H-4.md) | EOA payer can block collection via EIP-7702              | High     |
| [TRST-M-1](TRST-M-1.md) | Micro-thaw griefing via permissionless depositTo()       | Medium   |
| [TRST-M-2](TRST-M-2.md) | tempJit fallback in beforeCollection() unreachable       | Medium   |
| [TRST-M-3](TRST-M-3.md) | Instant escrow mode degradation via agreement offer      | Medium   |
| [TRST-L-1](TRST-L-1.md) | Insufficient gas for afterCollection callback            | Low      |
| [TRST-L-2](TRST-L-2.md) | Pending update over-reserves escrow                      | Low      |
| [TRST-L-3](TRST-L-3.md) | Unsafe approveAgreement behavior during pause            | Low      |
| [TRST-L-4](TRST-L-4.md) | Pair tracking removal blocked by 1 wei donation          | Low      |
| [TRST-L-5](TRST-L-5.md) | \_computeMaxFirstClaim overestimates near deadline       | Low      |

## Recommendations

| ID                      | Title                                          |
| ----------------------- | ---------------------------------------------- |
| [TRST-R-1](TRST-R-1.md) | Avoid redeployment of RewardsEligibilityOracle |
| [TRST-R-2](TRST-R-2.md) | Improve stale documentation                    |
| [TRST-R-3](TRST-R-3.md) | Incorporate defensive coding best practices    |
| [TRST-R-4](TRST-R-4.md) | Document critical assumptions in the RAM       |

## Centralization Risks

| ID                        | Title                                                           |
| ------------------------- | --------------------------------------------------------------- |
| [TRST-CR-1](TRST-CR-1.md) | RAM Governor has unilateral control over payment infrastructure |
| [TRST-CR-2](TRST-CR-2.md) | Operator role controls agreement lifecycle and escrow mode      |
| [TRST-CR-3](TRST-CR-3.md) | Single RAM instance manages all agreement escrow                |

## Systemic Risks

| ID                        | Title                                                          |
| ------------------------- | -------------------------------------------------------------- |
| [TRST-SR-1](TRST-SR-1.md) | JIT mode provider payment race condition                       |
| [TRST-SR-2](TRST-SR-2.md) | Escrow thawing period creates prolonged fund immobility        |
| [TRST-SR-3](TRST-SR-3.md) | Issuance distribution dependency for RAM solvency              |
| [TRST-SR-4](TRST-SR-4.md) | Try/catch callback pattern silently degrades state consistency |
