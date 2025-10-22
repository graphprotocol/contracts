/**
 * Shared test patterns and utilities to reduce duplication across test files
 */

import { expect } from 'chai'
import { ethers } from 'hardhat'

// Type definitions for test utilities
export interface TestAccounts {
  governor: any
  nonGovernor: any
  operator: any
  user: any
  indexer1: any
  indexer2: any
  selfMintingTarget: any
}

export interface ContractWithMethods {
  connect(signer: any): ContractWithMethods
  [methodName: string]: any
}

// Test constants - centralized to avoid magic numbers
export const TestConstants = {
  // Precision and tolerance constants
  RATIO_PRECISION: 1000n,
  DEFAULT_TOLERANCE: 50n,
  STRICT_TOLERANCE: 10n,

  // Common allocation percentages in PPM
  ALLOCATION_10_PERCENT: 100_000,
  ALLOCATION_20_PERCENT: 200_000,
  ALLOCATION_30_PERCENT: 300_000,
  ALLOCATION_40_PERCENT: 400_000,
  ALLOCATION_50_PERCENT: 500_000,
  ALLOCATION_60_PERCENT: 600_000,
  ALLOCATION_100_PERCENT: 1_000_000,

  // Role constants - pre-calculated to avoid repeated contract calls
  GOVERNOR_ROLE: ethers.keccak256(ethers.toUtf8Bytes('GOVERNOR_ROLE')),
  OPERATOR_ROLE: ethers.keccak256(ethers.toUtf8Bytes('OPERATOR_ROLE')),
  PAUSE_ROLE: ethers.keccak256(ethers.toUtf8Bytes('PAUSE_ROLE')),
  ORACLE_ROLE: ethers.keccak256(ethers.toUtf8Bytes('ORACLE_ROLE')),
} as const

// Consolidated role constants
export const ROLES = {
  GOVERNOR: TestConstants.GOVERNOR_ROLE,
  OPERATOR: TestConstants.OPERATOR_ROLE,
  PAUSE: TestConstants.PAUSE_ROLE,
  ORACLE: TestConstants.ORACLE_ROLE,
} as const

/**
 * Shared test pattern for governor-only access control
 */
export function shouldEnforceGovernorRole<T>(
  contractGetter: () => T,
  methodName: string,
  methodArgs: any[] = [],
  accounts?: any,
) {
  return function () {
    it(`should revert when non-governor calls ${methodName}`, async function () {
      const contract = contractGetter()
      const testAccounts = accounts || this.parent.ctx.accounts

      await expect(
        (contract as any).connect(testAccounts.nonGovernor)[methodName](...methodArgs),
      ).to.be.revertedWithCustomError(contract as any, 'AccessControlUnauthorizedAccount')
    })

    it(`should allow governor to call ${methodName}`, async function () {
      const contract = contractGetter()
      const testAccounts = accounts || this.parent.ctx.accounts

      await expect((contract as any).connect(testAccounts.governor)[methodName](...methodArgs)).to.not.be.reverted
    })
  }
}

/**
 * Shared test pattern for role-based access control
 */
export function shouldEnforceRoleAccess<T>(
  contractGetter: () => T,
  methodName: string,
  requiredRole: string,
  methodArgs: any[] = [],
  accounts?: any,
) {
  return function () {
    it(`should revert when account without ${requiredRole} calls ${methodName}`, async function () {
      const contract = contractGetter()
      const testAccounts = accounts || this.parent.ctx.accounts

      await expect(
        (contract as any).connect(testAccounts.nonGovernor)[methodName](...methodArgs),
      ).to.be.revertedWithCustomError(contract as any, 'AccessControlUnauthorizedAccount')
    })
  }
}

/**
 * Calculate ratio between two values with precision
 */
export function calculateRatio(
  value1: bigint,
  value2: bigint,
  precision: bigint = TestConstants.RATIO_PRECISION,
): bigint {
  return (value1 * precision) / value2
}

/**
 * Helper to verify ratio matches expected value within tolerance
 */
export function expectRatioToEqual(
  actual1: bigint,
  actual2: bigint,
  expectedRatio: bigint,
  tolerance: bigint = TestConstants.DEFAULT_TOLERANCE,
  precision: bigint = TestConstants.RATIO_PRECISION,
) {
  const actualRatio = calculateRatio(actual1, actual2, precision)
  expect(actualRatio).to.be.closeTo(expectedRatio, tolerance)
}

/**
 * Shared test pattern for initialization
 */
export function shouldInitializeCorrectly<T>(contractGetter: () => T, expectedValues: Record<string, any>) {
  return function () {
    Object.entries(expectedValues).forEach(([property, expectedValue]) => {
      it(`should set ${property} correctly during initialization`, async function () {
        const contract = contractGetter()
        // Type assertion is necessary here since we're accessing dynamic properties
        const actualValue = await (contract as any)[property]()
        expect(actualValue).to.equal(expectedValue)
      })
    })

    it('should revert when initialize is called more than once', async function () {
      const contract = contractGetter()
      const accounts = this.parent.ctx.accounts

      await expect((contract as any).initialize(accounts.governor.address)).to.be.revertedWithCustomError(
        contract as any,
        'InvalidInitialization',
      )
    })
  }
}

/**
 * Shared test pattern for pausing functionality
 */
export function shouldHandlePausingCorrectly<T>(
  contractGetter: () => T,
  pauseRoleAccount: any,
  methodName: string = 'distributeIssuance',
) {
  return function () {
    it('should allow pausing and unpausing by authorized account', async function () {
      const contract = contractGetter()

      await (contract as any).connect(pauseRoleAccount).pause()
      expect(await (contract as any).paused()).to.be.true

      await (contract as any).connect(pauseRoleAccount).unpause()
      expect(await (contract as any).paused()).to.be.false
    })

    it(`should handle ${methodName} when paused`, async function () {
      const contract = contractGetter()

      await (contract as any).connect(pauseRoleAccount).pause()

      // Should not revert when paused, but behavior may differ
      await expect((contract as any)[methodName]()).to.not.be.reverted
    })
  }
}

/**
 * Helper for mining blocks consistently across tests
 */
export async function mineBlocks(count: number): Promise<void> {
  for (let i = 0; i < count; i++) {
    await ethers.provider.send('evm_mine', [])
  }
}

/**
 * Helper to get current block number
 */
export async function getCurrentBlockNumber(): Promise<number> {
  return await ethers.provider.getBlockNumber()
}

/**
 * Helper to disable/enable auto-mining for precise block control
 */
export async function withAutoMiningDisabled<T>(callback: () => Promise<T>): Promise<T> {
  await ethers.provider.send('evm_setAutomine', [false])
  try {
    return await callback()
  } finally {
    await ethers.provider.send('evm_setAutomine', [true])
  }
}

/**
 * Helper to verify role assignment
 */
export async function expectRole(contract: any, role: string, account: string, shouldHaveRole: boolean) {
  const hasRole = await contract.hasRole(role, account)
  expect(hasRole).to.equal(shouldHaveRole)
}

/**
 * Helper to verify transaction reverts with specific error
 */
export async function expectRevert(transactionPromise: Promise<any>, errorName: string, contract?: any) {
  if (contract) {
    await expect(transactionPromise).to.be.revertedWithCustomError(contract, errorName)
  } else {
    await expect(transactionPromise).to.be.revertedWith(errorName)
  }
}

/**
 * Comprehensive access control test suite for a contract
 * Replaces multiple individual access control tests
 */
export function shouldEnforceAccessControl<T>(
  contractGetter: () => T,
  methods: Array<{
    name: string
    args: any[]
    requiredRole?: string
    allowedRoles?: string[]
  }>,
  accounts: any,
) {
  return function () {
    methods.forEach((method) => {
      const allowedRoles = method.allowedRoles || [TestConstants.GOVERNOR_ROLE]

      describe(`${method.name} access control`, () => {
        it(`should revert when unauthorized account calls ${method.name}`, async function () {
          const contract = contractGetter()
          await expect(
            (contract as any).connect(accounts.nonGovernor)[method.name](...method.args),
          ).to.be.revertedWithCustomError(contract as any, 'AccessControlUnauthorizedAccount')
        })

        allowedRoles.forEach((role) => {
          const roleName =
            role === TestConstants.GOVERNOR_ROLE
              ? 'governor'
              : role === TestConstants.OPERATOR_ROLE
                ? 'operator'
                : 'authorized'
          const account =
            role === TestConstants.GOVERNOR_ROLE
              ? accounts.governor
              : role === TestConstants.OPERATOR_ROLE
                ? accounts.operator
                : accounts.governor

          it(`should allow ${roleName} to call ${method.name}`, async function () {
            const contract = contractGetter()
            await expect((contract as any).connect(account)[method.name](...method.args)).to.not.be.reverted
          })
        })
      })
    })
  }
}

/**
 * Comprehensive initialization test suite
 * Replaces multiple individual initialization tests
 */
export function shouldInitializeProperly<T>(
  contractGetter: () => T,
  initializationTests: Array<{
    description: string
    check: (contract: T) => Promise<void>
  }>,
  reinitializationTest?: {
    method: string
    args: any[]
    expectedError: string
  },
) {
  return function () {
    describe('Initialization', () => {
      initializationTests.forEach((test) => {
        it(test.description, async function () {
          const contract = contractGetter()
          await test.check(contract)
        })
      })

      if (reinitializationTest) {
        it('should revert when initialize is called more than once', async function () {
          const contract = contractGetter()
          await expect(
            (contract as any)[reinitializationTest.method](...reinitializationTest.args),
          ).to.be.revertedWithCustomError(contract as any, reinitializationTest.expectedError)
        })
      }
    })
  }
}

/**
 * Comprehensive pausability test suite
 * Replaces multiple individual pause/unpause tests
 */
export function shouldHandlePausability<T>(
  contractGetter: () => T,
  pausableOperations: Array<{
    name: string
    args: any[]
    caller: string
  }>,
  accounts: any,
) {
  return function () {
    describe('Pausability', () => {
      it('should allow PAUSE_ROLE to pause and unpause', async function () {
        const contract = contractGetter()

        // Grant pause role to operator
        await (contract as any)
          .connect(accounts.governor)
          .grantRole(TestConstants.PAUSE_ROLE, accounts.operator.address)

        // Should be able to pause
        await expect((contract as any).connect(accounts.operator).pause()).to.not.be.reverted
        expect(await (contract as any).paused()).to.be.true

        // Should be able to unpause
        await expect((contract as any).connect(accounts.operator).unpause()).to.not.be.reverted
        expect(await (contract as any).paused()).to.be.false
      })

      it('should revert when non-PAUSE_ROLE tries to pause', async function () {
        const contract = contractGetter()
        await expect((contract as any).connect(accounts.nonGovernor).pause()).to.be.revertedWithCustomError(
          contract as any,
          'AccessControlUnauthorizedAccount',
        )
      })

      pausableOperations.forEach((operation) => {
        it(`should revert ${operation.name} when paused`, async function () {
          const contract = contractGetter()
          const caller =
            operation.caller === 'governor'
              ? accounts.governor
              : operation.caller === 'operator'
                ? accounts.operator
                : accounts.nonGovernor

          // Grant pause role and pause
          await (contract as any)
            .connect(accounts.governor)
            .grantRole(TestConstants.PAUSE_ROLE, accounts.governor.address)
          await (contract as any).connect(accounts.governor).pause()

          await expect(
            (contract as any).connect(caller)[operation.name](...operation.args),
          ).to.be.revertedWithCustomError(contract as any, 'EnforcedPause')
        })
      })
    })
  }
}

/**
 * Comprehensive role management test suite
 * Replaces multiple individual role grant/revoke tests
 */
export function shouldManageRoles<T>(
  contractGetter: () => T,
  roles: Array<{
    role: string
    roleName: string
    grantableBy?: string[]
  }>,
  accounts: any,
) {
  return function () {
    describe('Role Management', () => {
      roles.forEach((roleConfig) => {
        const grantableBy = roleConfig.grantableBy || ['governor']

        describe(`${roleConfig.roleName} management`, () => {
          grantableBy.forEach((granterRole) => {
            const granter = granterRole === 'governor' ? accounts.governor : accounts.operator

            it(`should allow ${granterRole} to grant ${roleConfig.roleName}`, async function () {
              const contract = contractGetter()
              await expect((contract as any).connect(granter).grantRole(roleConfig.role, accounts.user.address)).to.not
                .be.reverted

              expect(await (contract as any).hasRole(roleConfig.role, accounts.user.address)).to.be.true
            })

            it(`should allow ${granterRole} to revoke ${roleConfig.roleName}`, async function () {
              const contract = contractGetter()

              // First grant the role
              await (contract as any).connect(granter).grantRole(roleConfig.role, accounts.user.address)

              // Then revoke it
              await expect((contract as any).connect(granter).revokeRole(roleConfig.role, accounts.user.address)).to.not
                .be.reverted

              expect(await (contract as any).hasRole(roleConfig.role, accounts.user.address)).to.be.false
            })
          })

          it(`should revert when non-authorized tries to grant ${roleConfig.roleName}`, async function () {
            const contract = contractGetter()
            await expect(
              (contract as any).connect(accounts.nonGovernor).grantRole(roleConfig.role, accounts.user.address),
            ).to.be.revertedWithCustomError(contract as any, 'AccessControlUnauthorizedAccount')
          })
        })
      })
    })
  }
}

/**
 * Comprehensive interface compliance test suite
 * Replaces multiple individual interface support tests
 *
 * @param contractGetter - Function that returns the contract instance to test
 * @param interfaces - Array of Typechain factory classes with interfaceId and interfaceName
 *
 * @example
 * import { IPausableControl__factory, IAccessControl__factory } from '@graphprotocol/interfaces/types'
 *
 * shouldSupportInterfaces(
 *   () => contract,
 *   [
 *     IPausableControl__factory,
 *     IAccessControl__factory,
 *   ]
 * )
 */
export function shouldSupportInterfaces<T>(
  contractGetter: () => T,
  interfaces: Array<{
    interfaceId: string
    interfaceName: string
  }>,
) {
  return function () {
    describe('Interface Compliance', () => {
      it('should support ERC-165 interface', async function () {
        const contract = contractGetter()
        expect(await (contract as any).supportsInterface('0x01ffc9a7')).to.be.true
      })

      interfaces.forEach((iface) => {
        it(`should support ${iface.interfaceName} interface`, async function () {
          const contract = contractGetter()
          expect(await (contract as any).supportsInterface(iface.interfaceId)).to.be.true
        })
      })

      it('should not support random interface', async function () {
        const contract = contractGetter()
        expect(await (contract as any).supportsInterface('0x12345678')).to.be.false
      })
    })
  }
}

/**
 * Comprehensive validation test suite
 * Replaces multiple individual validation tests
 */
export function shouldValidateInputs<T>(
  contractGetter: () => T,
  validationTests: Array<{
    method: string
    args: any[]
    expectedError: string
    description: string
    caller?: string
  }>,
  accounts: any,
) {
  return function () {
    describe('Input Validation', () => {
      validationTests.forEach((test) => {
        it(test.description, async function () {
          const contract = contractGetter()
          const caller =
            test.caller === 'operator' ? accounts.operator : test.caller === 'user' ? accounts.user : accounts.governor

          await expect((contract as any).connect(caller)[test.method](...test.args)).to.be.revertedWithCustomError(
            contract as any,
            test.expectedError,
          )
        })
      })
    })
  }
}

/**
 * Shared assertion helpers for common test patterns
 */
export const TestAssertions = {
  /**
   * Assert that a target received tokens proportionally
   */
  expectProportionalDistribution: (
    distributions: bigint[],
    expectedRatios: number[],
    tolerance: bigint = TestConstants.DEFAULT_TOLERANCE,
  ) => {
    for (let i = 1; i < distributions.length; i++) {
      const expectedRatio = BigInt(
        Math.round((expectedRatios[0] / expectedRatios[i]) * Number(TestConstants.RATIO_PRECISION)),
      )
      expectRatioToEqual(distributions[0], distributions[i], expectedRatio, tolerance)
    }
  },

  /**
   * Assert that balance increased by at least expected amount
   */
  expectBalanceIncreasedBy: (initialBalance: bigint, finalBalance: bigint, expectedIncrease: bigint) => {
    const actualIncrease = finalBalance - initialBalance
    expect(actualIncrease).to.be.gte(expectedIncrease)
  },

  /**
   * Assert that total allocations add up correctly
   */
  expectTotalAllocation: (contract: any, expectedTotal: number) => {
    return async () => {
      const totalAlloc = await contract.getTotalAllocation()
      expect(totalAlloc.totalAllocationPPM).to.equal(expectedTotal)
    }
  },
}

/**
 * Shared test patterns organized by functionality
 */
export const TestPatterns = {
  roleManagement: {
    grantRole: async (contract: any, granter: any, role: string, account: string) => {
      await contract.connect(granter).grantRole(role, account)
    },

    revokeRole: async (contract: any, revoker: any, role: string, account: string) => {
      await contract.connect(revoker).revokeRole(role, account)
    },
  },

  pausable: {
    pause: async (contract: any, account: any) => {
      await contract.connect(account).pause()
    },

    unpause: async (contract: any, account: any) => {
      await contract.connect(account).unpause()
    },
  },
}
