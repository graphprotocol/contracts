import { expect } from 'chai'
import type { Abi } from 'viem'
import { toFunctionSelector } from 'viem'

import {
  IERC165_ABI,
  IERC165_INTERFACE_ID,
  IISSUANCE_TARGET_INTERFACE_ID,
  IREWARDS_MANAGER_INTERFACE_ID,
  ISSUANCE_TARGET_ABI,
  REWARDS_MANAGER_ABI,
} from '../lib/abis.js'

function computeInterfaceId(abi: Abi): `0x${string}` {
  const xor = abi
    .filter((item): item is Extract<(typeof abi)[number], { type: 'function' }> => item.type === 'function')
    .map((f) => Number.parseInt(toFunctionSelector(f).slice(2), 16) >>> 0)
    .reduce((a, s) => (a ^ s) >>> 0, 0)
  return `0x${xor.toString(16).padStart(8, '0')}`
}

describe('Interface ID Stability', function () {
  it('IERC165_INTERFACE_ID matches the IERC165 ABI', function () {
    expect(IERC165_INTERFACE_ID).to.equal(computeInterfaceId(IERC165_ABI))
  })

  it('IISSUANCE_TARGET_INTERFACE_ID matches the IIssuanceTarget ABI', function () {
    expect(IISSUANCE_TARGET_INTERFACE_ID).to.equal(computeInterfaceId(ISSUANCE_TARGET_ABI))
  })

  it('IREWARDS_MANAGER_INTERFACE_ID matches the IRewardsManager ABI', function () {
    expect(IREWARDS_MANAGER_INTERFACE_ID).to.equal(computeInterfaceId(REWARDS_MANAGER_ABI))
  })
})
