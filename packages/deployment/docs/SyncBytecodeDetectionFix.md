# Sync Bytecode Detection Fix

## Issues Identified

### Issue 1: Local Bytecode Changes Ignored

**Problem**: Deploy incorrectly reported "implementation unchanged" when local bytecode had actually changed.

**Evidence**:

```
Local artifact:    0x9c25d2f93e6a2a34cc19d00224872e288a8392d5d99b2df680b7e978d148d450
On-chain:          0xfafdeb48fae37e277e007e7b977f3cd124065ac1c27ed5208982c2965cf07008
Address book:      0x4805a902756c8f4421c2a2710dcc76885ffd01d7777bbe6cab010fe9748b7efa
```

All three hashes are different, yet deploy said "unchanged", meaning local changes would be ignored.

### Issue 2: Confusing Sync Behavior

**Problem**: Sync showed "code changed" but didn't handle the state appropriately:

1. Showed △ (code changed) indicator
2. But didn't sync implementation to rocketh
3. Saved proxy record with wrong bytecode
4. This confused rocketh's change detection

## Root Causes

### Cause 1: Missing/Stale Bytecode Hash

When the address book had no bytecode hash (or wrong hash):

- Sync detected "code changed" ([sync-utils.ts:475-477](../lib/sync-utils.ts#L475-L477))
- But only synced to rocketh if hash matched ([sync-utils.ts:653](../lib/sync-utils.ts#L653))
- This left rocketh with incomplete/wrong state

### Cause 2: Wrong Bytecode Stored for Proxy

The sync step saved the **implementation's bytecode** under the **proxy's deployment record**:

- Lines 508-532: Created proxy record with implementation artifact bytecode
- This is wrong - proxy should have its own bytecode (or none)
- Rocketh then compared wrong bytecode and gave incorrect results

## Fixes Applied

### Fix 1: Hash Comparison and Stale Record Cleanup ([sync-utils.ts:645-679](../lib/sync-utils.ts#L645-L679))

When sync processes an implementation:

1. **Compare local artifact hash to address-book-stored hash**
2. **If hashes match**: sync the implementation record to rocketh normally
3. **If hashes don't match**: overwrite any stale rocketh record with empty bytecode, forcing a fresh deployment

   ```typescript
   if (storedHash && localHash) {
     hashMatches = storedHash === localHash
   }

   // Clean up stale rocketh record if hash doesn't match
   if (!hashMatches && existingImpl) {
     // Overwrite stale record with empty bytecode - forces fresh deployment
     await env.save(`${spec.name}_Implementation`, {
       address: existingImpl.address,
       bytecode: '0x',
       deployedBytecode: undefined,
       ...
     })
   }
   ```

This ensures rocketh correctly detects when local code has changed and triggers a new deployment.

### Fix 2: Don't Store Wrong Bytecode for Proxy ([sync-utils.ts:508-532](../lib/sync-utils.ts#L508-L532))

Changed proxy record creation to **NOT include implementation bytecode**:

```typescript
// Before:
bytecode: artifact.bytecode // ← Wrong! This is implementation bytecode
deployedBytecode: artifact.deployedBytecode

// After:
bytecode: '0x' // ← Correct! Proxy record doesn't need bytecode
deployedBytecode: undefined
```

This ensures rocketh only uses implementation bytecode for the actual implementation record.

## Expected Behavior After Fix

### Scenario 1: Local Matches Address Book

When local artifact hash matches the stored hash, sync proceeds normally and rocketh
correctly reports the implementation as unchanged.

### Scenario 2: Local Code Changed

**Before**:

```
△   SubgraphService @ 0xc24A3dAC... → 0x2af1b0ed... (code changed)
✓ SubgraphService implementation unchanged  ← WRONG!
```

**After**:

```
△   SubgraphService @ 0xc24A3dAC... → 0x2af1b0ed... (local code changed)
📋 New SubgraphService implementation deployed: 0x...  ← NEW!
   Storing as pending implementation...
```

Deploy correctly detects the change and deploys new implementation.

### Scenario 3: Stale Rocketh Record

When the hash doesn't match and a stale rocketh record exists, sync overwrites it
with empty bytecode. This forces the next deploy to create a fresh implementation
record rather than incorrectly reporting "unchanged".

## Testing

To verify the fix works:

```bash
# Clean build
cd packages/deployment
pnpm build

# Run sync - should now show clearer messages
npx hardhat deploy --skip-prompts --network arbitrumSepolia --tags sync

# Run deploy - should correctly detect local changes
npx hardhat deploy --skip-prompts --network arbitrumSepolia --tags SubgraphService
```

## Migration Notes

- **No manual migration needed** - stale rocketh records are cleaned up automatically
- First sync after fix will detect hash mismatches and clear stale records
- Subsequent deploys will create fresh implementation records

## Related Files

- [sync-utils.ts](../lib/sync-utils.ts) - Main fix implementation
- [deploy-implementation.ts](../lib/deploy-implementation.ts) - Deploy logic (unchanged, now works correctly)
- [check-bytecode.ts](../scripts/check-bytecode.ts) - Diagnostic script for manual verification
