import { ethers } from 'ethers'

import type { TransactionResponse } from 'ethers'

export async function getEventData(tx: TransactionResponse, eventAbi: string) {
  const receipt = await tx.wait()
  const abi = [
    eventAbi,
  ]
  const iface = new ethers.Interface(abi)
  if (receipt?.logs === undefined) {
    return []
  }

  for (const log of receipt.logs) {
    const event = iface.parseLog(log)
    if (event !== null) {
      return event.args
    }
  }

  return []
}
