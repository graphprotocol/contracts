/**
 * Enhanced Test Fixtures with Performance Optimizations
 * Consolidates common test setup patterns and reduces duplication
 */

import hre from 'hardhat'

import * as fixtures from '../tests/helpers/fixtures'
import { TestConstants } from './testPatterns'
const { ethers } = hre

/**
 * Enhanced fixture for complete issuance system with optimized setup
 */
export async function setupOptimizedIssuanceSystem(customOptions: any = {}) {
  const accounts = await fixtures.getTestAccounts()

  const options = {
    issuancePerBlock: fixtures.Constants.DEFAULT_ISSUANCE_PER_BLOCK,
    setupMinterRole: true,
    setupTargets: true,
    targetCount: 2,
    ...customOptions,
  }

  // Deploy core system
  const { graphToken, issuanceAllocator, target1, target2, rewardsEligibilityOracle } =
    await fixtures.deployIssuanceSystem(accounts, options.issuancePerBlock)

  // Cache addresses to avoid repeated getAddress() calls
  const addresses = {
    graphToken: await graphToken.getAddress(),
    issuanceAllocator: await issuanceAllocator.getAddress(),
    target1: await target1.getAddress(),
    target2: await target2.getAddress(),
    rewardsEligibilityOracle: await rewardsEligibilityOracle.getAddress(),
  }

  // Setup minter role if requested
  if (options.setupMinterRole) {
    await (graphToken as any).addMinter(addresses.issuanceAllocator)
  }

  // Setup default targets if requested
  if (options.setupTargets) {
    await issuanceAllocator
      .connect(accounts.governor)
      [
        'setTargetAllocation(address,uint256,uint256,bool)'
      ](addresses.target1, TestConstants.ALLOCATION_30_PERCENT, 0, false)

    if (options.targetCount >= 2) {
      await issuanceAllocator
        .connect(accounts.governor)
        [
          'setTargetAllocation(address,uint256,uint256,bool)'
        ](addresses.target2, TestConstants.ALLOCATION_20_PERCENT, 0, false)
    }
  }

  return {
    accounts,
    contracts: {
      graphToken,
      issuanceAllocator,
      target1,
      target2,
      rewardsEligibilityOracle,
    },
    addresses,
    helpers: {
      // Helper to reset state without redeploying
      resetState: async () => {
        // Remove all targets
        const targets = await issuanceAllocator.getTargets()
        for (const targetAddr of targets) {
          await issuanceAllocator
            .connect(accounts.governor)
            ['setTargetAllocation(address,uint256,uint256,bool)'](targetAddr, 0, 0, false)
        }

        // Reset issuance rate
        await issuanceAllocator.connect(accounts.governor).setIssuancePerBlock(options.issuancePerBlock, false)
      },

      // Helper to setup standard allocations
      setupStandardAllocations: async () => {
        await issuanceAllocator
          .connect(accounts.governor)
          [
            'setTargetAllocation(address,uint256,uint256,bool)'
          ](addresses.target1, TestConstants.ALLOCATION_30_PERCENT, 0, false)
        await issuanceAllocator
          .connect(accounts.governor)
          [
            'setTargetAllocation(address,uint256,uint256,bool)'
          ](addresses.target2, TestConstants.ALLOCATION_40_PERCENT, 0, false)
      },

      // Helper to verify proportional distributions
      verifyProportionalDistribution: async (expectedRatios: number[]) => {
        const balance1: bigint = await (graphToken as any).balanceOf(addresses.target1)
        const balance2: bigint = await (graphToken as any).balanceOf(addresses.target2)

        if (balance2 > 0n) {
          const ratio: bigint = (balance1 * TestConstants.RATIO_PRECISION) / balance2
          const expectedRatio: bigint = BigInt(
            Math.round((expectedRatios[0] / expectedRatios[1]) * Number(TestConstants.RATIO_PRECISION)),
          )

          // Allow for small rounding errors
          const tolerance: bigint = 50n // TestConstants.DEFAULT_TOLERANCE
          const diff: bigint = ratio > expectedRatio ? ratio - expectedRatio : expectedRatio - ratio

          if (diff > tolerance) {
            throw new Error(
              `Distribution ratio ${ratio} does not match expected ${expectedRatio} within tolerance ${tolerance}`,
            )
          }
        }
      },
    },
  }
}

/**
 * Lightweight fixture for testing single contracts
 */
export async function setupSingleContract(
  contractType: 'issuanceAllocator' | 'directAllocation' | 'rewardsEligibilityOracle',
) {
  const accounts = await fixtures.getTestAccounts()
  const graphToken = await fixtures.deployTestGraphToken()
  const graphTokenAddress = await graphToken.getAddress()

  let contract: any

  switch (contractType) {
    case 'issuanceAllocator':
      contract = await fixtures.deployIssuanceAllocator(
        graphTokenAddress,
        accounts.governor,
        fixtures.Constants.DEFAULT_ISSUANCE_PER_BLOCK,
      )
      break
    case 'directAllocation':
      contract = await fixtures.deployDirectAllocation(graphTokenAddress, accounts.governor)
      break
    case 'rewardsEligibilityOracle':
      contract = await fixtures.deployRewardsEligibilityOracle(graphTokenAddress, accounts.governor)
      break
    default:
      throw new Error(`Unknown contract type: ${contractType}`)
  }

  return {
    accounts,
    contract,
    graphToken,
    addresses: {
      contract: await contract.getAddress(),
      graphToken: graphTokenAddress,
    },
  }
}

/**
 * Shared test data for consistent testing
 */
export const TestData = {
  // Standard allocation scenarios
  scenarios: {
    balanced: [
      { target: 'target1', allocatorPPM: TestConstants.ALLOCATION_30_PERCENT, selfPPM: 0 },
      { target: 'target2', allocatorPPM: TestConstants.ALLOCATION_40_PERCENT, selfPPM: 0 },
    ],
    mixed: [
      { target: 'target1', allocatorPPM: TestConstants.ALLOCATION_20_PERCENT, selfPPM: 0 },
      { target: 'target2', allocatorPPM: 0, selfPPM: TestConstants.ALLOCATION_30_PERCENT },
    ],
    selfMintingOnly: [
      { target: 'target1', allocatorPPM: 0, selfPPM: TestConstants.ALLOCATION_50_PERCENT },
      { target: 'target2', allocatorPPM: 0, selfPPM: TestConstants.ALLOCATION_30_PERCENT },
    ],
  },

  // Standard test parameters
  issuanceRates: {
    low: ethers.parseEther('10'),
    medium: ethers.parseEther('100'),
    high: ethers.parseEther('1000'),
  },

  // Common test tolerances
  tolerances: {
    strict: 1n,
    normal: 50n, // TestConstants.DEFAULT_TOLERANCE
    loose: 100n, // TestConstants.DEFAULT_TOLERANCE * 2n
  },
}

/**
 * Helper to apply a scenario to contracts
 */
export async function applyAllocationScenario(issuanceAllocator: any, addresses: any, scenario: any[], governor: any) {
  for (const allocation of scenario) {
    const targetAddress = addresses[allocation.target]
    await issuanceAllocator
      .connect(governor)
      [
        'setTargetAllocation(address,uint256,uint256,bool)'
      ](targetAddress, allocation.allocatorPPM, allocation.selfPPM, false)
  }
}

/**
 * OptimizedFixtures class for managing test contracts and state
 */
export class OptimizedFixtures {
  private accounts: any
  private sharedContracts: any = null

  constructor(accounts: any) {
    this.accounts = accounts
  }

  async setupDirectAllocationSuite() {
    const graphToken = await fixtures.deployTestGraphToken()
    const graphTokenAddress = await graphToken.getAddress()
    const directAllocation = await fixtures.deployDirectAllocation(graphTokenAddress, this.accounts.governor)
    const directAllocationAddress = await directAllocation.getAddress()

    const { GraphTokenHelper } = require('../tests/helpers/graphTokenHelper')
    const graphTokenHelper = new GraphTokenHelper(graphToken, this.accounts.governor)

    this.sharedContracts = {
      graphToken,
      directAllocation,
      graphTokenHelper,
      addresses: {
        graphToken: graphTokenAddress,
        directAllocation: directAllocationAddress,
      },
    }
  }

  getContracts() {
    if (!this.sharedContracts) {
      throw new Error('Contracts not initialized. Call setupDirectAllocationSuite() first.')
    }
    return this.sharedContracts
  }

  async resetContractsState() {
    if (!this.sharedContracts) return

    const { directAllocation } = this.sharedContracts
    const { ROLES } = require('./testPatterns')

    // Reset pause state
    try {
      if (await directAllocation.paused()) {
        await directAllocation.connect(this.accounts.governor).unpause()
      }
    } catch {
      // Ignore if not paused
    }

    // Remove all roles except governor
    try {
      for (const account of [this.accounts.operator, this.accounts.user, this.accounts.nonGovernor]) {
        if (await directAllocation.hasRole(ROLES.OPERATOR, account.address)) {
          await directAllocation.connect(this.accounts.governor).revokeRole(ROLES.OPERATOR, account.address)
        }
        if (await directAllocation.hasRole(ROLES.PAUSE, account.address)) {
          await directAllocation.connect(this.accounts.governor).revokeRole(ROLES.PAUSE, account.address)
        }
      }

      // Remove pause role from governor if present
      if (await directAllocation.hasRole(ROLES.PAUSE, this.accounts.governor.address)) {
        await directAllocation.connect(this.accounts.governor).revokeRole(ROLES.PAUSE, this.accounts.governor.address)
      }
    } catch {
      // Ignore role management errors during reset
    }
  }

  async createFreshDirectAllocation() {
    const graphToken = await fixtures.deployTestGraphToken()
    const graphTokenAddress = await graphToken.getAddress()
    const directAllocation = await fixtures.deployDirectAllocation(graphTokenAddress, this.accounts.governor)

    const { GraphTokenHelper } = require('../tests/helpers/graphTokenHelper')
    const graphTokenHelper = new GraphTokenHelper(graphToken, this.accounts.governor)

    return {
      directAllocation,
      graphToken,
      graphTokenHelper,
      addresses: {
        graphToken: graphTokenAddress,
        directAllocation: await directAllocation.getAddress(),
      },
    }
  }
}
