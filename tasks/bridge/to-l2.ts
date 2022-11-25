import { task } from 'hardhat/config'
import { cliOpts } from '../../cli/defaults'
import { sendToL2 } from '../../cli/commands/bridge/to-l2'
import { sendSubgraphToL2, finishSendSubgraphToL2 } from '../../cli/commands/bridge/gns'
import { loadEnv } from '../../cli/env'
import { TASK_NITRO_SETUP_SDK } from '../deployment/nitro'
import { BigNumber } from 'ethers'

export const TASK_BRIDGE_TO_L2 = 'bridge:send-to-l2'
export const TASK_SUBGRAPH_TO_L2 = 'bridge:send-subgraph-to-l2'
export const TASK_FINISH_SUBGRAPH_MIGRATION_L2 = 'bridge:finish-send-subgraph-to-l2'

task(TASK_BRIDGE_TO_L2, 'Bridge GRT tokens from L1 to L2')
  .addParam('amount', 'Amount of tokens to bridge')
  .addFlag('disableSecureAccounts', 'Disable secure accounts on GRE')
  .addOptionalParam('sender', 'Address of the sender. L1 deployer if empty.')
  .addOptionalParam('recipient', 'Receiving address in L2. Same as L1 address if empty.')
  .addOptionalParam('addressBook', cliOpts.addressBook.description)
  .addOptionalParam(
    'arbitrumAddressBook',
    cliOpts.arbitrumAddressBook.description,
    cliOpts.arbitrumAddressBook.default,
  )
  .addOptionalParam('l1GraphConfig', cliOpts.graphConfig.description)
  .addOptionalParam('l2GraphConfig', cliOpts.graphConfig.description)
  .addOptionalParam(
    'deploymentFile',
    'Nitro testnode deployment file. Must specify if using nitro test nodes.',
  )
  .setAction(async (taskArgs, hre) => {
    console.log('> Sending GRT to L2')
    const graph = hre.graph(taskArgs)

    // If local, add nitro test node networks to sdk
    if (taskArgs.deploymentFile) {
      console.log('> Adding nitro test node network to sdk')
      await hre.run(TASK_NITRO_SETUP_SDK, { deploymentFile: taskArgs.deploymentFile })
    }

    // Get the sender, use L1 deployer if not provided
    const l1Deployer = await graph.l1.getDeployer()
    const sender: string = taskArgs.sender ?? l1Deployer.address

    let wallet = await graph.l1.getWallet(sender)

    if (!wallet) {
      throw new Error(`No wallet found for address ${sender}`)
    } else {
      console.log(`> Using wallet ${wallet.address}`)
      wallet = wallet.connect(graph.l1.provider)
    }

    // Patch sendToL2 opts
    taskArgs.l2Provider = graph.l2.provider
    taskArgs.amount = hre.ethers.utils.formatEther(taskArgs.amount) // sendToL2 expects amount in GRT

    // L2 provider gas limit estimation has been hit or miss in CI, 400k should be more than enough
    if (process.env.CI) {
      taskArgs.maxGas = BigNumber.from('400000')
    }

    await sendToL2(await loadEnv(taskArgs, wallet), taskArgs)

    console.log('Done!')
  })

task(TASK_SUBGRAPH_TO_L2, 'Send subgraph from L1 to L2')
  .addParam('subgraphId', 'Supgraph ID to migrate')
  .addFlag('disableSecureAccounts', 'Disable secure accounts on GRE')
  .addOptionalParam('sender', 'Address of the sender. L1 deployer if empty.')
  .addOptionalParam('l2Owner', 'Subgraph owner in L2. Same as L1 address if empty.')
  .addOptionalParam('addressBook', cliOpts.addressBook.description)
  .addOptionalParam(
    'arbitrumAddressBook',
    cliOpts.arbitrumAddressBook.description,
    cliOpts.arbitrumAddressBook.default,
  )
  .addOptionalParam('l1GraphConfig', cliOpts.graphConfig.description)
  .addOptionalParam('l2GraphConfig', cliOpts.graphConfig.description)
  .addOptionalParam(
    'deploymentFile',
    'Nitro testnode deployment file. Must specify if using nitro test nodes.',
  )
  .setAction(async (taskArgs, hre) => {
    console.log('> Sending subgraph to L2')
    const graph = hre.graph(taskArgs)

    // If local, add nitro test node networks to sdk
    if (taskArgs.deploymentFile) {
      console.log('> Adding nitro test node network to sdk')
      await hre.run(TASK_NITRO_SETUP_SDK, { deploymentFile: taskArgs.deploymentFile })
    }

    // Get the sender, use L1 deployer if not provided
    const l1Deployer = await graph.l1.getDeployer()
    const sender: string = taskArgs.sender ?? l1Deployer.address

    let wallet = await graph.l1.getWallet(sender)

    if (!wallet) {
      throw new Error(`No wallet found for address ${sender}`)
    } else {
      console.log(`> Using wallet ${wallet.address}`)
      wallet = wallet.connect(graph.l1.provider)
    }

    // Patch sendSubgraphToL2 opts
    taskArgs.l2Provider = graph.l2.provider
    taskArgs.subgraphId = hre.ethers.BigNumber.from(taskArgs.subgraphId) // sendToL2 expects subgraphId as BigNumber

    // L2 provider gas limit estimation has been hit or miss in CI, 400k should be more than enough
    if (process.env.CI) {
      taskArgs.maxGas = BigNumber.from('400000')
    }

    await sendSubgraphToL2(await loadEnv(taskArgs, wallet), taskArgs)

    console.log('Done!')
  })

task(TASK_FINISH_SUBGRAPH_MIGRATION_L2, 'Finish subgraph migration from L1 to L2')
  .addParam('subgraphId', 'Supgraph ID to migrate')
  .addParam('subgraphDeploymentId', 'Subgraph deployment ID to use as the new version (hex)')
  .addParam('subgraphMetadata', 'Subgraph metadata to use for the subgraph in L2')
  .addParam('versionMetadata', 'Subgraph version metadata to use for the new version')
  .addFlag('disableSecureAccounts', 'Disable secure accounts on GRE')
  .addOptionalParam('sender', 'Address of the sender. L1 deployer if empty.')
  .addOptionalParam('addressBook', cliOpts.addressBook.description)
  .addOptionalParam(
    'arbitrumAddressBook',
    cliOpts.arbitrumAddressBook.description,
    cliOpts.arbitrumAddressBook.default,
  )
  .addOptionalParam('l1GraphConfig', cliOpts.graphConfig.description)
  .addOptionalParam('l2GraphConfig', cliOpts.graphConfig.description)
  .addOptionalParam(
    'deploymentFile',
    'Nitro testnode deployment file. Must specify if using nitro test nodes.',
  )
  .setAction(async (taskArgs, hre) => {
    console.log('> Sending subgraph to L2')
    const graph = hre.graph(taskArgs)

    // If local, add nitro test node networks to sdk
    if (taskArgs.deploymentFile) {
      console.log('> Adding nitro test node network to sdk')
      await hre.run(TASK_NITRO_SETUP_SDK, { deploymentFile: taskArgs.deploymentFile })
    }

    // Get the sender, use L1 deployer if not provided
    const l1Deployer = await graph.l1.getDeployer()
    const sender: string = taskArgs.sender ?? l1Deployer.address

    let wallet = await graph.l1.getWallet(sender)

    if (!wallet) {
      throw new Error(`No wallet found for address ${sender}`)
    } else {
      console.log(`> Using wallet ${wallet.address}`)
      wallet = wallet.connect(graph.l1.provider)
    }

    // Patch sendSubgraphToL2 opts
    taskArgs.l2Provider = graph.l2.provider
    taskArgs.subgraphId = hre.ethers.BigNumber.from(taskArgs.subgraphId) // sendToL2 expects subgraphId as BigNumber

    // L2 provider gas limit estimation has been hit or miss in CI, 400k should be more than enough
    if (process.env.CI) {
      taskArgs.maxGas = BigNumber.from('400000')
    }

    await finishSendSubgraphToL2(await loadEnv(taskArgs, wallet), taskArgs)

    console.log('Done!')
  })
