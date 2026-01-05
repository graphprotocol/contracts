import { expect } from 'chai'
import hre from 'hardhat'
const { ethers } = hre
const { upgrades } = require('hardhat')

import { deployTestGraphToken, getTestAccounts } from '../common/fixtures'

describe('IssuanceAllocator - Defensive Checks', function () {
  let accounts
  let issuanceAllocator
  let graphToken

  beforeEach(async function () {
    accounts = await getTestAccounts()
    graphToken = await deployTestGraphToken()

    // Deploy test harness as regular upgradeable contract with explicit validation skip
    const IssuanceAllocatorFactory = await ethers.getContractFactory('IssuanceAllocatorTestHarness')
    const issuanceAllocatorContract = await upgrades.deployProxy(
      IssuanceAllocatorFactory,
      [accounts.governor.address],
      {
        constructorArgs: [await graphToken.getAddress()],
        initializer: 'initialize',
        unsafeAllow: ['constructor', 'state-variable-immutable'],
      },
    )
    issuanceAllocator = issuanceAllocatorContract

    // Add IssuanceAllocator as minter
    await graphToken.connect(accounts.governor).addMinter(await issuanceAllocator.getAddress())
  })

  describe('_distributePendingProportionally defensive checks', function () {
    it('should return early when allocatedRate is 0', async function () {
      // Call exposed function with allocatedRate = 0
      // This should return early without reverting
      await expect(
        issuanceAllocator.exposed_distributePendingProportionally(
          100, // available
          0, // allocatedRate = 0 (defensive check)
          1000, // toBlockNumber
        ),
      ).to.not.be.reverted
    })

    it('should return early when available is 0', async function () {
      // Call exposed function with available = 0
      // This should return early without reverting
      await expect(
        issuanceAllocator.exposed_distributePendingProportionally(
          0, // available = 0 (defensive check)
          100, // allocatedRate
          1000, // toBlockNumber
        ),
      ).to.not.be.reverted
    })

    it('should return early when both are 0', async function () {
      // Call exposed function with both = 0
      // This should return early without reverting
      await expect(
        issuanceAllocator.exposed_distributePendingProportionally(
          0, // available = 0
          0, // allocatedRate = 0
          1000, // toBlockNumber
        ),
      ).to.not.be.reverted
    })
  })
})
