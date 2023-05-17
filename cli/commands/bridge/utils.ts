import { L1ToL2MessageStatus, L1ToL2MessageWriter } from '@arbitrum/sdk'

import { logger } from '../../logging'
import { toBN } from '../../network'

const logAutoRedeemReason = (autoRedeemRec) => {
  if (autoRedeemRec == null) {
    logger.info(`Auto redeem was not attempted.`)
    return
  }
  logger.info(`Auto redeem reverted.`)
}

export const checkAndRedeemMessage = async (l1ToL2Message: L1ToL2MessageWriter) => {
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

export const ifNotNullToBN = (val: string | null) => (val == null ? val : toBN(val))
