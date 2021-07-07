import { expect } from 'chai'
import { BigNumber } from 'ethers'

import { MathUtilsMock } from '../../build/types/MathUtilsMock'

import * as deployment from '../lib/deployment'
import {
  getAccounts,
  toGRT,
  Account,
  MAX_PPM,
  totalRatio,
  percentageOf,
  formatGRT,
} from '../lib/testHelpers'

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

  describe('percentage', () => {
    const percentTests: BigNumber[] = [
      0,
      1,
      2,
      1e6 * 0.1,
      1e6 * 0.25,
      1e6 * 0.5,
      1e6 * 0.75,
      1e6 * 0.9,
      1e6 * 1.0,
    ].map((e) => BigNumber.from(e))
    const valueTests: BigNumber[] = [1, 2, 3, toGRT(5000)].map((e) => BigNumber.from(e))

    for (const percent of percentTests) {
      for (const value of valueTests) {
        it(`${(percent.toNumber() / 1e6) * 100}% of ${formatGRT(value)} GRT`, async function () {
          const c = (await mathUtils.percentOf(percent, value)) as BigNumber
          expect(c).eq(percentageOf(percent, value))
        })
      }
    }
  })
})
