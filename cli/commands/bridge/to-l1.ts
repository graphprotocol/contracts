import { loadEnv, CLIArgs, CLIEnvironment } from '../../env'
import { logger } from '../../logging'
import { getAddressBook } from '../../address-book'
import { getProvider, sendTransaction, toGRT } from '../../network'
import { chainIdIsL2 } from '../../cross-chain'
import { loadAddressBookContract } from '../../contracts'
import { L2TransactionReceipt, L2ToL1MessageStatus, L2ToL1MessageWriter } from '@arbitrum/sdk'
import { L2GraphTokenGateway } from '../../../build/types/L2GraphTokenGateway'
import { BigNumber } from 'ethers'
import { JsonRpcProvider } from '@ethersproject/providers'
import { providers } from 'ethers'
import { L2GraphToken } from '../../../build/types/L2GraphToken'
import { getL2ToL1MessageReader, getL2ToL1MessageWriter } from '../../arbitrum'

const FOURTEEN_DAYS_IN_SECONDS = 24 * 3600 * 14

const BLOCK_SEARCH_THRESHOLD = 6 * 3600
const searchForArbBlockByTimestamp = async (
  l2Provider: JsonRpcProvider,
  timestamp: number,
): Promise<number> => {
  let step = 131072
  let block = await l2Provider.getBlock('latest')
  while (block.timestamp > timestamp) {
    while (block.number - step < 0) {
      step = Math.round(step / 2)
    }
    block = await l2Provider.getBlock(block.number - step)
  }
  while (step > 1 && Math.abs(block.timestamp - timestamp) > BLOCK_SEARCH_THRESHOLD) {
    step = Math.round(step / 2)
    if (block.timestamp - timestamp > 0) {
      block = await l2Provider.getBlock(block.number - step)
    } else {
      block = await l2Provider.getBlock(block.number + step)
    }
  }
  return block.number
}

const wait = (ms: number): Promise<void> => {
  return new Promise((res) => setTimeout(res, ms))
}

const waitUntilOutboxEntryCreatedWithCb = async (
  msg: L2ToL1MessageWriter,
  provider: providers.Provider,
  retryDelay: number,
  callback: () => void,
) => {
  let done = false
  while (!done) {
    const status = await msg.status(provider)
    if (status == L2ToL1MessageStatus.CONFIRMED || status == L2ToL1MessageStatus.EXECUTED) {
      done = true
    } else {
      callback()
      await wait(retryDelay)
    }
  }
}

export const startSendToL1 = async (cli: CLIEnvironment, cliArgs: CLIArgs): Promise<void> => {
  logger.info(`>>> Sending tokens to L1 <<<\n`)
  const l2Provider = getProvider(cliArgs.l2ProviderUrl)
  const l2ChainId = (await l2Provider.getNetwork()).chainId

  if (chainIdIsL2(cli.chainId) || !chainIdIsL2(l2ChainId)) {
    throw new Error(
      'Please use an L1 provider in --provider-url, and an L2 provider in --l2-provider-url',
    )
  }

  const l1GRT = cli.contracts['GraphToken']
  const l1GRTAddress = l1GRT.address
  const amount = toGRT(cliArgs.amount)
  const recipient = cliArgs.recipient ? cliArgs.recipient : cli.wallet.address
  const l2Wallet = cli.wallet.connect(l2Provider)
  const l2AddressBook = getAddressBook(cliArgs.addressBook, l2ChainId.toString())

  const gateway = loadAddressBookContract('L2GraphTokenGateway', l2AddressBook, l2Wallet)
  const l2GRT = loadAddressBookContract('L2GraphToken', l2AddressBook, l2Wallet) as L2GraphToken

  const l1Gateway = cli.contracts['L1GraphTokenGateway']
  logger.info(`Will send ${cliArgs.amount} GRT to ${recipient}`)
  logger.info(`Using L2 gateway ${gateway.address} and L1 gateway ${l1Gateway.address}`)

  const senderBalance = await l2GRT.balanceOf(cli.wallet.address)
  if (senderBalance.lt(amount)) {
    throw new Error('Sender balance is insufficient for the transfer')
  }

  const params = [l1GRTAddress, recipient, amount, '0x']
  logger.info('Approving token transfer')
  await sendTransaction(l2Wallet, l2GRT, 'approve', [gateway.address, amount])
  logger.info('Sending outbound transfer transaction')
  const receipt = await sendTransaction(
    l2Wallet,
    gateway,
    'outboundTransfer(address,address,uint256,bytes)',
    params,
  )

  const l2ToL1Message = await getL2ToL1MessageReader(receipt, cli.wallet.provider, l2Provider)
  const l2Receipt = new L2TransactionReceipt(receipt)

  const ethBlockNum = await l2ToL1Message.getFirstExecutableBlock(l2Provider)
  if (ethBlockNum === null) {
    logger.info(`L2 to L1 message can or already has been executed. If not finalized call`)
  } else {
    logger.info(`The transaction generated an L2 to L1 message in outbox with eth block number:`)
    logger.info(ethBlockNum.toString())
    logger.info(
      `After the dispute period is finalized (in ~1 week), you can finalize this by calling`,
    )
  }
  logger.info(`finish-send-to-l1 with the following txhash:`)
  logger.info(l2Receipt.transactionHash)
}

export const finishSendToL1 = async (
  cli: CLIEnvironment,
  cliArgs: CLIArgs,
  wait: boolean,
): Promise<void> => {
  logger.info(`>>> Finishing transaction sending tokens to L1 <<<\n`)
  const l2Provider = getProvider(cliArgs.l2ProviderUrl)
  const l2ChainId = (await l2Provider.getNetwork()).chainId

  if (chainIdIsL2(cli.chainId) || !chainIdIsL2(l2ChainId)) {
    throw new Error(
      'Please use an L1 provider in --provider-url, and an L2 provider in --l2-provider-url',
    )
  }

  const l2AddressBook = getAddressBook(cliArgs.addressBook, l2ChainId.toString())

  const gateway = loadAddressBookContract(
    'L2GraphTokenGateway',
    l2AddressBook,
    l2Provider,
  ) as L2GraphTokenGateway
  let txHash: string
  if (cliArgs.txHash) {
    txHash = cliArgs.txHash
  } else {
    logger.info(
      `Looking for withdrawals initiated by ${cli.wallet.address} in roughly the last 14 days`,
    )
    const fromBlock = await searchForArbBlockByTimestamp(
      l2Provider,
      Math.round(Date.now() / 1000) - FOURTEEN_DAYS_IN_SECONDS,
    )
    const filt = gateway.filters.WithdrawalInitiated(null, cli.wallet.address)
    const allEvents = await gateway.queryFilter(filt, BigNumber.from(fromBlock).toHexString())
    if (allEvents.length == 0) {
      throw new Error('No withdrawals found')
    }
    txHash = allEvents[allEvents.length - 1].transactionHash
  }
  logger.info(`Getting receipt from transaction ${txHash}`)
  const l2ToL1Message = await getL2ToL1MessageWriter(
    txHash,
    cli.wallet.provider,
    l2Provider,
    cli.wallet,
  )

  if (wait) {
    const retryDelayMs = cliArgs.retryDelaySeconds ? cliArgs.retryDelaySeconds * 1000 : 60000
    logger.info('Waiting for outbox entry to be created, this can take a full week...')
    await waitUntilOutboxEntryCreatedWithCb(l2ToL1Message, l2Provider, retryDelayMs, () => {
      logger.info('Still waiting...')
    })
  } else {
    const status = await l2ToL1Message.status(l2Provider)
    if (status == L2ToL1MessageStatus.EXECUTED) {
      throw new Error('Message already executed!')
    } else if (status != L2ToL1MessageStatus.CONFIRMED) {
      throw new Error(
        `Transaction is not confirmed, status is ${status} when it should be ${L2ToL1MessageStatus.CONFIRMED}. Has the dispute period passed?`,
      )
    }
  }

  logger.info('Executing outbox transaction')
  const tx = await l2ToL1Message.execute(l2Provider)
  const outboxExecuteReceipt = await tx.wait()
  logger.info('Transaction succeeded! tx hash:')
  logger.info(outboxExecuteReceipt.transactionHash)
}

export const startSendToL1Command = {
  command: 'start-send-to-l1 <amount> [recipient]',
  describe: 'Start an L2-to-L1 Graph Token transaction',
  handler: async (argv: CLIArgs): Promise<void> => {
    return startSendToL1(await loadEnv(argv), argv)
  },
}

export const finishSendToL1Command = {
  command: 'finish-send-to-l1 [txHash]',
  describe:
    'Finish an L2-to-L1 Graph Token transaction. L2 dispute period must have completed. ' +
    'If txHash is not specified, the last withdrawal from the main account in the past 14 days will be redeemed.',
  handler: async (argv: CLIArgs): Promise<void> => {
    return finishSendToL1(await loadEnv(argv), argv, false)
  },
}

export const waitFinishSendToL1Command = {
  command: 'wait-finish-send-to-l1 [txHash] [retryDelaySeconds]',
  describe:
    "Wait for an L2-to-L1 Graph Token transaction's dispute period to complete (which takes about a week), and then finalize it. " +
    'If txHash is not specified, the last withdrawal from the main account in the past 14 days will be redeemed.',
  handler: async (argv: CLIArgs): Promise<void> => {
    return finishSendToL1(await loadEnv(argv), argv, true)
  },
}
