import { Argv } from 'yargs'
import { utils } from 'ethers'
import { L1TransactionReceipt, L1ToL2MessageStatus, L1ToL2MessageWriter } from '@arbitrum/sdk'

import { loadEnv, CLIArgs, CLIEnvironment } from '../../env'
import { logger } from '../../logging'
import { getProvider, sendTransaction, toGRT, ensureAllowance, toBN } from '../../network'
import { chainIdIsL2, estimateRetryableTxGas } from '../../cross-chain'
import { getL1ToL2MessageWriter } from '../../arbitrum'

const logAutoRedeemReason = (autoRedeemRec) => {
  if (autoRedeemRec == null) {
    logger.info(`Auto redeem was not attempted.`)
    return
  }
  logger.info(`Auto redeem reverted.`)
}

const checkAndRedeemMessage = async (l1ToL2Message: L1ToL2MessageWriter) => {
  logger.info(`Waiting for status of ${l1ToL2Message.retryableCreationId}`)
  const res = await l1ToL2Message.waitForStatus()
  logger.info('Getting auto redeem attempt')
  const autoRedeemRec = await l1ToL2Message.getAutoRedeemAttempt()
  const l2TxReceipt = res.status === L1ToL2MessageStatus.REDEEMED ? res.l2TxReceipt : autoRedeemRec
  let l2TxHash = l2TxReceipt ? l2TxReceipt.transactionHash : 'null'
  if (res.status === L1ToL2MessageStatus.FUNDS_DEPOSITED_ON_L2) {
    /** Message wasn't auto-redeemed! */
    logger.warn('Funds were deposited on L2 but the retryable ticket was not redeemed')
    logAutoRedeemReason(autoRedeemRec)
    logger.info('Attempting to redeem...')
    await l1ToL2Message.redeem(process.env.CI ? { gasLimit: 2_000_000 } : {})
    const redeemAttempt = await l1ToL2Message.getSuccessfulRedeem()
    if (redeemAttempt.status == L1ToL2MessageStatus.REDEEMED) {
      l2TxHash = redeemAttempt.l2TxReceipt ? redeemAttempt.l2TxReceipt.transactionHash : 'null'
    } else {
      throw new Error(`Unexpected L1ToL2MessageStatus after redeem attempt: ${res.status}`)
    }
  } else if (res.status != L1ToL2MessageStatus.REDEEMED) {
    throw new Error(`Unexpected L1ToL2MessageStatus ${res.status}`)
  }
  logger.info(`Transfer successful: ${l2TxHash}`)
}

const ifNotNullToBN = (val: string | null) => (val == null ? val : toBN(val))

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
    const l1ToL2Message = await getL1ToL2MessageWriter(
      txReceipt,
      cli.wallet.provider,
      l2Provider,
      cli.wallet,
    )
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
        description: 'Receiving address in L2. Same to L1 address if empty',
      })
      .positional('calldata', {
        description: 'Calldata to pass to the recipient. Must be allowlisted in the bridge',
      })
      .coerce({
        maxGas: ifNotNullToBN,
        gasPriceBid: ifNotNullToBN,
        maxSubmissionCost: ifNotNullToBN,
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
