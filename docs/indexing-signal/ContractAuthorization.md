# Contract-Based RCA Authorization

Analysis of whether IndexingSignal can create RCAs on-chain, replacing off-chain Dipper signing.

## Current State

RecurringCollector and Authorizable are **not deployed** to any network. No Ignition modules exist. Changes are low-cost.

### How RCA Signing Works Today

1. **Authorization**: Payer calls `RC.authorizeSigner(signer, proofDeadline, proof)`. The `proof` is an ECDSA signature from `signer` over `(chainId, RC address, "authorizeSignerProof", deadline, payer)`. Authorizable stores `authorizations[signer].authorizer = payer`.

2. **RCA creation**: Authorized signer produces EIP712 ECDSA signature over the RCA struct (deadline, endsAt, payer, dataService, serviceProvider, token limits, timing, nonce, metadata).

3. **Acceptance**: DataService (SubgraphService) calls `RC.accept(signedRCA)`. RC recovers signer via `ECDSA.recover()`, checks `_isAuthorized(rca.payer, signer)`, stores agreement.

Both steps use `ECDSA.recover()` — only EOAs with private keys can participate. Contracts cannot produce ECDSA signatures.

### Two ECDSA Gates

| Gate | Where | What's Signed |
|------|-------|---------------|
| Authorization proof | `Authorizable._verifyAuthorizationProof()` | `(chainId, RC, "authorizeSignerProof", deadline, authorizer)` |
| RCA signature | `RC._recoverRCASigner()` → `_requireAuthorizedRCASigner()` | EIP712 hash of full RCA struct |

Both must be unlocked for a contract to create RCAs.

## The Restriction

The current design **assumes** RCA creation happens off-chain. This is baked in at the protocol level — there's no option for on-chain creation, even where it would be natural (like IS reacting to signal events).

This isn't a security requirement. It's an implementation choice: ECDSA was simpler and sufficient for the original use case (bilateral agreements between known parties). But it makes the authorization model unnecessarily narrow.

## Contract Authorization: Different Trust Model, Not Weaker

| | ECDSA (current) | Contract-based |
|---|---|---|
| **Trust basis** | Private key custody | Contract logic + governance |
| **Authorization** | "Holder of key K authorized this" | "Contract C's code authorized this" |
| **Auditability** | Key management is opaque | Logic is on-chain, auditable |
| **Revocation** | Thaw → revoke signer | Same (contract is the signer) |
| **Attack surface** | Key compromise | Contract bug or governance attack |

For IS specifically: the contract's authorization logic would be governed (only callers with appropriate roles can trigger agreement creation). The authorization chain is: governance grants role → role holder calls IS → IS creates RCA → RC accepts. Every step is on-chain and auditable.

## Proposed Change: Contract Approver Support in Authorizable

### Design

Add a parallel authorization path for contract approvers. When the signer is a contract, skip ECDSA proof — instead verify the contract confirms the authorization via a callback.

**Key insight from user**: `isValidSignature` (EIP-1271's name) is misleading here. IS isn't validating a signature — it's confirming it authorized an agreement. The naming should reflect what's actually happening.

### Option A: Custom Interface (Recommended)

```solidity
/// @notice Interface for contracts that can act as authorized agreement creators
interface IContractApprover {
    /// @notice Confirms this contract authorized the given signer authorization
    /// @param authorizer The payer authorizing this contract
    /// @return magic bytes4(keccak256("isAuthorizedSigner(address)"))
    function isAuthorizedSigner(address authorizer) external view returns (bytes4);
}
```

In Authorizable:

```solidity
function authorizeSigner(address signer, uint256 proofDeadline, bytes calldata proof) external {
    require(authorizations[signer].authorizer == address(0), ...);

    if (signer.code.length > 0) {
        // Contract approver: verify via callback
        bytes4 magic = IContractApprover(signer).isAuthorizedSigner(msg.sender);
        require(magic == IContractApprover.isAuthorizedSigner.selector, AuthorizableInvalidSignerProof());
    } else {
        // EOA signer: verify via ECDSA proof (existing path)
        _verifyAuthorizationProof(proof, proofDeadline, signer);
    }

    authorizations[signer].authorizer = msg.sender;
    emit SignerAuthorized(msg.sender, signer);
}
```

For RCA signing, RC would similarly check if the recovered "signer" is a contract:

```solidity
function _requireAuthorizedRCASigner(SignedRCA memory _signedRCA) private view returns (address) {
    bytes32 messageHash = _hashRCA(_signedRCA.rca);

    // Try ECDSA recovery first
    address signer = ECDSA.recover(messageHash, _signedRCA.signature);

    // If recovered address is a contract, verify via callback instead
    if (signer.code.length > 0) {
        // For contract approvers, the "signature" encodes the contract address
        // The contract must confirm it created this agreement
        address contractApprover = abi.decode(_signedRCA.signature, (address));
        require(
            IContractApprover(contractApprover).isAuthorizedAgreement(messageHash),
            RecurringCollectorInvalidSigner()
        );
        signer = contractApprover;
    }

    require(_isAuthorized(_signedRCA.rca.payer, signer), RecurringCollectorInvalidSigner());
    return signer;
}
```

**Problem**: ECDSA.recover on a non-ECDSA signature returns a garbage address, not a contract. The "try ECDSA first" approach doesn't cleanly distinguish contract vs EOA signatures.

### Option B: Separate Accept Path (Cleaner)

Instead of overloading the signature field, add a distinct method:

```solidity
/// @notice Accept an RCA where the signer is an authorized contract
/// @dev Contract must be authorized via authorizeSigner() and confirm via callback
function acceptFromContract(
    RecurringCollectionAgreement calldata rca,
    address contractApprover
) external returns (bytes16) {
    require(msg.sender == rca.dataService, ...);
    require(contractApprover.code.length > 0, ...);
    require(_isAuthorized(rca.payer, contractApprover), ...);

    // Verify the contract actually created this agreement
    bytes32 agreementHash = _hashRCA(rca);
    bytes4 magic = IContractApprover(contractApprover).isAuthorizedAgreement(agreementHash);
    require(magic == IContractApprover.isAuthorizedAgreement.selector, ...);

    // Same acceptance logic as accept()
    ...
}
```

This avoids overloading the signature semantics entirely.

### Option C: EIP-1271 (Standard but Misnamed)

Use EIP-1271's `isValidSignature(bytes32 hash, bytes signature)` standard interface. All EIP-1271-compatible wallets (Safe, etc.) would work automatically.

```solidity
import { IERC1271 } from "@openzeppelin/contracts/interfaces/IERC1271.sol";

// In _recoverRCASigner or a new validation function:
if (signer.code.length > 0) {
    require(
        IERC1271(signer).isValidSignature(messageHash, _signedRCA.signature) == IERC1271.isValidSignature.selector,
        RecurringCollectorInvalidSigner()
    );
}
```

**Downside**: As noted, `isValidSignature` is misleading for what IS does. IS isn't validating an external signature — it's confirming its own authorization. But it's a widely-recognized standard.

## Recommendation

**Option B** (separate `acceptFromContract`) with a custom `IContractApprover` interface.

Rationale:
- Cleanest separation: EOA path unchanged, contract path explicit
- No ambiguity in signature parsing
- Interface name reflects what's happening (`isAuthorizedAgreement`, not `isValidSignature`)
- Authorization gate in Authorizable uses `isAuthorizedSigner` — clear intent
- EIP-1271 compatibility can be added later if needed (wrapper that delegates)

### IContractApprover Interface

```solidity
interface IContractApprover {
    /// @notice Confirms this contract is willing to be authorized as signer for the given authorizer
    function isAuthorizedSigner(address authorizer) external view returns (bytes4);

    /// @notice Confirms this contract authorized the creation of the given agreement
    function isAuthorizedAgreement(bytes32 agreementHash) external view returns (bytes4);
}
```

## IS Flow With Contract Authorization

```
1. Governance authorizes IS as signer for depositor:
   depositor.authorizeSigner(IS_address, ...)
     → Authorizable checks IS.isAuthorizedSigner(depositor) → magic value
     → stores authorization

2. Signal event triggers agreement creation:
   Dipper calls IS.createAgreement(indexer, subgraphDeploymentID, params)
     → IS constructs RCA struct
     → IS stores agreementHash in pending set
     → IS calls SS.acceptIndexingAgreement(rca, IS_address)
       → SS calls RC.acceptFromContract(rca, IS_address)
         → RC calls IS.isAuthorizedAgreement(hash) → magic value
         → Agreement accepted

3. Collection proceeds normally:
   SS → IA → RC → EscrowRouter → IS → GraphPayments
```

## What This Enables

- IS reacts to signal deposits/indexer set changes by creating agreements on-chain
- No off-chain signing infrastructure needed for the IS path
- Dipper still exists but as a trigger (calling IS functions), not as a key holder
- EOA path completely unchanged — existing bilateral agreements work identically

## What Changes

| Component | Change | Impact |
|-----------|--------|--------|
| `IAuthorizable` | No change (interface stays the same) | None |
| `Authorizable` | `authorizeSigner()` checks `code.length`, calls `IContractApprover` for contracts | Additive |
| `IRecurringCollector` | Add `acceptFromContract()` | Additive |
| `RecurringCollector` | Implement `acceptFromContract()` sharing logic with `accept()` | Moderate |
| `IContractApprover` | New interface | New |
| `IndexingSignal` | Implement `IContractApprover`, add agreement creation logic | Moderate |

Neither RC nor Authorizable are deployed, so no migration concerns.

## Navigation

- [Status.md](./Status.md)
- [CollectionContext.md](./CollectionContext.md)
- [Disconnects.md](./Disconnects.md) — see #7 (RCA creation)
