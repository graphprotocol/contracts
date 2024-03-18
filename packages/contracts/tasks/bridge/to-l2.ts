import { BigNumber } from 'ethers'
import { greTask } from '@graphprotocol/sdk/gre'
import { sendToL2 } from '@graphprotocol/sdk'
import { SignerWithAddress } from '@nomiclabs/hardhat-ethers/signers'

greTask('bridge:send-to-l2', 'Bridge GRT tokens from L1 to L2')
  .addParam('amount', 'Amount of tokens to bridge')
  .addOptionalParam(
    'sender',
    'Address of the sender, must be managed by the provider node. L1 deployer if empty.',
  )
  .addOptionalParam('recipient', 'Receiving address in L2. Same to L1 address if empty.')
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
      await hre.run('migrate:nitro:register', { deploymentFile: taskArgs.deploymentFile })
    }

    // Get the sender, use L1 deployer if not provided
    const sender = taskArgs.sender
      ? await SignerWithAddress.create(graph.l1.provider.getSigner(taskArgs.sender))
      : await graph.l1.getDeployer()
    console.log(`> Using wallet ${sender.address}`)

    // Patch sendToL2 opts
    taskArgs.l2Provider = graph.l2.provider
    taskArgs.amount = hre.ethers.utils.parseEther(taskArgs.amount) // sendToL2 expects amount in GRT

    // L2 provider gas limit estimation has been hit or miss in CI, 400k should be more than enough
    if (process.env.CI) {
      taskArgs.maxGas = BigNumber.from('400000')
    }

    await sendToL2(graph.contracts, sender, {
      l2Provider: graph.l2.provider,
      amount: taskArgs.amount,
      recipient: taskArgs.recipient,
      maxGas: taskArgs.maxGas,
      gasPriceBid: taskArgs.gasPriceBid,
      maxSubmissionCost: taskArgs.maxSubmissionCost,
    })

    console.log('Done!')
  })
