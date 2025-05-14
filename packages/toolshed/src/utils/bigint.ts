import { hexlify } from 'ethers'

import { randomBytes } from 'ethers'

export function randomBigInt(min: bigint, max: bigint): bigint {
  if (min > max) throw new Error('min must be <= max')
  const range = max - min + 1n
  const bits = range.toString(2).length
  const byteLen = Math.ceil(bits / 8)

  let rand: bigint
  do {
    const bytes = randomBytes(byteLen)
    rand = BigInt('0x' + hexlify(bytes).slice(2))
  } while (rand >= range)

  return min + rand
}
