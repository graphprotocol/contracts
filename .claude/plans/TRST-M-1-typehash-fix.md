# TRST-M-1: Fix TYPEHASH Type Mismatch in RecurringCollector

**Audit Issue**: TRST-M-1 Wrong TYPEHASH string is used for agreement updates, limiting functionality  
**Category**: Typo errors  
**Source**: RecurringCollector.sol  
**Status**: Open  
**Created**: 2025-07-22

## Issue Summary

The `RecurringCollector` contract has a critical type mismatch in the EIP-712 TYPEHASH for `RecurringCollectionAgreementUpdate`. The struct definition uses `uint64` for `deadline` and `endsAt` fields, but the TYPEHASH string incorrectly declares them as `uint256`.

This prevents off-chain parties from generating valid signatures for agreement updates, effectively breaking the update functionality.

## Root Cause Analysis

### Struct Definition
**File**: `packages/horizon/contracts/interfaces/IRecurringCollector.sol:95-104`

```solidity
struct RecurringCollectionAgreementUpdate {
    bytes16 agreementId;
    uint64 deadline;        // ← uint64 type
    uint64 endsAt;          // ← uint64 type
    uint256 maxInitialTokens;
    uint256 maxOngoingTokensPerSecond;
    uint32 minSecondsPerCollection;
    uint32 maxSecondsPerCollection;
    bytes metadata;
}
```

### TYPEHASH Definition
**File**: `packages/horizon/contracts/payments/collectors/RecurringCollector.sol:36-39`

```solidity
bytes32 public constant EIP712_RCAU_TYPEHASH =
    keccak256(
        "RecurringCollectionAgreementUpdate(bytes16 agreementId,uint256 deadline,uint256 endsAt,uint256 maxInitialTokens,uint256 maxOngoingTokensPerSecond,uint32 minSecondsPerCollection,uint32 maxSecondsPerCollection,bytes metadata)"
        //                                                      ^^^^^^^ wrong  ^^^^^^^ wrong
    );
```

### Impact
1. **Signature Verification Failure**: Off-chain generated signatures using correct struct types fail on-chain verification
2. **Broken Update Functionality**: Agreement updates cannot be successfully processed
3. **Protocol Integration Issues**: External parties cannot interact with the update mechanism

## Proposed Solution

### Code Change Required
**File**: `packages/horizon/contracts/payments/collectors/RecurringCollector.sol:36-39`

**Current Code**:
```solidity
bytes32 public constant EIP712_RCAU_TYPEHASH =
    keccak256(
        "RecurringCollectionAgreementUpdate(bytes16 agreementId,uint256 deadline,uint256 endsAt,uint256 maxInitialTokens,uint256 maxOngoingTokensPerSecond,uint32 minSecondsPerCollection,uint32 maxSecondsPerCollection,bytes metadata)"
    );
```

**Fixed Code**:
```solidity
bytes32 public constant EIP712_RCAU_TYPEHASH =
    keccak256(
        "RecurringCollectionAgreementUpdate(bytes16 agreementId,uint64 deadline,uint64 endsAt,uint256 maxInitialTokens,uint256 maxOngoingTokensPerSecond,uint32 minSecondsPerCollection,uint32 maxSecondsPerCollection,bytes metadata)"
    );
```

### Changes Summary
- Change `uint256 deadline` → `uint64 deadline` in TYPEHASH
- Change `uint256 endsAt` → `uint64 endsAt` in TYPEHASH

## Risk Assessment

### Risk Level: **LOW**
- **Type**: Pure bug fix aligning TYPEHASH with struct definition
- **Scope**: Limited to signature verification for RCAU updates
- **Backward Compatibility**: May invalidate any existing signed RCAU updates (if any exist)

### Considerations
1. **No Behavioral Changes**: This fixes intended functionality rather than changing behavior
2. **Deployment Impact**: New deployments will have correct signature verification
3. **Existing Deployments**: Will continue to have broken update functionality until upgraded

## Testing Requirements

### Unit Tests
1. **Signature Generation**: Test off-chain signature generation matches on-chain verification
2. **Type Consistency**: Verify TYPEHASH matches struct field types exactly
3. **Hash Consistency**: Ensure `hashRCAU()` function produces expected results

### Integration Tests
1. **Update Flow**: Test complete agreement update workflow
2. **Signature Recovery**: Verify `recoverRCAUSigner()` works correctly
3. **EIP-712 Compliance**: Ensure proper EIP-712 standard compliance

### Regression Tests
1. **Existing RCA Functionality**: Ensure RCA (non-update) signatures still work
2. **Collection Flow**: Verify payment collection remains unaffected
3. **Agreement Management**: Test accept/cancel operations work correctly

## Implementation Steps

1. **Code Fix**: Update TYPEHASH constant in RecurringCollector.sol
2. **Test Validation**: Run comprehensive test suite
3. **Documentation**: Update any relevant documentation
4. **Review**: Security review of the change
5. **Deployment**: Deploy updated contract

## Verification Checklist

- [ ] TYPEHASH string matches struct field types exactly
- [ ] All tests pass (unit, integration, regression)
- [ ] Off-chain signature generation works with on-chain verification
- [ ] EIP-712 compliance maintained
- [ ] No impact on existing RCA functionality
- [ ] Documentation updated if needed

## Related Files

- `packages/horizon/contracts/payments/collectors/RecurringCollector.sol` (main fix)
- `packages/horizon/contracts/interfaces/IRecurringCollector.sol` (struct definition)
- Relevant test files in `packages/horizon/test/`

## Audit Reference

**Original Audit Finding**:
> The RecurringCollector uses the following structure for an agreement update... However, the structure EIP-712 TYPEHASH is defined below... The type mismatch would cause parties producing an agreement update hash from the correct structure to fail.

**Recommended Mitigation**: 
> Use the same types as the struct definition.