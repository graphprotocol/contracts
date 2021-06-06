import { expect } from 'chai'
import { constants, BigNumber } from 'ethers'

import { MathUtilsMock } from '../../build/types/MathUtilsMock'

import * as deployment from '../lib/deployment'
import { getAccounts, toGRT, Account, MAX_PPM, totalRatio } from '../lib/testHelpers'

describe('MathUtils', () => {
  let me: Account

  let mathUtils: MathUtilsMock

  beforeEach(async function () {
    ;[me] = await getAccounts()
    mathUtils = (await deployment.deployContract('MathUtilsMock', me.signer)) as MathUtilsMock
  })

  describe('ratio', () => {
    it('a = b', async function () {
      const a = toGRT('1')
      const b = toGRT('1')
      const c = await mathUtils.totalRatio(a, b)
      expect(c).eq(totalRatio(a, b))
    })

    it('a > b', async function () {
      const a = toGRT('1000')
      const b = toGRT('1')
      const c = await mathUtils.totalRatio(a, b)
      expect(c).eq(totalRatio(a, b))
    })

    it('a < b', async function () {
      const a = toGRT('1')
      const b = toGRT('1000')
      const c = await mathUtils.totalRatio(a, b)
      expect(c).eq(totalRatio(a, b))
    })

    it('edge a < b', async function () {
      const a = 1
      const b = toGRT('1000')
      const c = await mathUtils.totalRatio(a, b)
      expect(c).eq(0) // not enough precision
    })

    it('edge a > b', async function () {
      const a = toGRT('1000')
      const b = 1
      const c = await mathUtils.totalRatio(a, b)
      expect(c).eq(totalRatio(a, BigNumber.from(b)))
    })

    it('edge a=0 b=~', async function () {
      const a = 0
      const b = toGRT('1000')
      const c = await mathUtils.totalRatio(a, b)
      expect(c).eq(0)
    })

    it('edge a=~ b=0', async function () {
      const a = toGRT('1000')
      const b = 0
      const c = await mathUtils.totalRatio(a, b)
      expect(c).eq(MAX_PPM)
    })
  })
})
