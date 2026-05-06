# Trust Security Audit - PR #1301 / #1312 / #1325 / #1331

**Auditor:** Trust Security
**Period:** 2026-03-03 to 2026-03-19
**Commit:** 7405c9d5f73bce04734efb3f609b76d95ffb520e
**Fix review commit:** 0bbb476f37f85d042927e84d8764fa58eb020ccf
**2nd fix review commit:** f44fc5a4c74fa5190fd2892ae15a083b79f715f3
**3rd fix review commit:** bbec75e04aa14c34d771681528b9a655be1f8249 (post-rebase)
**Report:** [Graph_PR1331_v04.pdf](Graph_PR1331_v04.pdf)

> **SHA note.** The first three commits cited above are pre-rebase SHAs on
> `indexing-payments-management-audit-fix-2-light`, which was rebased onto
> current `main` as `indexing-payments-management-audit-fixed-rebased`. The pre-rebase tip is
> preserved at tag `indexing-payments-management-audit-pre-rebase`
> (`a3c73f87e`). The 3rd fix review commit is post-rebase only (it
> records the SHA mapping itself). Old → new mapping is at the bottom of
> this file.

## Findings Summary

| ID                        | Title                                                    | Severity | Status       |
| ------------------------- | -------------------------------------------------------- | -------- | ------------ |
| [TRST-H-1](TRST-H-1.md)   | Malicious payer gas siphoning via 63/64 rule             | High     | Fixed        |
| [TRST-H-2](TRST-H-2.md)   | Invalid supportsInterface() returndata escapes try/catch | High     | Fixed        |
| [TRST-H-3](TRST-H-3.md)   | Stale escrow snapshot causes perpetual revert loop       | High     | Fixed        |
| [TRST-H-4](TRST-H-4.md)   | EOA payer can block collection via EIP-7702              | High     | Fixed        |
| [TRST-M-1](TRST-M-1.md)   | Micro-thaw griefing via permissionless depositTo()       | Medium   | Fixed        |
| [TRST-M-2](TRST-M-2.md)   | tempJit fallback in beforeCollection() unreachable       | Medium   | Fixed        |
| [TRST-M-3](TRST-M-3.md)   | Instant escrow mode degradation via agreement offer      | Medium   | Acknowledged |
| [TRST-M-4](TRST-M-4.md)   | Returndata bombing via payer callbacks                   | Medium   | Fixed        |
| [TRST-L-1](TRST-L-1.md)   | Insufficient gas for afterCollection callback            | Low      | Fixed        |
| [TRST-L-2](TRST-L-2.md)   | Pending update over-reserves escrow                      | Low      | Fixed        |
| [TRST-L-3](TRST-L-3.md)   | Unsafe approveAgreement behavior during pause            | Low      | Fixed        |
| [TRST-L-4](TRST-L-4.md)   | Pair tracking removal blocked by 1 wei donation          | Low      | Acknowledged |
| [TRST-L-5](TRST-L-5.md)   | \_computeMaxFirstClaim overestimates near deadline       | Low      | Fixed        |
| [TRST-L-6](TRST-L-6.md)   | cancel() order sensitivity leaves RCAU offer unreachable | Low      | Fixed        |
| [TRST-L-7](TRST-L-7.md)   | EOA payer signatures cannot be revoked before deadline   | Low      | Fixed        |
| [TRST-L-8](TRST-L-8.md)   | Callback gas precheck does not account for overhead      | Low      | Fixed        |
| [TRST-L-9](TRST-L-9.md)   | EIP-7702 payer code change enables callback gas griefing | Low      | Fixed        |
| [TRST-L-10](TRST-L-10.md) | Inaccurate state flags in getAgreementDetails()          | Low      | Fixed        |

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
| [TRST-R-14](TRST-R-14.md) | Avoid magic numbers in production code                          |

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

## Notes on findings dropped between v02 and v03

- v02 **TRST-M-5** (Perpetual thaw griefing via micro deposits) was withdrawn in v03; the underlying concern is treated as a sub-vector of TRST-M-1, addressed by `minResidualEscrowFactor`.
- v02 **TRST-L-6** (Update offer cleanup bypassed via planted offer) was withdrawn in v03; the agreement.payer / per-version persistence refactor done for v03 TRST-L-6 / TRST-L-10 supersedes the original cleanup concern.

## Pre-rebase → post-rebase SHA mapping

`indexing-payments-management-audit-fix-2-light` was rebased onto current `main` as `indexing-payments-management-audit-fixed-rebased`. The first-parent linear chain was re-signed (new SHAs); side-branch commits reachable through the two internal merges kept their original SHAs and signatures.

Verify audit-side content was preserved byte-identically:

```bash
ORIG=indexing-payments-management-audit-pre-rebase   # tag at a3c73f87e
REB=2292e6ae8                                        # rebased tip before this commit
diff <(git diff "$ORIG" "$REB") <(git diff ddee12b11 main)
# expected: empty
```

| old         | new         | subject                                                                                             |
| ----------- | ----------- | --------------------------------------------------------------------------------------------------- |
| `5c51f0d6a` | `ad157562f` | chore: use ^0.8.27 caret pragma and bump solc to 0.8.34                                             |
| `bf6d4cb70` | `9b2fddc51` | Merge commit '0e469beeba0ec433e313be8c9129bcf99acdaac6' into indexing-payments-management-audit     |
| `28edcd7a3` | `2a9d80b3e` | Merge commit 'd9f053a7d96a8a4d81415303ae1d537f836f887c' into indexing-payments-management-audit     |
| `f4451f189` | `927cd08cf` | feat: add back legacy allocation id collision check                                                 |
| `fd962344c` | `9edb765ae` | chore: restore pragma                                                                               |
| `fa9951427` | `79af54585` | fix: cap maxSecondsPerCollection instead of reverting                                               |
| `c6836a716` | `20abcac15` | fix: enforce temporal validation on zero-token collections and remove zero-POI special case         |
| `8efaec97d` | `8776d4931` | feat: add adjustThaw to PaymentsEscrow                                                              |
| `3f1578cdc` | `5ea7b1e19` | refactor: rename IRewardsEligibility to IProviderEligibility                                        |
| `d20bc844d` | `d31a2c95c` | feat: contract approver model for RecurringCollector accept/update                                  |
| `ec7236086` | `2bcc8ec88` | feat: IDataServiceAgreements interface and SubgraphService integration                              |
| `89def3d34` | `7d7927a10` | feat: enumerable indexer tracking for REO and issuance constructor cleanup                          |
| `a23ad681e` | `15bd6ceca` | feat: RecurringAgreementManager with lifecycle, escrow funding, and agreement updates               |
| `8673c34c0` | `8ca9cc1e1` | fix(rewards): reorder subtraction in \_updateSubgraphRewards to avoid underflow                     |
| `506601ff8` | `2b5bce3e8` | fix(test): set subgraphService in snapshot inversion tests                                          |
| `32bd36134` | `0d9e8fe44` | fix(test): exclude named test users from fuzz-generated indexer addresses                           |
| `0f4f48693` | `cd2f1b468` | feat: add issuance distribution integration to RAM                                                  |
| `86a5d6e2b` | `89ba6e873` | docs: clarify two-layer token capping semantics in collection flow                                  |
| `7405c9d5f` | `50e984da9` | docs: add payments trust model                                                                      |
| `9ae7643eb` | `6a9e37209` | test: add cross-package testing harness with callback gas measurements                              |
| `efc51160f` | `251e16f28` | docs(audit): add PR1301 audit report and findings                                                   |
| `956d983aa` | `f5617ef98` | feat(RAM): threshold-based escrow basis degradation (TRST-M-2, TRST-M-3)                            |
| `e1d73c109` | `435a281f7` | fix(RAM): refresh escrow snapshot in \_updateEscrow (TRST-H-3)                                      |
| `e1a3c5ade` | `4fc2be9fd` | fix(RAM): add minimum thaw fraction to prevent dust-thaw griefing (TRST-M-1)                        |
| `56322cc50` | `e3bec768d` | feat(RM): add revert control for ineligible indexers                                                |
| `3b617b47b` | `3f9c68c12` | docs(audit): acknowledge audit findings (TRST-CR-1/3, L-4, R-1, SR-1/2/3)                           |
| `df93851fb` | `df7f08123` | feat: resize allocations to zero instead of force-closing                                           |
| `b1246562b` | `4c61ad9d6` | feat: revert closing allocations with active indexing agreement                                     |
| `40c910464` | `a93ee9285` | fix(collector): reject agreements with overflow-prone token/duration terms                          |
| `83e25156a` | `74aaa3417` | feat(collector): offer storage, stored-hash auth, scoped claims and cancel (TRST-L-2, L-5)          |
| `38b090c2b` | `68c8a39f4` | fix(collector): harden payer callbacks, add opt-in eligibility gate (TRST-H-1, H-2, H-4, L-1, SR-4) |
| `5b4100543` | `9d16819a7` | fix: compiler stack overflow                                                                        |
| `608346eb2` | `f56be5f8e` | refactor(RAM): replace set-based range views with indexed accessors                                 |
| `0b22a1408` | `fc8e14124` | feat(RAM): add emergency role control and eligibility oracle escape hatch                           |
| `77fc87f78` | `22eab2737` | refactor(RAM): convert offerAgreement and cancelAgreement to IAgreementCollector pass-throughs      |
| `64bc0f0ed` | `87a0b899c` | refactor(RAM): remove offerAgreementUpdate, revokeAgreementUpdate, and revokeOffer                  |
| `daf0b47ed` | `2e75ecc92` | refactor(RAM): restructure storage into collector → provider hierarchy                              |
| `9ec2c072e` | `67af760a7` | feat(collector): make RecurringCollector upgradeable                                                |
| `bbe019588` | `be5cead8c` | feat(collector): add pause mechanism to RecurringCollector (TRST-L-3)                               |
| `0bbb476f3` | `70b8fa1d7` | fix(subgraph-service): remove VALID_PROVISION and REGISTERED from cancelIndexingAgreement           |
| `df9a8464e` | `b289023b9` | docs: update audit extracts for PR1301 v02 report                                                   |
| `cb6c45c1a` | `a882efc15` | fix(collector): add gas overhead buffer to callback prechecks (TRST-L-9)                            |
| `3ce581315` | `8a22a87ae` | fix(collector): cap returndata copy in payer callbacks (TRST-M-4)                                   |
| `8e50abda2` | `c7f3c4b79` | docs: add response to TRST-L-10 EIP-7702 callback dispatch (won't fix)                              |
| `6a0ac799d` | `a7a730558` | feat(RAM): drop pair tracking below residual escrow threshold (TRST-M-1, TRST-M-5)                  |
| `f96a7316c` | `c1ba8b5ba` | docs: add responses to TRST-L-6, TRST-R-7 (both won't fix)                                          |
| `35447e703` | `466599894` | docs(audit): acknowledge TRST-R-3 cancelAgreement defensive check                                   |
| `2dd23720f` | `018a31524` | fix(collector): remove dead oldHash guard (TRST-R-6)                                                |
| `c1ef1cb68` | `7a2ceeafc` | fix(collector): non-zero offer types, reserve OFFER_TYPE_NONE=0 sentinel (TRST-R-5)                 |
| `36217930d` | `98acdddfe` | refactor(interfaces): drop unused state and offer-option flags, tighten flag NatSpec (TRST-R-11)    |
| `f32e55024` | `bebf0dbff` | docs(audit): acknowledge trust-boundary correction in TRST-H-4                                      |
| `d2fd36444` | `65a63fa91` | docs(audit): acknowledge reclaim-reason change in TRST-R-13                                         |
| `b61d4415f` | `eb511caa0` | docs(ram): document collector replay-protection assumption (TRST-R-4)                               |
| `02710154d` | `f2441eabc` | docs(ram): document non-retroactive role-change semantics (TRST-R-10)                               |
| `1ee49f232` | `ad829d054` | docs(ram): align pause-escalation prose with whenNotPaused scope (TRST-R-8)                         |
| `9396dbd12` | `c2c15eb74` | docs(collector): note self-authorization auth-check obligation (TRST-R-9)                           |
| `1e5a6b33a` | `229ede684` | fix(subgraph-service): validate update terms against RCAU rate, not stale agreement rate            |
| `8be1aa0c8` | `35ba8639a` | refactor(collector): preparatory helpers, signatures, and version constants                         |
| `cfaf39b21` | `9ad649837` | refactor(collector): drop unreachable agreementId-zero check                                        |
| `35748ff47` | `cb36d5717` | refactor(collector): extract \_requireValidTerms from duplicated validation                         |
| `0ad0be4fd` | `25fd07088` | refactor(collector): split accept logic out of \_validateAndStoreAgreement                          |
| `bfe77547d` | `4fdbdab9b` | refactor(collector): split update apply out of \_validateAndStoreUpdate                             |
| `594d19b07` | `08634a331` | feat(subgraph-service): idempotent accept/update with allocation rebinding                          |
| `885555e91` | `51963df39` | refactor(collector): hoist solhint-disable, idiomatic deadline comparisons                          |
| `572853b01` | `c4c52dea4` | fix(collector): validate offer terms against deadline, not block.timestamp                          |
| `b6adbf16b` | `523171e84` | refactor(collector): extract \_getAgreementDetails/\_versionHashAt helpers                          |
| `8b48437be` | `41caee8fc` | fix(collector): persistent agreement.payer for independent cancellation (TRST-L-7)                  |
| `769b252e5` | `de4997923` | feat(collector): idempotent accept/update/cancel-on-nothing                                         |
| `f96b4ea65` | `600951db2` | feat(collector): add OfferCancelled event for SCOPE_PENDING cancellations                           |
| `c1dfc34af` | `ef0c92e47` | feat(collector): per-version semantics in getAgreementDetails (TRST-L-11)                           |
| `33d2cede2` | `f2361e8b4` | feat(collector): compose cancel/settled flags in getAgreementDetails (TRST-R-12)                    |
| `fe13b1128` | `262d9cc51` | feat(collector): add SCOPE_SIGNED to cancel() for EOA offer revocation (TRST-L-8)                   |
| `b13d9106c` | `258a0f32b` | feat(issuance): expose getIssuanceAllocator on IIssuanceTarget                                      |
| `e4cd9e026` | `d28e30c10` | fix(collector): validate full terms at offer time                                                   |
| `6772545f1` | `1434b1249` | fix(collector): respect deadlines in scoped claim cap                                               |
| `067168e4d` | `740192335` | refactor(collector): collapse redundant state guard in \_getMaxNextClaim                            |
| `757da4174` | `950b23b13` | fix(collector): use dedicated error for invalid offer type in offer()                               |
| `87ee8b6df` | `7c12e2f80` | chore(collector): make module-level constants internal to free EIP-170 headroom                     |
| `f44fc5a4c` | `a8f46322a` | feat(collector): add CONDITION_AGREEMENT_OWNER for ERC-165-validated callback opt-in                |
| `5b07b5833` | `11292cf12` | docs(audits): drop withdrawn TRST findings, retitle and park remaining lows for v03                 |
| `68cd77e5f` | `3af1424fc` | docs(audits): rename parked v03 lows from TRST-L-{old}-{new}.md to final paths                      |
| `f09c2e3ac` | `7911e1de9` | docs(audits): incorporate Trust Security PR1325 v03 fix-review                                      |
| `9b30707b0` | `80c5010cf` | docs(collector): clarify cancel() signer-vs-payer caller for SCOPE_SIGNED (TRST-L-7)                |
| `c21d7f88f` | `8d1653753` | test(collector): assert callbacks receive MAX_PAYER_CALLBACK_GAS with safety margin (TRST-L-8)      |
| `75cae7ceb` | `66dec495f` | docs(collector): document EIP-7702 trust assumption for CONDITION_ELIGIBILITY_CHECK (TRST-L-9)      |
| `c8a5c2150` | `93e7d1cbb` | refactor(ram): use VERSION_CURRENT instead of magic 0 in getAgreementDetails (TRST-R-14)            |
| `a3c73f87e` | `2292e6ae8` | chore(ci): fix flaky CI tests and silence block-timestamp lint                                      |
