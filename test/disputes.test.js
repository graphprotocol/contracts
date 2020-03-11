const { expect } = require('chai')
const { expectEvent, expectRevert } = require('openzeppelin-test-helpers')

// helpers
const deployment = require('./lib/deployment')
const helpers = require('./lib/testHelpers')

const MAX_PPM = 1000000

contract('Disputes', ([me, other, governor, arbitrator, indexNode]) => {
  let deployedServiceRegistry

  before(async () => {
    // deploy graph token
    graphToken = await deployment.deployGraphToken(governor, { from: me })

    // deploy staking contract
    staking = await deployment.deployStakingContract(
      governor,
      graphToken.address,
      { from: me },
    )

    // deploy dispute contract
    disputeManager = await deployment.deployDisputeManagerContract(
      governor,
      graphToken.address,
      arbitrator,
      staking.address,
      { from: me },
    )
  })

  describe('state variables', () => {
    it('should set `governor`', async function() {
      // set right in the constructor
      expect(await disputeManager.governor()).to.equal(governor)

      // can set if allowed
      await disputeManager.transferGovernance(other, { from: governor })
      expect(await disputeManager.governor()).to.equal(other)

      // restore
      await disputeManager.transferGovernance(governor, { from: other })
    })

    it('should set `graphToken`', async function() {
      // set right in the constructor
      expect(await disputeManager.token()).to.equal(graphToken.address)
    })

    it('should set `arbitrator` only if allowd', async function() {
      // set right in the constructor
      expect(await disputeManager.arbitrator()).to.equal(arbitrator)

      // can set if allowed
      await disputeManager.setArbitrator(other, { from: governor })
      expect(await disputeManager.arbitrator()).to.equal(other)

      // restore
      await disputeManager.setArbitrator(arbitrator, { from: governor })
      expect(await disputeManager.arbitrator()).to.equal(arbitrator)
    })

    it('reject set `arbitrator` if not allowed', async function() {
      await expectRevert.unspecified(
        disputeManager.setArbitrator(arbitrator, { from: other }),
      )
    })

    it('should set `slashingPercent`', async function() {
      // set right in the constructor
      expect(await disputeManager.slashingPercent()).to.be.bignumber.equal(
        helpers.stakingConstants.slashingPercent.toString(),
      )

      // can set if allowed
      await disputeManager.setSlashingPercent(0, { from: governor })
      await disputeManager.setSlashingPercent(1, { from: governor })
      await disputeManager.setSlashingPercent(helpers.stakingConstants.slashingPercent, { from: governor })
    })

    it('reject set `slashingPercent` if out of bounds', async function() {
      await expectRevert(
        disputeManager.setSlashingPercent(MAX_PPM + 1, { from: governor }),
        'Slashing percent must be below or equal to MAX_PPM',
      )
    })

    it('reject set `slashingPercent` if not allowed', async function() {
      // reject if not allowed
      await expectRevert(
        disputeManager.setSlashingPercent(50, { from: other }),
        'Only Governor can call',
      )
    })
  })

  describe('reward calculation', () => {
    it("should calculate the reward for a stake", async function() {
      const stakedAmount = 1000
      const trueReward = (helpers.stakingConstants.slashingPercent * stakedAmount) / MAX_PPM
      const funcReward = await disputeManager.getRewardForStake(stakedAmount)
      expect(funcReward).to.be.bignumber.equal(trueReward.toString())
    })
  })
})
