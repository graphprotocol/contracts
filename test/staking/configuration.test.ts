import { expect, use } from 'chai'
import { constants } from 'ethers'
import { solidity } from 'ethereum-waffle'

import { Curation } from '../../build/typechain/contracts/Curation'
import { EpochManager } from '../../build/typechain/contracts/EpochManager'
import { GraphToken } from '../../build/typechain/contracts/GraphToken'
import { Staking } from '../../build/typechain/contracts/Staking'

import { provider, toBN } from '../lib/testHelpers'
import { loadFixture } from './fixture.test'

use(solidity)

const { AddressZero } = constants

const MAX_PPM = toBN('1000000')

describe('Staking', () => {
  const [me, other, governor, slasher] = provider().getWallets()

  let curation: Curation
  let epochManager: EpochManager
  let grt: GraphToken
  let staking: Staking

  beforeEach(async function() {
    ;({ curation, epochManager, grt, staking } = await loadFixture(governor, slasher))
  })

  describe('configuration', function() {
    it('should set `governor`', async function() {
      // Set right in the constructor
      expect(await staking.governor()).eq(governor.address)
    })

    it('should set `graphToken`', async function() {
      // Set right in the constructor
      expect(await staking.token()).eq(grt.address)
    })

    describe('setSlasher', function() {
      it('should set `slasher`', async function() {
        expect(await staking.slashers(me.address)).eq(false)
        await staking.connect(governor).setSlasher(me.address, true)
        expect(await staking.slashers(me.address)).eq(true)
      })

      it('reject set `slasher` if not allowed', async function() {
        const tx = staking.connect(other).setSlasher(me.address, true)
        await expect(tx).revertedWith('Only Governor can call')
      })
    })

    describe('channelDisputeEpochs', function() {
      it('should set `channelDisputeEpochs`', async function() {
        const newValue = toBN('5')
        await staking.connect(governor).setChannelDisputeEpochs(newValue)
        expect(await staking.channelDisputeEpochs()).eq(newValue)
      })

      it('reject set `channelDisputeEpochs` if not allowed', async function() {
        const newValue = toBN('5')
        const tx = staking.connect(other).setChannelDisputeEpochs(newValue)
        await expect(tx).revertedWith('Only Governor can call')
      })
    })

    describe('curation', function() {
      it('should set `curation`', async function() {
        // Set right in the constructor
        expect(await staking.curation()).eq(curation.address)

        await staking.connect(governor).setCuration(AddressZero)
        expect(await staking.curation()).eq(AddressZero)
      })

      it('reject set `curation` if not allowed', async function() {
        const tx = staking.connect(other).setChannelDisputeEpochs(AddressZero)
        await expect(tx).revertedWith('Only Governor can call')
      })
    })

    describe('curationPercentage', function() {
      it('should set `curationPercentage`', async function() {
        const newValue = toBN('5')
        await staking.connect(governor).setCurationPercentage(newValue)
        expect(await staking.curationPercentage()).eq(newValue)
      })

      it('reject set `curationPercentage` if out of bounds', async function() {
        const newValue = MAX_PPM.add(toBN('1'))
        const tx = staking.connect(governor).setCurationPercentage(newValue)
        await expect(tx).revertedWith('Curation percentage must be below or equal to MAX_PPM')
      })

      it('reject set `curationPercentage` if not allowed', async function() {
        const tx = staking.connect(other).setCurationPercentage(50)
        await expect(tx).revertedWith('Only Governor can call')
      })
    })

    describe('maxAllocationEpochs', function() {
      it('should set `maxAllocationEpochs`', async function() {
        const newValue = toBN('5')
        await staking.connect(governor).setMaxAllocationEpochs(newValue)
        expect(await staking.maxAllocationEpochs()).eq(newValue)
      })

      it('reject set `maxAllocationEpochs` if not allowed', async function() {
        const newValue = toBN('5')
        const tx = staking.connect(other).setMaxAllocationEpochs(newValue)
        await expect(tx).revertedWith('Only Governor can call')
      })
    })

    describe('thawingPeriod', function() {
      it('should set `thawingPeriod`', async function() {
        const newValue = toBN('5')
        await staking.connect(governor).setThawingPeriod(newValue)
        expect(await staking.thawingPeriod()).eq(newValue)
      })

      it('reject set `thawingPeriod` if not allowed', async function() {
        const newValue = toBN('5')
        const tx = staking.connect(other).setThawingPeriod(newValue)
        await expect(tx).revertedWith('Only Governor can call')
      })
    })
  })
})
