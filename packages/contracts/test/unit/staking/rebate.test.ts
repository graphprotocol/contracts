import hre from 'hardhat'
import { expect } from 'chai'
import { BigNumber, Contract } from 'ethers'

import { LibExponential } from '../../../build/types/LibExponential'

import { formatGRT, isGraphL1ChainId, toGRT } from '@graphprotocol/sdk'
import { SignerWithAddress } from '@nomiclabs/hardhat-ethers/signers'
import { NetworkFixture } from '../lib/fixtures'

const toFloat = (n: BigNumber) => parseFloat(formatGRT(n))
const toFixed = (n: number | BigNumber, precision = 12) => {
  if (typeof n === 'number') {
    return n.toFixed(precision)
  }
  return toFloat(n).toFixed(precision)
}

const ABI_LIB_EXPONENTIAL = [
  {
    inputs: [
      {
        internalType: 'uint256',
        name: 'fees',
        type: 'uint256',
      },
      {
        internalType: 'uint256',
        name: 'stake',
        type: 'uint256',
      },
      {
        internalType: 'uint32',
        name: 'alphaNumerator',
        type: 'uint32',
      },
      {
        internalType: 'uint32',
        name: 'alphaDenominator',
        type: 'uint32',
      },
      {
        internalType: 'uint32',
        name: 'lambdaNumerator',
        type: 'uint32',
      },
      {
        internalType: 'uint32',
        name: 'lambdaDenominator',
        type: 'uint32',
      },
    ],
    name: 'exponentialRebates',
    outputs: [
      {
        internalType: 'uint256',
        name: '',
        type: 'uint256',
      },
    ],
    stateMutability: 'pure',
    type: 'function',
  },
]

type RebateParameters = number[]

interface RebateTestCase {
  totalRewards: number
  fees: number
  totalFees: number
  stake: number
  totalStake: number
}

// This function calculates the exponential rebates formula in Typescript so we can compare against
// the Solidity implementation
export function exponentialRebates(
  fees: number,
  stake: number,
  alphaNumerator: number,
  alphaDenominator: number,
  lambdaNumerator: number,
  lambdaDenominator: number,
): number {
  const alpha = alphaNumerator / alphaDenominator
  if (alpha === 0) {
    return fees
  }

  const lambda = lambdaNumerator / lambdaDenominator
  if (fees === 0) {
    return 0
  }

  const exponent = (lambda * stake) / fees
  // eslint-disable-next-line no-secrets/no-secrets
  // LibExponential.MAX_EXPONENT = 15
  if (exponent > 15) {
    return fees
  }

  return fees * (1 - alpha * Math.exp(-exponent))
}

describe('Staking:rebates', () => {
  const graph = hre.graph({ addressBook: 'addresses-local.json' })

  let libExponential: LibExponential
  let fixture: NetworkFixture

  let governor: SignerWithAddress

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

  // Test if the Solidity implementation of the rebate formula match the local implementation
  async function shouldMatchFormulas(testCases: RebateTestCase[], rebateParams: RebateParameters) {
    const [alphaNumerator, alphaDenominator, lambdaNumerator, lambdaDenominator] = rebateParams

    for (const testCase of testCases) {
      // Test Typescript exponential rebates formula implementation
      const r1 = exponentialRebates(
        testCase.fees,
        testCase.stake,
        alphaNumerator,
        alphaDenominator,
        lambdaNumerator,
        lambdaDenominator,
      )

      // Convert non-alpha values to wei before sending for precision
      const r2 = await libExponential.exponentialRebates(
        toGRT(testCase.fees),
        toGRT(testCase.stake),
        alphaNumerator,
        alphaDenominator,
        lambdaNumerator,
        lambdaDenominator,
      )

      // Must match : contracts to local implementation
      expect(toFixed(r1)).eq(toFixed(r2))
    }
  }

  function testRebateParameters(fn, testCases) {
    // *** Exponential rebates ***
    // Typical alpha and lambda
    it('alpha 1 - lambda 0.6', async function () {
      const params: RebateParameters = [10, 10, 6, 10]
      await fn(testCases, params)
    })

    // Typical alpha and lambda
    it('alpha 0.25 - lambda 0.1', async function () {
      const params: RebateParameters = [1, 4, 1, 10]
      await fn(testCases, params)
    })

    // Periodic alpha and lambda
    it('alpha ~0.33 - lambda ~0.66', async function () {
      const params: RebateParameters = [1, 3, 2, 3]
      await fn(testCases, params)
    })

    // Small alpha typical lambda
    it('alpha 0.005 - lambda 0.6', async function () {
      const params: RebateParameters = [1, 200, 6, 10]
      await fn(testCases, params)
    })

    // Typical alpha small lambda
    it('alpha 1 - lambda 0.6', async function () {
      const params: RebateParameters = [1, 1, 1, 200]
      await fn(testCases, params)
    })

    // Edge alpha - typical lambda
    it('alpha 0 - lambda 0.6', async function () {
      const params: RebateParameters = [0, 1, 6, 10]
      await fn(testCases, params)
    })

    // Typical alpha - edge lambda
    it('alpha 1 - lambda 0', async function () {
      const params: RebateParameters = [1, 1, 0, 10]
      await fn(testCases, params)
    })
  }

  before(async function () {
    ({ governor } = await graph.getNamedAccounts())
    fixture = new NetworkFixture(graph.provider)
    await fixture.load(governor)

    const stakingName = isGraphL1ChainId(graph.chainId) ? 'L1Staking' : 'L2Staking'
    const entry = graph.addressBook.getEntry(stakingName)
    libExponential = new Contract(
      entry.implementation.libraries.LibExponential,
      ABI_LIB_EXPONENTIAL,
      graph.provider,
    ) as LibExponential
  })

  describe('should match rebates Solidity implementation', function () {
    describe('normal test case', function () {
      testRebateParameters(shouldMatchFormulas, testCases)
    })

    describe('edge #1 test case', function () {
      testRebateParameters(shouldMatchFormulas, edgeCases1)
    })

    describe('edge #2 test case', function () {
      testRebateParameters(shouldMatchFormulas, edgeCases2)
    })
  })
})
