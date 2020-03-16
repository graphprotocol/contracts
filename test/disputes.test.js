const { expect } = require('chai')
const { expectEvent, expectRevert } = require('openzeppelin-test-helpers')

// helpers
const attestation = require('./lib/attestation')
const deployment = require('./lib/deployment')
const helpers = require('./lib/testHelpers')

const MAX_PPM = 1000000
const NON_EXISTING_DISPUTE_ID = '0x0'

contract(
  'Disputes',
  ([me, other, governor, arbitrator, indexNode, fisherman]) => {
    beforeEach(async function() {
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

    describe('state variables accesors', () => {
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

      it('should set `arbitrator` only if allowed', async function() {
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

    describe('dispute lifecycle', function() {
      before(async function() {
        // Defaults
        this.tokensForIndexNode =
          helpers.graphTokenConstants.tokensMintedForStaker
        this.tokensForFisherman =
          helpers.graphTokenConstants.tokensMintedForStaker
        this.indexNodeStake = this.tokensForIndexNode

        // Create a subgraphId
        this.subgraphId = helpers.randomSubgraphIdHex0x()
      })

      context('when stake does not exist', function() {
        it('reject create a dispute', async function() {
          // Give some funds to the fisherman
          await this.graphToken.mint(fisherman, this.tokensForFisherman, {
            from: governor,
          })

          // Get index node signed attestation
          const dispute = await attestation.createDisputePayload(
            this.subgraphId,
            this.disputeManager.address,
            indexNode,
          )

          // Create dispute
          await expectRevert(
            this.graphToken.transferToTokenReceiver(
              this.disputeManager.address,
              this.tokensForFisherman,
              dispute.payload,
              { from: fisherman },
            ),
            'Dispute has no stake on the subgraph by the indexer node',
          )
        })
      })

      context('when stake does exist', function() {
        beforeEach(async function() {
          // Dispute manager is allowed to slash
          await this.staking.addSlasher(this.disputeManager.address, {
            from: governor,
          })

          // Give some funds to the indexNode
          await this.graphToken.mint(indexNode, this.tokensForIndexNode, {
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

        describe('create dispute', function() {
          beforeEach(async function() {
            // Get index node signed attestation
            this.dispute = await attestation.createDisputePayload(
              this.subgraphId,
              this.disputeManager.address,
              indexNode,
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
                this.dispute.payload,
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
              this.dispute.payload,
              { from: fisherman },
            )

            // Event emitted
            expectEvent.inTransaction(
              tx,
              this.disputeManager.constructor,
              'DisputeCreated',
              {
                disputeID: this.dispute.messageHash,
                subgraphID: this.subgraphId,
                indexNode: indexNode,
                fisherman: fisherman,
                attestation: this.dispute.attestation,
              },
            )
          })

          it('reject create duplicated dispute', async function() {
            // Give some funds to the fisherman
            await this.graphToken.mint(fisherman, this.tokensForFisherman, {
              from: governor,
            })

            // Create dispute
            await this.graphToken.transferToTokenReceiver(
              this.disputeManager.address,
              this.tokensForFisherman,
              this.dispute.payload,
              { from: fisherman },
            )

            // Give some funds to the fisherman
            await this.graphToken.mint(fisherman, this.tokensForFisherman, {
              from: governor,
            })

            // Create dispute (duplicated)
            await expectRevert(
              this.graphToken.transferToTokenReceiver(
                this.disputeManager.address,
                this.tokensForFisherman,
                this.dispute.payload,
                { from: fisherman },
              ),
              'Dispute already created',
            )
          })
        })

        context('when dispute is created', function() {
          beforeEach(async function() {
            // Get index node signed attestation
            this.dispute = await attestation.createDisputePayload(
              this.subgraphId,
              this.disputeManager.address,
              indexNode,
            )

            // Give some funds to the fisherman
            await this.graphToken.mint(fisherman, this.tokensForFisherman, {
              from: governor,
            })

            // Create dispute
            await this.graphToken.transferToTokenReceiver(
              this.disputeManager.address,
              this.tokensForFisherman,
              this.dispute.payload,
              { from: fisherman },
            )
          })

          describe('accept a dispute', function() {
            it('reject to accept a non-existing dispute', async function() {
              await expectRevert(
                this.disputeManager.acceptDispute(NON_EXISTING_DISPUTE_ID, {
                  from: arbitrator,
                }),
                'Dispute does not exist',
              )
            })

            it('reject to accept a dispute if not the arbitrator', async function() {
              await expectRevert(
                this.disputeManager.acceptDispute(this.dispute.messageHash, {
                  from: me,
                }),
                'Caller is not the Arbitrator',
              )
            })

            it('should resolve dispute, slash indexer and reward the fisherman', async function() {
              const fishermanBalanceBefore = await this.graphToken.balanceOf(
                fisherman,
              )
              const totalSupplyBefore = await this.graphToken.totalSupply()
              const reward = await this.disputeManager.getRewardForStake(
                this.indexNodeStake,
              )

              // Perform transaction (accept)
              await this.disputeManager.acceptDispute(
                this.dispute.messageHash,
                { from: arbitrator },
              )

              // Fisherman reward properly assigned + deposit returned
              const deposit = web3.utils.toBN(this.tokensForFisherman)
              const fishermanBalanceAfter = await this.graphToken.balanceOf(
                fisherman,
              )
              expect(fishermanBalanceAfter).to.be.bignumber.equal(
                fishermanBalanceBefore.add(deposit).add(reward),
              )

              // IndexNode slashed
              const currentIndexNodeStake = await this.staking.getIndexingNodeStake(
                this.subgraphId,
                indexNode,
              )
              expect(currentIndexNodeStake).to.be.bignumber.equal(
                web3.utils.toBN(0),
              )

              // Slashed funds burned
              const indexNodeStake = web3.utils.toBN(this.indexNodeStake)
              const totalSupplyAfter = await this.graphToken.totalSupply()
              expect(totalSupplyAfter).to.be.bignumber.equal(
                totalSupplyBefore.sub(indexNodeStake.sub(reward)),
              )
            })
          })

          describe('reject a dispute', async function() {
            it('reject to reject a non-existing dispute', async function() {
              await expectRevert(
                this.disputeManager.rejectDispute(NON_EXISTING_DISPUTE_ID, {
                  from: arbitrator,
                }),
                'Dispute does not exist',
              )
            })

            it('reject to reject a dispute if not the arbitrator', async function() {
              await expectRevert(
                this.disputeManager.rejectDispute(this.dispute.messageHash, {
                  from: me,
                }),
                'Caller is not the Arbitrator',
              )
            })

            it('should reject a dispute and burn deposit', async function() {
              const fishermanBalanceBefore = await this.graphToken.balanceOf(
                fisherman,
              )
              const totalSupplyBefore = await this.graphToken.totalSupply()

              // Perform transaction (reject)
              const { tx } = await this.disputeManager.rejectDispute(
                this.dispute.messageHash,
                { from: arbitrator },
              )

              // No change in fisherman balance
              const fishermanBalanceAfter = await this.graphToken.balanceOf(
                fisherman,
              )
              expect(fishermanBalanceAfter).to.be.bignumber.equal(
                fishermanBalanceBefore,
              )

              // Burn fisherman deposit
              const totalSupplyAfter = await this.graphToken.totalSupply()
              const burnedTokens = web3.utils.toBN(this.tokensForFisherman)
              expect(totalSupplyAfter).to.be.bignumber.equal(
                totalSupplyBefore.sub(burnedTokens),
              )

              // Event emitted
              expectEvent.inTransaction(
                tx,
                this.disputeManager.constructor,
                'DisputeRejected',
                {
                  disputeID: this.dispute.messageHash,
                  subgraphID: this.subgraphId,
                  indexNode: indexNode,
                  fisherman: fisherman,
                  amount: this.tokensForFisherman,
                },
              )
            })
          })

          describe('ignore a dispute', async function() {
            it('reject to ignore a non-existing dispute', async function() {
              await expectRevert(
                this.disputeManager.ignoreDispute(NON_EXISTING_DISPUTE_ID, {
                  from: arbitrator,
                }),
                'Dispute does not exist',
              )
            })

            it('reject to ignore a dispute if not the arbitrator', async function() {
              await expectRevert(
                this.disputeManager.ignoreDispute(this.dispute.messageHash, {
                  from: me,
                }),
                'Caller is not the Arbitrator',
              )
            })

            it('should ignore a dispute and return deposit', async function() {
              const fishermanBalanceBefore = await this.graphToken.balanceOf(
                fisherman,
              )

              // Perform transaction (ignore)
              const { tx } = await this.disputeManager.ignoreDispute(
                this.dispute.messageHash,
                { from: arbitrator },
              )

              // Fisherman should see the deposit returned
              const fishermanBalanceAfter = await this.graphToken.balanceOf(
                fisherman,
              )
              const deposit = web3.utils.toBN(this.tokensForFisherman)
              expect(fishermanBalanceAfter).to.be.bignumber.equal(
                fishermanBalanceBefore.add(deposit),
              )

              // Event emitted
              expectEvent.inTransaction(
                tx,
                this.disputeManager.constructor,
                'DisputeIgnored',
                {
                  disputeID: this.dispute.messageHash,
                  subgraphID: this.subgraphId,
                  indexNode: indexNode,
                  fisherman: fisherman,
                  amount: this.tokensForFisherman,
                },
              )
            })
          })
        })
      })
    })
  },
)
