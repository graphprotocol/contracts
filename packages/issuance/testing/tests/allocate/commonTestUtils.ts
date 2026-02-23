/**
 * Common test utilities for access control and other shared test patterns
 */

import { expect } from 'chai'
import type { Contract } from 'ethers'

import type { HardhatEthersSigner } from '../common/ethersHelper'

/**
 * Test multiple access control methods on a contract
 * @param contract - The contract to test
 * @param methods - Array of methods to test with their arguments
 * @param authorizedAccount - Account that should have access
 * @param unauthorizedAccount - Account that should not have access
 */

export async function testMultipleAccessControl(
  contract: Contract,
  methods: Array<{
    method: string
    args: unknown[]
    description: string
  }>,
  authorizedAccount: HardhatEthersSigner,
  unauthorizedAccount: HardhatEthersSigner,
): Promise<void> {
  for (const methodConfig of methods) {
    const { method, args, description: _description } = methodConfig

    // Test that unauthorized account is rejected
    await expect(contract.connect(unauthorizedAccount)[method](...args)).to.be.revertedWithCustomError(
      contract,
      'AccessControlUnauthorizedAccount',
    )

    // Test that authorized account can call the method (if it exists and is callable)
    try {
      // Some methods might revert for business logic reasons even with proper access
      // We just want to ensure they don't revert with AccessControlUnauthorizedAccount
      await contract.connect(authorizedAccount)[method](...args)
    } catch (error: any) {
      // If it reverts, make sure it's not due to access control
      expect(error.message).to.not.include('AccessControlUnauthorizedAccount')
    }
  }
}
