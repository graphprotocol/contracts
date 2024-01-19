import { hexZeroPad } from 'ethers/lib/utils'
import { toBN } from '../units'

// Adapted from:
// https://github.com/livepeer/arbitrum-lpt-bridge/blob/e1a81edda3594e434dbcaa4f1ebc95b7e67ecf2a/utils/arbitrum/messaging.ts#L118
export const applyL1ToL2Alias = (l1Address: string): string => {
  const offset = toBN('0x1111000000000000000000000000000000001111')
  const l1AddressAsNumber = toBN(l1Address)
  const l2AddressAsNumber = l1AddressAsNumber.add(offset)

  const mask = toBN(2).pow(160)
  return hexZeroPad(l2AddressAsNumber.mod(mask).toHexString(), 20)
}
