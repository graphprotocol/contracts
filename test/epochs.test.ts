import { expect } from 'chai'
import { BigNumber } from 'ethers'

import { EpochManager } from '../build/types/EpochManager'

import * as deployment from './lib/deployment'
import { defaults } from './lib/deployment'
import {
  advanceBlock,
  advanceBlockTo,
  latestBlock,
  getAccounts,
  toBN,
  Account,
  initNetwork,
} from './lib/testHelpers'

describe('EpochManager', () => {
  let me: Account
  let governor: Account

  let epochManager: EpochManager

  const epochLength: BigNumber = toBN('3')

  before(async function () {
    await initNetwork()
    ;[me, governor] = await getAccounts()
  })

  beforeEach(async function () {
    const controller = await deployment.deployController(governor.signer)
    const proxyAdmin = await deployment.deployProxyAdmin(governor.signer)
    epochManager = await deployment.deployEpochManager(
      governor.signer,
      controller.address,
      proxyAdmin,
    )
  })

  describe('configuration', () => {
    it('should set `epochLength', async function () {
      // Set right in the constructor
      expect(await epochManager.epochLength()).eq(defaults.epochs.lengthInBlocks)

      // Update and check new value
      const newEpochLength = toBN('4')
      const currentEpoch = await epochManager.currentEpoch()
      const tx = epochManager.connect(governor.signer).setEpochLength(newEpochLength)
      await expect(tx)
        .emit(epochManager, 'EpochLengthUpdate')
        .withArgs(currentEpoch, newEpochLength)
      expect(await epochManager.epochLength()).eq(newEpochLength)
    })

    it('reject set `epochLength` if zero', async function () {
      // Update and check new value
      const newEpochLength = toBN('0')
      const tx = epochManager.connect(governor.signer).setEpochLength(newEpochLength)
      await expect(tx).revertedWith('Epoch length cannot be 0')
    })
  })

  describe('epoch lifecycle', function () {
    // Use epochs every three blocks
    // Blocks -> (1,2,3)(4,5,6)(7,8,9)
    // Epochs ->   1    2    3
    beforeEach(async function () {
      await epochManager.connect(governor.signer).setEpochLength(epochLength)
    })

    describe('calculations', () => {
      it('first epoch should be 1', async function () {
        const currentEpoch = await epochManager.currentEpoch()
        expect(currentEpoch).eq(1)
      })

      it('should return correct block number', async function () {
        const currentBlock = await latestBlock()
        expect(await epochManager.blockNum()).eq(currentBlock)
      })

      it('should return same starting block if we stay on the same epoch', async function () {
        // Move right to the start of a new epoch
        const blocksSinceEpochStart = await epochManager.currentEpochBlockSinceStart()
        const blocksToNextEpoch = epochLength.sub(blocksSinceEpochStart)
        await advanceBlockTo((await epochManager.blockNum()).add(blocksToNextEpoch))

        const beforeCurrentEpochBlock = await epochManager.currentEpochBlock()

        // Advance block - will not jump to next epoch
        await advanceBlock()

        const afterCurrentEpochBlock = await epochManager.currentEpochBlock()
        expect(afterCurrentEpochBlock).equal(beforeCurrentEpochBlock)
      })

      it('should return next starting block if we move to the next epoch', async function () {
        const beforeCurrentEpochBlock = await epochManager.currentEpochBlock()

        // Advance blocks to move to the next epoch
        await advanceBlockTo(beforeCurrentEpochBlock.add(epochLength))

        const afterCurrentEpochBlock = await epochManager.currentEpochBlock()
        expect(afterCurrentEpochBlock).not.eq(beforeCurrentEpochBlock)
      })

      it('should return next epoch if advance > epochLength', async function () {
        const nextEpoch = (await epochManager.currentEpoch()).add(toBN('1'))

        // Advance blocks and move to the next epoch
        const currentEpochBlock = await epochManager.currentEpochBlock()
        await advanceBlockTo(currentEpochBlock.add(epochLength))

        const afterCurrentEpoch = await epochManager.currentEpoch()
        expect(afterCurrentEpoch).eq(nextEpoch)
      })
    })

    describe('progression', () => {
      beforeEach(async function () {
        const currentEpochBlock = await epochManager.currentEpochBlock()
        await advanceBlockTo(currentEpochBlock.add(epochLength))
      })

      context('> epoch not run', function () {
        it('should return that current epoch is not run', async function () {
          expect(await epochManager.isCurrentEpochRun()).eq(false)
        })

        it('should run new epoch', async function () {
          // Run epoch
          const currentEpoch = await epochManager.currentEpoch()
          const tx = epochManager.connect(me.signer).runEpoch()
          await expect(tx).emit(epochManager, 'EpochRun').withArgs(currentEpoch, me.address)

          // State
          const lastRunEpoch = await epochManager.lastRunEpoch()
          expect(lastRunEpoch).eq(currentEpoch)
        })
      })

      context('> epoch run', function () {
        beforeEach(async function () {
          await epochManager.runEpoch()
        })

        it('should return current epoch is already run', async function () {
          expect(await epochManager.isCurrentEpochRun()).eq(true)
        })

        it('reject run new epoch', async function () {
          const tx = epochManager.runEpoch()
          await expect(tx).revertedWith('Current epoch already run')
        })
      })
    })
  })
})
