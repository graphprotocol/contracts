const { expect } = require('chai')
const {
  expectEvent,
  expectRevert,
  time,
} = require('@openzeppelin/test-helpers')
const BN = web3.utils.BN

// helpers
const deployment = require('./lib/deployment')
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
      await this.epochManager.transferOwnership(other, { from: governor })
      expect(await this.epochManager.governor()).to.equal(other)
    })

    it('should set `epochLength', async function() {
      // Set right in the constructor
      expect(await this.epochManager.epochLength()).to.be.bignumber.equal(
        defaults.epochs.lengthInBlocks,
      )

      // Update and check new value
      const newEpochLength = new BN(4)
      const currentEpoch = await this.epochManager.currentEpoch()
      const { logs } = await this.epochManager.setEpochLength(newEpochLength, {
        from: governor,
      })
      expect(await this.epochManager.epochLength()).to.be.bignumber.equal(
        newEpochLength,
      )

      // Event emitted
      expectEvent.inLogs(logs, 'EpochLengthUpdate', {
        epoch: currentEpoch,
        epochLength: newEpochLength,
      })
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

  describe('epoch lifecycle', function() {
    // Use epochs every three blocks
    // Blocks -> (1,2,3)(4,5,6)(7,8,9)
    // Epochs ->   1    2    3
    beforeEach(async function() {
      this.epochLength = new BN(3)
      await this.epochManager.setEpochLength(this.epochLength, {
        from: governor,
      })
    })

    describe('calculations', () => {
      it('should return correct block number', async function() {
        const currentBlock = await time.latestBlock()
        expect(await this.epochManager.blockNum()).to.be.bignumber.equal(
          currentBlock,
        )
      })

      it('should return same starting block if we stay on the same epoch', async function() {
        const currentEpochBlockBefore = await this.epochManager.currentEpochBlock()

        // Advance blocks to stay on the same epoch
        await time.advanceBlock()

        const currentEpochBlockAfter = await this.epochManager.currentEpochBlock()
        expect(currentEpochBlockAfter).to.be.bignumber.equal(
          currentEpochBlockBefore,
        )
      })

      it('should return next starting block if we move to the next epoch', async function() {
        const currentEpochBlockBefore = await this.epochManager.currentEpochBlock()

        // Advance blocks to move to the next epoch
        await time.advanceBlockTo(currentEpochBlockBefore.add(this.epochLength))

        const currentEpochBlockAfter = await this.epochManager.currentEpochBlock()
        expect(currentEpochBlockAfter).to.be.bignumber.not.equal(
          currentEpochBlockBefore,
        )
      })

      it('should return next epoch if advance > epochLength', async function() {
        const nextEpoch = (await this.epochManager.currentEpoch()).add(
          new BN(1),
        )

        // Advance blocks and move to the next epoch
        const currentEpochBlock = await this.epochManager.currentEpochBlock()
        await time.advanceBlockTo(currentEpochBlock.add(this.epochLength))

        const currentEpochAfter = await this.epochManager.currentEpoch()
        expect(currentEpochAfter).to.be.bignumber.equal(nextEpoch)
      })
    })

    describe('progression', () => {
      beforeEach(async function() {
        const currentEpochBlock = await this.epochManager.currentEpochBlock()
        await time.advanceBlockTo(currentEpochBlock.add(this.epochLength))
      })

      context('epoch not run', function() {
        it('should return that current epoch is not run', async function() {
          expect(await this.epochManager.isCurrentEpochRun(), false)
        })

        it('should run new epoch', async function() {
          // Run epoch
          const currentEpoch = await this.epochManager.currentEpoch()
          const { logs } = await this.epochManager.runEpoch({ from: me })
          const currentBlock = await time.latestBlock()

          // State
          const lastRunEpoch = await this.epochManager.lastRunEpoch()
          expect(lastRunEpoch).to.be.bignumber.equal(currentEpoch)

          // Event emitted
          expectEvent.inLogs(logs, 'NewEpoch', {
            epoch: currentEpoch,
            blockNumber: currentBlock,
            caller: me,
          })
        })
      })

      context('epoch run', function() {
        beforeEach(async function() {
          await this.epochManager.runEpoch()
        })

        it('should return current epoch is already run', async function() {
          expect(await this.epochManager.isCurrentEpochRun(), true)
        })

        it('reject run new epoch', async function() {
          await expectRevert(
            this.epochManager.runEpoch(),
            'Current epoch already run',
          )
        })
      })
    })
  })
})
