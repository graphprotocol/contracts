import { task } from 'hardhat/config'
import { cliOpts } from '../../cli/defaults'
import { sendToL2 } from '../../cli/commands/bridge/to-l2'
import { loadEnv } from '../../cli/env'
import { BigNumber } from 'ethers'

task('bridge:send-to-l2', 'Bridge GRT tokens from L1 to L2')
  .addParam('amount', 'Amount of tokens to bridge')
  .addOptionalParam('sender', 'Address of the sender. L1 deployer if empty.')
  .addOptionalParam('recipient', 'Receiving address in L2. Same to L1 address if empty.')
  .addOptionalParam('addressBook', cliOpts.addressBook.description)
  .addOptionalParam('l1GraphConfig', cliOpts.graphConfig.description)
  .addOptionalParam('l2GraphConfig', cliOpts.graphConfig.description)
  .setAction(async (taskArgs, hre) => {
    const graph = hre.graph(taskArgs)

    console.log('> Sending GRT to L2')

    // Get the sender, use L1 deployer if non provided
    const l1Deployer = await graph.l1.getDeployer()
    const sender: string = taskArgs.sender ?? l1Deployer.address

    const wallets = await graph.l1.getWallets()
    let wallet = wallets.find((w) => w.address === sender)

    if (!wallet) {
      throw new Error(`No wallet found for address ${sender}`)
    } else {
      console.log(`> Using wallet ${wallet.address}`)
      wallet = wallet.connect(graph.l1.provider)
    }

    // Patch sendToL2 opts
    taskArgs.l2Provider = graph.l2.provider

    // Arbitrum SDK does not support local testnode so we hardcode estimations
    if (graph.l2.chainId === 412346) {
      taskArgs.maxGas = BigNumber.from(200_000)
      taskArgs.gasPriceBid = BigNumber.from(300_000_000)
      taskArgs.maxSubmissionCost = BigNumber.from(500_000)
    }

    await sendToL2(await loadEnv(taskArgs, wallet), taskArgs)

    console.log('Done!')
  })
