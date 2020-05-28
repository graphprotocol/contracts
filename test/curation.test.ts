import { expect } from 'chai'

import { Curation } from '../build/typechain/contracts/Curation'
import { GraphToken } from '../build/typechain/contracts/GraphToken'

import * as deployment from './lib/deployment'
import { defaults, provider, randomHexBytes, toBN, toGRT } from './lib/testHelpers'

const MAX_PPM = 1000000

describe('Curation', () => {
  const [me, other, governor, curator, staking] = provider().getWallets()

  let curation: Curation
  let grt: GraphToken

  beforeEach(async function() {
    // Deploy graph token
    grt = await deployment.deployGRT(governor.address, me)

    // Deploy curation contract
    curation = await deployment.deployCuration(governor.address, grt.address, me)
    await curation.connect(governor).setStaking(staking.address)

    // Randomize a subgraphId
    this.subgraphID = randomHexBytes()

    // Test values
    this.shareAmountFor1000Tokens = toBN('3')
  })

  describe('configuration', function() {
    it('should set `governor`', async function() {
      // Set right in the constructor
      expect(await curation.governor()).to.eq(governor.address)
    })

    it('should set `graphToken`', async function() {
      // Set right in the constructor
      expect(await curation.token()).to.eq(grt.address)
    })

    describe('staking', function() {
      it('should set `staking`', async function() {
        // Set right in the constructor
        expect(await curation.staking()).to.eq(staking.address)

        // Can set if allowed
        await curation.connect(governor).setStaking(other.address)
        expect(await curation.staking()).to.eq(other.address)
      })

      it('reject set `staking` if not allowed', async function() {
        const tx = curation.connect(other).setStaking(staking.address)
        await expect(tx).to.be.revertedWith('Only Governor can call')
      })
    })

    describe('defaultReserveRatio', function() {
      it('should set `defaultReserveRatio`', async function() {
        // Set right in the constructor
        expect(await curation.defaultReserveRatio()).to.eq(defaults.curation.reserveRatio)

        // Can set if allowed
        const newValue = toBN('100')
        await curation.connect(governor).setDefaultReserveRatio(newValue)
        expect(await curation.defaultReserveRatio()).to.be.eq(newValue)
      })

      it('reject set `defaultReserveRatio` if out of bounds', async function() {
        const tx1 = curation.connect(governor).setDefaultReserveRatio(0)
        await expect(tx1).to.be.revertedWith('Default reserve ratio must be > 0')

        const tx2 = curation.connect(governor).setDefaultReserveRatio(MAX_PPM + 1)
        await expect(tx2).to.be.revertedWith('Default reserve ratio cannot be higher than MAX_PPM')
      })

      it('reject set `defaultReserveRatio` if not allowed', async function() {
        const tx = curation.connect(other).setDefaultReserveRatio(defaults.curation.reserveRatio)
        await expect(tx).to.be.revertedWith('Only Governor can call')
      })
    })

    describe('minimumCurationStake', function() {
      it('should set `minimumCurationStake`', async function() {
        // Set right in the constructor
        expect(await curation.minimumCurationStake()).to.eq(defaults.curation.minimumCurationStake)

        // Can set if allowed
        const newValue = toBN(100)
        await curation.connect(governor).setMinimumCurationStake(newValue)
        expect(await curation.minimumCurationStake()).to.eq(newValue)
      })

      it('reject set `minimumCurationStake` if out of bounds', async function() {
        const tx = curation.connect(governor).setMinimumCurationStake(0)
        await expect(tx).to.be.revertedWith('Minimum curation stake cannot be 0')
      })

      it('reject set `minimumCurationStake` if not allowed', async function() {
        const tx = curation
          .connect(other)
          .setMinimumCurationStake(defaults.curation.minimumCurationStake)
        await expect(tx).to.be.revertedWith('Only Governor can call')
      })
    })

    describe('withdrawalFeePercentage', function() {
      it('should set `withdrawalFeePercentage`', async function() {
        const withdrawalFeePercentage = defaults.curation.withdrawalFeePercentage

        // Set new value
        await curation.connect(governor).setWithdrawalFeePercentage(0)
        await curation.connect(governor).setWithdrawalFeePercentage(withdrawalFeePercentage)
      })

      it('reject set `withdrawalFeePercentage` if out of bounds', async function() {
        const tx = curation.connect(governor).setWithdrawalFeePercentage(MAX_PPM + 1)
        await expect(tx).revertedWith('Withdrawal fee percentage must be below or equal to MAX_PPM')
      })

      it('reject set `withdrawalFeePercentage` if not allowed', async function() {
        const tx = curation.connect(other).setWithdrawalFeePercentage(0)
        await expect(tx).to.be.revertedWith('Only Governor can call')
      })
    })
  })

  describe('curation', function() {
    beforeEach(async function() {
      // Give some funds to the curator and approve the curation contract
      this.curatorTokens = toGRT('1000')
      await grt.connect(governor).mint(curator.address, this.curatorTokens)
      await grt.connect(curator).approve(curation.address, this.curatorTokens)

      // Give some funds to the staking contract and approve the curation contract
      this.tokensToCollect = toGRT('1000')
      await grt.connect(governor).mint(staking.address, this.tokensToCollect)
      await grt.connect(staking).approve(curation.address, this.curatorTokens)
    })

    context('> bonding curve', function() {
      beforeEach(function() {
        this.subgraphID = randomHexBytes()
      })

      it('convert shares to tokens', async function() {
        // Curate a subgraph
        await curation.connect(curator).stake(this.subgraphID, this.curatorTokens)

        // Conversion
        const shares = (await curation.subgraphs(this.subgraphID)).shares
        const tokens = await curation.sharesToTokens(this.subgraphID, shares)
        expect(tokens).to.eq(this.curatorTokens)
      })

      it('convert tokens to shares', async function() {
        // Conversion
        const tokens = toGRT('1000')
        const shares = await curation.tokensToShares(this.subgraphID, tokens)
        expect(shares).to.eq(this.shareAmountFor1000Tokens)
      })
    })

    context('> when subgraph is not curated', function() {
      it('should stake on a subgraph', async function() {
        // Before balances
        const curatorTokensBefore = await grt.balanceOf(curator.address)
        const curatorSharesBefore = await curation.getCuratorShares(
          curator.address,
          this.subgraphID,
        )
        const subgraphBefore = await curation.subgraphs(this.subgraphID)
        const totalBalanceBefore = await grt.balanceOf(curation.address)

        // Curate a subgraph
        // Staking the minimum required = 1 share
        const tokensToStake = defaults.curation.minimumCurationStake
        const sharesToReceive = toBN(1)
        const tx = curation.connect(curator).stake(this.subgraphID, tokensToStake)
        await expect(tx)
          .to.emit(curation, 'Staked')
          .withArgs(curator.address, this.subgraphID, tokensToStake, sharesToReceive)

        // After balances
        const curatorTokensAfter = await grt.balanceOf(curator.address)
        const curatorSharesAfter = await curation.getCuratorShares(curator.address, this.subgraphID)
        const subgraphAfter = await curation.subgraphs(this.subgraphID)
        const totalBalanceAfter = await grt.balanceOf(curation.address)

        // Tokens transferred properly
        expect(curatorTokensAfter).to.eq(curatorTokensBefore.sub(tokensToStake))
        expect(curatorSharesAfter).to.eq(curatorSharesBefore.add(sharesToReceive))

        // Subgraph allocated and balance updated
        expect(subgraphAfter.tokens).to.eq(subgraphBefore.tokens.add(tokensToStake))
        expect(subgraphAfter.shares).to.eq(subgraphBefore.shares.add(sharesToReceive))
        expect(subgraphAfter.reserveRatio).to.eq(defaults.curation.reserveRatio)

        // Contract balance updated
        expect(totalBalanceAfter).to.eq(totalBalanceBefore.add(tokensToStake))
      })
    })

    it('reject stake below minimum tokens required', async function() {
      const tokensToStake = defaults.curation.minimumCurationStake.sub(toBN(1))
      const tx = curation.connect(curator).stake(this.subgraphID, tokensToStake)
      await expect(tx).to.revertedWith('Curation stake is below minimum required')
    })

    it('reject redeem more than a curator owns', async function() {
      const tx = curation.connect(me).redeem(this.subgraphID, 1)
      await expect(tx).to.revertedWith('Cannot redeem more shares than you own')
    })

    it('reject collect tokens distributed as fees for the subgraph', async function() {
      // Source of tokens must be the staking for this to work
      const tx = curation.connect(staking).collect(this.subgraphID, this.tokensToCollect)
      await expect(tx).to.revertedWith('Subgraph must be curated to collect fees')
    })

    context('> when subgraph is curated', function() {
      beforeEach(async function() {
        await curation.connect(curator).stake(this.subgraphID, this.curatorTokens)
      })

      it('should create subgraph curation with default reserve ratio', async function() {
        const defaultReserveRatio = await curation.defaultReserveRatio()
        const subgraph = await curation.subgraphs(this.subgraphID)
        expect(subgraph.reserveRatio).to.eq(defaultReserveRatio)
      })

      it('reject redeem zero shares from a subgraph', async function() {
        const tx = curation.redeem(this.subgraphID, 0)
        await expect(tx).to.revertedWith('Cannot redeem zero shares')
      })

      it('should assign the right amount of shares according to bonding curve', async function() {
        // Shares should be the ones bought with minimum stake (1) + more shares
        const curatorShares = await curation.getCuratorShares(curator.address, this.subgraphID)
        expect(curatorShares).to.eq(this.shareAmountFor1000Tokens)
      })

      it('should allow to redeem *partially* on a subgraph', async function() {
        // Before balances
        const tokenTotalSupplyBefore = await grt.totalSupply()
        const curatorTokensBefore = await grt.balanceOf(curator.address)
        const curatorSharesBefore = await curation.getCuratorShares(
          curator.address,
          this.subgraphID,
        )
        const subgraphBefore = await curation.subgraphs(this.subgraphID)
        const totalTokensBefore = await grt.balanceOf(curation.address)

        // Redeem
        const sharesToRedeem = toBN(1) // Curator want to sell 1 share
        const tokensToRedeem = await curation.sharesToTokens(this.subgraphID, sharesToRedeem)
        const withdrawalFeePercentage = await curation.withdrawalFeePercentage()
        const withdrawalFees = withdrawalFeePercentage.mul(tokensToRedeem).div(toBN(MAX_PPM))

        const tx = curation.connect(curator).redeem(this.subgraphID, sharesToRedeem)
        await expect(tx)
          .to.emit(curation, 'Redeemed')
          .withArgs(
            curator.address,
            this.subgraphID,
            tokensToRedeem,
            sharesToRedeem,
            withdrawalFees,
          )

        // After balances
        const tokenTotalSupplyAfter = await grt.totalSupply()
        const curatorTokensAfter = await grt.balanceOf(curator.address)
        const curatorSharesAfter = await curation.getCuratorShares(curator.address, this.subgraphID)
        const subgraphAfter = await curation.subgraphs(this.subgraphID)
        const totalTokensAfter = await grt.balanceOf(curation.address)

        // Curator balance updated
        expect(curatorTokensAfter).to.eq(curatorTokensBefore.add(tokensToRedeem))
        expect(curatorSharesAfter).to.eq(curatorSharesBefore.sub(sharesToRedeem))

        // Subgraph balance updated
        expect(subgraphAfter.tokens).to.eq(subgraphBefore.tokens.sub(tokensToRedeem))
        expect(subgraphAfter.shares).to.eq(subgraphBefore.shares.sub(sharesToRedeem))

        // Contract balance updated
        expect(totalTokensAfter).to.eq(totalTokensBefore.sub(tokensToRedeem))

        // Withdrawal fees are burned
        expect(tokenTotalSupplyAfter).to.eq(tokenTotalSupplyBefore.sub(withdrawalFees))
      })

      it('should allow to redeem *fully* on a subgraph', async function() {
        // Before balances
        const tokenTotalSupplyBefore = await grt.totalSupply()
        const subgraphBefore = await curation.subgraphs(this.subgraphID)

        // Redeem all shares
        const sharesToRedeem = subgraphBefore.shares // we are selling all shares in the subgraph
        const tokensToRedeem = subgraphBefore.tokens // we are withdrawing all funds
        const withdrawalFeePercentage = await curation.withdrawalFeePercentage()
        const withdrawalFees = withdrawalFeePercentage.mul(tokensToRedeem).div(toBN(MAX_PPM))

        const tx = curation.connect(curator).redeem(this.subgraphID, sharesToRedeem)
        await expect(tx)
          .to.emit(curation, 'Redeemed')
          .withArgs(
            curator.address,
            this.subgraphID,
            tokensToRedeem,
            sharesToRedeem,
            withdrawalFees,
          )

        // After balances
        const tokenTotalSupplyAfter = await grt.totalSupply()
        const curatorTokensAfter = await grt.balanceOf(curator.address)
        const curatorSharesAfter = await curation.getCuratorShares(curator.address, this.subgraphID)
        const subgraphAfter = await curation.subgraphs(this.subgraphID)
        const totalTokensAfter = await grt.balanceOf(curation.address)

        // Curator balance updated
        expect(curatorTokensAfter).to.eq(tokensToRedeem)
        expect(curatorSharesAfter).to.eq(toBN(0))

        // Subgraph deallocated
        expect(subgraphAfter.tokens).to.eq(toBN(0))
        expect(subgraphAfter.shares).to.eq(toBN(0))
        expect(subgraphAfter.reserveRatio).to.eq(toBN(0))

        // Contract balance updated
        expect(totalTokensAfter).to.eq(toBN(0))

        // Withdrawal fees are burned
        expect(tokenTotalSupplyAfter).to.eq(tokenTotalSupplyBefore.sub(withdrawalFees))
      })

      it('should collect tokens distributed as reserves for a subgraph', async function() {
        // Before balances
        const totalBalanceBefore = await grt.balanceOf(curation.address)
        const subgraphBefore = await curation.subgraphs(this.subgraphID)

        // Source of tokens must be the staking for this to work
        const tx = curation.connect(staking).collect(this.subgraphID, this.tokensToCollect)
        await expect(tx)
          .to.emit(curation, 'Collected')
          .withArgs(this.subgraphID, this.tokensToCollect)

        // After balances
        const totalBalanceAfter = await grt.balanceOf(curation.address)
        const subgraphAfter = await curation.subgraphs(this.subgraphID)

        // Subgraph balance updated
        expect(subgraphAfter.tokens).to.eq(subgraphBefore.tokens.add(this.tokensToCollect))

        // Contract balance updated
        expect(totalBalanceAfter).to.eq(totalBalanceBefore.add(this.tokensToCollect))
      })
    })
  })
})
