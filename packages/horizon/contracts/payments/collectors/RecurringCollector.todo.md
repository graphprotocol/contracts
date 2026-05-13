# RecurringCollector.sol — pending updates

Tracking pending edits noted but deferred to avoid touching contract source until the next maintenance window. When picking up, drop the corresponding entry below as part of the same commit. Line numbers reflect the file at time of writing and will drift.

## Refactor candidates

Code-clarity / micro-bytecode wins. Deployed bytecode is **22,558 / 24,576 bytes** (~2 KB free) after `7c12e2f80` made module-level constants `internal`, so none of these are urgent. Pick up opportunistically — e.g. when the adjacent code is already being touched, or in a focused cleanup pass before a future audit round.

- **Drop `try/catch` around `decodeCollectData`** (`collect()` L213–217). The external-self call + try/catch only converts an ABI-decode panic into `RecurringCollectorInvalidCollectData`. Replace with direct `abi.decode`. Code clarity win + ~150–300 bytes.
- **Hoist callback gas-precheck threshold to a constant.** Three uses at L835, L855, L884 of `(MAX_PAYER_CALLBACK_GAS * 64) / 63 + CALLBACK_GAS_OVERHEAD`. Promote to `private constant MIN_GASLEFT_FOR_CALLBACK`. ~30–60 bytes, plus the threshold becomes inspectable.
- **Extract `_invokePayerCallback` helper.** Three near-identical assembly blocks: eligibility staticcall (L834–851, reads return value), `beforeCollection` call (L854–864), `afterCollection` call (L882–897). Probably two helpers (return-value vs. fire-and-forget). Auditor needs to verify assembly preserved + return-value semantics — defer unless the assembly is being touched anyway. ~200–500 bytes.
- **Inline `_getMaxNextClaim(AgreementData storage)` into `_getMaxNextClaimScoped`.** Single call site (L1321, the Accepted branch). Optimizer at `runs: 100` almost certainly already inlines; explicit removal removes a hop for readers. ~50–150 bytes if not already inlined.

## Offer-keyed terms storage

Architectural restructure considered — defer to next storage-level pass. Split `AgreementData` so identity + terms live in `offers[hash]` (per-version, immutable) and lifecycle lives in `agreements[id]` (per-agreement, mutates). Decode once at store time; all internal reads go through `offers[hash]`. Collapses the three-way dispatch in `_getMaxNextClaimScoped`, folds `_getMaxNextClaim(_a)` into it, removes the double-write in `_validateAndStoreAgreement` / `_offerNew` (agreement-storage terms + `rcaOffers` blob), simplifies `_validateAndStoreUpdate`. Preserves `offers[hash].data` / `offerType` for API compat. A synthesizing getter keeps `getAgreement(id)`'s return shape stable. Prototype preserved at `archive/indexing-payments-management-unified-terms-storage` (`a9c2737038`) — see "Related archived branches" below.

## Related archived branches

Broader RecurringCollector / RAM refactors explored on parallel branches and preserved as tags rather than merged. Useful context when revisiting the architecture:

- `archive/indexing-payments-management-unified-terms-storage` (`a9c2737038`) — full TRST-L-11 storage refactor: single `terms[hash]` mapping replaces `rcaOffers`/`rcauOffers`, `AgreementData` slimmed from 7 to 5 slots with `pendingTermsHash` pointer, `_storeTerms` as the only validated write gate; the 3-way state dispatch in max-claim collapses into `_activeClaimWindow`/`_maxClaimForTerms`, NEW path shared between `offer(NEW)` and `accept()`. This is the prototype of the "Offer-keyed terms storage" sketch above. Superseded by `-2-light`, which kept the existing storage and addressed TRST-L-11 minimally via per-version semantics in `getAgreementDetails`.
- `archive/indexing-payments-management-collector-led-lifecycle` — full RAM/Collector boundary inversion (audit-fix PR1301 round): payer interacts with the Collector first via a two-phase offer/accept flow, Collector then notifies the data service via `acceptAgreement` / `afterAgreementStateChange` callbacks (with `MAX_CALLBACK_GAS` cap and `PayerCallbackFailed` events); ECDSA signing and `Authorizable` dropped from the Collector. Generic agreement methods moved from `IRecurringCollector` to `IAgreementCollector`; `OfferResult`/`AgreementVersion` unified into a single `AgreementDetails`; `Pair` dropped from RAM's public API. Superseded by `-reduced`, which preserved the data-service-as-orchestrator pattern and instead tightened internals (collector→provider storage hierarchy, stored-hash auth, scoped claims, pausable/upgradeable Collector).
