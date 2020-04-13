const BN = web3.utils.BN
const { expect } = require('chai')
const { expectRevert, expectEvent } = require('@openzeppelin/test-helpers')

// helpers
const deployment = require('../lib/deployment')
const helpers = require('../lib/testHelpers')
const { defaults } = require('../lib/testHelpers')

contract('Staking (general)', ([me, other, governor, indexNode, otherIndexNode]) => {
  beforeEach(async function() {
    // Deploy epoch contract
    this.epochManager = await deployment.deployEpochManagerContract(governor, { from: me })

    // Deploy graph token
    this.graphToken = await deployment.deployGraphToken(governor, {
      from: me,
    })

    // Deploy staking contract
    this.staking = await deployment.deployStakingContract(
      governor,
      this.graphToken.address,
      this.epochManager.address,
      { from: me },
    )
  })

  describe('state variables functions', function() {
    it('should set `governor`', async function() {
      // Set right in the constructor
      expect(await this.staking.governor()).to.equal(governor)
    })

    it('should set `graphToken`', async function() {
      // Set right in the constructor
      expect(await this.staking.token()).to.equal(this.graphToken.address)
    })

    it('should set `setMaxSettlementDuration`', async function() {
      // Set right in the constructor
      expect(await this.staking.maxSettlementDuration()).to.be.bignumber.equal(
        new BN(defaults.staking.maxSettlementDuration),
      )

      // Can set if allowed
      const newValue = new BN(5)
      await this.staking.setMaxSettlementDuration(newValue, { from: governor })
      expect(await this.staking.maxSettlementDuration()).to.be.bignumber.equal(newValue)
    })

    it('reject set `setMaxSettlementDuration` if not allowed', async function() {
      const newValue = new BN(5)
      await expectRevert(
        this.staking.setMaxSettlementDuration(newValue, { from: other }),
        'Only Governor can call',
      )
    })

    it('should set `setThawingPeriod`', async function() {
      // Set right in the constructor
      expect(await this.staking.thawingPeriod()).to.be.bignumber.equal(
        new BN(defaults.staking.thawingPeriod),
      )

      // Can set if allowed
      const newValue = new BN(5)
      await this.staking.setThawingPeriod(newValue, { from: governor })
      expect(await this.staking.thawingPeriod()).to.be.bignumber.equal(newValue)
    })

    it('reject set `setThawingPeriod` if not allowed', async function() {
      const newValue = 5
      await expectRevert(
        this.staking.setThawingPeriod(newValue, { from: other }),
        'Only Governor can call',
      )
    })
  })

  describe('staking', function() {
    beforeEach(async function() {
      this.channelId = '0x10'
      this.subgraphId = helpers.randomSubgraphIdHex0x()

      // Give some funds to the index node
      this.indexNodeTokens = web3.utils.toWei(new BN('1000'))
      await this.graphToken.mint(indexNode, this.indexNodeTokens, {
        from: governor,
      })

      // Helpers
      this.stake = async function(tokens) {
        const PAYMENT_PAYLOAD = '0x00'
        return this.graphToken.transferToTokenReceiver(
          this.staking.address,
          tokens,
          PAYMENT_PAYLOAD,
          { from: indexNode },
        )
      }

      this.allocate = function(tokens) {
        return this.staking.allocate(this.subgraphId, tokens, this.channelId, {
          from: indexNode,
        })
      }
    })

    context('when not staked', function() {
      it('should not have stakes `hasStake()`', async function() {
        expect(await this.staking.hasStake(indexNode)).to.be.equal(false)
      })

      it('should stake tokens', async function() {
        const indexNodeStake = web3.utils.toWei(new BN('100'))

        // Stake
        await this.stake(indexNodeStake)
        const tokens1 = await this.staking.getIndexNodeStakeTokens(indexNode)
        expect(tokens1).to.be.bignumber.equal(indexNodeStake)

        // Re-stake
        const { tx } = await this.stake(indexNodeStake)
        const tokens2 = await this.staking.getIndexNodeStakeTokens(indexNode)
        expect(tokens2).to.be.bignumber.equal(indexNodeStake.add(indexNodeStake))
        expectEvent.inTransaction(tx, this.staking.constructor, 'StakeUpdate', {
          indexNode: indexNode,
          tokens: tokens2,
        })
      })

      it('reject allocate to subgraph', async function() {
        const indexNodeStake = web3.utils.toWei(new BN('100'))
        await expectRevert(this.allocate(indexNodeStake), 'Allocate: index node has no stakes')
      })
    })

    context('when staked', function() {
      beforeEach(async function() {
        // Stake
        this.indexNodeStake = web3.utils.toWei(new BN('100'))
        await this.stake(this.indexNodeStake)
      })

      it('should have stakes `hasStake()`', async function() {
        expect(await this.staking.hasStake(indexNode)).to.be.equal(true)
      })

      it('should allocate to subgraph', async function() {
        await this.allocate(this.indexNodeStake)
      })

      it('reject allocate to subgraph more than available tokens', async function() {
        const tokensOverCapacity = this.indexNodeStake.add(new BN(1))
        await expectRevert(
          this.allocate(tokensOverCapacity),
          'Allocate: not enough available tokens',
        )
      })

      context('when subgraph allocated', function() {
        beforeEach(async function() {
          this.allocTokens = web3.utils.toWei(new BN('10'))
          await this.allocate(this.allocTokens)
        })

        it('reject allocate to subgraph if channel is active', async function() {
          const tokens = web3.utils.toWei(new BN('10'))
          await expectRevert(this.allocate(tokens), 'Allocate: payment channel ID already in use')
        })
      })
    })
  })
})
