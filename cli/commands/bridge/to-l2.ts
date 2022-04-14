import { loadEnv, CLIArgs, CLIEnvironment } from '../../env'
import { logger } from '../../logging'
import { getProvider, sendTransaction, toGRT } from '../../network'
import { utils } from 'ethers'
import { parseEther } from '@ethersproject/units'
import {
  L1TransactionReceipt,
  L1ToL2MessageStatus,
  L1ToL2MessageWriter,
  L1ToL2MessageGasEstimator,
} from '@arbitrum/sdk'
import { chainIdIsL2, createNitroNetwork } from '../../utils'

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
    await l1ToL2Message.redeem()
    l2TxHash = (await l1ToL2Message.getSuccessfulRedeem()).transactionHash
  } else if (res.status != L1ToL2MessageStatus.REDEEMED) {
    throw new Error(`Unexpected L1ToL2MessageStatus ${res.status}`)
  }
  logger.info(`Transfer successful: ${l2TxHash}`)
}

export const sendToL2 = async (cli: CLIEnvironment, cliArgs: CLIArgs): Promise<void> => {
  logger.info(`>>> Sending tokens to L2 <<<\n`)
  const l2Provider = getProvider(cliArgs.l2ProviderUrl)
  const l2ChainId = (await l2Provider.getNetwork()).chainId
  createNitroNetwork(cliArgs.providerUrl)
  if (chainIdIsL2(cli.chainId) || !chainIdIsL2(l2ChainId)) {
    throw new Error(
      'Please use an L1 provider in --provider-url, and an L2 provider in --l2-provider-url',
    )
  }
  const gateway = cli.contracts['L1GraphTokenGateway']
  const l1GRT = cli.contracts['GraphToken']
  const l1GRTAddress = l1GRT.address
  const amount = toGRT(cliArgs.amount)
  const recipient = cliArgs.recipient ? cliArgs.recipient : cli.wallet.address
  const l2Dest = await gateway.l2Counterpart()

  logger.info(`Will send ${cliArgs.amount} GRT to ${recipient}`)
  logger.info(`Using L1 gateway ${gateway.address} and L2 gateway ${l2Dest}`)
  // See https://github.com/OffchainLabs/arbitrum/blob/master/packages/arb-ts/src/lib/bridge.ts
  const depositCalldata = await gateway.getOutboundCalldata(
    l1GRTAddress,
    cli.wallet.address,
    recipient,
    amount,
    '0x',
  )

  // Comment from Offchain Labs' implementation:
  // we add a 0.05 ether "deposit" buffer to pay for execution in the gas estimation
  logger.info('Estimating retryable ticket gas:')
  const baseFee = (await cli.wallet.provider.getBlock('latest')).baseFeePerGas
  const gasEstimator = new L1ToL2MessageGasEstimator(l2Provider)
  const gasParams = await gasEstimator.estimateMessage(
    gateway.address,
    l2Dest,
    depositCalldata,
    parseEther('0'),
    baseFee,
    gateway.address,
    gateway.address,
  )
  const maxGas = gasParams.maxGasBid
  const gasPriceBid = gasParams.maxGasPriceBid
  const maxSubmissionPrice = gasParams.maxSubmissionPriceBid
  logger.info(
    `Using max gas: ${maxGas}, gas price bid: ${gasPriceBid}, max submission price: ${maxSubmissionPrice}`,
  )

  const ethValue = maxSubmissionPrice.add(gasPriceBid.mul(maxGas))
  logger.info(`tx value: ${ethValue}`)
  const data = utils.defaultAbiCoder.encode(['uint256', 'bytes'], [maxSubmissionPrice, '0x'])

  const params = [l1GRTAddress, recipient, amount, maxGas, gasPriceBid, data]
  logger.info('Approving token transfer')
  await sendTransaction(cli.wallet, l1GRT, 'approve', [gateway.address, amount])
  logger.info('Sending outbound transfer transaction')
  const receipt = await sendTransaction(cli.wallet, gateway, 'outboundTransfer', params, {
    value: ethValue,
  })
  const l1Receipt = new L1TransactionReceipt(receipt)
  const l1ToL2Message = await l1Receipt.getL1ToL2Message(cli.wallet.connect(l2Provider))

  logger.info('Waiting for message to propagate to L2...')
  try {
    await checkAndRedeemMessage(l1ToL2Message)
  } catch (e) {
    logger.error('Auto redeem failed')
    logger.error(e)
    logger.error('You can re-attempt using redeem-send-to-l2 with the following txHash:')
    logger.error(receipt.transactionHash)
  }
}

export const redeemSendToL2 = async (cli: CLIEnvironment, cliArgs: CLIArgs): Promise<void> => {
  logger.info(`>>> Redeeming pending tokens on L2 <<<\n`)
  const l2Provider = getProvider(cliArgs.l2ProviderUrl)
  const l2ChainId = (await l2Provider.getNetwork()).chainId
  createNitroNetwork(cliArgs.providerUrl)
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
  command: 'send-to-l2 <amount> [recipient]',
  describe: 'Perform an L1-to-L2 Graph Token transaction',
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
