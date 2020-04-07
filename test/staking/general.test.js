const BN = web3.utils.BN
const { expect } = require('chai')
const { constants, expectRevert, expectEvent } = require('@openzeppelin/test-helpers')

// helpers
const deployment = require('../lib/deployment')
const helpers = require('../lib/testHelpers')

contract('Staking (general)', ([me, other, governor, indexNode]) => {
  before(async function() {
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
  })

  describe('staking', function() {
    beforeEach(async function() {
      // Give some funds to the indexNode
      this.indexNodeTokens = web3.utils.toWei(new BN('1000'))
      await this.graphToken.mint(indexNode, this.indexNodeTokens, {
        from: governor,
      })
    })

    it('should stake tokens', async function() {
      // Stake as an index node
      const indexNodeStake = web3.utils.toWei(new BN('100'))
      await this.graphToken.transferToTokenReceiver(this.staking.address, indexNodeStake, '0x00', {
        from: indexNode,
      })

      const stakeTokens = await this.staking.getStakeTokens(indexNode)
      expect(stakeTokens).to.be.bignumber.equal(indexNodeStake)
    })
  })
})
