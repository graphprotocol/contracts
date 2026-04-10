# Contract-Based RCA Authorization

Analysis of whether IndexingSignal can create RCAs on-chain, replacing off-chain Dipper signing.

## Current State

RecurringCollector and Authorizable are **not deployed** to any network. No Ignition modules exist. Changes are low-cost.

### How RCA Signing Works Today

1. **Authorization**: Payer calls `RC.authorizeSigner(signer, proofDeadline, proof)`. The `proof` is an ECDSA signature from `signer` over `(chainId, RC address, "authorizeSignerProof", deadline, payer)`. Authorizable stores `authorizations[signer].authorizer = payer`.

2. **RCA creation**: Authorized signer produces EIP712 ECDSA signature over the RCA struct (deadline, endsAt, payer, dataService, serviceProvider, token limits, timing, nonce, metadata).

3. **Acceptance**: DataService (SubgraphService) calls `RC.accept(signedRCA)`. RC recovers signer via `ECDSA.recover()`, checks `_isAuthorized(rca.payer, signer)`, stores agreement.

Both steps use `ECDSA.recover()` — only EOAs with private keys can participate. Contracts cannot produce ECDSA signatures.

### The Two ECDSA Gates

| Gate                | Where                                                      | What's Signed                                                 |
| ------------------- | ---------------------------------------------------------- | ------------------------------------------------------------- |
| Authorization proof | `Authorizable._verifyAuthorizationProof()`                 | `(chainId, RC, "authorizeSignerProof", deadline, authorizer)` |
| RCA signature       | `RC._recoverRCASigner()` → `_requireAuthorizedRCASigner()` | EIP712 hash of full RCA struct                                |

Both must be bypassed for a contract to create RCAs.

## Contract Authorization: Different Trust Model, Not Weaker

|                    | ECDSA (current)                   | Contract-based                      |
| ------------------ | --------------------------------- | ----------------------------------- |
| **Trust basis**    | Private key custody               | Contract logic + governance         |
| **Authorization**  | "Holder of key K authorized this" | "Contract C's code authorized this" |
| **Auditability**   | Key management is opaque          | Logic is on-chain, auditable        |
| **Revocation**     | Thaw → revoke signer              | Same (contract is the signer)       |
| **Attack surface** | Key compromise                    | Contract bug or governance attack   |

For IS specifically: the contract's authorization logic is governed (only callers with appropriate roles can trigger agreement creation). The authorization chain is: governance grants role → role holder calls IS → IS creates RCA → RC accepts. Every step is on-chain and auditable.

## Options Considered

### Option A: Overload ECDSA Recovery

Add code.length checks to both Authorizable.authorizeSigner() and RC.\_requireAuthorizedRCASigner(). **Rejected** — ECDSA.recover on non-ECDSA signature returns garbage address. Can't cleanly distinguish contract vs EOA.

### Option B: Separate Accept Path (Chosen)

Add `RC.acceptFromContract(rca, contractApprover)` — distinct method, no signature overloading. Contract implements `IContractApprover.isAuthorizedAgreement(hash)` callback.

### Option C: EIP-1271

Use standard `isValidSignature`. **Rejected** — misleading name. IS isn't validating a signature, it's confirming it authorized an agreement.

## What Was Implemented

Option B, but simplified from the original proposal:

### IContractApprover (single function)

```solidity
interface IContractApprover {
  function isAuthorizedAgreement(bytes32 agreementHash) external view returns (bytes4);
}
```

`isAuthorizedSigner` was removed — per-payer Authorizable setup is unnecessary. The contract's callback _is_ the authorization.

### RC.acceptFromContract (no \_isAuthorized check)

```solidity
function acceptFromContract(
    RecurringCollectionAgreement calldata rca,
    address contractApprover
) external returns (bytes16) {
    require(contractApprover.code.length > 0, ...);
    bytes32 agreementHash = _hashRCA(rca);
    require(
        IContractApprover(contractApprover).isAuthorizedAgreement(agreementHash) ==
            IContractApprover.isAuthorizedAgreement.selector, ...
    );
    return _validateAndStoreAgreement(rca);
}
```

No `_isAuthorized(rca.payer, contractApprover)` check. The contract's `isAuthorizedAgreement` callback is the only gate. The trust chain is:

- `_validateAndStoreAgreement` checks `msg.sender == rca.dataService`
- DataService (SS) has its own access control (allocation validation, etc.)
- The contract approver confirms the specific agreement hash
- The contract approver's `prepareAgreement()` has role-based access control

### Authorizable unchanged

No code.length branch. The original plan to modify Authorizable was reverted — it was solving a problem that doesn't exist when the contract approver path bypasses Authorizable entirely.

### What changed vs original proposal

| Proposed                                                                | Implemented                  | Why                                                          |
| ----------------------------------------------------------------------- | ---------------------------- | ------------------------------------------------------------ |
| `IContractApprover` with `isAuthorizedSigner` + `isAuthorizedAgreement` | Only `isAuthorizedAgreement` | Per-payer auth unnecessary — contract callback is sufficient |
| Authorizable code.length branch                                         | No change to Authorizable    | acceptFromContract bypasses Authorizable entirely            |
| `_isAuthorized` check in acceptFromContract                             | Removed                      | Same reason — contract path doesn't need Authorizable        |
| Two-function interface                                                  | Single-function interface    | Simpler, only one gate needed                                |

## IS Flow With Contract Authorization

```
1. Governance setup:
   - EscrowRouter.setEscrowOverride(IS_address, IS) — routes collection to IS
   - IS grants INDEXER_SET_OPERATOR_ROLE to operator

2. Operator prepares agreement:
   operator calls IS.prepareAgreement(subgraphID, indexer, agreementHash, encodedRCA)
     → IS validates agreement escrow has signal for (subgraph, indexer)
     → IS stores pendingAgreements[hash] = true
     → IS emits AgreementPrepared(subgraph, indexer, hash, encodedRCA)

3. Indexer accepts:
   indexer calls SS.acceptIndexingAgreementFromContract(allocationId, rca, IS_address)
     → SS validates allocation, metadata, subgraph match
     → SS calls RC.acceptFromContract(rca, IS_address)
       → RC verifies IS_address.code.length > 0
       → RC calls IS.isAuthorizedAgreement(hash) → magic value
       → RC calls _validateAndStoreAgreement(rca) → agreement stored

4. Collection:
   SS → IndexingAgreement → RC.collect() → EscrowRouter.collect()
     → EscrowRouter sees override for IS_address → delegates to IS
     → IS._collectVirtual(subgraph, indexer, amount) → mints GRT
     → IS distributes via GraphPayments
```

## What Changes

| Component                     | Change                                                                               | Impact   |
| ----------------------------- | ------------------------------------------------------------------------------------ | -------- |
| `IAuthorizable`               | No change                                                                            | None     |
| `Authorizable`                | No change                                                                            | None     |
| `IRecurringCollector`         | Add `acceptFromContract()`                                                           | Additive |
| `RecurringCollector`          | Implement `acceptFromContract()` with shared `_validateAndStoreAgreement()`          | Moderate |
| `IContractApprover`           | New interface (single function)                                                      | New      |
| `ISubgraphService`            | Add `acceptIndexingAgreementFromContract()`                                          | Additive |
| `SubgraphService`             | Implement `acceptIndexingAgreementFromContract()`                                    | Additive |
| `IndexingAgreement` (library) | Add `acceptFromContract()` with shared `_validateAndPrepareAccept()`                 | Moderate |
| `IndexingSignal`              | Implement `IContractApprover`, add `prepareAgreement()` / `clearPreparedAgreement()` | Moderate |

Neither RC nor Authorizable are deployed, so no migration concerns.

## Open Questions

**RC authorization gap**: `acceptFromContract` has no check on _who_ the contractApprover is — any contract that returns the magic value can approve agreements. The current trust relies on:

- SS access control (only valid allocations can call)
- The contract approver's own internal logic (IS uses role-based `prepareAgreement`)

Should RC have a governance whitelist of approved contract approvers? The `_validateAndStoreAgreement` check that `msg.sender == rca.dataService` limits exposure (only the data service can trigger acceptance), but the data service can pass any contractApprover address.

## Navigation

- [Status.md](./Status.md)
- [CollectionContext.md](./CollectionContext.md)
- [Disconnects.md](./Disconnects.md)
