const { expect } = require('chai')
const { expectEvent, expectRevert } = require('openzeppelin-test-helpers')

// helpers
const attestation = require('./lib/attestation')
const deployment = require('./lib/deployment')
const helpers = require('./lib/testHelpers')

const MAX_PPM = 1000000

contract(
  'Disputes',
  ([me, other, governor, arbitrator, indexNode, fisherman]) => {
    let deployedServiceRegistry

    async function deployContracts() {
      // Deploy graph token
      graphToken = await deployment.deployGraphToken(governor, { from: me })

      // Deploy staking contract
      staking = await deployment.deployStakingContract(
        governor,
        graphToken.address,
        { from: me },
      )

      // Deploy dispute contract
      disputeManager = await deployment.deployDisputeManagerContract(
        governor,
        graphToken.address,
        arbitrator,
        staking.address,
        { from: me },
      )
    }

    before(async () => {
      await deployContracts()
    })

    describe('state variables', () => {
      it('should set `governor`', async function() {
        // Set right in the constructor
        expect(await disputeManager.governor()).to.equal(governor)

        // Can set if allowed
        await disputeManager.transferGovernance(other, { from: governor })
        expect(await disputeManager.governor()).to.equal(other)

        // Restore
        await disputeManager.transferGovernance(governor, { from: other })
      })

      it('should set `graphToken`', async function() {
        // Set right in the constructor
        expect(await disputeManager.token()).to.equal(graphToken.address)
      })

      it('should set `arbitrator` only if allowd', async function() {
        // Set right in the constructor
        expect(await disputeManager.arbitrator()).to.equal(arbitrator)

        // Can set if allowed
        await disputeManager.setArbitrator(other, { from: governor })
        expect(await disputeManager.arbitrator()).to.equal(other)

        // Restore
        await disputeManager.setArbitrator(arbitrator, { from: governor })
        expect(await disputeManager.arbitrator()).to.equal(arbitrator)
      })

      it('reject set `arbitrator` if not allowed', async function() {
        await expectRevert.unspecified(
          disputeManager.setArbitrator(arbitrator, { from: other }),
        )
      })

      it('should set `slashingPercent`', async function() {
        // Set right in the constructor
        expect(await disputeManager.slashingPercent()).to.be.bignumber.equal(
          helpers.stakingConstants.slashingPercent.toString(),
        )

        // Can set if allowed
        await disputeManager.setSlashingPercent(0, { from: governor })
        await disputeManager.setSlashingPercent(1, { from: governor })
        await disputeManager.setSlashingPercent(
          helpers.stakingConstants.slashingPercent,
          { from: governor },
        )
      })

      it('reject set `slashingPercent` if out of bounds', async function() {
        await expectRevert(
          disputeManager.setSlashingPercent(MAX_PPM + 1, { from: governor }),
          'Slashing percent must be below or equal to MAX_PPM',
        )
      })

      it('reject set `slashingPercent` if not allowed', async function() {
        await expectRevert(
          disputeManager.setSlashingPercent(50, { from: other }),
          'Only Governor can call',
        )
      })
    })

    describe('reward calculation', () => {
      it('should calculate the reward for a stake', async function() {
        const stakedAmount = 1000
        const trueReward =
          (helpers.stakingConstants.slashingPercent * stakedAmount) / MAX_PPM
        const funcReward = await disputeManager.getRewardForStake(stakedAmount)
        expect(funcReward).to.be.bignumber.equal(trueReward.toString())
      })
    })

    describe('start a dispute', () => {
      it.only('should create a dispute', async function() {
        const tokensMintedForStaker =
          helpers.graphTokenConstants.tokensMintedForStaker

        // Give some funds to the indexNode
        await graphToken.mint(indexNode, tokensMintedForStaker, {
          from: governor,
        })

        // Give some funds to the fisherman
        await graphToken.mint(fisherman, tokensMintedForStaker, {
          from: governor,
        })

        // Dispute manager is allowed to slash
        await staking.addSlasher(disputeManager.address, { from: governor })

        // Index node stake funds
        const subgraphId = helpers.randomSubgraphIdHex0x()

        const data = '0x00' + subgraphId.substring(2)
        await graphToken.transferToTokenReceiver(
          staking.address,
          tokensMintedForStaker,
          data,
          { from: indexNode },
        )

        // Fisherman create a dispute
        const dispute = await attestation.createDisputePayload(
          subgraphId,
          disputeManager.address,
          indexNode,
        )

        // Create dispute
        const {
          tx,
        } = await graphToken.transferToTokenReceiver(
          disputeManager.address,
          tokensMintedForStaker,
          dispute.payload,
          { from: fisherman },
        )

        // Event emitted
        expectEvent.inTransaction(
          tx,
          disputeManager.constructor,
          'DisputeCreated',
          {
            disputeID: dispute.messageHash,
            subgraphID: subgraphId,
            indexNode: indexNode,
            fisherman: fisherman,
            attestation: dispute.attestation,
          },
        )
      })
    })
  },
)
