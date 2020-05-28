const BN = web3.utils.BN
const { expect } = require('chai')
const { expectRevert, expectEvent } = require('@openzeppelin/test-helpers')

// helpers
const deployment = require('./lib/deployment')
const helpers = require('./lib/testHelpers')
const { defaults } = require('./lib/testHelpers')

const MAX_PPM = 1000000

function toGRT(value) {
  return new BN(web3.utils.toWei(value))
}

contract('Curation', ([me, other, governor, curator, staking]) => {
  beforeEach(async function() {
    // Deploy graph token
    this.grt = await deployment.deployGRT(governor, {
      from: me,
    })

    // Deploy curation contract
    this.curation = await deployment.deployCurationContract(governor, this.grt.address, {
      from: me,
    })
    await this.curation.setStaking(staking, { from: governor })

    // Randomize a subgraphId
    this.subgraphID = helpers.randomSubgraphId()

    // Test values
    this.shareAmountFor1000Tokens = new BN(3)
  })

  describe('configuration', function() {
    it('should set `governor`', async function() {
      // Set right in the constructor
      expect(await this.curation.governor()).to.eq(governor)
    })

    it('should set `graphToken`', async function() {
      // Set right in the constructor
      expect(await this.curation.token()).to.eq(this.grt.address)
    })

    describe('staking', function() {
      it('should set `staking`', async function() {
        // Set right in the constructor
        expect(await this.curation.staking()).to.eq(staking)

        // Can set if allowed
        await this.curation.setStaking(other, { from: governor })
        expect(await this.curation.staking()).to.eq(other)
      })

      it('reject set `staking` if not allowed', async function() {
        await expectRevert(
          this.curation.setStaking(staking, { from: other }),
          'Only Governor can call',
        )
      })
    })

    describe('defaultReserveRatio', function() {
      it('should set `defaultReserveRatio`', async function() {
        // Set right in the constructor
        expect(await this.curation.defaultReserveRatio()).to.be.bignumber.eq(
          defaults.curation.reserveRatio,
        )

        // Can set if allowed
        const newDefaultReserveRatio = defaults.curation.reserveRatio.add(new BN(100))
        await this.curation.setDefaultReserveRatio(newDefaultReserveRatio, {
          from: governor,
        })
        expect(await this.curation.defaultReserveRatio()).to.be.bignumber.eq(newDefaultReserveRatio)
      })

      it('reject set `defaultReserveRatio` if out of bounds', async function() {
        await expectRevert(
          this.curation.setDefaultReserveRatio(0, { from: governor }),
          'Default reserve ratio must be > 0',
        )
        await expectRevert(
          this.curation.setDefaultReserveRatio(MAX_PPM + 1, {
            from: governor,
          }),
          'Default reserve ratio cannot be higher than MAX_PPM',
        )
      })

      it('reject set `defaultReserveRatio` if not allowed', async function() {
        await expectRevert(
          this.curation.setDefaultReserveRatio(defaults.curation.reserveRatio, {
            from: other,
          }),
          'Only Governor can call',
        )
      })
    })

    describe('minimumCurationStake', function() {
      it('should set `minimumCurationStake`', async function() {
        // Set right in the constructor
        expect(await this.curation.minimumCurationStake()).to.be.bignumber.eq(
          defaults.curation.minimumCurationStake,
        )

        // Can set if allowed
        const newMinimumCurationStake = defaults.curation.minimumCurationStake.add(new BN(100))
        await this.curation.setMinimumCurationStake(newMinimumCurationStake, {
          from: governor,
        })
        expect(await this.curation.minimumCurationStake()).to.be.bignumber.eq(
          newMinimumCurationStake,
        )
      })

      it('reject set `minimumCurationStake` if out of bounds', async function() {
        await expectRevert(
          this.curation.setMinimumCurationStake(0, { from: governor }),
          'Minimum curation stake cannot be 0',
        )
      })

      it('reject set `minimumCurationStake` if not allowed', async function() {
        await expectRevert(
          this.curation.setMinimumCurationStake(defaults.curation.minimumCurationStake, {
            from: other,
          }),
          'Only Governor can call',
        )
      })
    })

    describe('withdrawalFeePercentage', function() {
      it('should set `withdrawalFeePercentage`', async function() {
        const withdrawalFeePercentage = defaults.curation.withdrawalFeePercentage

        // Set new value
        await this.curation.setWithdrawalFeePercentage(0, { from: governor })
        await this.curation.setWithdrawalFeePercentage(1, { from: governor })
        await this.curation.setWithdrawalFeePercentage(withdrawalFeePercentage, {
          from: governor,
        })
      })

      it('reject set `withdrawalFeePercentage` if out of bounds', async function() {
        await expectRevert(
          this.curation.setWithdrawalFeePercentage(MAX_PPM + 1, {
            from: governor,
          }),
          'Withdrawal fee percentage must be below or equal to MAX_PPM',
        )
      })

      it('reject set `withdrawalFeePercentage` if not allowed', async function() {
        await expectRevert(
          this.curation.setWithdrawalFeePercentage(0, { from: other }),
          'Only Governor can call',
        )
      })
    })
  })

  describe('curation', function() {
    beforeEach(async function() {
      // Give some funds to the curator
      this.curatorTokens = toGRT('1000')
      await this.grt.mint(curator, this.curatorTokens, {
        from: governor,
      })
      // Approve all curator's funds to be used in the curation contract
      await this.grt.approve(this.curation.address, this.curatorTokens, { from: curator })

      // Give some funds to the staking contract
      this.tokensToCollect = toGRT('1000')
      await this.grt.mint(staking, this.tokensToCollect, {
        from: governor,
      })
      // Approve staking contract funds to be used in the curation contract
      await this.grt.approve(this.curation.address, this.curatorTokens, { from: staking })
    })

    describe('bonding curve', function() {
      it('convert shares to tokens', async function() {
        // Curate a subgraph
        await this.curation.stake(this.subgraphID, this.curatorTokens, { from: curator })

        // Conversion
        const shares = (await this.curation.subgraphs(this.subgraphID)).shares
        const tokens = await this.curation.sharesToTokens(this.subgraphID, shares)
        expect(tokens).to.be.bignumber.eq(this.curatorTokens)
      })

      it('convert tokens to shares', async function() {
        // Conversion
        const tokens = toGRT('1000')
        const shares = await this.curation.tokensToShares(this.subgraphID, tokens)
        expect(shares).to.be.bignumber.eq(this.shareAmountFor1000Tokens)
      })
    })

    context('> when subgraph is not curated', function() {
      it('should stake on a subgraph', async function() {
        // Before balances
        const curatorTokensBefore = await this.grt.balanceOf(curator)
        const curatorSharesBefore = await this.curation.getCuratorShares(curator, this.subgraphID)
        const subgraphBefore = await this.curation.subgraphs(this.subgraphID)
        const totalBalanceBefore = await this.grt.balanceOf(this.curation.address)

        // Curate a subgraph
        // Staking the minimum required = 1 share
        const tokensToStake = defaults.curation.minimumCurationStake
        const sharesToReceive = new BN(1)
        const { logs } = await this.curation.stake(this.subgraphID, tokensToStake, {
          from: curator,
        })
        expectEvent.inLogs(logs, 'Staked', {
          curator: curator,
          subgraphID: this.subgraphID,
          tokens: tokensToStake,
          shares: sharesToReceive,
        })

        // After balances
        const curatorTokensAfter = await this.grt.balanceOf(curator)
        const curatorSharesAfter = await this.curation.getCuratorShares(curator, this.subgraphID)
        const subgraphAfter = await this.curation.subgraphs(this.subgraphID)
        const totalBalanceAfter = await this.grt.balanceOf(this.curation.address)

        // Tokens transferred properly
        expect(curatorTokensAfter).to.be.bignumber.eq(curatorTokensBefore.sub(tokensToStake))
        expect(curatorSharesAfter).to.be.bignumber.eq(curatorSharesBefore.add(sharesToReceive))

        // Subgraph allocated and balance updated
        expect(subgraphAfter.tokens).to.be.bignumber.eq(subgraphBefore.tokens.add(tokensToStake))
        expect(subgraphAfter.shares).to.be.bignumber.eq(subgraphBefore.shares.add(sharesToReceive))
        expect(subgraphAfter.reserveRatio).to.be.bignumber.eq(defaults.curation.reserveRatio)

        // Contract balance updated
        expect(totalBalanceAfter).to.be.bignumber.eq(totalBalanceBefore.add(tokensToStake))
      })

      it('reject stake below minimum tokens required', async function() {
        const tokensToStake = defaults.curation.minimumCurationStake.sub(new BN(1))
        await expectRevert(
          this.curation.stake(this.subgraphID, tokensToStake, { from: curator }),
          'Curation stake is below minimum required',
        )
      })

      it('reject redeem more than a curator owns', async function() {
        await expectRevert(
          this.curation.redeem(this.subgraphID, 1),
          'Cannot redeem more shares than you own',
        )
      })

      it('reject collect tokens distributed as fees for the subgraph', async function() {
        // Source of tokens must be the staking for this to work
        await expectRevert(
          this.curation.collect(this.subgraphID, this.tokensToCollect, { from: staking }),
          'Subgraph must be curated to collect fees',
        )
      })
    })

    context('> when subgraph is curated', function() {
      beforeEach(async function() {
        await this.curation.stake(this.subgraphID, this.curatorTokens, { from: curator })
      })

      it('should create subgraph curation with default reserve ratio', async function() {
        const defaultReserveRatio = await this.curation.defaultReserveRatio()
        const subgraph = await this.curation.subgraphs(this.subgraphID)
        expect(subgraph.reserveRatio).to.be.bignumber.eq(defaultReserveRatio)
      })

      it('reject redeem zero shares from a subgraph', async function() {
        await expectRevert(this.curation.redeem(this.subgraphID, 0), 'Cannot redeem zero shares')
      })

      it('should assign the right amount of shares according to bonding curve', async function() {
        // Shares should be the ones bought with minimum stake (1) + more shares
        const curatorShares = await this.curation.getCuratorShares(curator, this.subgraphID)
        expect(curatorShares).to.be.bignumber.eq(this.shareAmountFor1000Tokens)
      })

      it('should allow to redeem *partially* on a subgraph', async function() {
        // Before balances
        const tokenTotalSupplyBefore = await this.grt.totalSupply()
        const curatorTokensBefore = await this.grt.balanceOf(curator)
        const curatorSharesBefore = await this.curation.getCuratorShares(curator, this.subgraphID)
        const subgraphBefore = await this.curation.subgraphs(this.subgraphID)
        const totalTokensBefore = await this.grt.balanceOf(this.curation.address)

        // Redeem
        const sharesToRedeem = new BN(1) // Curator want to sell 1 share
        const tokensToRedeem = await this.curation.sharesToTokens(this.subgraphID, sharesToRedeem)
        const withdrawalFeePercentage = await this.curation.withdrawalFeePercentage()
        const withdrawalFees = withdrawalFeePercentage.mul(tokensToRedeem).div(new BN(MAX_PPM))
        const tokensToReceive = tokensToRedeem.sub(withdrawalFees)

        const { logs } = await this.curation.redeem(this.subgraphID, sharesToRedeem, {
          from: curator,
        })
        expectEvent.inLogs(logs, 'Redeemed', {
          curator: curator,
          subgraphID: this.subgraphID,
          tokens: tokensToReceive,
          shares: sharesToRedeem,
          withdrawalFees: withdrawalFees,
        })

        // After balances
        const tokenTotalSupplyAfter = await this.grt.totalSupply()
        const curatorTokensAfter = await this.grt.balanceOf(curator)
        const curatorSharesAfter = await this.curation.getCuratorShares(curator, this.subgraphID)
        const subgraphAfter = await this.curation.subgraphs(this.subgraphID)
        const totalTokensAfter = await this.grt.balanceOf(this.curation.address)

        // Curator balance updated
        expect(curatorTokensAfter).to.be.bignumber.eq(curatorTokensBefore.add(tokensToReceive))
        expect(curatorSharesAfter).to.be.bignumber.eq(curatorSharesBefore.sub(sharesToRedeem))

        // Subgraph balance updated
        expect(subgraphAfter.tokens).to.be.bignumber.eq(subgraphBefore.tokens.sub(tokensToRedeem))
        expect(subgraphAfter.shares).to.be.bignumber.eq(subgraphBefore.shares.sub(sharesToRedeem))

        // Contract balance updated
        expect(totalTokensAfter).to.be.bignumber.eq(totalTokensBefore.sub(tokensToRedeem))

        // Withdrawal fees are burned
        expect(tokenTotalSupplyAfter).to.be.bignumber.eq(tokenTotalSupplyBefore.sub(withdrawalFees))
      })

      it('should allow to redeem *fully* on a subgraph', async function() {
        // Before balances
        const tokenTotalSupplyBefore = await this.grt.totalSupply()
        const subgraphBefore = await this.curation.subgraphs(this.subgraphID)

        // Redeem all shares
        const sharesToRedeem = subgraphBefore.shares // we are selling all shares in the subgraph
        const tokensToRedeem = subgraphBefore.tokens // we are withdrawing all funds
        const withdrawalFeePercentage = await this.curation.withdrawalFeePercentage()
        const withdrawalFees = withdrawalFeePercentage.mul(tokensToRedeem).div(new BN(MAX_PPM))
        const tokensToReceive = tokensToRedeem.sub(withdrawalFees)

        const { logs } = await this.curation.redeem(this.subgraphID, sharesToRedeem, {
          from: curator,
        })
        expectEvent.inLogs(logs, 'Redeemed', {
          curator: curator,
          subgraphID: this.subgraphID,
          tokens: tokensToReceive,
          shares: sharesToRedeem,
          withdrawalFees: withdrawalFees,
        })

        // After balances
        const tokenTotalSupplyAfter = await this.grt.totalSupply()
        const curatorTokensAfter = await this.grt.balanceOf(curator)
        const curatorSharesAfter = await this.curation.getCuratorShares(curator, this.subgraphID)
        const subgraphAfter = await this.curation.subgraphs(this.subgraphID)
        const totalTokensAfter = await this.grt.balanceOf(this.curation.address)

        // Curator balance updated
        expect(curatorTokensAfter).to.be.bignumber.eq(tokensToReceive)
        expect(curatorSharesAfter).to.be.bignumber.eq(new BN(0))

        // Subgraph deallocated
        expect(subgraphAfter.tokens).to.be.bignumber.eq(new BN(0))
        expect(subgraphAfter.shares).to.be.bignumber.eq(new BN(0))
        expect(subgraphAfter.reserveRatio).to.be.bignumber.eq(new BN(0))

        // Contract balance updated
        expect(totalTokensAfter).to.be.bignumber.eq(new BN(0))

        // Withdrawal fees are burned
        expect(tokenTotalSupplyAfter).to.be.bignumber.eq(tokenTotalSupplyBefore.sub(withdrawalFees))
      })

      it('should collect tokens distributed as reserves for a subgraph', async function() {
        // Before balances
        const totalBalanceBefore = await this.grt.balanceOf(this.curation.address)
        const subgraphBefore = await this.curation.subgraphs(this.subgraphID)

        // Source of tokens must be the staking for this to work
        const { logs } = await this.curation.collect(this.subgraphID, this.tokensToCollect, {
          from: staking,
        })
        expectEvent.inLogs(logs, 'Collected', {
          subgraphID: this.subgraphID,
          tokens: this.tokensToCollect,
        })

        // After balances
        const totalBalanceAfter = await this.grt.balanceOf(this.curation.address)
        const subgraphAfter = await this.curation.subgraphs(this.subgraphID)

        // Subgraph balance updated
        expect(subgraphAfter.tokens).to.be.bignumber.eq(
          subgraphBefore.tokens.add(this.tokensToCollect),
        )

        // Contract balance updated
        expect(totalBalanceAfter).to.be.bignumber.eq(totalBalanceBefore.add(this.tokensToCollect))
      })
    })
  })
})
