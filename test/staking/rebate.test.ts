import { expect } from 'chai'
import { BigNumber } from 'ethers'

import { deployContract } from '../lib/deployment'
import { RebatePoolMock } from '../../build/types/RebatePoolMock'

import { getAccounts, toBN, toGRT, formatGRT, Account, initNetwork } from '../lib/testHelpers'

const toFloat = (n: BigNumber) => parseFloat(formatGRT(n))
const toFixed = (n: number | BigNumber, precision = 12) => {
  if (typeof n === 'number') {
    return n.toFixed(precision)
  }
  return toFloat(n).toFixed(precision)
}

type RebateRatio = number[]

interface RebateTestCase {
  totalRewards: number
  fees: number
  totalFees: number
  stake: number
  totalStake: number
}

describe('Staking:Rebate', () => {
  let deployer: Account

  let rebatePoolMock: RebatePoolMock

  const testCases: RebateTestCase[] = [
    { totalRewards: 1400, fees: 100, totalFees: 1400, stake: 5000, totalStake: 7300 },
    { totalRewards: 1400, fees: 300, totalFees: 1400, stake: 600, totalStake: 7300 },
    { totalRewards: 1400, fees: 1000, totalFees: 1400, stake: 500, totalStake: 7300 },
    { totalRewards: 1400, fees: 0, totalFees: 1400, stake: 1200, totalStake: 7300 },
  ]

  // Edge case #1 - No closed allocations any query fees
  const edgeCases1: RebateTestCase[] = [
    { totalRewards: 0, fees: 0, totalFees: 0, stake: 5000, totalStake: 7300 },
    { totalRewards: 0, fees: 0, totalFees: 0, stake: 600, totalStake: 7300 },
    { totalRewards: 0, fees: 0, totalFees: 0, stake: 500, totalStake: 7300 },
    { totalRewards: 0, fees: 0, totalFees: 0, stake: 1200, totalStake: 7300 },
  ]

  // Edge case #2 - Closed allocations with queries but no stake
  const edgeCases2: RebateTestCase[] = [
    { totalRewards: 1300, fees: 100, totalFees: 1300, stake: 0, totalStake: 0 },
    { totalRewards: 1300, fees: 0, totalFees: 1300, stake: 0, totalStake: 0 },
    { totalRewards: 1300, fees: 200, totalFees: 1300, stake: 0, totalStake: 0 },
    { totalRewards: 1300, fees: 1000, totalFees: 1300, stake: 0, totalStake: 0 },
  ]

  // This function calculates the Cobb-Douglas formula in Typescript so we can compare against
  // the Solidity implementation
  // TODO: consider using bignumber.js to get extra precision
  function cobbDouglas(
    totalRewards: number,
    fees: number,
    totalFees: number,
    stake: number,
    totalStake: number,
    alphaNumerator: number,
    alphaDenominator: number,
  ) {
    if (totalFees === 0 || totalStake === 0) {
      return 0
    }
    const feeRatio = fees / totalFees
    const stakeRatio = stake / totalStake
    const alpha = alphaNumerator / alphaDenominator
    return totalRewards * feeRatio ** alpha * stakeRatio ** (1 - alpha)
  }

  // Test if the Solidity implementation of the rebate formula match the local implementation
  async function shouldMatchFormulas(testCases: RebateTestCase[], alpha: RebateRatio) {
    const [alphaNumerator, alphaDenominator] = alpha

    for (const testCase of testCases) {
      // Test Typescript cobb-doubglas formula implementation
      const r1 = cobbDouglas(
        testCase.totalRewards,
        testCase.fees,
        testCase.totalFees,
        testCase.stake,
        testCase.totalStake,
        alphaNumerator,
        alphaDenominator,
      )
      // Convert non-alpha values to wei before sending for precision
      const r2 = await rebatePoolMock.cobbDouglas(
        toGRT(testCase.totalRewards),
        toGRT(testCase.fees),
        toGRT(testCase.totalFees),
        toGRT(testCase.stake),
        toGRT(testCase.totalStake),
        alphaNumerator,
        alphaDenominator,
      )

      // Must match : contracts to local implementation
      expect(toFixed(r1)).eq(toFixed(r2))
    }
  }

  // Test if the fees deposited into the rebate pool are conserved, this means that we are
  // not able to extract more rewards than we initially deposited
  async function shouldConserveBalances(testCases: RebateTestCase[], alpha: RebateRatio) {
    const [alphaNumerator, alphaDenominator] = alpha
    await rebatePoolMock.setRebateRatio(alphaNumerator, alphaDenominator)

    let totalFees = toBN(0)
    for (const testCase of testCases) {
      totalFees = totalFees.add(toGRT(testCase.fees))
      await rebatePoolMock.add(toGRT(testCase.fees), toGRT(testCase.stake))
    }

    let totalRewards = toBN(0)
    for (const testCase of testCases) {
      const rewards = await redeem(toGRT(testCase.fees), toGRT(testCase.stake))
      totalRewards = totalRewards.add(rewards)
    }

    expect(totalRewards).lte(totalFees)
  }

  async function shouldMatchOut(testCases: RebateTestCase[], alpha: RebateRatio) {
    const [alphaNumerator, alphaDenominator] = alpha
    await rebatePoolMock.setRebateRatio(alphaNumerator, alphaDenominator)

    let totalFees = toBN(0)
    for (const testCase of testCases) {
      totalFees = totalFees.add(toGRT(testCase.fees))
      await rebatePoolMock.add(toGRT(testCase.fees), toGRT(testCase.stake))
    }

    for (const testCase of testCases) {
      const rebatePool = await rebatePoolMock.rebatePool()
      const unclaimedFees = rebatePool.fees.sub(rebatePool.claimedRewards)
      const rewards = await redeem(toGRT(testCase.fees), toGRT(testCase.stake))
      let expectedOut = await rebatePoolMock.cobbDouglas(
        toGRT(testCase.totalRewards),
        toGRT(testCase.fees),
        toGRT(testCase.totalFees),
        toGRT(testCase.stake),
        toGRT(testCase.totalStake),
        alphaNumerator,
        alphaDenominator,
      )
      if (expectedOut.gt(unclaimedFees)) {
        expectedOut = unclaimedFees
      }
      expect(rewards).eq(expectedOut)
    }
  }

  async function redeem(fees: BigNumber, stake: BigNumber): Promise<BigNumber> {
    const tx = await rebatePoolMock.pop(fees, stake)
    const rx = await tx.wait()
    return rx.events[0].args[0]
  }

  async function testAlphas(fn, testCases) {
    // Typical alpha
    it('alpha 0.90', async function () {
      const alpha: RebateRatio = [90, 100]
      await fn(testCases, alpha)
    })

    // Typical alpha
    it('alpha 0.25', async function () {
      const alpha: RebateRatio = [1, 4]
      await fn(testCases, alpha)
    })

    // Periodic alpha
    it('alpha 0.33~', async function () {
      const alpha: RebateRatio = [1, 3]
      await fn(testCases, alpha)
    })

    // Small alpha
    it('alpha 0.005', async function () {
      const alpha: RebateRatio = [1, 200]
      await fn(testCases, alpha)
    })

    // Edge alpha
    it('alpha 1', async function () {
      const alpha: RebateRatio = [1, 1]
      await fn(testCases, alpha)
    })
  }

  beforeEach(async function () {
    await initNetwork()
    ;[deployer] = await getAccounts()
    rebatePoolMock = (await deployContract(
      'RebatePoolMock',
      deployer.signer,
    )) as unknown as RebatePoolMock
  })

  describe('should match cobb-douglas Solidity implementation', function () {
    describe('normal test case', function () {
      testAlphas(shouldMatchFormulas, testCases)
    })

    describe('edge #1 test case', function () {
      testAlphas(shouldMatchFormulas, edgeCases1)
    })

    describe('edge #2 test case', function () {
      testAlphas(shouldMatchFormulas, edgeCases2)
    })
  })

  describe('should match rewards out from rebates', function () {
    describe('normal test case', function () {
      testAlphas(shouldMatchOut, testCases)
    })

    describe('edge #1 test case', function () {
      testAlphas(shouldMatchOut, edgeCases1)
    })

    describe('edge #2 test case', function () {
      testAlphas(shouldMatchFormulas, edgeCases2)
    })
  })

  describe('should always be that sum of rebate rewards obtained <= to total rewards', function () {
    describe('normal test case', function () {
      testAlphas(shouldConserveBalances, testCases)
    })

    describe('edge #1 test case', function () {
      testAlphas(shouldConserveBalances, edgeCases1)
    })

    describe('edge #2 test case', function () {
      testAlphas(shouldMatchFormulas, edgeCases2)
    })
  })
})
