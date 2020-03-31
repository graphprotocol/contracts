const { expect } = require('chai')
const {
  constants,
  expectEvent,
  expectRevert,
  time,
} = require('@openzeppelin/test-helpers')
const { ZERO_ADDRESS } = constants
const BN = web3.utils.BN

// helpers
const deployment = require('./lib/deployment')
const helpers = require('./lib/testHelpers')
const { defaults } = require('./lib/testHelpers')

contract('EpochManager', ([me, other, governor]) => {
  beforeEach(async function() {
    // Deploy epoch manager contract
    this.epochManager = await deployment.deployEpochManagerContract(governor, {
      from: me,
    })
  })

  describe('state variables functions', () => {
    it('should set `governor`', async function() {
      // Set right in the constructor
      expect(await this.epochManager.governor()).to.equal(governor)

      // Can set if allowed
      await this.epochManager.transferGovernance(other, { from: governor })
      expect(await this.epochManager.governor()).to.equal(other)
    })

    it('should set `epochLength', async function() {
      // Set right in the constructor
      expect(await this.epochManager.epochLength()).to.be.bignumber.equal(
        defaults.epochs.lengthInBlocks,
      )

      // Update and check new value
      const newEpochLength = new BN(4)
      await this.epochManager.setEpochLength(newEpochLength, { from: governor })
      expect(await this.epochManager.epochLength()).to.be.bignumber.equal(
        newEpochLength,
      )
    })

    it('reject set `epochLength` if zero', async function() {
      // Update and check new value
      const newEpochLength = new BN(0)
      await expectRevert(
        this.epochManager.setEpochLength(newEpochLength, { from: governor }),
        'Epoch length cannot be 0',
      )
    })
  })

  describe('epoch calculations', () => {
    it('block number is current', async function() {
      const currentBlock = await time.latestBlock()
      expect(await this.epochManager.blockNum()).to.be.bignumber.equal(
        currentBlock,
      )
    })
  })
})
