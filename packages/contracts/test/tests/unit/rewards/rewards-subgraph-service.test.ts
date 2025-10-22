import { Curation } from '@graphprotocol/contracts'
import { GraphToken } from '@graphprotocol/contracts'
import { RewardsManager } from '@graphprotocol/contracts'
import { GraphNetworkContracts, helpers, randomAddress, randomHexBytes, toGRT } from '@graphprotocol/sdk'
import type { SignerWithAddress } from '@nomiclabs/hardhat-ethers/signers'
import { expect } from 'chai'
import { constants } from 'ethers'
import hre from 'hardhat'
import { network } from 'hardhat'

import { NetworkFixture } from '../lib/fixtures'

describe('Rewards - SubgraphService', () => {
  const graph = hre.graph()
  let curator1: SignerWithAddress
  let governor: SignerWithAddress
  let indexer1: SignerWithAddress

  let fixture: NetworkFixture

  let contracts: GraphNetworkContracts
  let grt: GraphToken
  let curation: Curation
  let rewardsManager: RewardsManager

  const subgraphDeploymentID1 = randomHexBytes()
  const allocationID1 = randomAddress()

  const ISSUANCE_PER_BLOCK = toGRT('200') // 200 GRT every block

  before(async function () {
    const testAccounts = await graph.getTestAccounts()
    curator1 = testAccounts[0]
    indexer1 = testAccounts[1]
    ;({ governor } = await graph.getNamedAccounts())

    fixture = new NetworkFixture(graph.provider)
    contracts = await fixture.load(governor)
    grt = contracts.GraphToken as GraphToken
    curation = contracts.Curation as Curation
    rewardsManager = contracts.RewardsManager

    // 200 GRT per block
    await rewardsManager.connect(governor).setIssuancePerBlock(ISSUANCE_PER_BLOCK)

    // Distribute test funds
    for (const wallet of [indexer1, curator1]) {
      await grt.connect(governor).mint(wallet.address, toGRT('1000000'))
      await grt.connect(wallet).approve(curation.address, toGRT('1000000'))
    }
  })

  beforeEach(async function () {
    await fixture.setUp()
  })

  afterEach(async function () {
    await fixture.tearDown()
  })

  describe('subgraph service configuration', function () {
    it('should reject setSubgraphService if unauthorized', async function () {
      const newService = randomAddress()
      const tx = rewardsManager.connect(indexer1).setSubgraphService(newService)
      await expect(tx).revertedWith('Only Controller governor')
    })

    it('should set subgraph service if governor', async function () {
      const newService = randomAddress()
      const tx = rewardsManager.connect(governor).setSubgraphService(newService)

      await expect(tx).emit(rewardsManager, 'SubgraphServiceSet').withArgs(constants.AddressZero, newService)

      expect(await rewardsManager.subgraphService()).eq(newService)
    })

    it('should allow setting to zero address', async function () {
      const service = randomAddress()
      await rewardsManager.connect(governor).setSubgraphService(service)

      const tx = rewardsManager.connect(governor).setSubgraphService(constants.AddressZero)
      await expect(tx).emit(rewardsManager, 'SubgraphServiceSet').withArgs(service, constants.AddressZero)

      expect(await rewardsManager.subgraphService()).eq(constants.AddressZero)
    })

    it('should emit event when setting different address', async function () {
      const service1 = randomAddress()
      const service2 = randomAddress()

      await rewardsManager.connect(governor).setSubgraphService(service1)

      // Setting a different address should emit event
      const tx = await rewardsManager.connect(governor).setSubgraphService(service2)
      await expect(tx).emit(rewardsManager, 'SubgraphServiceSet').withArgs(service1, service2)
    })
  })

  describe('subgraph service as rewards issuer', function () {
    let mockSubgraphService: any

    beforeEach(async function () {
      // Deploy mock SubgraphService
      const MockSubgraphServiceFactory = await hre.ethers.getContractFactory(
        'contracts/tests/MockSubgraphService.sol:MockSubgraphService',
      )
      mockSubgraphService = await MockSubgraphServiceFactory.deploy()
      await mockSubgraphService.deployed()

      // Set it on RewardsManager
      await rewardsManager.connect(governor).setSubgraphService(mockSubgraphService.address)
    })

    describe('getRewards from subgraph service', function () {
      it('should calculate rewards for subgraph service allocations', async function () {
        // Setup: Create signal for rewards calculation
        const signalled1 = toGRT('1500')
        await curation.connect(curator1).mint(subgraphDeploymentID1, signalled1, 0)

        // Setup allocation data in mock
        const tokensAllocated = toGRT('12500')
        await mockSubgraphService.setAllocation(
          allocationID1,
          true, // isActive
          indexer1.address,
          subgraphDeploymentID1,
          tokensAllocated,
          0, // accRewardsPerAllocatedToken
          0, // accRewardsPending
        )

        await mockSubgraphService.setSubgraphAllocatedTokens(subgraphDeploymentID1, tokensAllocated)

        // Mine some blocks to accrue rewards
        await helpers.mine(10)

        // Get rewards - should return calculated amount
        const rewards = await rewardsManager.getRewards(mockSubgraphService.address, allocationID1)
        expect(rewards).to.be.gt(0)
      })

      it('should return zero for inactive allocation', async function () {
        // Setup allocation as inactive
        await mockSubgraphService.setAllocation(
          allocationID1,
          false, // isActive = false
          indexer1.address,
          subgraphDeploymentID1,
          toGRT('12500'),
          0,
          0,
        )

        const rewards = await rewardsManager.getRewards(mockSubgraphService.address, allocationID1)
        expect(rewards).to.equal(0)
      })

      it('should reject getRewards from non-rewards-issuer contract', async function () {
        const randomContract = randomAddress()
        const tx = rewardsManager.getRewards(randomContract, allocationID1)
        await expect(tx).revertedWith('Not a rewards issuer')
      })
    })

    describe('takeRewards from subgraph service', function () {
      it('should take rewards through subgraph service', async function () {
        // Setup: Create signal for rewards calculation
        const signalled1 = toGRT('1500')
        await curation.connect(curator1).mint(subgraphDeploymentID1, signalled1, 0)

        // Setup allocation data in mock
        const tokensAllocated = toGRT('12500')
        await mockSubgraphService.setAllocation(
          allocationID1,
          true, // isActive
          indexer1.address,
          subgraphDeploymentID1,
          tokensAllocated,
          0, // accRewardsPerAllocatedToken
          0, // accRewardsPending
        )

        await mockSubgraphService.setSubgraphAllocatedTokens(subgraphDeploymentID1, tokensAllocated)

        // Mine some blocks to accrue rewards
        await helpers.mine(10)

        // Before state
        const beforeSubgraphServiceBalance = await grt.balanceOf(mockSubgraphService.address)
        const beforeTotalSupply = await grt.totalSupply()

        // Impersonate the mock subgraph service contract
        await network.provider.request({
          method: 'hardhat_impersonateAccount',
          params: [mockSubgraphService.address],
        })
        await network.provider.send('hardhat_setBalance', [mockSubgraphService.address, '0x1000000000000000000'])

        const mockSubgraphServiceSigner = await hre.ethers.getSigner(mockSubgraphService.address)

        // Take rewards (called by subgraph service)
        const tx = await rewardsManager.connect(mockSubgraphServiceSigner).takeRewards(allocationID1)
        const receipt = await tx.wait()

        // Stop impersonating
        await network.provider.request({
          method: 'hardhat_stopImpersonatingAccount',
          params: [mockSubgraphService.address],
        })

        // Parse the event
        const event = receipt.logs
          .map((log: any) => {
            try {
              return rewardsManager.interface.parseLog(log)
            } catch {
              return null
            }
          })
          .find((e: any) => e?.name === 'HorizonRewardsAssigned')

        expect(event).to.not.be.undefined
        expect(event?.args.indexer).to.equal(indexer1.address)
        expect(event?.args.allocationID).to.equal(allocationID1)
        expect(event?.args.amount).to.be.gt(0)

        // After state - verify tokens minted to subgraph service
        const afterSubgraphServiceBalance = await grt.balanceOf(mockSubgraphService.address)
        const afterTotalSupply = await grt.totalSupply()

        expect(afterSubgraphServiceBalance).to.be.gt(beforeSubgraphServiceBalance)
        expect(afterTotalSupply).to.be.gt(beforeTotalSupply)
      })

      it('should return zero rewards for inactive allocation', async function () {
        // Setup allocation as inactive
        await mockSubgraphService.setAllocation(
          allocationID1,
          false, // isActive = false
          indexer1.address,
          subgraphDeploymentID1,
          toGRT('12500'),
          0,
          0,
        )

        // Impersonate the mock subgraph service contract
        await network.provider.request({
          method: 'hardhat_impersonateAccount',
          params: [mockSubgraphService.address],
        })
        await network.provider.send('hardhat_setBalance', [mockSubgraphService.address, '0x1000000000000000000'])

        const mockSubgraphServiceSigner = await hre.ethers.getSigner(mockSubgraphService.address)

        // Take rewards should return 0 and emit event with 0 amount
        const tx = rewardsManager.connect(mockSubgraphServiceSigner).takeRewards(allocationID1)
        await expect(tx).emit(rewardsManager, 'HorizonRewardsAssigned').withArgs(indexer1.address, allocationID1, 0)

        // Stop impersonating
        await network.provider.request({
          method: 'hardhat_stopImpersonatingAccount',
          params: [mockSubgraphService.address],
        })
      })

      it('should reject takeRewards from non-rewards-issuer contract', async function () {
        const tx = rewardsManager.connect(indexer1).takeRewards(allocationID1)
        await expect(tx).revertedWith('Caller must be a rewards issuer')
      })

      it('should handle zero rewards scenario', async function () {
        // Setup with zero issuance
        await rewardsManager.connect(governor).setIssuancePerBlock(0)

        // Setup allocation
        await mockSubgraphService.setAllocation(
          allocationID1,
          true,
          indexer1.address,
          subgraphDeploymentID1,
          toGRT('12500'),
          0,
          0,
        )

        await mockSubgraphService.setSubgraphAllocatedTokens(subgraphDeploymentID1, toGRT('12500'))

        // Mine blocks
        await helpers.mine(10)

        // Impersonate the mock subgraph service contract
        await network.provider.request({
          method: 'hardhat_impersonateAccount',
          params: [mockSubgraphService.address],
        })
        await network.provider.send('hardhat_setBalance', [mockSubgraphService.address, '0x1000000000000000000'])

        const mockSubgraphServiceSigner = await hre.ethers.getSigner(mockSubgraphService.address)

        // Take rewards should succeed with 0 amount
        const tx = rewardsManager.connect(mockSubgraphServiceSigner).takeRewards(allocationID1)
        await expect(tx).emit(rewardsManager, 'HorizonRewardsAssigned').withArgs(indexer1.address, allocationID1, 0)

        // Stop impersonating
        await network.provider.request({
          method: 'hardhat_stopImpersonatingAccount',
          params: [mockSubgraphService.address],
        })
      })
    })

    describe('mixed allocations from staking and subgraph service', function () {
      it('should account for both staking and subgraph service allocations in getAccRewardsPerAllocatedToken', async function () {
        // This test verifies that getSubgraphAllocatedTokens is called for both issuers
        // and rewards are distributed proportionally

        // Setup: Create signal
        const signalled1 = toGRT('1500')
        await curation.connect(curator1).mint(subgraphDeploymentID1, signalled1, 0)

        // Setup subgraph service allocation
        const tokensFromSubgraphService = toGRT('5000')
        await mockSubgraphService.setSubgraphAllocatedTokens(subgraphDeploymentID1, tokensFromSubgraphService)

        // Note: We can't easily create a real staking allocation in this test
        // but the contract code at lines 381-388 loops through both issuers
        // and sums their allocated tokens. This test verifies the subgraph service path.

        // Mine some blocks
        await helpers.mine(5)

        // Get accumulated rewards per allocated token
        const [accRewardsPerAllocatedToken, accRewardsForSubgraph] =
          await rewardsManager.getAccRewardsPerAllocatedToken(subgraphDeploymentID1)

        // Should have calculated rewards based on subgraph service allocations
        expect(accRewardsPerAllocatedToken).to.be.gt(0)
        expect(accRewardsForSubgraph).to.be.gt(0)
      })

      it('should handle case where only subgraph service has allocations', async function () {
        // Setup: Create signal
        const signalled1 = toGRT('1500')
        await curation.connect(curator1).mint(subgraphDeploymentID1, signalled1, 0)

        // Only subgraph service has allocations
        const tokensFromSubgraphService = toGRT('10000')
        await mockSubgraphService.setSubgraphAllocatedTokens(subgraphDeploymentID1, tokensFromSubgraphService)

        // Mine blocks
        await helpers.mine(5)

        // Get rewards
        const [accRewardsPerAllocatedToken] = await rewardsManager.getAccRewardsPerAllocatedToken(subgraphDeploymentID1)

        expect(accRewardsPerAllocatedToken).to.be.gt(0)
      })

      it('should return zero when neither issuer has allocations', async function () {
        // Setup: Create signal but no allocations
        const signalled1 = toGRT('1500')
        await curation.connect(curator1).mint(subgraphDeploymentID1, signalled1, 0)

        // No allocations from either issuer
        await mockSubgraphService.setSubgraphAllocatedTokens(subgraphDeploymentID1, 0)

        // Mine blocks
        await helpers.mine(5)

        // Get rewards - should return 0 when no allocations
        const [accRewardsPerAllocatedToken, accRewardsForSubgraph] =
          await rewardsManager.getAccRewardsPerAllocatedToken(subgraphDeploymentID1)

        expect(accRewardsPerAllocatedToken).to.equal(0)
        expect(accRewardsForSubgraph).to.be.gt(0) // Subgraph still accrues, but no per-token rewards
      })
    })

    describe('subgraph service with denylist and eligibility', function () {
      it('should deny rewards from subgraph service when subgraph is on denylist', async function () {
        // Setup denylist
        await rewardsManager.connect(governor).setSubgraphAvailabilityOracle(governor.address)
        await rewardsManager.connect(governor).setDenied(subgraphDeploymentID1, true)

        // Setup allocation
        await mockSubgraphService.setAllocation(
          allocationID1,
          true,
          indexer1.address,
          subgraphDeploymentID1,
          toGRT('12500'),
          0,
          0,
        )

        // Impersonate the mock subgraph service contract
        await network.provider.request({
          method: 'hardhat_impersonateAccount',
          params: [mockSubgraphService.address],
        })
        await network.provider.send('hardhat_setBalance', [mockSubgraphService.address, '0x1000000000000000000'])

        const mockSubgraphServiceSigner = await hre.ethers.getSigner(mockSubgraphService.address)

        // Take rewards should be denied
        const tx = rewardsManager.connect(mockSubgraphServiceSigner).takeRewards(allocationID1)
        await expect(tx).emit(rewardsManager, 'RewardsDenied').withArgs(indexer1.address, allocationID1)

        // Stop impersonating
        await network.provider.request({
          method: 'hardhat_stopImpersonatingAccount',
          params: [mockSubgraphService.address],
        })
      })

      it('should deny rewards from subgraph service when indexer is ineligible', async function () {
        // Setup REO that denies indexer1
        const MockRewardsEligibilityOracleFactory = await hre.ethers.getContractFactory(
          'contracts/tests/MockRewardsEligibilityOracle.sol:MockRewardsEligibilityOracle',
        )
        const mockREO = await MockRewardsEligibilityOracleFactory.deploy(false) // Deny by default
        await mockREO.deployed()
        await rewardsManager.connect(governor).setRewardsEligibilityOracle(mockREO.address)

        // Setup: Create signal
        const signalled1 = toGRT('1500')
        await curation.connect(curator1).mint(subgraphDeploymentID1, signalled1, 0)

        // Setup allocation
        const tokensAllocated = toGRT('12500')
        await mockSubgraphService.setAllocation(
          allocationID1,
          true,
          indexer1.address,
          subgraphDeploymentID1,
          tokensAllocated,
          0,
          0,
        )

        await mockSubgraphService.setSubgraphAllocatedTokens(subgraphDeploymentID1, tokensAllocated)

        // Mine blocks to accrue rewards
        await helpers.mine(5)

        // Impersonate the mock subgraph service contract
        await network.provider.request({
          method: 'hardhat_impersonateAccount',
          params: [mockSubgraphService.address],
        })
        await network.provider.send('hardhat_setBalance', [mockSubgraphService.address, '0x1000000000000000000'])

        const mockSubgraphServiceSigner = await hre.ethers.getSigner(mockSubgraphService.address)

        // Take rewards should be denied due to eligibility
        const tx = rewardsManager.connect(mockSubgraphServiceSigner).takeRewards(allocationID1)
        await expect(tx).emit(rewardsManager, 'RewardsDeniedDueToEligibility')

        // Stop impersonating
        await network.provider.request({
          method: 'hardhat_stopImpersonatingAccount',
          params: [mockSubgraphService.address],
        })
      })
    })
  })
})
