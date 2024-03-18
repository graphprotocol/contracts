

## Deploy a TokenManager (L1)

The following instructions are for testnet (goerli), use `--network mainnet` to deploy to Mainnet.

### 1. Deploy a Token Manager contract

During this process the master copy of the GraphTokenLockWallet will be deployed and used in the Manager.

```
npx hardhat deploy --tags manager --network goerli
```

### 2. Fund the manager with the amount we need to deploy contracts

The task will convert the amount passed in GRT to wei before calling the contracts.

```
npx hardhat manager-deposit --amount <amount-in-grt> --network goerli
```

### 3. Deploy a number of Token Lock contracts using the Manager

The process to set up the CSV file is described in the [README](./README.md).

```
npx hardhat create-token-locks --deploy-file <deploy-file.csv> --result-file <result-file.csv> --owner-address <owner-address> --network goerli
```

### 4. Setup the Token Manager to allow default protocol functions

```
npx hardhat manager-setup-auth --target-address <staking-address> --network goerli
```

## Deploying the manager, wallet and transfer tools to L2

This assumes a manager and token lock have already been deployed in L1 (and potentially many managers and token locks).

The following instructions are for testnet (goerli and Arbitrum goerli), use `--network mainnet` to deploy to Mainnet and `--network arbitrum-one` for Arbitrum One.

### 1. Deploy the L2GraphTokenLockWallet master copy

Keep in mind you might want to use a different mnemonic in `.env` for the L2 deployer. Note that each transfer tool in L1 will only support a single wallet implementation in L2, so if you deploy several L2 managers, make sure all of them use the same wallet master copy in L2.

```
npx hardhat deploy --tags l2-wallet --network arbitrum-goerli
```

### 2. Deploy the L1GraphTokenLockTransferTool

You will be prompted for a few relevant addresses, including the Staking contract and the address of the L2GraphTokenLockWallet implementation that you just deployed.

Note the transfer tool is upgradeable (uses an OZ transparent proxy).

```
npx hardhat deploy --tags l1-transfer-tool --network goerli
```

### 3. Deploy the L2GraphTokenLockManager for each L1 manager

Note this will not ask you for the L1 manager address, it is set separately in the transfer tool contract.

You can optionally fund the L2 manager if you'd like to also create L2-native vesting contracts with it.

```
npx hardhat deploy --tags l2-manager --network arbitrum-goerli
```

### 4. Deploy the L2GraphTokenLockTransferTool

Note the transfer tool is upgradeable (uses an OZ transparent proxy).

```
npx hardhat deploy --tags l2-transfer-tool --network arbitrum-goerli
```

### 5. Set the L2 owners and manager addresses

Each token lock has an owner, that may map to a different address in L2. So we need to set the owner address in the L1GraphTokenLockTransferTool.

This is done using a hardhat console on L1, i.e. `npx hardhat console --network goerli`:

```javascript
transferToolAddress = '<the L1 transfer tool address>'
l1Owner = '<the L1 owner address, e.g. for the Foundation multisig on mainnet>'
l2Owner = '<the L2 owner address, e.g. for the Foundation multisig on Arbitrum>'
deployer = (await hre.ethers.getSigners())[0]
transferTool = await hre.ethers.getContractAt('L1GraphTokenLockTransferTool', transferToolAddress)
await transferTool.connect(deployer).setL2WalletOwner(l1Owner, l2Owner)
// Repeat for each owner...
```

After doing this for each owner, you must also set the L2GraphTokenLockManager address that corresponds to each L1 manager:

```javascript
transferToolAddress = '<the L1 transfer tool address>'
l1Manager = '<the L1 manager address>'
l2Manager = '<the L2 manager address>'
deployer = (await hre.ethers.getSigners())[0]
transferTool = await hre.ethers.getContractAt('L1GraphTokenLockTransferTool', transferToolAddress)
await transferTool.connect(deployer).setL2LockManager(l1Manager, l2Manager)
// Repeat for each manager...
```

### 6. Configure the new authorized functions in L1

The addition of the L1 transfer tool means adding a new authorized contract and functions in the L1 manager's allowlist. For each manager, we need to add a new token destination (the L1 transfer tool) and the corresponding functions. This assumes the deployer is also the manager owner, if that's not the case, use the correct signer:

```javascript
transferToolAddress = '<the L1 transfer tool address>'
stakingAddress = '<the L1 Staking address>
l1Manager = '<the L1 manager address>'
deployer = (await hre.ethers.getSigners())[0]
tokenLockManager = await hre.ethers.getContractAt('GraphTokenLockManager', l1Manager)
await tokenLockManager.setAuthFunctionCall('depositToL2Locked(uint256,address,uint256,uint256,uint256)', transferToolAddress)
await tokenLockManager.setAuthFunctionCall('withdrawETH(address,uint256)', transferToolAddress)
await tokenLockManager.setAuthFunctionCall('setL2WalletAddressManually(address)', transferToolAddress)
await tokenLockManager.addTokenDestination(transferToolAddress)
await tokenLockManager.setAuthFunctionCall('transferLockedDelegationToL2(address,uint256,uint256,uint256)', stakingAddress)
await tokenLockManager.setAuthFunctionCall('transferLockedStakeToL2(uint256,uint256,uint256,uint256)', stakingAddress)
// Repeat for each manager...
```

Keep in mind that existing lock wallets that had already called `approveProtocol()` to interact with the protocol will need to call `revokeProtocol()` and then `approveProtocol()` to be able to use the transfer tool.

### 7. Configure the authorized functions on L2

The L2 managers will also need to authorize the functions to interact with the protocol. This is similar to step 4 when setting up the manager in L1, but here we must specify the manager name used when deploying the L2 manager

```
npx hardhat manager-setup-auth --target-address <l2-staking-address> --manager-name <l2-manager-deployment-name> --network arbitrum-goerli
```

We then need to also add authorization to call the L2 transfer tool on a hardhat console:

```javascript
transferToolAddress = '<the L2 transfer tool address>'
l2Manager = '<the L2 manager address>'
deployer = (await hre.ethers.getSigners())[0]
tokenLockManager = await hre.ethers.getContractAt('L2GraphTokenLockManager', l2Manager)
await tokenLockManager.setAuthFunctionCall('withdrawToL1Locked(uint256)', transferToolAddress)
await tokenLockManager.addTokenDestination(transferToolAddress)
// Repeat for each manager...
```

### 8. Make sure the protocol is configured

The contracts for The Graph must be configured such that the L1 transfer tool is added to the bridge callhook allowlist so that it can send data through the bridge.
Additionally, the L1Staking contract must be configured to use the L1 transfer tool when transferring stake and delegation for vesting contracts; this is done using the `setL1GraphTokenLockTransferTool` (called by the Governor, i.e. the Council).
