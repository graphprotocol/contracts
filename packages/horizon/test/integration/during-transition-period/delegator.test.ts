import hre from 'hardhat'

import { delegators } from '../../../tasks/test/fixtures/delegators'
import { ethers } from 'hardhat'
import { expect } from 'chai'
import { HardhatEthersSigner } from '@nomicfoundation/hardhat-ethers/signers'
import { HorizonStakingActions } from '@graphprotocol/toolshed/actions/horizon'

import type { HorizonStaking, L2GraphToken } from '@graphprotocol/toolshed/deployments/horizon'

describe('Delegator', () => {
  let horizonStaking: HorizonStaking
  let graphToken: L2GraphToken
  let snapshotId: string

  const thawingPeriod = 2419200n // 28 days

  // Subgraph service address is not set for integration tests
  const subgraphServiceAddress = '0x0000000000000000000000000000000000000000'

  before(() => {
    const graph = hre.graph()

    horizonStaking = graph.horizon!.contracts.HorizonStaking
    graphToken = graph.horizon!.contracts.L2GraphToken
  })

  beforeEach(async () => {
    // Take a snapshot before each test
    snapshotId = await ethers.provider.send('evm_snapshot', [])
  })

  afterEach(async () => {
    // Revert to the snapshot after each test
    await ethers.provider.send('evm_revert', [snapshotId])
  })

  describe('Existing Protocol Users', () => {
    describe('User undelegated before horizon was deployed', () => {
      let indexer: HardhatEthersSigner
      let delegator: HardhatEthersSigner
      let tokens: bigint

      before(async () => {
        const delegatorFixture = delegators[2]
        const delegationFixture = delegatorFixture.delegations[0]

        // Verify delegator is undelegated
        expect(delegatorFixture.undelegate).to.be.true

        // Get signers
        indexer = await ethers.getSigner(delegationFixture.indexerAddress)
        delegator = await ethers.getSigner(delegatorFixture.address)

        // Get tokens
        tokens = delegationFixture.tokens
      })

      it('should be able to withdraw their tokens after the thawing period', async () => {
        // Get the thawing period
        const thawingPeriod = await horizonStaking.__DEPRECATED_getThawingPeriod()

        // Mine remaining blocks to complete thawing period
        for (let i = 0; i < Number(thawingPeriod) + 1; i++) {
          await ethers.provider.send('evm_mine', [])
        }

        // Get delegator balance before withdrawing
        const balanceBefore = await graphToken.balanceOf(delegator.address)

        // Withdraw tokens
        await HorizonStakingActions.withdrawDelegatedLegacy({
          horizonStaking,
          delegator,
          serviceProvider: indexer,
        })

        // Get delegator balance after withdrawing
        const balanceAfter = await graphToken.balanceOf(delegator.address)

        // Expected balance after is the balance before plus the tokens minus the 0.5% delegation tax
        const expectedBalanceAfter = balanceBefore + tokens - (tokens * 5000n / 1000000n)

        // Verify tokens are withdrawn
        expect(balanceAfter).to.equal(expectedBalanceAfter)
      })

      it('should revert if the thawing period has not passed', async () => {
        // Withdraw tokens
        await expect(HorizonStakingActions.withdrawDelegatedLegacy({
          horizonStaking,
          delegator,
          serviceProvider: indexer,
        })).to.be.revertedWithCustomError(horizonStaking, 'HorizonStakingNothingToWithdraw')
      })
    })

    describe('Transition period is over', () => {
      let governor: HardhatEthersSigner
      let indexer: HardhatEthersSigner
      let delegator: HardhatEthersSigner
      let tokens: bigint

      before(async () => {
        const delegatorFixture = delegators[0]
        const delegationFixture = delegatorFixture.delegations[0]

        // Get signers
        governor = (await ethers.getSigners())[1]
        indexer = await ethers.getSigner(delegationFixture.indexerAddress)
        delegator = await ethers.getSigner(delegatorFixture.address)

        // Get tokens
        tokens = delegationFixture.tokens
      })

      it('should be able to undelegate during transition period and withdraw after transition period', async () => {
        // Get delegator's delegation
        const delegation = await horizonStaking.getDelegation(
          indexer.address,
          subgraphServiceAddress,
          delegator.address,
        )

        // Undelegate tokens
        await HorizonStakingActions.undelegate({
          horizonStaking,
          delegator,
          serviceProvider: indexer,
          verifier: subgraphServiceAddress,
          shares: delegation.shares,
        })

        // Wait for thawing period
        await ethers.provider.send('evm_increaseTime', [Number(thawingPeriod) + 1])
        await ethers.provider.send('evm_mine', [])

        // Clear thawing period
        await HorizonStakingActions.clearThawingPeriod({ horizonStaking, governor })

        // Get delegator balance before withdrawing
        const balanceBefore = await graphToken.balanceOf(delegator.address)

        // Withdraw tokens
        await HorizonStakingActions.withdrawDelegated({
          horizonStaking,
          delegator,
          serviceProvider: indexer,
          verifier: subgraphServiceAddress,
          nThawRequests: BigInt(1),
        })

        // Get delegator balance after withdrawing
        const balanceAfter = await graphToken.balanceOf(delegator.address)

        // Expected balance after is the balance before plus the tokens minus the 0.5% delegation tax
        // because the delegation was before the horizon upgrade, after the upgrade there is no tax
        const expectedBalanceAfter = balanceBefore + tokens - (tokens * 5000n / 1000000n)

        // Verify tokens are withdrawn
        expect(balanceAfter).to.equal(expectedBalanceAfter)
      })
    })
  })
})
