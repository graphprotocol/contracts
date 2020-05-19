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

contract('Disputes', ([me, other, governor, arbitrator, indexer, fisherman, otherIndexer]) => {
  beforeEach(async function() {
    // Private key for account #4
    this.indexerPrivKey = '0xadd53f9a7e588d003326d1cbf9e4a43c061aadd9bc938c843a79e7b4fd2ad743'
    // Private key for account #6
    this.otherIndexerPrivKey = '0xe485d098507f54e7733a205420dfddbe58db035fa577fc294ebd14db90767a52'

    // Deploy epoch contract
    this.epochManager = await deployment.deployEpochManagerContract(governor, { from: me })

    // Deploy graph token
    this.grt = await deployment.deployGRT(governor, {
      from: me,
    })

    // Deploy staking contract
    this.staking = await deployment.deployStakingContract(
      governor,
      this.grt.address,
      this.epochManager.address,
      ZERO_ADDRESS,
      { from: me },
    )

    // Deploy dispute contract
    this.disputeManager = await deployment.deployDisputeManagerContract(
      governor,
      this.grt.address,
      arbitrator,
      this.staking.address,
      { from: me },
    )
  })

  describe('state variables functions', () => {
    it('should set `governor`', async function() {
      // Set right in the constructor
      expect(await this.disputeManager.governor()).to.eq(governor)
    })

    it('should set `graphToken`', async function() {
      // Set right in the constructor
      expect(await this.disputeManager.token()).to.eq(this.grt.address)
    })

    describe('arbitrator', function() {
      it('should set `arbitrator`', async function() {
        // Set right in the constructor
        expect(await this.disputeManager.arbitrator()).to.eq(arbitrator)

        // Can set if allowed
        await this.disputeManager.setArbitrator(other, { from: governor })
        expect(await this.disputeManager.arbitrator()).to.eq(other)
      })

      it('reject set `arbitrator` if not allowed', async function() {
        await expectRevert(
          this.disputeManager.setArbitrator(arbitrator, { from: other }),
          'Only Governor can call',
        )
      })
    })

    describe('minimumDeposit', function() {
      it('should set `minimumDeposit`', async function() {
        const minimumDeposit = defaults.dispute.minimumDeposit
        const newMinimumDeposit = web3.utils.toBN(1)

        // Set right in the constructor
        expect(await this.disputeManager.minimumDeposit()).to.be.bignumber.eq(minimumDeposit)

        // Set new value
        await this.disputeManager.setMinimumDeposit(newMinimumDeposit, {
          from: governor,
        })
        expect(await this.disputeManager.minimumDeposit()).to.be.bignumber.eq(newMinimumDeposit)
      })

      it('reject set `minimumDeposit` if not allowed', async function() {
        await expectRevert(
          this.disputeManager.setMinimumDeposit(defaults.dispute.minimumDeposit, {
            from: other,
          }),
          'Only Governor can call',
        )
      })
    })

    describe('fishermanRewardPercentage', function() {
      it('should set `fishermanRewardPercentage`', async function() {
        const fishermanRewardPercentage = defaults.dispute.fishermanRewardPercentage

        // Set right in the constructor
        expect(await this.disputeManager.fishermanRewardPercentage()).to.be.bignumber.eq(
          fishermanRewardPercentage.toString(),
        )

        // Set new value
        await this.disputeManager.setFishermanRewardPercentage(0, { from: governor })
        await this.disputeManager.setFishermanRewardPercentage(1, { from: governor })
        await this.disputeManager.setFishermanRewardPercentage(fishermanRewardPercentage, {
          from: governor,
        })
      })

      it('reject set `fishermanRewardPercentage` if out of bounds', async function() {
        await expectRevert(
          this.disputeManager.setFishermanRewardPercentage(MAX_PPM + 1, {
            from: governor,
          }),
          'Reward percentage must be below or equal to MAX_PPM',
        )
      })

      it('reject set `fishermanRewardPercentage` if not allowed', async function() {
        await expectRevert(
          this.disputeManager.setFishermanRewardPercentage(50, { from: other }),
          'Only Governor can call',
        )
      })
    })

    describe('slashingPercentage', function() {
      it('should set `slashingPercentage`', async function() {
        const slashingPercentage = defaults.dispute.slashingPercentage

        // Set right in the constructor
        expect(await this.disputeManager.slashingPercentage()).to.be.bignumber.eq(
          slashingPercentage.toString(),
        )

        // Set new value
        await this.disputeManager.setSlashingPercentage(0, { from: governor })
        await this.disputeManager.setSlashingPercentage(1, { from: governor })
        await this.disputeManager.setSlashingPercentage(slashingPercentage, {
          from: governor,
        })
      })

      it('reject set `slashingPercentage` if out of bounds', async function() {
        await expectRevert(
          this.disputeManager.setSlashingPercentage(MAX_PPM + 1, {
            from: governor,
          }),
          'Slashing percentage must be below or equal to MAX_PPM',
        )
      })

      it('reject set `slashingPercentage` if not allowed', async function() {
        await expectRevert(
          this.disputeManager.setSlashingPercentage(50, { from: other }),
          'Only Governor can call',
        )
      })
    })

    describe('staking', function() {
      it('should set `staking`', async function() {
        // Set right in the constructor
        expect(await this.disputeManager.staking()).to.eq(this.staking.address)

        // Can set if allowed
        await this.disputeManager.setStaking(this.grt.address, { from: governor })
        expect(await this.disputeManager.staking()).to.eq(this.grt.address)
      })

      it('reject set `staking` if not allowed', async function() {
        await expectRevert(
          this.disputeManager.setStaking(this.grt.address, {
            from: other,
          }),
          'Only Governor can call',
        )
      })
    })
  })

  describe('dispute lifecycle', function() {
    beforeEach(async function() {
      // Give some funds to the fisherman
      this.fishermanTokens = web3.utils.toWei(new BN('100000'))
      this.fishermanDeposit = web3.utils.toWei(new BN('1000'))
      await this.grt.mint(fisherman, this.fishermanTokens, {
        from: governor,
      })
      await this.grt.approve(this.disputeManager.address, this.fishermanTokens, {
        from: fisherman,
      })

      // Create a dispute
      const receipt = {
        requestCID: web3.utils.randomHex(32),
        responseCID: web3.utils.randomHex(32),
        subgraphID: helpers.randomSubgraphId(),
      }
      this.dispute = await attestation.createDispute(
        receipt,
        this.disputeManager.address,
        this.indexerPrivKey,
      )
    })

    context('> when stake does not exist', function() {
      it('reject create a dispute', async function() {
        // Create dispute
        await expectRevert(
          this.disputeManager.createDispute(this.dispute.attestation, this.fishermanDeposit, {
            from: fisherman,
          }),
          'Dispute has no stake by the indexer',
        )
      })
    })

    context('> when stake does exist', function() {
      beforeEach(async function() {
        // Dispute manager is allowed to slash
        await this.staking.setSlasher(this.disputeManager.address, true, {
          from: governor,
        })

        // Stake
        this.indexerTokens = web3.utils.toWei(new BN('100000'))
        for (const indexerAddress of [indexer, otherIndexer]) {
          // Give some funds to the indexer
          await this.grt.mint(indexerAddress, this.indexerTokens, {
            from: governor,
          })
          await this.grt.approve(this.staking.address, this.indexerTokens, {
            from: indexerAddress,
          })

          // Indexer stake funds
          await this.staking.stake(this.indexerTokens, { from: indexerAddress })
        }
      })

      describe('reward calculation', function() {
        it('should calculate the reward for a stake', async function() {
          const stakedAmount = this.indexerTokens
          const trueReward = stakedAmount
            .mul(defaults.dispute.slashingPercentage)
            .div(new BN(MAX_PPM))
            .mul(defaults.dispute.fishermanRewardPercentage)
            .div(new BN(MAX_PPM))
          const funcReward = await this.disputeManager.getTokensToReward(indexer)
          expect(funcReward).to.be.bignumber.eq(trueReward.toString())
        })
      })

      context('> when dispute is not created', function() {
        describe('create dispute', function() {
          it('reject fisherman deposit below minimum required', async function() {
            // Minimum deposit a fisherman is required to do should be >= reward
            const minimumDeposit = await this.disputeManager.minimumDeposit()
            const belowMinimumDeposit = minimumDeposit.sub(web3.utils.toBN(1))

            // Create invalid dispute as deposit is below minimum
            await expectRevert(
              this.disputeManager.createDispute(this.dispute.attestation, belowMinimumDeposit, {
                from: fisherman,
              }),
              'Dispute deposit under minimum required',
            )
          })

          it('should create a dispute', async function() {
            // Create dispute
            const { logs } = await this.disputeManager.createDispute(
              this.dispute.attestation,
              this.fishermanDeposit,
              { from: fisherman },
            )

            // Event emitted
            expectEvent.inLogs(logs, 'DisputeCreated', {
              disputeID: this.dispute.id,
              subgraphID: this.dispute.receipt.subgraphID,
              indexer: indexer,
              fisherman: fisherman,
              tokens: this.fishermanDeposit,
              attestation: this.dispute.attestation,
            })
          })
        })
      })

      context('> when dispute is created', function() {
        beforeEach(async function() {
          // Create dispute
          await this.disputeManager.createDispute(this.dispute.attestation, this.fishermanDeposit, {
            from: fisherman,
          })
        })

        describe('create a dispute', function() {
          it('should create dispute if receipt is equal but for different indexer', async function() {
            // Create dispute (same receipt but different indexer)
            const newDispute = await attestation.createDispute(
              this.dispute.receipt,
              this.disputeManager.address,
              this.otherIndexerPrivKey,
            )
            const { logs } = await this.disputeManager.createDispute(
              newDispute.attestation,
              this.fishermanDeposit,
              { from: fisherman },
            )

            // Event emitted
            expectEvent.inLogs(logs, 'DisputeCreated', {
              disputeID: newDispute.id,
              subgraphID: newDispute.receipt.subgraphID,
              indexer: otherIndexer,
              fisherman: fisherman,
              tokens: this.fishermanDeposit,
              attestation: newDispute.attestation,
            })
          })

          it('reject create duplicated dispute', async function() {
            await expectRevert(
              this.disputeManager.createDispute(this.dispute.attestation, this.fishermanDeposit, {
                from: fisherman,
              }),
              'Dispute already created',
            )
          })
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
              this.disputeManager.acceptDispute(this.dispute.id, {
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
              this.disputeManager.acceptDispute(this.dispute.id, {
                from: arbitrator,
              }),
              'Caller is not a Slasher',
            )
          })

          it('should resolve dispute, slash indexer and reward the fisherman', async function() {
            const indexerStakeBefore = await this.staking.getIndexerStakeTokens(indexer)
            const tokensToSlash = await this.disputeManager.getTokensToSlash(indexer)
            const fishermanBalanceBefore = await this.grt.balanceOf(fisherman)
            const totalSupplyBefore = await this.grt.totalSupply()
            const reward = await this.disputeManager.getTokensToReward(indexer)

            // Perform transaction (accept)
            const { tx } = await this.disputeManager.acceptDispute(this.dispute.id, {
              from: arbitrator,
            })

            // Fisherman reward properly assigned + deposit returned
            const fishermanBalanceAfter = await this.grt.balanceOf(fisherman)
            expect(fishermanBalanceAfter).to.be.bignumber.eq(
              fishermanBalanceBefore.add(this.fishermanDeposit).add(reward),
            )

            // Indexer slashed
            const indexerStakeAfter = await this.staking.getIndexerStakeTokens(indexer)
            expect(indexerStakeAfter).to.be.bignumber.eq(indexerStakeBefore.sub(tokensToSlash))

            // Slashed funds burned
            const tokensToBurn = tokensToSlash.sub(reward)
            const totalSupplyAfter = await this.grt.totalSupply()
            expect(totalSupplyAfter).to.be.bignumber.eq(totalSupplyBefore.sub(tokensToBurn))

            // Event emitted
            expectEvent.inTransaction(tx, this.disputeManager.constructor, 'DisputeAccepted', {
              disputeID: this.dispute.id,
              subgraphID: this.dispute.receipt.subgraphID,
              indexer: indexer,
              fisherman: fisherman,
              tokens: this.fishermanDeposit.add(reward),
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
              this.disputeManager.rejectDispute(this.dispute.id, {
                from: me,
              }),
              'Caller is not the Arbitrator',
            )
          })

          it('should reject a dispute and burn deposit', async function() {
            const fishermanBalanceBefore = await this.grt.balanceOf(fisherman)
            const totalSupplyBefore = await this.grt.totalSupply()

            // Perform transaction (reject)
            const { tx } = await this.disputeManager.rejectDispute(this.dispute.id, {
              from: arbitrator,
            })

            // No change in fisherman balance
            const fishermanBalanceAfter = await this.grt.balanceOf(fisherman)
            expect(fishermanBalanceAfter).to.be.bignumber.eq(fishermanBalanceBefore)

            // Burn fisherman deposit
            const totalSupplyAfter = await this.grt.totalSupply()
            const burnedTokens = web3.utils.toBN(this.fishermanDeposit)
            expect(totalSupplyAfter).to.be.bignumber.eq(totalSupplyBefore.sub(burnedTokens))

            // Event emitted
            expectEvent.inTransaction(tx, this.disputeManager.constructor, 'DisputeRejected', {
              disputeID: this.dispute.id,
              subgraphID: this.dispute.receipt.subgraphID,
              indexer: indexer,
              fisherman: fisherman,
              tokens: this.fishermanDeposit,
            })
          })
        })

        describe('draw a dispute', async function() {
          it('reject to draw a non-existing dispute', async function() {
            await expectRevert(
              this.disputeManager.drawDispute(NON_EXISTING_DISPUTE_ID, {
                from: arbitrator,
              }),
              'Dispute does not exist',
            )
          })

          it('reject to draw a dispute if not the arbitrator', async function() {
            await expectRevert(
              this.disputeManager.drawDispute(this.dispute.id, {
                from: me,
              }),
              'Caller is not the Arbitrator',
            )
          })

          it('should draw a dispute and return deposit', async function() {
            const fishermanBalanceBefore = await this.grt.balanceOf(fisherman)

            // Perform transaction (draw)
            const { tx } = await this.disputeManager.drawDispute(this.dispute.id, {
              from: arbitrator,
            })

            // Fisherman should see the deposit returned
            const fishermanBalanceAfter = await this.grt.balanceOf(fisherman)
            expect(fishermanBalanceAfter).to.be.bignumber.eq(
              fishermanBalanceBefore.add(this.fishermanDeposit),
            )

            // Event emitted
            expectEvent.inTransaction(tx, this.disputeManager.constructor, 'DisputeDrawn', {
              disputeID: this.dispute.id,
              subgraphID: this.dispute.receipt.subgraphID,
              indexer: indexer,
              fisherman: fisherman,
              tokens: this.fishermanDeposit,
            })
          })
        })
      })
    })
  })
})
