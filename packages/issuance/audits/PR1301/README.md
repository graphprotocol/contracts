# Trust Security Audit - PR #1301 / #1312

**Auditor:** Trust Security
**Period:** 2026-03-03 to 2026-03-19
**Commit:** 7405c9d5f73bce04734efb3f609b76d95ffb520e
**Fix review commit:** 0bbb476f37f85d042927e84d8764fa58eb020ccf
**Report:** [Graph_PR1301_v02.pdf](Graph_PR1301_v02.pdf)

## Findings Summary

| ID                        | Title                                                    | Severity | Status       |
| ------------------------- | -------------------------------------------------------- | -------- | ------------ |
| [TRST-H-1](TRST-H-1.md)   | Malicious payer gas siphoning via 63/64 rule             | High     | Fixed        |
| [TRST-H-2](TRST-H-2.md)   | Invalid supportsInterface() returndata escapes try/catch | High     | Fixed        |
| [TRST-H-3](TRST-H-3.md)   | Stale escrow snapshot causes perpetual revert loop       | High     | Fixed        |
| [TRST-H-4](TRST-H-4.md)   | EOA payer can block collection via EIP-7702              | High     | Fixed        |
| [TRST-M-1](TRST-M-1.md)   | Micro-thaw griefing via permissionless depositTo()       | Medium   | Open         |
| [TRST-M-2](TRST-M-2.md)   | tempJit fallback in beforeCollection() unreachable       | Medium   | Fixed        |
| [TRST-M-3](TRST-M-3.md)   | Instant escrow mode degradation via agreement offer      | Medium   | Acknowledged |
| [TRST-M-4](TRST-M-4.md)   | Returndata bombing via payer callbacks                   | Medium   | Open         |
| [TRST-M-5](TRST-M-5.md)   | Perpetual thaw griefing via micro deposits               | Medium   | Open         |
| [TRST-L-1](TRST-L-1.md)   | Insufficient gas for afterCollection callback            | Low      | Fixed        |
| [TRST-L-2](TRST-L-2.md)   | Pending update over-reserves escrow                      | Low      | Fixed        |
| [TRST-L-3](TRST-L-3.md)   | Unsafe approveAgreement behavior during pause            | Low      | Fixed        |
| [TRST-L-4](TRST-L-4.md)   | Pair tracking removal blocked by 1 wei donation          | Low      | Acknowledged |
| [TRST-L-5](TRST-L-5.md)   | \_computeMaxFirstClaim overestimates near deadline       | Low      | Fixed        |
| [TRST-L-6](TRST-L-6.md)   | Update offer cleanup bypassed via planted offer          | Low      | Open         |
| [TRST-L-7](TRST-L-7.md)   | cancel() order sensitivity leaves RCAU offer unreachable | Low      | Open         |
| [TRST-L-8](TRST-L-8.md)   | EOA payer signatures cannot be revoked before deadline   | Low      | Open         |
| [TRST-L-9](TRST-L-9.md)   | Callback gas precheck does not account for overhead      | Low      | Open         |
| [TRST-L-10](TRST-L-10.md) | EIP-7702 payer code change enables callback gas griefing | Low      | Open         |
| [TRST-L-11](TRST-L-11.md) | Inaccurate state flags in getAgreementDetails()          | Low      | Open         |

## Recommendations

| ID                        | Title                                                           |
| ------------------------- | --------------------------------------------------------------- |
| [TRST-R-1](TRST-R-1.md)   | Avoid redeployment of RewardsEligibilityOracle                  |
| [TRST-R-2](TRST-R-2.md)   | Improve stale documentation                                     |
| [TRST-R-3](TRST-R-3.md)   | Incorporate defensive coding best practices                     |
| [TRST-R-4](TRST-R-4.md)   | Document critical assumptions in the RAM                        |
| [TRST-R-5](TRST-R-5.md)   | Ambiguous return value in getAgreementOfferAt()                 |
| [TRST-R-6](TRST-R-6.md)   | Dead code guard in \_validateAndStoreUpdate()                   |
| [TRST-R-7](TRST-R-7.md)   | Remove consumed offers in accept() and update()                 |
| [TRST-R-8](TRST-R-8.md)   | Align pause documentation with callback behavior in the RAM     |
| [TRST-R-9](TRST-R-9.md)   | \_isAuthorized() override trusts itself for any authorizer      |
| [TRST-R-10](TRST-R-10.md) | Document role-change semantics for existing agreements          |
| [TRST-R-11](TRST-R-11.md) | Remove or implement unused state flags in IAgreementCollector   |
| [TRST-R-12](TRST-R-12.md) | Document ACCEPTED state returned for cancelled agreements       |
| [TRST-R-13](TRST-R-13.md) | Document reclaim reason change for stale allocation force-close |

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
