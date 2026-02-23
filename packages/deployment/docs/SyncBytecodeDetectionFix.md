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

### Fix 1: Auto-Heal Bytecode Hash ([sync-utils.ts:641-683](../lib/sync-utils.ts#L641-L683))

When sync detects missing/mismatched bytecode hash:

1. **Fetch on-chain bytecode** from the implementation address
2. **Compare three versions**: local artifact, on-chain, address book
3. **Auto-heal** if local matches on-chain:

   ```typescript
   if (localHash === onChainHash) {
     // Update address book with verified hash
     hashMatches = true
     shouldSync = true
     syncNotes.push('hash verified' or 'hash healed')
   }
   ```

4. **Show clear status** if they differ:
   - `local code changed` - local differs from on-chain (ready to deploy)
   - `impl state unclear` - all three hashes differ (investigation needed)
   - `impl unverified` - couldn't fetch on-chain bytecode

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

### Scenario 1: Local Matches On-Chain (Hash Missing)

**Before**:

```
△   SubgraphService @ 0xc24A3dAC... → 0x2af1b0ed... (code changed)
✓ SubgraphService implementation unchanged  ← WRONG!
```

**After**:

```
△   SubgraphService @ 0xc24A3dAC... → 0x2af1b0ed... (hash verified)
✓ SubgraphService implementation unchanged  ← Correct (hash now matches)
```

Address book is auto-healed with correct bytecode hash.

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

### Scenario 3: Complex State (All Different)

**Before**:

```
△   SubgraphService @ 0xc24A3dAC... → 0x2af1b0ed... (code changed)
```

**After**:

```
△   SubgraphService @ 0xc24A3dAC... → 0x2af1b0ed... (impl state unclear)
```

Clear warning that investigation needed - all three hashes differ.

## Testing

To verify the fix works:

```bash
# Clean build
cd packages/deployment
pnpm build

# Run sync - should now show clearer messages
npx hardhat deploy --skip-prompts --network arbitrumSepolia --tags sync

# Run deploy - should correctly detect local changes
npx hardhat deploy --skip-prompts --network arbitrumSepolia --tags subgraph-service
```

## Migration Notes

- **No manual migration needed** - the fix auto-heals address books
- First sync after fix will fetch on-chain bytecode and update hashes
- Address book will be updated in place with correct metadata
- Subsequent syncs will use the healed hashes

## Related Files

- [sync-utils.ts](../lib/sync-utils.ts) - Main fix implementation
- [deploy-implementation.ts](../lib/deploy-implementation.ts) - Deploy logic (unchanged, now works correctly)
- [check-bytecode.ts](../scripts/check-bytecode.ts) - Diagnostic script for manual verification
