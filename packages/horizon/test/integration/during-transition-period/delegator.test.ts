import { ethers } from 'hardhat'
import { expect } from 'chai'
import hre from 'hardhat'

import { SignerWithAddress } from '@nomicfoundation/hardhat-ethers/signers'

import { IGraphToken, IHorizonStaking } from '../../../typechain-types'
import { HorizonStakingActions } from 'hardhat-graph-protocol/sdk'

import { delegators } from '../../../tasks/test/fixtures/delegators'

describe('Delegator', () => {
  let horizonStaking: IHorizonStaking
  let graphToken: IGraphToken
  let snapshotId: string

  const thawingPeriod = 2419200n // 28 days

  // TODO: FIX THIS
  const subgraphServiceAddress = '0x254dffcd3277C0b1660F6d42EFbB754edaBAbC2B'

  before(() => {
    const graph = hre.graph()

    horizonStaking = graph.horizon!.contracts.HorizonStaking as unknown as IHorizonStaking
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

  describe('Existing Protocol Users', () => {
    describe('User undelegated before horizon was deployed', () => {
      let indexer: SignerWithAddress
      let delegator: SignerWithAddress
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
        })).to.be.revertedWith('!tokens')
      })
    })

    describe('Transition period is over', () => {
      let governor: SignerWithAddress
      let indexer: SignerWithAddress
      let delegator: SignerWithAddress
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
