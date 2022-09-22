import { ContractTransaction } from 'ethers'
import { task } from 'hardhat/config'
import { cliOpts } from '../../cli/defaults'
import { chainIdIsL2 } from '../../cli/cross-chain'

task('migrate:sync', 'Sync controller contracts')
  .addParam('addressBook', cliOpts.addressBook.description, cliOpts.addressBook.default)
  .addParam('graphConfig', cliOpts.graphConfig.description, cliOpts.graphConfig.default)
  .setAction(async (taskArgs, hre) => {
    const { contracts, getDeployer } = hre.graph({
      addressBook: taskArgs.addressBook,
      graphConfig: taskArgs.graphConfig,
    })
    const deployer = await getDeployer()

    const chainId = hre.network.config.chainId?.toString() ?? '1337'
    const isL2 = chainIdIsL2(chainId)

    // Sync contracts
    console.log(
      `Syncing cache for contract addresses on chainId ${chainId} (${isL2 ? 'L2' : 'L1'})`,
    )
    const txs: ContractTransaction[] = []
    console.log('> Syncing cache on Curation')
    txs.push(await contracts['Curation'].connect(deployer).syncAllContracts())
    console.log('> Syncing cache on GNS')
    txs.push(await contracts['GNS'].connect(deployer).syncAllContracts())
    console.log('> Syncing cache on ServiceRegistry')
    txs.push(await contracts['ServiceRegistry'].connect(deployer).syncAllContracts())
    console.log('> Syncing cache on DisputeManager')
    txs.push(await contracts['DisputeManager'].connect(deployer).syncAllContracts())
    console.log('> Syncing cache on RewardsManager')
    txs.push(await contracts['RewardsManager'].connect(deployer).syncAllContracts())
    console.log('> Syncing cache on Staking')
    txs.push(await contracts['Staking'].connect(deployer).syncAllContracts())
    if (isL2) {
      console.log('> Syncing cache on L2GraphTokenGateway')
      txs.push(await contracts['L2GraphTokenGateway'].connect(deployer).syncAllContracts())
      if (contracts['L2Reservoir']) {
        console.log('> Syncing cache on L2Reservoir')
        txs.push(await contracts['L2Reservoir'].connect(deployer).syncAllContracts())
      }
    } else {
      // L1 chains might not have these contracts deployed yet...
      if (contracts['L1GraphTokenGateway']) {
        console.log('> Syncing cache on L1GraphTokenGateway')
        txs.push(await contracts['L1GraphTokenGateway'].connect(deployer).syncAllContracts())
      } else {
        console.log('Skipping L1GraphTokenGateway as it does not seem to be deployed yet')
      }
      if (contracts['BridgeEscrow']) {
        console.log('> Syncing cache on BridgeEscrow')
        txs.push(await contracts['BridgeEscrow'].connect(deployer).syncAllContracts())
      } else {
        console.log('Skipping BridgeEscrow as it does not seem to be deployed yet')
      }
      if (contracts['L1Reservoir']) {
        console.log('> Syncing cache on L1Reservoir')
        txs.push(await contracts['L1Reservoir'].connect(deployer).syncAllContracts())
      } else {
        console.log('Skipping L1Reservoir as it does not seem to be deployed yet')
      }
    }
    await Promise.all(
      txs.map((tx) => {
        console.log(tx.hash)
        return tx.wait()
      }),
    )
    console.log('Done!')
  })
