const BN = web3.utils.BN
const { expect } = require('chai')
const { constants, expectRevert, expectEvent } = require('@openzeppelin/test-helpers')

// helpers
const deployment = require('../lib/deployment')
const helpers = require('../lib/testHelpers')
const { defaults } = require('../lib/testHelpers')

const MAX_PPM = 1000000

contract('Curation', ([me, other, governor, curator, distributor]) => {
  beforeEach(async function() {
    // Deploy graph token
    this.graphToken = await deployment.deployGraphToken(governor, {
      from: me,
    })

    // Deploy curation contract
    this.curation = await deployment.deployCurationContract(
      governor,
      this.graphToken.address,
      distributor,
      { from: me },
    )
  })

  describe('state variables functions', function() {
    it('should set `governor`', async function() {
      // Set right in the constructor
      expect(await this.curation.governor()).to.equal(governor)
    })

    it('should set `graphToken`', async function() {
      // Set right in the constructor
      expect(await this.curation.token()).to.equal(this.graphToken.address)
    })

    it('should set `distributor`', async function() {
      // Set right in the constructor
      expect(await this.curation.distributor()).to.equal(distributor)

      // Can set if allowed
      await this.curation.setDistributor(other, { from: governor })
      expect(await this.curation.distributor()).to.equal(other)
    })

    it('reject set `distributor` if empty address', async function() {
      await expectRevert(
        this.curation.setDistributor(constants.ZERO_ADDRESS, {
          from: governor,
        }),
        'Distributor must be set',
      )
    })

    it('reject set `distributor` if not allowed', async function() {
      await expectRevert(
        this.curation.setDistributor(distributor, { from: other }),
        'Only Governor can call',
      )
    })

    it('should set `defaultReserveRatio`', async function() {
      // Set right in the constructor
      expect(await this.curation.defaultReserveRatio()).to.be.bignumber.equal(
        defaults.curation.reserveRatio,
      )

      // Can set if allowed
      const newDefaultReserveRatio = defaults.curation.reserveRatio.add(new BN(100))
      await this.curation.setDefaultReserveRatio(newDefaultReserveRatio, {
        from: governor,
      })
      expect(await this.curation.defaultReserveRatio()).to.be.bignumber.equal(
        newDefaultReserveRatio,
      )
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

    it('should set `minimumCurationStake`', async function() {
      // Set right in the constructor
      expect(await this.curation.minimumCurationStake()).to.be.bignumber.equal(
        defaults.curation.minimumCurationStake,
      )

      // Can set if allowed
      const newMinimumCurationStake = defaults.curation.minimumCurationStake.add(new BN(100))
      await this.curation.setMinimumCurationStake(newMinimumCurationStake, {
        from: governor,
      })
      expect(await this.curation.minimumCurationStake()).to.be.bignumber.equal(
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

  context('bonding curve', function() {
    beforeEach(function() {
      this.subgraphId = helpers.randomSubgraphIdHex0x()
    })

    it('convert shares to tokens', async function() {
      // Give some funds to the curator
      const curatorTokens = web3.utils.toWei(new BN('1000'))
      await this.graphToken.mint(curator, curatorTokens, {
        from: governor,
      })

      // Curate a subgraph
      await this.graphToken.transferToTokenReceiver(
        this.curation.address,
        curatorTokens,
        this.subgraphId,
        { from: curator },
      )

      // Conversion
      const shares = (await this.curation.subgraphs(this.subgraphId)).shares
      const tokens = await this.curation.subgraphSharesToTokens(this.subgraphId, shares)
      expect(tokens).to.be.bignumber.equal(curatorTokens)
    })

    it('convert tokens to shares', async function() {
      // Conversion
      const tokens = web3.utils.toWei(new BN('1000'))
      const shares = await this.curation.subgraphTokensToShares(this.subgraphId, tokens)
      expect(shares).to.be.bignumber.equal(defaults.curation.shareAmountFor1000Tokens)
    })
  })

  context('when subgraph is not curated', function() {
    beforeEach(function() {
      this.subgraphId = helpers.randomSubgraphIdHex0x()
    })

    it('should stake on a subgraph', async function() {
      // Give some funds to the curator
      const curatorTokens = web3.utils.toWei(new BN('1000'))
      await this.graphToken.mint(curator, curatorTokens, {
        from: governor,
      })

      // Before balances
      const totalBalanceBefore = await this.graphToken.balanceOf(this.curation.address)
      const curatorBalanceBefore = await this.graphToken.balanceOf(curator)

      // Curate a subgraph
      // Staking the minimum required = 1 share
      const curatorStake = defaults.curation.minimumCurationStake
      const { tx } = await this.graphToken.transferToTokenReceiver(
        this.curation.address,
        curatorStake,
        this.subgraphId,
        { from: curator },
      )

      // After balances
      const totalBalanceAfter = await this.graphToken.balanceOf(this.curation.address)
      const curatorBalanceAfter = await this.graphToken.balanceOf(curator)

      // Tokens transferred properly
      expect(totalBalanceAfter).to.be.bignumber.equal(totalBalanceBefore.add(curatorStake))
      expect(curatorBalanceAfter).to.be.bignumber.equal(curatorBalanceBefore.sub(curatorStake))

      // State properly updated
      const subgraph = await this.curation.subgraphs(this.subgraphId)
      expect(subgraph.reserveRatio).to.be.bignumber.equal(defaults.curation.reserveRatio)
      expect(subgraph.tokens).to.be.bignumber.equal(curatorStake)
      expect(subgraph.shares).to.be.bignumber.equal(web3.utils.toBN(1))

      const curatorShares = await this.curation.getCuratorShares(curator, this.subgraphId)
      expect(curatorShares).to.be.bignumber.equal(web3.utils.toBN(1))

      const totalTokens = await this.curation.totalTokens()
      expect(totalTokens).to.be.bignumber.equal(curatorStake)

      // Event emitted
      expectEvent.inTransaction(tx, this.curation.constructor, 'CuratorStakeUpdated', {
        curator: curator,
        subgraphID: this.subgraphId,
        shares: '1',
      })

      expectEvent.inTransaction(tx, this.curation.constructor, 'SubgraphStakeUpdated', {
        subgraphID: this.subgraphId,
        shares: '1',
        tokens: curatorStake,
      })
    })

    it('reject unstake', async function() {
      await expectRevert(
        this.curation.unstake(this.subgraphId, 1),
        'Cannot unstake more shares than you own',
      )
    })

    it('reject collect tokens distributed as fees for the subgraph', async function() {
      // Give some funds to the distributor
      const tokens = web3.utils.toWei(new BN('1000'))
      await this.graphToken.mint(distributor, tokens, {
        from: governor,
      })

      // Source of tokens must be the distributor for this to work
      await expectRevert(
        this.graphToken.transferToTokenReceiver(this.curation.address, tokens, this.subgraphId, {
          from: distributor,
        }),
        'Subgraph must be curated to collect fees',
      )
    })
  })

  context('when subgraph is curated', function() {
    beforeEach(async function() {
      this.subgraphId = helpers.randomSubgraphIdHex0x()

      // Give some funds to the curator
      const curatorTokens = web3.utils.toWei(new BN('1000'))
      await this.graphToken.mint(curator, curatorTokens, {
        from: governor,
      })

      // Curate a subgraph
      await this.graphToken.transferToTokenReceiver(
        this.curation.address,
        curatorTokens,
        this.subgraphId,
        { from: curator },
      )
    })

    it('reject unstake zero shares from a subgraph', async function() {
      await expectRevert(this.curation.unstake(this.subgraphId, 0), 'Cannot unstake zero shares')
    })

    it('should assign the right amount of shares according to bonding curve', async function() {
      // Shares should be curatorShares bought with minimum stake (1) + newShares with rest of tokens
      const curatorShares = await this.curation.getCuratorShares(curator, this.subgraphId)
      expect(curatorShares).to.be.bignumber.equal(defaults.curation.shareAmountFor1000Tokens)
    })

    it('should allow to unstake *partially* on a subgraph', async function() {
      // Before balances
      const subgraphBefore = await this.curation.subgraphs(this.subgraphId)
      const curatorTokensBefore = await this.graphToken.balanceOf(curator)
      const curatorSharesBefore = await this.curation.getCuratorShares(curator, this.subgraphId)
      const totalTokensBefore = await this.curation.totalTokens()

      // Unstake
      const sharesToSell = new BN(1) // Curator want to sell 1 share
      const expectedTokens = await this.curation.subgraphSharesToTokens(
        this.subgraphId,
        sharesToSell,
      )
      const { tx } = await this.curation.unstake(this.subgraphId, sharesToSell, { from: curator })

      // After balances
      const subgraphAfter = await this.curation.subgraphs(this.subgraphId)
      const curatorTokensAfter = await this.graphToken.balanceOf(curator)
      const curatorSharesAfter = await this.curation.getCuratorShares(curator, this.subgraphId)
      const totalTokensAfter = await this.curation.totalTokens()

      // State properly updated
      expect(curatorTokensAfter).to.be.bignumber.equal(curatorTokensBefore.add(expectedTokens))
      expect(curatorSharesAfter).to.be.bignumber.equal(curatorSharesBefore.sub(sharesToSell))
      expect(subgraphAfter.shares).to.be.bignumber.equal(subgraphBefore.shares.sub(sharesToSell))
      expect(totalTokensAfter).to.be.bignumber.equal(totalTokensBefore.sub(expectedTokens))

      // Event emitted
      expectEvent.inTransaction(tx, this.curation.constructor, 'CuratorStakeUpdated', {
        curator: curator,
        subgraphID: this.subgraphId,
        shares: curatorSharesAfter,
      })

      expectEvent.inTransaction(tx, this.curation.constructor, 'SubgraphStakeUpdated', {
        subgraphID: this.subgraphId,
        shares: subgraphAfter.shares,
        tokens: subgraphAfter.tokens,
      })
    })

    it('should allow to unstake *fully* on a subgraph', async function() {
      // Before balances
      const subgraphBefore = await this.curation.subgraphs(this.subgraphId)

      // Unstake all shares
      const sharesToSell = subgraphBefore.shares // we are selling all shares in the subgraph
      const tokensToReceive = subgraphBefore.tokens // we are withdrawing all funds
      await this.curation.unstake(this.subgraphId, sharesToSell, {
        from: curator,
      })

      // After balances
      const subgraphAfter = await this.curation.subgraphs(this.subgraphId)
      const curatorTokensAfter = await this.graphToken.balanceOf(curator)
      const curatorSharesAfter = await this.curation.getCuratorShares(curator, this.subgraphId)
      const totalTokensAfter = await this.curation.totalTokens()

      // State properly updated
      expect(curatorTokensAfter).to.be.bignumber.equal(tokensToReceive)
      expect(curatorSharesAfter).to.be.bignumber.equal(new BN(0))
      expect(subgraphAfter.tokens).to.be.bignumber.equal(new BN(0))
      expect(subgraphAfter.shares).to.be.bignumber.equal(new BN(0))
      expect(totalTokensAfter).to.be.bignumber.equal(new BN(0))
    })

    it('should collect tokens distributed as reserves for a subgraph', async function() {
      // Give some funds to the distributor
      const tokens = web3.utils.toWei(new BN('1000'))
      await this.graphToken.mint(distributor, tokens, {
        from: governor,
      })

      // Before balances
      const totalBalanceBefore = await this.graphToken.balanceOf(this.curation.address)
      const subgraphBefore = await this.curation.subgraphs(this.subgraphId)

      // Source of tokens must be the distributor for this to work
      const { tx } = await this.graphToken.transferToTokenReceiver(
        this.curation.address,
        tokens,
        this.subgraphId,
        { from: distributor },
      )

      // After balances
      const totalBalanceAfter = await this.graphToken.balanceOf(this.curation.address)
      const subgraphAfter = await this.curation.subgraphs(this.subgraphId)

      // State properly updated
      expect(totalBalanceAfter).to.be.bignumber.equal(totalBalanceBefore.add(tokens))
      expect(subgraphAfter.tokens).to.be.bignumber.equal(subgraphBefore.tokens.add(tokens))

      // Event emitted
      expectEvent.inTransaction(tx, this.curation.constructor, 'SubgraphStakeUpdated', {
        subgraphID: this.subgraphId,
        shares: subgraphAfter.shares,
        tokens: subgraphAfter.tokens,
      })
    })
  })
})
