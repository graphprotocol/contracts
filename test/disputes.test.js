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
    before(async function() {
      // Deploy graph token
      this.graphToken = await deployment.deployGraphToken(governor, {
        from: me,
      })

      // Deploy staking contract
      this.staking = await deployment.deployStakingContract(
        governor,
        this.graphToken.address,
        { from: me },
      )

      // Deploy dispute contract
      this.disputeManager = await deployment.deployDisputeManagerContract(
        governor,
        this.graphToken.address,
        arbitrator,
        this.staking.address,
        { from: me },
      )
    })

    describe('state variables', () => {
      it('should set `governor`', async function() {
        // Set right in the constructor
        expect(await this.disputeManager.governor()).to.equal(governor)

        // Can set if allowed
        await this.disputeManager.transferGovernance(other, { from: governor })
        expect(await this.disputeManager.governor()).to.equal(other)

        // Restore
        await this.disputeManager.transferGovernance(governor, { from: other })
      })

      it('should set `graphToken`', async function() {
        // Set right in the constructor
        expect(await this.disputeManager.token()).to.equal(
          this.graphToken.address,
        )
      })

      it('should set `arbitrator` only if allowd', async function() {
        // Set right in the constructor
        expect(await this.disputeManager.arbitrator()).to.equal(arbitrator)

        // Can set if allowed
        await this.disputeManager.setArbitrator(other, { from: governor })
        expect(await this.disputeManager.arbitrator()).to.equal(other)

        // Restore
        await this.disputeManager.setArbitrator(arbitrator, { from: governor })
        expect(await this.disputeManager.arbitrator()).to.equal(arbitrator)
      })

      it('reject set `arbitrator` if not allowed', async function() {
        await expectRevert.unspecified(
          this.disputeManager.setArbitrator(arbitrator, { from: other }),
        )
      })

      it('should set `slashingPercent`', async function() {
        // Set right in the constructor
        expect(
          await this.disputeManager.slashingPercent(),
        ).to.be.bignumber.equal(
          helpers.stakingConstants.slashingPercent.toString(),
        )

        // Can set if allowed
        await this.disputeManager.setSlashingPercent(0, { from: governor })
        await this.disputeManager.setSlashingPercent(1, { from: governor })
        await this.disputeManager.setSlashingPercent(
          helpers.stakingConstants.slashingPercent,
          { from: governor },
        )
      })

      it('reject set `slashingPercent` if out of bounds', async function() {
        await expectRevert(
          this.disputeManager.setSlashingPercent(MAX_PPM + 1, {
            from: governor,
          }),
          'Slashing percent must be below or equal to MAX_PPM',
        )
      })

      it('reject set `slashingPercent` if not allowed', async function() {
        await expectRevert(
          this.disputeManager.setSlashingPercent(50, { from: other }),
          'Only Governor can call',
        )
      })
    })

    describe('reward calculation', () => {
      it('should calculate the reward for a stake', async function() {
        const stakedAmount = 1000
        const trueReward =
          (helpers.stakingConstants.slashingPercent * stakedAmount) / MAX_PPM
        const funcReward = await this.disputeManager.getRewardForStake(
          stakedAmount,
        )
        expect(funcReward).to.be.bignumber.equal(trueReward.toString())
      })
    })

    describe('create a dispute', function() {
      before(async function() {
        this.tokensForIndexNode =
          helpers.graphTokenConstants.tokensMintedForStaker
        this.tokensForFisherman =
          helpers.graphTokenConstants.tokensMintedForStaker
        this.indexNodeStake = this.tokensForIndexNode

        // Create a subgraphId
        this.subgraphId = helpers.randomSubgraphIdHex0x()

        // Get index node signed attestation
        this.validDispute = await attestation.createDisputePayload(
          this.subgraphId,
          this.disputeManager.address,
          indexNode,
        )
      })

      context('when stake does not exist', function() {
        it('reject create a dispute', async function() {
          // Give some funds to the fisherman
          await this.graphToken.mint(fisherman, this.tokensForFisherman, {
            from: governor,
          })

          // Create dispute
          await expectRevert(
            this.graphToken.transferToTokenReceiver(
              this.disputeManager.address,
              this.tokensForFisherman,
              this.validDispute.payload,
              { from: fisherman },
            ),
            'Dispute has no stake on the subgraph by the indexer node',
          )
        })
      })

      context('when stake exists', function() {
        before(async function() {
          // Give some funds to the indexNode
          await this.graphToken.mint(indexNode, this.tokensForIndexNode, {
            from: governor,
          })

          // Dispute manager is allowed to slash
          await this.staking.addSlasher(this.disputeManager.address, {
            from: governor,
          })

          // Index node stake funds
          const data = '0x00' + this.subgraphId.substring(2)
          await this.graphToken.transferToTokenReceiver(
            this.staking.address,
            this.indexNodeStake,
            data,
            { from: indexNode },
          )
        })

        it('reject fisherman deposit below minimum required', async function() {
          // Give some funds to the fisherman
          await this.graphToken.mint(fisherman, this.tokensForFisherman, {
            from: governor,
          })

          // Minimum deposit a fisherman is required to do should be >= reward
          const minimumDeposit = await this.disputeManager.getRewardForStake(
            this.indexNodeStake,
          )
          const belowMinimumDeposit = minimumDeposit.sub(web3.utils.toBN(1))

          // Create invalid dispute as deposit is below minimum
          await expectRevert(
            this.graphToken.transferToTokenReceiver(
              this.disputeManager.address,
              belowMinimumDeposit,
              this.validDispute.payload,
              { from: fisherman },
            ),
            'Dispute deposit under minimum required',
          )
        })

        it('should create a dispute', async function() {
          // Give some funds to the fisherman
          await this.graphToken.mint(fisherman, this.tokensForFisherman, {
            from: governor,
          })

          // Create dispute
          const { tx } = await this.graphToken.transferToTokenReceiver(
            this.disputeManager.address,
            this.tokensForFisherman,
            this.validDispute.payload,
            { from: fisherman },
          )

          // Event emitted
          expectEvent.inTransaction(
            tx,
            this.disputeManager.constructor,
            'DisputeCreated',
            {
              disputeID: this.validDispute.messageHash,
              subgraphID: this.subgraphId,
              indexNode: indexNode,
              fisherman: fisherman,
              attestation: this.validDispute.attestation,
            },
          )
        })

        it('reject create duplicated dispute', async function() {
          // Give some funds to the fisherman
          await this.graphToken.mint(fisherman, this.tokensForFisherman, {
            from: governor,
          })

          // Create dispute
          await await expectRevert(
            this.graphToken.transferToTokenReceiver(
              this.disputeManager.address,
              this.tokensForFisherman,
              this.validDispute.payload,
              { from: fisherman },
            ),
            'Dispute already created',
          )
        })
      })
    })
  },
)
