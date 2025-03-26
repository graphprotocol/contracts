import { keccak256, toUtf8Bytes } from 'ethers'
import { ethers } from 'hardhat'
import { expect } from 'chai'
import hre from 'hardhat'

import { SignerWithAddress } from '@nomicfoundation/hardhat-ethers/signers'

import { IGraphToken, IHorizonStaking, IRewardsManager } from '../../../typechain-types'
import { HorizonStakingActions } from 'hardhat-graph-protocol/sdk'
import { HorizonStakingExtensionActions } from 'hardhat-graph-protocol/sdk'

import { indexers } from '../../../tasks/test/fixtures/indexers'

describe('Service Provider', () => {
  let horizonStaking: IHorizonStaking
  let rewardsManager: IRewardsManager
  let graphToken: IGraphToken
  let snapshotId: string

  // TODO: FIX THIS
  const subgraphServiceAddress = '0x254dffcd3277C0b1660F6d42EFbB754edaBAbC2B'

  before(() => {
    const graph = hre.graph()

    horizonStaking = graph.horizon!.contracts.HorizonStaking as unknown as IHorizonStaking
    rewardsManager = graph.horizon!.contracts.RewardsManager as unknown as IRewardsManager
    graphToken = graph.horizon!.contracts.L2GraphToken as unknown as IGraphToken
  })

  beforeEach(async () => {
    // Take a snapshot before each test
    snapshotId = await ethers.provider.send('evm_snapshot', [])
  })

  afterEach(async () => {
    // Revert to the snapshot after each test
    await ethers.provider.send('evm_revert', [snapshotId])
  })

  describe(('New Protocol Users'), () => {
    let serviceProvider: SignerWithAddress

    const tokensToStake = ethers.parseEther('1000')

    before(async () => {
      const signers = await ethers.getSigners()
      serviceProvider = signers[7]

      // Stake tokens to service provider
      await HorizonStakingActions.stake({ horizonStaking, graphToken, serviceProvider, tokens: tokensToStake })
    })

    it('should allow service provider to unstake and withdraw after thawing period', async () => {
      const tokensToUnstake = ethers.parseEther('100')
      const balanceBefore = await graphToken.balanceOf(serviceProvider.address)

      // First unstake request
      await HorizonStakingActions.unstake({ horizonStaking, serviceProvider, tokens: tokensToUnstake })

      // During transition period, tokens are locked by thawing period
      const thawingPeriod = await horizonStaking.__DEPRECATED_getThawingPeriod()

      // Mine remaining blocks to complete thawing period
      for (let i = 0; i < Number(thawingPeriod) + 1; i++) {
        await ethers.provider.send('evm_mine', [])
      }

      // Now we can withdraw
      await HorizonStakingActions.withdraw({ horizonStaking, serviceProvider })
      const balanceAfter = await graphToken.balanceOf(serviceProvider.address)

      expect(balanceAfter).to.equal(balanceBefore + tokensToUnstake, 'Tokens were not transferred back to service provider')
    })

    it('should handle multiple unstake requests correctly', async () => {
      // Make multiple unstake requests
      const request1 = ethers.parseEther('50')
      const request2 = ethers.parseEther('75')

      const thawingPeriod = await horizonStaking.__DEPRECATED_getThawingPeriod()

      // First unstake request
      await HorizonStakingActions.unstake({ horizonStaking, serviceProvider, tokens: request1 })

      // Mine half of thawing period blocks
      const halfThawingPeriod = Number(thawingPeriod) / 2
      for (let i = 0; i < halfThawingPeriod; i++) {
        await ethers.provider.send('evm_mine', [])
      }

      // Second unstake request
      await HorizonStakingActions.unstake({ horizonStaking, serviceProvider, tokens: request2 })

      // Mine remaining blocks to complete first unstake thawing period
      for (let i = 0; i < halfThawingPeriod; i++) {
        await ethers.provider.send('evm_mine', [])
      }

      // Check that withdraw reverts since thawing period is not complete
      await expect(
        HorizonStakingActions.withdraw({ horizonStaking, serviceProvider }),
      ).to.be.revertedWithCustomError(horizonStaking, 'HorizonStakingStillThawing')

      // Mine remaining blocks to complete thawing period
      for (let i = 0; i < halfThawingPeriod + 1; i++) {
        await ethers.provider.send('evm_mine', [])
      }

      // Get balance before withdrawing
      const balanceBefore = await graphToken.balanceOf(serviceProvider.address)

      // Withdraw all thawed tokens
      await HorizonStakingActions.withdraw({ horizonStaking, serviceProvider })

      // Verify all tokens are withdrawn and transferred back to service provider
      const balanceAfter = await graphToken.balanceOf(serviceProvider.address)
      expect(balanceAfter).to.equal(balanceBefore + request1 + request2, 'Tokens were not transferred back to service provider')
    })
  })

  describe('Existing Protocol Users', () => {
    let indexer: SignerWithAddress
    let tokensUnstaked: bigint

    before(async () => {
      const indexerFixture = indexers[0]
      indexer = await ethers.getSigner(indexerFixture.address)
      tokensUnstaked = indexerFixture.tokensToUnstake || 0n
    })

    it('should allow service provider to withdraw their locked tokens after thawing period passes', async () => {
      // Get balance before withdrawing
      const balanceBefore = await graphToken.balanceOf(indexer.address)

      // Get thawing period
      const thawingPeriod = await horizonStaking.__DEPRECATED_getThawingPeriod()

      // Mine blocks to complete thawing period
      for (let i = 0; i < Number(thawingPeriod) + 1; i++) {
        await ethers.provider.send('evm_mine', [])
      }

      // Withdraw tokens
      await HorizonStakingActions.withdraw({ horizonStaking, serviceProvider: indexer })

      // Verify tokens are transferred back to service provider
      const balanceAfter = await graphToken.balanceOf(indexer.address)
      expect(balanceAfter).to.equal(balanceBefore + tokensUnstaked, 'Tokens were not transferred back to service provider')
    })

    describe('Legacy allocations', () => {
      describe('Restaking', () => {
        let delegationIndexingCut: number
        let delegationQueryFeeCut: number
        let allocationID: string
        let allocationTokens: bigint
        let gateway: SignerWithAddress

        beforeEach(async () => {
          const indexerFixture = indexers[0]
          indexer = await ethers.getSigner(indexerFixture.address)
          delegationIndexingCut = indexerFixture.indexingRewardCut
          delegationQueryFeeCut = indexerFixture.queryFeeCut
          allocationID = indexerFixture.allocations[0].allocationID
          allocationTokens = indexerFixture.allocations[0].tokens
          gateway = (await ethers.getSigners())[18]
        })

        it('should be able to close an open legacy allocation and collect rewards', async () => {
          // Use a non-zero POI
          const poi = ethers.getBytes(keccak256(toUtf8Bytes('poi')))
          const thawingPeriod = await horizonStaking.__DEPRECATED_getThawingPeriod()

          // Get delegation pool before closing allocation
          const delegationPoolBefore = await horizonStaking.getDelegationPool(indexer.address, subgraphServiceAddress)
          const delegationPoolTokensBefore = delegationPoolBefore.tokens

          // Mine blocks to simulate time passing
          const halfThawingPeriod = Number(thawingPeriod) / 2
          for (let i = 0; i < halfThawingPeriod; i++) {
            await ethers.provider.send('evm_mine', [])
          }

          // Get idle stake before closing allocation
          const idleStakeBefore = await horizonStaking.getIdleStake(indexer.address)

          // Close allocation
          await horizonStaking.connect(indexer).closeAllocation(allocationID, poi)

          // Get rewards
          const rewards = await rewardsManager.getRewards(horizonStaking.target, allocationID)
          // Verify rewards are not zero
          expect(rewards).to.not.equal(0, 'Rewards were not transferred to service provider')

          // Verify rewards minus delegation cut are restaked
          const idleStakeAfter = await horizonStaking.getIdleStake(indexer.address)
          const idleStakeRewardsTokens = rewards * BigInt(delegationIndexingCut) / 1000000n
          expect(idleStakeAfter).to.equal(idleStakeBefore + allocationTokens + idleStakeRewardsTokens, 'Rewards were not restaked')

          // Verify delegators cut is added to delegation pool
          const delegationPool = await horizonStaking.getDelegationPool(indexer.address, subgraphServiceAddress)
          const delegationPoolTokensAfter = delegationPool.tokens
          const delegationRewardsTokens = rewards - idleStakeRewardsTokens
          expect(delegationPoolTokensAfter).to.equal(delegationPoolTokensBefore + delegationRewardsTokens, 'Delegators cut was not added to delegation pool')
        })

        it('should be able to collect query fees', async () => {
          const tokensToCollect = ethers.parseEther('1000')

          // Get idle stake before collecting
          const idleStakeBefore = await horizonStaking.getIdleStake(indexer.address)

          // Get delegation pool before collecting
          const delegationPoolBefore = await horizonStaking.getDelegationPool(indexer.address, subgraphServiceAddress)
          const delegationPoolTokensBefore = delegationPoolBefore.tokens

          // Collect query fees
          await HorizonStakingExtensionActions.collect({ horizonStaking, graphToken, gateway, allocationID, tokens: tokensToCollect })

          // Get idle stake after collecting
          const idleStakeAfter = await horizonStaking.getIdleStake(indexer.address)

          // Subtract protocol tax (1%) and curation fees (10% after the protocol tax deduction)
          const protocolTax = tokensToCollect * 1n / 100n
          const curationFees = tokensToCollect * 99n / 1000n
          const remainingTokens = tokensToCollect - protocolTax - curationFees

          // Verify tokens minus delegators cut are restaked
          const indexerCutTokens = remainingTokens * BigInt(delegationQueryFeeCut) / 1000000n
          expect(idleStakeAfter).to.equal(idleStakeBefore + indexerCutTokens, 'Indexer cut was not restaked')

          // Verify delegators cut is added to delegation pool
          const delegationPool = await horizonStaking.getDelegationPool(indexer.address, subgraphServiceAddress)
          const delegationPoolTokensAfter = delegationPool.tokens
          const delegationCutTokens = remainingTokens - indexerCutTokens
          expect(delegationPoolTokensAfter).to.equal(delegationPoolTokensBefore + delegationCutTokens, 'Delegators cut was not added to delegation pool')
        })

        it('should be able to close an allocation and collect query fees for the closed allocation', async () => {
          // Use a non-zero POI
          const poi = ethers.getBytes(keccak256(toUtf8Bytes('poi')))
          const thawingPeriod = await horizonStaking.__DEPRECATED_getThawingPeriod()

          // Mine blocks to simulate time passing
          const halfThawingPeriod = Number(thawingPeriod) / 2
          for (let i = 0; i < halfThawingPeriod; i++) {
            await ethers.provider.send('evm_mine', [])
          }

          // Close allocation
          await horizonStaking.connect(indexer).closeAllocation(allocationID, poi)

          // Tokens to collect
          const tokensToCollect = ethers.parseEther('1000')

          // Get idle stake before collecting
          const idleStakeBefore = await horizonStaking.getIdleStake(indexer.address)

          // Get delegation pool before collecting
          const delegationPoolBefore = await horizonStaking.getDelegationPool(indexer.address, subgraphServiceAddress)
          const delegationPoolTokensBefore = delegationPoolBefore.tokens

          // Collect query fees
          await HorizonStakingExtensionActions.collect({ horizonStaking, graphToken, gateway, allocationID, tokens: tokensToCollect })

          // Get idle stake after collecting
          const idleStakeAfter = await horizonStaking.getIdleStake(indexer.address)

          // Subtract protocol tax (1%) and curation fees (10% after the protocol tax deduction)
          const protocolTax = tokensToCollect * 1n / 100n
          const curationFees = tokensToCollect * 99n / 1000n
          const remainingTokens = tokensToCollect - protocolTax - curationFees

          // Verify tokens minus delegators cut are restaked
          const indexerCutTokens = remainingTokens * BigInt(delegationQueryFeeCut) / 1000000n
          expect(idleStakeAfter).to.equal(idleStakeBefore + indexerCutTokens, 'Indexer cut was not restaked')

          // Verify delegators cut is added to delegation pool
          const delegationPool = await horizonStaking.getDelegationPool(indexer.address, subgraphServiceAddress)
          const delegationPoolTokensAfter = delegationPool.tokens
          const delegationCutTokens = remainingTokens - indexerCutTokens
          expect(delegationPoolTokensAfter).to.equal(delegationPoolTokensBefore + delegationCutTokens, 'Delegators cut was not added to delegation pool')
        })
      })

      describe('With beneficiary', () => {
        let delegationIndexingCut: number
        let delegationQueryFeeCut: number
        let rewardsDestination: string
        let allocationID: string
        let gateway: SignerWithAddress

        beforeEach(async () => {
          const indexerFixture = indexers[1]
          indexer = await ethers.getSigner(indexerFixture.address)
          delegationIndexingCut = indexerFixture.indexingRewardCut
          delegationQueryFeeCut = indexerFixture.queryFeeCut
          rewardsDestination = indexerFixture.rewardsDestination!
          allocationID = indexerFixture.allocations[0].allocationID
          gateway = (await ethers.getSigners())[18]
        })

        it('should be able to close an open allocation and collect rewards', async () => {
          // Use a non-zero POI
          const poi = ethers.getBytes(keccak256(toUtf8Bytes('poi')))
          const thawingPeriod = await horizonStaking.__DEPRECATED_getThawingPeriod()

          // Get delegation tokens before
          const delegationPoolBefore = await horizonStaking.getDelegationPool(indexer.address, subgraphServiceAddress)
          const delegationPoolTokensBefore = delegationPoolBefore.tokens

          // Mine blocks to simulate time passing
          const halfThawingPeriod = Number(thawingPeriod) / 2
          for (let i = 0; i < halfThawingPeriod; i++) {
            await ethers.provider.send('evm_mine', [])
          }

          // Get rewards destination balance before closing allocation
          const balanceBefore = await graphToken.balanceOf(rewardsDestination)

          // Close allocation
          await horizonStaking.connect(indexer).closeAllocation(allocationID, poi)

          // Get rewards
          const rewards = await rewardsManager.getRewards(horizonStaking.target, allocationID)
          // Verify rewards are not zero
          expect(rewards).to.not.equal(0, 'Rewards were not transferred to rewards destination')

          // Verify indexer rewards cut is transferred to rewards destination
          const balanceAfter = await graphToken.balanceOf(rewardsDestination)
          const indexerCutTokens = rewards * BigInt(delegationIndexingCut) / 1000000n
          expect(balanceAfter).to.equal(balanceBefore + indexerCutTokens, 'Indexer cut was not transferred to rewards destination')

          // Verify delegators cut is added to delegation pool
          const delegationPoolAfter = await horizonStaking.getDelegationPool(indexer.address, subgraphServiceAddress)
          const delegationPoolTokensAfter = delegationPoolAfter.tokens
          const delegationCutTokens = rewards - indexerCutTokens
          expect(delegationPoolTokensAfter).to.equal(delegationPoolTokensBefore + delegationCutTokens, 'Delegators cut was not added to delegation pool')
        })

        it('should be able to collect query fees', async () => {
          const tokensToCollect = ethers.parseEther('1000')

          // Get rewards destination balance before collecting
          const balanceBefore = await graphToken.balanceOf(rewardsDestination)

          // Get delegation tokens before
          const delegationPoolBefore = await horizonStaking.getDelegationPool(indexer.address, subgraphServiceAddress)
          const delegationPoolTokensBefore = delegationPoolBefore.tokens

          // Collect query fees
          await HorizonStakingExtensionActions.collect({ horizonStaking, graphToken, gateway, allocationID, tokens: tokensToCollect })

          // Get rewards destination balance after collecting
          const balanceAfter = await graphToken.balanceOf(rewardsDestination)

          // Subtract protocol tax (1%) and curation fees (10% after the protocol tax deduction)
          const protocolTax = tokensToCollect * 1n / 100n
          const curationFees = tokensToCollect * 99n / 1000n
          const remainingTokens = tokensToCollect - protocolTax - curationFees

          // Verify indexer cut is transferred to rewards destination
          const indexerCutTokens = remainingTokens * BigInt(delegationQueryFeeCut) / 1000000n
          expect(balanceAfter).to.equal(balanceBefore + indexerCutTokens, 'Indexer cut was not transferred to rewards destination')

          // Verify delegators cut is added to delegation pool
          const delegationPoolAfter = await horizonStaking.getDelegationPool(indexer.address, subgraphServiceAddress)
          const delegationPoolTokensAfter = delegationPoolAfter.tokens
          const delegationCutTokens = remainingTokens - indexerCutTokens
          expect(delegationPoolTokensAfter).to.equal(delegationPoolTokensBefore + delegationCutTokens, 'Delegators cut was not added to delegation pool')
        })
      })
    })
  })
})
