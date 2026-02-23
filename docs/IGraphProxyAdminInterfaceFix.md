# IGraphProxyAdmin Interface Signature Fix

## Issue

The IGraphProxyAdmin interface in `packages/interfaces/contracts/contracts/upgrades/IGraphProxyAdmin.sol` had incorrect function signatures that didn't match the actual GraphProxyAdmin contract implementation.

### Understanding the Two Different `acceptProxy` Methods

There are **two different contracts** with similar-sounding methods, which can cause confusion:

1. **GraphUpgradeable** (base class for implementation contracts):

   ```solidity
   // Called ON the implementation contract
   function acceptProxy(IGraphProxy _proxy) external onlyProxyAdmin(_proxy) {
     _proxy.acceptUpgrade();
   }
   ```

   This is inherited by implementation contracts like RewardsManager, Staking, etc.

2. **GraphProxyAdmin** (admin contract that manages upgrades):

   ```solidity
   // Called ON the admin contract, which then calls the implementation
   function acceptProxy(GraphUpgradeable _implementation, IGraphProxy _proxy) external onlyGovernor {
     _implementation.acceptProxy(_proxy);
   }
   ```

   This is the admin contract that orchestrates upgrades.

**IGraphProxyAdmin represents the second one** - the GraphProxyAdmin admin contract, not the GraphUpgradeable base class.

### Incorrect Interface (Before)

The interface mistakenly used the single-parameter signature from GraphUpgradeable:

```solidity
function acceptProxy(IGraphProxy proxy) external;

function acceptProxyAndCall(IGraphProxy proxy, bytes calldata data) external;
```

### Actual GraphProxyAdmin Implementation

From `packages/contracts/contracts/upgrades/GraphProxyAdmin.sol`:

```solidity
function acceptProxy(GraphUpgradeable _implementation, IGraphProxy _proxy) external onlyGovernor {
  _implementation.acceptProxy(_proxy);
}

function acceptProxyAndCall(
  GraphUpgradeable _implementation,
  IGraphProxy _proxy,
  bytes calldata _data
) external onlyGovernor {
  _implementation.acceptProxyAndCall(_proxy, _data);
}
```

The interface was **missing the first parameter** (`implementation` address) from both functions. It had copied the signature from GraphUpgradeable instead of using the correct GraphProxyAdmin signature.

## Impact

### Why This Mattered

The deployment package (`@graphprotocol/deployment`) needs to call `acceptProxy` with the correct signature to upgrade proxy contracts. The function requires TWO parameters:

1. The implementation contract address
2. The proxy contract address

Because the interface was wrong, the deployment code had to work around it by loading the full contract ABI instead of using the cleaner interface ABI:

```typescript
// packages/deployment/lib/abis.ts (old workaround)
// Note: Load from actual contract, not interface, because IGraphProxyAdmin is outdated
// Interface shows: acceptProxy(IGraphProxy proxy)
// Contract has: acceptProxy(GraphUpgradeable _implementation, IGraphProxy _proxy)
export const GRAPH_PROXY_ADMIN_ABI = loadAbi(
  '@graphprotocol/contracts/artifacts/contracts/upgrades/GraphProxyAdmin.sol/GraphProxyAdmin.json',
)
```

### Why Horizon is Not Affected

GraphDirectory in horizon (`packages/horizon/contracts/utilities/GraphDirectory.sol`) imports and uses IGraphProxyAdmin, but **only as a type reference**:

```solidity
IGraphProxyAdmin private immutable GRAPH_PROXY_ADMIN;

constructor(address controller) {
    GRAPH_PROXY_ADMIN = IGraphProxyAdmin(_getContractFromController("GraphProxyAdmin"));
}

function _graphProxyAdmin() internal view returns (IGraphProxyAdmin) {
    return GRAPH_PROXY_ADMIN;
}
```

GraphDirectory:

- Stores the address as an immutable reference
- Returns it via a getter function
- **Never calls any methods on IGraphProxyAdmin** (like `acceptProxy`)

Since horizon doesn't call the methods, fixing the interface signature doesn't break horizon.

## Fix Applied

### Updated Interface

```solidity
/**
 * @notice Accept ownership of a proxy contract
 * @param implementation The implementation contract accepting the proxy
 * @param proxy The proxy contract to accept
 */
function acceptProxy(address implementation, IGraphProxy proxy) external;

/**
 * @notice Accept ownership of a proxy contract and call a function
 * @param implementation The implementation contract accepting the proxy
 * @param proxy The proxy contract to accept
 * @param data The calldata to execute after accepting
 */
function acceptProxyAndCall(address implementation, IGraphProxy proxy, bytes calldata data) external;
```

**Notes on parameter type choice:**

- Used `address` instead of `GraphUpgradeable` for the implementation parameter
- This avoids creating a dependency from interfaces package to contracts package
- The actual contract uses `GraphUpgradeable`, but `address` is compatible (Solidity allows passing addresses for contract types)
- The ABI encoding is identical - both produce the same function selector and parameter encoding

**Call flow for context:**

```
Deployer/Governor
  → GraphProxyAdmin.acceptProxy(implAddress, proxyAddress)  ← IGraphProxyAdmin represents THIS
      → implAddress.acceptProxy(proxyAddress)                ← GraphUpgradeable provides this
          → proxyAddress.acceptUpgrade()
```

### Updated Deployment Code

Removed the workaround comment and switched to using the interface:

```typescript
// packages/deployment/lib/abis.ts (now clean)
export const GRAPH_PROXY_ADMIN_ABI = loadAbi(
  '@graphprotocol/interfaces/artifacts/contracts/contracts/upgrades/IGraphProxyAdmin.sol/IGraphProxyAdmin.json',
)
```

## Files Changed

1. `packages/interfaces/contracts/contracts/upgrades/IGraphProxyAdmin.sol`
   - Fixed `acceptProxy` signature
   - Fixed `acceptProxyAndCall` signature

2. `packages/deployment/lib/abis.ts`
   - Removed workaround comment
   - Changed to load from interface instead of full contract

## Testing

Build verification:

- ✅ interfaces package builds successfully
- ✅ deployment package dependencies build successfully
- ✅ No TypeScript compilation errors
- ✅ Hardhat compilation successful

The deployment code in `packages/deployment/lib/upgrade-implementation.ts` already calls acceptProxy with both parameters:

```typescript
const acceptData = encodeFunctionData({
  abi: GRAPH_PROXY_ADMIN_ABI,
  functionName: 'acceptProxy',
  args: [pendingImpl as `0x${string}`, proxyAddress as `0x${string}`],
})
```

This call now works with the corrected interface ABI.

## Recommendation

This fix should be safe to merge. The interface now accurately reflects the actual contract implementation, and no existing code is broken by the change since:

1. Deployment already expects the two-parameter signature
2. Horizon only uses the type, never calls the methods
3. The fix aligns the interface with reality, reducing confusion

## Questions for Team Review

1. Are there other consumers of IGraphProxyAdmin that might be affected?
2. Should this be considered a breaking change requiring a major version bump of @graphprotocol/interfaces?
3. Is there a reason the interface was historically wrong (legacy compatibility concerns)?
