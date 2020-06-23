import { expect, use } from 'chai'
import { BigNumber } from 'ethers'
import { solidity } from 'ethereum-waffle'

import { EpochManager } from '../build/typechain/contracts/EpochManager'

import * as deployment from './lib/deployment'
import {
  advanceBlock,
  advanceBlockTo,
  defaults,
  latestBlock,
  provider,
  toBN,
} from './lib/testHelpers'

use(solidity)

describe('EpochManager', () => {
  const [me, governor] = provider().getWallets()

  let epochManager: EpochManager

  const epochLength: BigNumber = toBN('3')

  beforeEach(async function () {
    // Deploy epoch manager contract
    epochManager = await deployment.deployEpochManager(governor.address)
  })

  describe('state variables functions', () => {
    it('should set `governor`', async function () {
      // Set right in the constructor
      expect(await epochManager.governor()).to.eq(governor.address)
    })

    it('should set `epochLength', async function () {
      // Set right in the constructor
      expect(await epochManager.epochLength()).to.eq(defaults.epochs.lengthInBlocks)

      // Update and check new value
      const newEpochLength = toBN('4')
      const currentEpoch = await epochManager.currentEpoch()
      const tx = epochManager.connect(governor).setEpochLength(newEpochLength)
      await expect(tx)
        .to.emit(epochManager, 'EpochLengthUpdate')
        .withArgs(currentEpoch, newEpochLength)
      expect(await epochManager.epochLength()).to.eq(newEpochLength)
    })

    it('reject set `epochLength` if zero', async function () {
      // Update and check new value
      const newEpochLength = toBN('0')
      const tx = epochManager.connect(governor).setEpochLength(newEpochLength)
      await expect(tx).to.be.revertedWith('Epoch length cannot be 0')
    })
  })

  describe('epoch lifecycle', function () {
    // Use epochs every three blocks
    // Blocks -> (1,2,3)(4,5,6)(7,8,9)
    // Epochs ->   1    2    3
    beforeEach(async function () {
      await epochManager.connect(governor).setEpochLength(epochLength)
    })

    describe('calculations', () => {
      it('should return correct block number', async function () {
        const currentBlock = await latestBlock()
        expect(await epochManager.blockNum()).to.eq(currentBlock)
      })

      it('should return same starting block if we stay on the same epoch', async function () {
        // Move right to the start of a new epoch
        const blocksSinceEpochStart = await epochManager.currentEpochBlockSinceStart()
        const blocksToNextEpoch = epochLength.sub(blocksSinceEpochStart)
        await advanceBlockTo((await epochManager.blockNum()).add(blocksToNextEpoch))

        const currentEpochBlockBefore = await epochManager.currentEpochBlock()

        // Advance block - will not jump to next epoch
        await advanceBlock()

        const currentEpochBlockAfter = await epochManager.currentEpochBlock()
        expect(currentEpochBlockAfter).to.equal(currentEpochBlockBefore)
      })

      it('should return next starting block if we move to the next epoch', async function () {
        const currentEpochBlockBefore = await epochManager.currentEpochBlock()

        // Advance blocks to move to the next epoch
        await advanceBlockTo(currentEpochBlockBefore.add(epochLength))

        const currentEpochBlockAfter = await epochManager.currentEpochBlock()
        expect(currentEpochBlockAfter).to.not.eq(currentEpochBlockBefore)
      })

      it('should return next epoch if advance > epochLength', async function () {
        const nextEpoch = (await epochManager.currentEpoch()).add(toBN('1'))

        // Advance blocks and move to the next epoch
        const currentEpochBlock = await epochManager.currentEpochBlock()
        await advanceBlockTo(currentEpochBlock.add(epochLength))

        const currentEpochAfter = await epochManager.currentEpoch()
        expect(currentEpochAfter).to.eq(nextEpoch)
      })
    })

    describe('progression', () => {
      beforeEach(async function () {
        const currentEpochBlock = await epochManager.currentEpochBlock()
        await advanceBlockTo(currentEpochBlock.add(epochLength))
      })

      context('> epoch not run', function () {
        it('should return that current epoch is not run', async function () {
          expect(await epochManager.isCurrentEpochRun()).to.be.eq(false)
        })

        it('should run new epoch', async function () {
          // Run epoch
          const currentEpoch = await epochManager.currentEpoch()
          const tx = epochManager.connect(me).runEpoch()
          await expect(tx).to.emit(epochManager, 'EpochRun').withArgs(currentEpoch, me.address)

          // State
          const lastRunEpoch = await epochManager.lastRunEpoch()
          expect(lastRunEpoch).to.eq(currentEpoch)
        })
      })

      context('> epoch run', function () {
        beforeEach(async function () {
          await epochManager.runEpoch()
        })

        it('should return current epoch is already run', async function () {
          expect(await epochManager.isCurrentEpochRun()).to.be.eq(true)
        })

        it('reject run new epoch', async function () {
          const tx = epochManager.runEpoch()
          await expect(tx).to.be.revertedWith('Current epoch already run')
        })
      })
    })
  })
})
