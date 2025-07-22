# TRST-M-1 Engineering Tasks

**Issue**: Fix TYPEHASH Type Mismatch in RecurringCollector  
**Created**: 2025-07-22  
**Status**: Pending Implementation

## High Priority Tasks

### 1. Code Fix - TYPEHASH Constant Update
**File**: `packages/horizon/contracts/payments/collectors/RecurringCollector.sol:36-39`

- [ ] Change `uint256 deadline` to `uint64 deadline` in EIP712_RCAU_TYPEHASH
- [ ] Change `uint256 endsAt` to `uint64 endsAt` in EIP712_RCAU_TYPEHASH
- [ ] Verify exact string format matches struct definition

**Expected Change**:
```diff
bytes32 public constant EIP712_RCAU_TYPEHASH =
    keccak256(
-       "RecurringCollectionAgreementUpdate(bytes16 agreementId,uint256 deadline,uint256 endsAt,uint256 maxInitialTokens,uint256 maxOngoingTokensPerSecond,uint32 minSecondsPerCollection,uint32 maxSecondsPerCollection,bytes metadata)"
+       "RecurringCollectionAgreementUpdate(bytes16 agreementId,uint64 deadline,uint64 endsAt,uint256 maxInitialTokens,uint256 maxOngoingTokensPerSecond,uint32 minSecondsPerCollection,uint32 maxSecondsPerCollection,bytes metadata)"
    );
```

### 2. Test Execution & Validation
**Location**: `packages/horizon/`

- [ ] Run Horizon package test suite: `cd packages/horizon && pnpm test`
- [ ] Verify no test regressions or failures
- [ ] Test signature verification for RCAU updates works correctly
- [ ] Ensure existing RCA (non-update) functionality remains unaffected

**Test Commands**:
```bash
cd packages/horizon
pnpm test                    # Run all Forge tests
pnpm test:deployment         # Run Hardhat deployment tests  
pnpm test:integration        # Run integration tests
```

## Medium Priority Tasks

### 3. Build & Compilation Verification
**Location**: Root directory and `packages/horizon/`

- [ ] Run build process: `pnpm build` (from root)
- [ ] Ensure no compilation errors in Horizon package
- [ ] Verify contract size analysis passes: `cd packages/horizon && pnpm build`

### 4. Code Quality & Verification
**Files**: `packages/horizon/contracts/payments/collectors/RecurringCollector.sol`

- [ ] Verify TYPEHASH string exactly matches struct field types in IRecurringCollector.sol:95-104
- [ ] Run linting: `cd packages/horizon && pnpm lint`
- [ ] Check that no other TYPEHASH constants have similar issues

### 5. Documentation & Review
- [ ] Update CLAUDE.md if necessary (likely not needed for this fix)
- [ ] Prepare commit message following repository conventions
- [ ] Review change against audit recommendation

## Implementation Order

1. **Code Fix** (Tasks 1) - Update TYPEHASH constant
2. **Testing** (Tasks 2) - Validate functionality
3. **Build Verification** (Tasks 3) - Ensure compilation success
4. **Final Verification** (Tasks 4-5) - Code quality and documentation

## Success Criteria

- [ ] TYPEHASH string matches struct definition exactly
- [ ] All tests pass without regression
- [ ] Build completes successfully
- [ ] Signature verification works for RCAU updates
- [ ] No impact on existing functionality

## Risk Mitigation

- **Test Coverage**: Comprehensive testing before and after the fix
- **Isolation**: Change affects only RCAU signature verification
- **Reversibility**: Simple change that can be easily reverted if issues arise

## Post-Implementation

- [ ] Run final test suite
- [ ] Create commit with appropriate audit reference
- [ ] Mark audit issue as resolved
- [ ] Clean up temporary todo files (this file can be deleted after completion)

---

**Note**: This is a temporary engineering task list. Delete this file after successful implementation and testing.