import { L2TransactionReceipt, L2ToL1MessageStatus, L2ToL1MessageWriter } from '@arbitrum/sdk'
import { BigNumber } from 'ethers'
import { Contract, providers } from 'ethers'
import { wait as waitFn } from '../../../utils/time'
import { getL2ToL1MessageReader, getL2ToL1MessageWriter } from '../../../utils/arbitrum'

import type { GraphNetworkAction } from './types'
import type { GraphNetworkContracts } from '../deployment/contracts/load'
import type { SignerWithAddress } from '@nomiclabs/hardhat-ethers/signers'
import type { L2GraphToken, L2GraphTokenGateway } from '@graphprotocol/contracts'

const LEGACY_L2_GRT_ADDRESS = '0x23A941036Ae778Ac51Ab04CEa08Ed6e2FE103614'
const LEGACY_L2_GATEWAY_ADDRESS = '0x09e9222e96e7b4ae2a407b98d48e330053351eee'

const FOURTEEN_DAYS_IN_SECONDS = 24 * 3600 * 14
const BLOCK_SEARCH_THRESHOLD = 6 * 3600

export const startSendToL1: GraphNetworkAction<{
  l1Provider: providers.Provider
  amount: BigNumber
  recipient: string
  legacyToken: boolean
}> = async (
  contracts: GraphNetworkContracts,
  signer: SignerWithAddress,
  args: {
    l1Provider: providers.Provider
    amount: BigNumber
    recipient: string
    legacyToken?: boolean
  },
): Promise<void> => {
  const { l1Provider, amount, recipient, legacyToken } = args
  const l2Provider = contracts.GraphToken.provider

  console.info(`>>> Sending tokens to L1 <<<\n`)
  console.info(`Will send ${amount} GRT to ${recipient}`)

  // GRT
  const GraphToken = legacyToken
    ? (new Contract(LEGACY_L2_GRT_ADDRESS, contracts.GraphToken.interface, signer) as L2GraphToken)
    : contracts.GraphToken
  console.info(`Using L2 GRT ${GraphToken.address}`)

  // Gateway
  const GraphTokenGateway = (
    legacyToken
      ? new Contract(LEGACY_L2_GATEWAY_ADDRESS, contracts.GraphTokenGateway.interface, signer)
      : contracts.GraphTokenGateway
  ) as L2GraphTokenGateway
  console.info(`Using L2 gateway ${GraphTokenGateway.address}`)
  const l1GraphTokenAddress = await GraphTokenGateway.l1Counterpart()

  // Check sender balance
  const senderBalance = await GraphToken.balanceOf(signer.address)
  if (senderBalance.lt(amount)) {
    throw new Error('Sender balance is insufficient for the transfer')
  }

  if (!legacyToken) {
    console.info('Approving token transfer')
    await GraphToken.connect(signer).approve(GraphTokenGateway.address, amount)
  }
  console.info('Sending outbound transfer transaction')
  const tx = await GraphTokenGateway['outboundTransfer(address,address,uint256,bytes)'](
    l1GraphTokenAddress,
    recipient,
    amount,
    '0x',
  )
  const receipt = await tx.wait()

  const l2ToL1Message = await getL2ToL1MessageReader(receipt, l1Provider, l2Provider)
  const l2Receipt = new L2TransactionReceipt(receipt)

  const ethBlockNum = await l2ToL1Message.getFirstExecutableBlock(l2Provider)
  if (ethBlockNum === null) {
    console.info(`L2 to L1 message can or already has been executed. If not finalized call`)
  } else {
    console.info(`The transaction generated an L2 to L1 message in outbox with eth block number:`)
    console.info(ethBlockNum.toString())
    console.info(
      `After the dispute period is finalized (in ~1 week), you can finalize this by calling`,
    )
  }
  console.info(`finish-send-to-l1 with the following txhash:`)
  console.info(l2Receipt.transactionHash)
}

export const finishSendToL1: GraphNetworkAction<{
  l1Provider: providers.Provider
  legacyToken: boolean
  txHash?: string
  wait?: boolean
  retryDelaySeconds?: number
}> = async (
  contracts: GraphNetworkContracts,
  signer: SignerWithAddress,
  args: {
    l1Provider: providers.Provider
    legacyToken: boolean
    txHash?: string
    wait?: boolean
    retryDelaySeconds?: number
  },
): Promise<void> => {
  const { l1Provider, legacyToken, wait, retryDelaySeconds } = args
  let txHash = args.txHash
  const l2Provider = contracts.GraphToken.provider

  console.info(`>>> Finishing transaction sending tokens to L1 <<<\n`)

  // Gateway
  const GraphTokenGateway = (
    legacyToken
      ? new Contract(LEGACY_L2_GATEWAY_ADDRESS, contracts.GraphTokenGateway.interface, signer)
      : contracts.GraphTokenGateway
  ) as L2GraphTokenGateway
  console.info(`Using L2 gateway ${GraphTokenGateway.address}`)

  if (txHash === undefined) {
    console.info(
      `Looking for withdrawals initiated by ${signer.address} in roughly the last 14 days`,
    )
    const fromBlock = await searchForArbBlockByTimestamp(
      l2Provider,
      Math.round(Date.now() / 1000) - FOURTEEN_DAYS_IN_SECONDS,
    )
    const filt = GraphTokenGateway.filters.WithdrawalInitiated(null, signer.address)
    const allEvents = await GraphTokenGateway.queryFilter(
      filt,
      BigNumber.from(fromBlock).toHexString(),
    )
    if (allEvents.length == 0) {
      throw new Error('No withdrawals found')
    }
    txHash = allEvents[allEvents.length - 1].transactionHash
  }

  console.info(`Getting receipt from transaction ${txHash}`)
  const l2ToL1Message = await getL2ToL1MessageWriter(txHash, l1Provider, l2Provider, signer)

  if (wait) {
    const retryDelayMs = (retryDelaySeconds ?? 60) * 1000
    console.info('Waiting for outbox entry to be created, this can take a full week...')
    await waitUntilOutboxEntryCreatedWithCb(l2ToL1Message, l2Provider, retryDelayMs, () => {
      console.info('Still waiting...')
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

  console.info('Executing outbox transaction')
  const tx = await l2ToL1Message.execute(l2Provider)
  const outboxExecuteReceipt = await tx.wait()
  console.info('Transaction succeeded! tx hash:')
  console.info(outboxExecuteReceipt.transactionHash)
}

const searchForArbBlockByTimestamp = async (
  l2Provider: providers.Provider,
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
      await waitFn(retryDelay)
    }
  }
}
