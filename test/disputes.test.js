const BN = web3.utils.BN
const { expect } = require('chai')
const { constants, expectEvent, expectRevert } = require('@openzeppelin/test-helpers')
const { ZERO_ADDRESS } = constants

// helpers
const attestation = require('./lib/attestation')
const deployment = require('./lib/deployment')
const helpers = require('./lib/testHelpers')
const { defaults } = require('./lib/testHelpers')

const MAX_PPM = 1000000
const NON_EXISTING_DISPUTE_ID = '0x0'

contract('Disputes', ([me, other, governor, arbitrator, indexNode, fisherman]) => {
  beforeEach(async function() {
    this.indexNodePrivKey = '0xadd53f9a7e588d003326d1cbf9e4a43c061aadd9bc938c843a79e7b4fd2ad743'

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

    // Deploy dispute contract
    this.disputeManager = await deployment.deployDisputeManagerContract(
      governor,
      this.graphToken.address,
      arbitrator,
      this.staking.address,
      { from: me },
    )
  })

  describe('state variables functions', () => {
    it('should set `governor`', async function() {
      // Set right in the constructor
      expect(await this.disputeManager.governor()).to.equal(governor)
    })

    it('should set `graphToken`', async function() {
      // Set right in the constructor
      expect(await this.disputeManager.token()).to.equal(this.graphToken.address)
    })

    it('should set `arbitrator`', async function() {
      // Set right in the constructor
      expect(await this.disputeManager.arbitrator()).to.equal(arbitrator)

      // Can set if allowed
      await this.disputeManager.setArbitrator(other, { from: governor })
      expect(await this.disputeManager.arbitrator()).to.equal(other)
    })

    it('reject set `arbitrator` if empty address', async function() {
      await expectRevert(
        this.disputeManager.setArbitrator(ZERO_ADDRESS, { from: governor }),
        'Cannot set arbitrator to empty address',
      )
    })

    it('reject set `arbitrator` if not allowed', async function() {
      await expectRevert(
        this.disputeManager.setArbitrator(arbitrator, { from: other }),
        'Only Governor can call',
      )
    })

    it('should set `rewardPercentage`', async function() {
      const rewardPercentage = defaults.dispute.rewardPercentage

      // Set right in the constructor
      expect(await this.disputeManager.rewardPercentage()).to.be.bignumber.equal(
        rewardPercentage.toString(),
      )

      // Set new value
      await this.disputeManager.setRewardPercentage(0, { from: governor })
      await this.disputeManager.setRewardPercentage(1, { from: governor })
      await this.disputeManager.setRewardPercentage(rewardPercentage, {
        from: governor,
      })
    })

    it('reject set `rewardPercentage` if out of bounds', async function() {
      await expectRevert(
        this.disputeManager.setRewardPercentage(MAX_PPM + 1, {
          from: governor,
        }),
        'Reward percentage must be below or equal to MAX_PPM',
      )
    })

    it('reject set `rewardPercentage` if not allowed', async function() {
      await expectRevert(
        this.disputeManager.setRewardPercentage(50, { from: other }),
        'Only Governor can call',
      )
    })

    it('should set `minimumDeposit`', async function() {
      const minimumDeposit = helpers.stakingConstants.minimumDisputeDepositAmount
      const newMinimumDeposit = web3.utils.toBN(1)

      // Set right in the constructor
      expect(await this.disputeManager.minimumDeposit()).to.be.bignumber.equal(minimumDeposit)

      // Set new value
      await this.disputeManager.setMinimumDeposit(newMinimumDeposit, {
        from: governor,
      })
      expect(await this.disputeManager.minimumDeposit()).to.be.bignumber.equal(newMinimumDeposit)
    })

    it('reject set `minimumDeposit` if not allowed', async function() {
      const minimumDeposit = helpers.stakingConstants.minimumDisputeDepositAmount

      await expectRevert(
        this.disputeManager.setMinimumDeposit(minimumDeposit, {
          from: other,
        }),
        'Only Governor can call',
      )
    })
  })

  describe('token transfer', function() {
    it('reject calls to token received hook if not the GRT token contract', async function() {
      await expectRevert(
        this.disputeManager.tokensReceived(fisherman, 10000, '0x0', {
          from: me,
        }),
        'Caller is not the GRT token contract',
      )
    })
  })

  describe('dispute lifecycle', function() {
    before(async function() {
      // Defaults
      this.tokensForIndexNode = helpers.graphTokenConstants.tokensMintedForStaker
      this.tokensForFisherman = helpers.graphTokenConstants.tokensMintedForStaker
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
          this.indexNodePrivKey,
        )

        // Create dispute
        await expectRevert(
          this.graphToken.transferToTokenReceiver(
            this.disputeManager.address,
            this.tokensForFisherman,
            dispute.payload,
            { from: fisherman },
          ),
          'Dispute has no stake by the index node',
        )
      })
    })

    context('when stake does exist', function() {
      beforeEach(async function() {
        // Dispute manager is allowed to slash
        await this.staking.setSlasher(this.disputeManager.address, true, {
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

      describe('reward calculation', function() {
        it('should calculate the reward for a stake', async function() {
          const stakedAmount = this.indexNodeStake
          const trueReward = stakedAmount
            .mul(defaults.staking.slashingPercentage)
            .div(new BN(MAX_PPM))
            .mul(defaults.dispute.rewardPercentage)
            .div(new BN(MAX_PPM))
          const funcReward = await this.disputeManager.getRewardForStake(indexNode)
          expect(funcReward).to.be.bignumber.equal(trueReward.toString())
        })
      })

      describe('create dispute', function() {
        beforeEach(async function() {
          // Get index node signed attestation
          this.dispute = await attestation.createDisputePayload(
            this.subgraphId,
            this.disputeManager.address,
            this.indexNodePrivKey,
          )
        })

        it('reject fisherman deposit below minimum required', async function() {
          // Give some funds to the fisherman
          await this.graphToken.mint(fisherman, this.tokensForFisherman, {
            from: governor,
          })

          // Minimum deposit a fisherman is required to do should be >= reward
          const minimumDeposit = await this.disputeManager.minimumDeposit()
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
          expectEvent.inTransaction(tx, this.disputeManager.constructor, 'DisputeCreated', {
            disputeID: this.dispute.messageHash,
            subgraphID: this.subgraphId,
            indexNode: indexNode,
            fisherman: fisherman,
            attestation: this.dispute.attestation,
          })
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
            this.indexNodePrivKey,
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

          it('reject to accept dispute if DisputeManager is not slasher', async function() {
            // Dispute manager is not allowed to slash
            await this.staking.setSlasher(this.disputeManager.address, false, {
              from: governor,
            })

            // Perform transaction (accept)
            await expectRevert(
              this.disputeManager.acceptDispute(this.dispute.messageHash, {
                from: arbitrator,
              }),
              'Caller is not a Slasher',
            )
          })

          it('should resolve dispute, slash indexer and reward the fisherman', async function() {
            const indexNodeStakeBefore = await this.staking.getStakeTokens(indexNode)
            const tokensToSlash = await this.staking.getSlashingAmount(indexNode)
            const fishermanBalanceBefore = await this.graphToken.balanceOf(fisherman)
            const totalSupplyBefore = await this.graphToken.totalSupply()
            const reward = await this.disputeManager.getRewardForStake(indexNode)

            // Perform transaction (accept)
            const { tx } = await this.disputeManager.acceptDispute(this.dispute.messageHash, {
              from: arbitrator,
            })

            // Fisherman reward properly assigned + deposit returned
            const deposit = web3.utils.toBN(this.tokensForFisherman)
            const fishermanBalanceAfter = await this.graphToken.balanceOf(fisherman)
            expect(fishermanBalanceAfter).to.be.bignumber.equal(
              fishermanBalanceBefore.add(deposit).add(reward),
            )

            // Index node slashed
            const indexNodeStakeAfter = await this.staking.getStakeTokens(indexNode)
            expect(indexNodeStakeAfter).to.be.bignumber.equal(
              indexNodeStakeBefore.sub(tokensToSlash),
            )

            // Slashed funds burned
            const tokensToBurn = tokensToSlash.sub(reward)
            const totalSupplyAfter = await this.graphToken.totalSupply()
            expect(totalSupplyAfter).to.be.bignumber.equal(totalSupplyBefore.sub(tokensToBurn))

            // Event emitted
            expectEvent.inTransaction(tx, this.disputeManager.constructor, 'DisputeAccepted', {
              disputeID: this.dispute.messageHash,
              subgraphID: this.subgraphId,
              indexNode: indexNode,
              fisherman: fisherman,
              deposit: deposit.add(reward),
            })
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
            const fishermanBalanceBefore = await this.graphToken.balanceOf(fisherman)
            const totalSupplyBefore = await this.graphToken.totalSupply()

            // Perform transaction (reject)
            const { tx } = await this.disputeManager.rejectDispute(this.dispute.messageHash, {
              from: arbitrator,
            })

            // No change in fisherman balance
            const fishermanBalanceAfter = await this.graphToken.balanceOf(fisherman)
            expect(fishermanBalanceAfter).to.be.bignumber.equal(fishermanBalanceBefore)

            // Burn fisherman deposit
            const totalSupplyAfter = await this.graphToken.totalSupply()
            const burnedTokens = web3.utils.toBN(this.tokensForFisherman)
            expect(totalSupplyAfter).to.be.bignumber.equal(totalSupplyBefore.sub(burnedTokens))

            // Event emitted
            expectEvent.inTransaction(tx, this.disputeManager.constructor, 'DisputeRejected', {
              disputeID: this.dispute.messageHash,
              subgraphID: this.subgraphId,
              indexNode: indexNode,
              fisherman: fisherman,
              deposit: this.tokensForFisherman,
            })
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
            const fishermanBalanceBefore = await this.graphToken.balanceOf(fisherman)

            // Perform transaction (ignore)
            const { tx } = await this.disputeManager.ignoreDispute(this.dispute.messageHash, {
              from: arbitrator,
            })

            // Fisherman should see the deposit returned
            const fishermanBalanceAfter = await this.graphToken.balanceOf(fisherman)
            const deposit = web3.utils.toBN(this.tokensForFisherman)
            expect(fishermanBalanceAfter).to.be.bignumber.equal(fishermanBalanceBefore.add(deposit))

            // Event emitted
            expectEvent.inTransaction(tx, this.disputeManager.constructor, 'DisputeIgnored', {
              disputeID: this.dispute.messageHash,
              subgraphID: this.subgraphId,
              indexNode: indexNode,
              fisherman: fisherman,
              deposit: this.tokensForFisherman,
            })
          })
        })
      })
    })
  })
})
