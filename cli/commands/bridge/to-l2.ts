import { Argv } from 'yargs'
import { utils } from 'ethers'
import { L1TransactionReceipt } from '@arbitrum/sdk'

import { loadEnv, CLIArgs, CLIEnvironment } from '../../env'
import { logger } from '../../logging'
import { getProvider, sendTransaction, toGRT, ensureAllowance, toBN } from '../../network'
import { chainIdIsL2, estimateRetryableTxGas } from '../../cross-chain'
import { checkAndRedeemMessage } from './common'

export const sendToL2 = async (cli: CLIEnvironment, cliArgs: CLIArgs): Promise<void> => {
  logger.info(`>>> Sending tokens to L2 <<<\n`)

  // parse provider
  const l1Provider = cli.wallet.provider
  // TODO: fix this hack for usage with hardhat
  const l2Provider = cliArgs.l2Provider ? cliArgs.l2Provider : getProvider(cliArgs.l2ProviderUrl)
  const l1ChainId = cli.chainId
  const l2ChainId = (await l2Provider.getNetwork()).chainId
  if (chainIdIsL2(l1ChainId) || !chainIdIsL2(l2ChainId)) {
    throw new Error(
      'Please use an L1 provider in --provider-url, and an L2 provider in --l2-provider-url',
    )
  }

  // parse params
  const { L1GraphTokenGateway: l1Gateway, GraphToken: l1GRT } = cli.contracts
  const amount = toGRT(cliArgs.amount)
  const recipient = cliArgs.recipient ?? cli.wallet.address
  const l1GatewayAddress = l1Gateway.address
  const l2GatewayAddress = await l1Gateway.l2Counterpart()
  const calldata = cliArgs.calldata ?? '0x'

  // transport tokens
  logger.info(`Will send ${cliArgs.amount} GRT to ${recipient}`)
  logger.info(`Using L1 gateway ${l1GatewayAddress} and L2 gateway ${l2GatewayAddress}`)
  await ensureAllowance(cli.wallet, l1GatewayAddress, l1GRT, amount)

  // estimate L2 ticket
  // See https://github.com/OffchainLabs/arbitrum/blob/master/packages/arb-ts/src/lib/bridge.ts
  const depositCalldata = await l1Gateway.getOutboundCalldata(
    l1GRT.address,
    cli.wallet.address,
    recipient,
    amount,
    calldata,
  )
  const { maxGas, gasPriceBid, maxSubmissionCost } = await estimateRetryableTxGas(
    l1Provider,
    l2Provider,
    l1GatewayAddress,
    l2GatewayAddress,
    depositCalldata,
    {
      maxGas: cliArgs.maxGas,
      gasPriceBid: cliArgs.gasPriceBid,
      maxSubmissionCost: cliArgs.maxSubmissionCost,
    },
  )
  const ethValue = maxSubmissionCost.add(gasPriceBid.mul(maxGas))
  logger.info(
    `Using maxGas:${maxGas}, gasPriceBid:${gasPriceBid}, maxSubmissionCost:${maxSubmissionCost} = tx value: ${ethValue}`,
  )

  // build transaction
  logger.info('Sending outbound transfer transaction')
  const txData = utils.defaultAbiCoder.encode(['uint256', 'bytes'], [maxSubmissionCost, calldata])
  const txParams = [l1GRT.address, recipient, amount, maxGas, gasPriceBid, txData]
  const txReceipt = await sendTransaction(cli.wallet, l1Gateway, 'outboundTransfer', txParams, {
    value: ethValue,
  })

  // get l2 ticket status
  if (txReceipt.status == 1) {
    logger.info('Waiting for message to propagate to L2...')
    const l1Receipt = new L1TransactionReceipt(txReceipt)
    const l1ToL2Messages = await l1Receipt.getL1ToL2Messages(cli.wallet.connect(l2Provider))
    const l1ToL2Message = l1ToL2Messages[0]
    try {
      await checkAndRedeemMessage(l1ToL2Message)
    } catch (e) {
      logger.error('Auto redeem failed')
      logger.error(e)
      logger.error('You can re-attempt using redeem-send-to-l2 with the following txHash:')
      logger.error(txReceipt.transactionHash)
    }
  }
}

export const redeemSendToL2 = async (cli: CLIEnvironment, cliArgs: CLIArgs): Promise<void> => {
  logger.info(`>>> Redeeming pending tokens on L2 <<<\n`)
  const l2Provider = getProvider(cliArgs.l2ProviderUrl)
  const l2ChainId = (await l2Provider.getNetwork()).chainId

  if (chainIdIsL2(cli.chainId) || !chainIdIsL2(l2ChainId)) {
    throw new Error(
      'Please use an L1 provider in --provider-url, and an L2 provider in --l2-provider-url',
    )
  }
  const l1Provider = cli.wallet.provider

  const receipt = await l1Provider.getTransactionReceipt(cliArgs.txHash)
  const l1Receipt = new L1TransactionReceipt(receipt)
  const l1ToL2Messages = await l1Receipt.getL1ToL2Messages(cli.wallet.connect(l2Provider))
  const l1ToL2Message = l1ToL2Messages[0]

  logger.info('Checking message status in L2...')
  await checkAndRedeemMessage(l1ToL2Message)
}

export const sendToL2Command = {
  command: 'send-to-l2 <amount> [recipient] [calldata]',
  describe: 'Perform an L1-to-L2 Graph Token transaction',
  builder: (yargs: Argv): Argv => {
    return yargs
      .option('max-gas', {
        description: 'Max gas for the L2 redemption attempt',
        requiresArg: true,
        type: 'string',
      })
      .option('gas-price-bid', {
        description: 'Gas price for the L2 redemption attempt',
        requiresArg: true,
        type: 'string',
      })
      .option('max-submission-cost', {
        description: 'Max submission cost for the retryable ticket',
        requiresArg: true,
        type: 'string',
      })
      .positional('amount', { description: 'Amount to send (will be converted to wei)' })
      .positional('recipient', {
        description: 'Receiving address in L2. Same as L1 address if empty',
      })
      .positional('calldata', {
        description: 'Calldata to pass to the recipient. Must be allowlisted in the bridge',
      })
      .coerce({
        maxGas: toBN,
        gasPriceBid: toBN,
        maxSubmissionCost: toBN,
      })
  },
  handler: async (argv: CLIArgs): Promise<void> => {
    return sendToL2(await loadEnv(argv), argv)
  },
}

export const redeemSendToL2Command = {
  command: 'redeem-send-to-l2 <txHash>',
  describe: 'Finish an L1-to-L2 Graph Token transaction if it failed to auto-redeem',
  handler: async (argv: CLIArgs): Promise<void> => {
    return redeemSendToL2(await loadEnv(argv), argv)
  },
}
