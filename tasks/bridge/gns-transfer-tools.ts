import { task } from 'hardhat/config'
import { cliOpts } from '../../cli/defaults'
import {
  sendSubgraphToL2,
  sendCurationToL2,
  finishSubgraphTransferToL2,
} from '../../cli/commands/bridge/gns-transfer-tools'
import { loadEnv } from '../../cli/env'
import { TASK_NITRO_SETUP_SDK } from '../deployment/nitro'
import { BigNumber } from 'ethers'

export const TASK_SEND_SUBGRAPH_TO_L2 = 'bridge:send-subgraph-to-l2'
export const TASK_FINISH_SUBGRAPH_L2 = 'bridge:finish-subgraph-transfer-to-l2'
export const TASK_SEND_CURATION_TO_L2 = 'bridge:send-curation-to-l2'

async function prepareBridgeArgs(taskArgs, hre) {
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

  // L2 provider gas limit estimation has been hit or miss in CI, 400k should be more than enough
  if (process.env.CI) {
    taskArgs.maxGas = BigNumber.from('400000')
  }
  return { graph, wallet, taskArgs }
}

task(TASK_SEND_SUBGRAPH_TO_L2, 'Transfer subgraph from L1 to L2')
  .addParam('subgraphId', 'Subgraph ID to transfer')
  .addOptionalParam('sender', 'Address of the sender. L1 deployer if empty.')
  .addOptionalParam('beneficiary', 'Receiving address in L2. Same to L1 address if empty.')
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
    const { taskArgs: updatedTaskArgs, wallet } = await prepareBridgeArgs(taskArgs, hre)
    await sendSubgraphToL2(await loadEnv(updatedTaskArgs, wallet), updatedTaskArgs)
    console.log('Done!')
  })

task(TASK_FINISH_SUBGRAPH_L2, 'Finish subgraph transfer from L1 to L2')
  .addParam('l1SubgraphId', 'L1 Subgraph ID that was transferred')
  .addParam('versionMetadata', 'IPFS hash for the subgraph version metadata')
  .addParam('subgraphMetadata', 'IPFS hash for the subgraph metadata')
  .addOptionalParam(
    'sender',
    'Address in L2 that will execute the tx, must be the beneficiary from the transfer. L1 deployer if empty.',
  )
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
    console.log('> Finishing subgraph transfer to L2')
    const { taskArgs: updatedTaskArgs, wallet } = await prepareBridgeArgs(taskArgs, hre)
    await finishSubgraphTransferToL2(await loadEnv(updatedTaskArgs, wallet), updatedTaskArgs)
    console.log('Done!')
  })

task(TASK_SEND_CURATION_TO_L2, 'Transfer curation from L1 to L2')
  .addParam('subgraphId', 'Subgraph ID to transfer')
  .addOptionalParam('sender', 'Address of the sender. L1 deployer if empty.')
  .addOptionalParam('beneficiary', 'Receiving address in L2. Same to L1 address if empty.')
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
    console.log('> Sending Curation to L2')
    const { taskArgs: updatedTaskArgs, wallet } = await prepareBridgeArgs(taskArgs, hre)
    await sendCurationToL2(await loadEnv(updatedTaskArgs, wallet), updatedTaskArgs)
    console.log('Done!')
  })
