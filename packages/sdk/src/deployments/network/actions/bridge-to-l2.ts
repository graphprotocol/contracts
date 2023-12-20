import { BigNumber, providers, utils } from 'ethers'

import { L1TransactionReceipt, L1ToL2MessageStatus, L1ToL2MessageWriter } from '@arbitrum/sdk'
import { GraphNetworkAction } from './types'
import { GraphNetworkContracts } from '../deployment/contracts/load'
import { SignerWithAddress } from '@nomiclabs/hardhat-ethers/signers'
import { setGRTAllowance } from './graph-token'
import { estimateRetryableTxGas, getL1ToL2MessageWriter } from '../../../utils/arbitrum'

export const sendToL2: GraphNetworkAction<{
  l2Provider: providers.Provider
  amount: BigNumber
  recipient: string
  calldata?: string
  maxGas: BigNumber
  gasPriceBid: BigNumber
  maxSubmissionCost: BigNumber
}> = async (
  contracts: GraphNetworkContracts,
  signer: SignerWithAddress,
  args: {
    l2Provider: providers.Provider
    amount: BigNumber
    recipient: string
    calldata?: string
    maxGas: BigNumber
    gasPriceBid: BigNumber
    maxSubmissionCost: BigNumber
  },
): Promise<void> => {
  const { l2Provider, amount, recipient } = args
  const l1Provider = contracts.GraphToken.provider
  const calldata = args.calldata ?? '0x'

  console.info(`>>> Sending tokens to L2 <<<\n`)

  const l1GatewayAddress = contracts.GraphTokenGateway.address
  const l2GatewayAddress = await contracts.L1GraphTokenGateway!.l2Counterpart()

  console.info(`Will send ${amount} GRT to ${recipient}`)
  console.info(`Using L1 gateway ${l1GatewayAddress} and L2 gateway ${l2GatewayAddress}`)
  await setGRTAllowance(contracts, signer, { spender: l1GatewayAddress, allowance: amount })

  // estimate L2 ticket
  // See https://github.com/OffchainLabs/arbitrum/blob/master/packages/arb-ts/src/lib/bridge.ts
  const depositCalldata = await contracts.L1GraphTokenGateway!.getOutboundCalldata(
    contracts.GraphToken.address,
    signer.address,
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
      maxGas: args.maxGas,
      gasPriceBid: args.gasPriceBid,
      maxSubmissionCost: args.maxSubmissionCost,
    },
  )
  const ethValue = maxSubmissionCost.add(gasPriceBid.mul(maxGas))
  console.info(
    `Using maxGas:${maxGas}, gasPriceBid:${gasPriceBid}, maxSubmissionCost:${maxSubmissionCost} = tx value: ${ethValue}`,
  )

  // build transaction
  console.info('Sending outbound transfer transaction')
  const txData = utils.defaultAbiCoder.encode(['uint256', 'bytes'], [maxSubmissionCost, calldata])
  const tx = await contracts
    .L1GraphTokenGateway!.connect(signer)
    .outboundTransfer(
      contracts.GraphToken.address,
      recipient,
      amount,
      maxGas,
      gasPriceBid,
      txData,
      {
        value: ethValue,
      },
    )
  const receipt = await tx.wait()

  // get l2 ticket status
  if (receipt.status == 1) {
    console.info('Waiting for message to propagate to L2...')
    try {
      const l1ToL2Message = await getL1ToL2MessageWriter(receipt, l1Provider, l2Provider)
      await checkAndRedeemMessage(l1ToL2Message)
    } catch (e) {
      console.error('Auto redeem failed')
      console.error(e)
      console.error('You can re-attempt using redeem-send-to-l2 with the following txHash:')
      console.error(receipt.transactionHash)
    }
  }
}

export const redeemSendToL2: GraphNetworkAction<{
  txHash: string
  l2Provider: providers.Provider
}> = async (
  contracts: GraphNetworkContracts,
  signer: SignerWithAddress,
  args: {
    txHash: string
    l2Provider: providers.Provider
  },
): Promise<void> => {
  console.info(`>>> Redeeming pending tokens on L2 <<<\n`)
  const l1Provider = contracts.GraphToken.provider
  const l2Provider = args.l2Provider

  const receipt = await l1Provider.getTransactionReceipt(args.txHash)
  const l1Receipt = new L1TransactionReceipt(receipt)
  const l1ToL2Messages = await l1Receipt.getL1ToL2Messages(signer.connect(l2Provider))
  const l1ToL2Message = l1ToL2Messages[0]

  console.info('Checking message status in L2...')
  await checkAndRedeemMessage(l1ToL2Message)
}

const logAutoRedeemReason = (autoRedeemRec: any) => {
  if (autoRedeemRec == null) {
    console.info(`Auto redeem was not attempted.`)
    return
  }
  console.info(`Auto redeem reverted.`)
}

const checkAndRedeemMessage = async (l1ToL2Message: L1ToL2MessageWriter) => {
  console.info(`Waiting for status of ${l1ToL2Message.retryableCreationId}`)
  const res = await l1ToL2Message.waitForStatus()
  console.info('Getting auto redeem attempt')
  const autoRedeemRec = await l1ToL2Message.getAutoRedeemAttempt()
  const l2TxReceipt = res.status === L1ToL2MessageStatus.REDEEMED ? res.l2TxReceipt : autoRedeemRec
  let l2TxHash = l2TxReceipt ? l2TxReceipt.transactionHash : 'null'
  if (res.status === L1ToL2MessageStatus.FUNDS_DEPOSITED_ON_L2) {
    /** Message wasn't auto-redeemed! */
    console.warn('Funds were deposited on L2 but the retryable ticket was not redeemed')
    logAutoRedeemReason(autoRedeemRec)
    console.info('Attempting to redeem...')
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
  console.info(`Transfer successful: ${l2TxHash}`)
}
