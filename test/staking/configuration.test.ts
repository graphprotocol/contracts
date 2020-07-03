import { expect, use } from 'chai'
import { constants } from 'ethers'
import { solidity } from 'ethereum-waffle'

import { Curation } from '../../build/typechain/contracts/Curation'
import { GraphToken } from '../../build/typechain/contracts/GraphToken'
import { Staking } from '../../build/typechain/contracts/Staking'

import { provider, toBN } from '../lib/testHelpers'
import { loadFixture } from './fixture.test'

use(solidity)

const { AddressZero } = constants

const MAX_PPM = toBN('1000000')

describe('Staking:Config', () => {
  const [me, other, governor, slasher] = provider().getWallets()

  let curation: Curation
  let grt: GraphToken
  let staking: Staking

  beforeEach(async function () {
    ;({ curation, grt, staking } = await loadFixture(governor, slasher))
  })

  it('should set `governor`', async function () {
    // Set right in the constructor
    expect(await staking.governor()).eq(governor.address)
  })

  it('should set `graphToken`', async function () {
    // Set right in the constructor
    expect(await staking.token()).eq(grt.address)
  })

  describe('setSlasher', function () {
    it('should set `slasher`', async function () {
      expect(await staking.slashers(me.address)).eq(false)
      await staking.connect(governor).setSlasher(me.address, true)
      expect(await staking.slashers(me.address)).eq(true)
    })

    it('reject set `slasher` if not allowed', async function () {
      const tx = staking.connect(other).setSlasher(me.address, true)
      await expect(tx).revertedWith('Only Governor can call')
    })
  })

  describe('channelDisputeEpochs', function () {
    it('should set `channelDisputeEpochs`', async function () {
      const newValue = toBN('5')
      await staking.connect(governor).setChannelDisputeEpochs(newValue)
      expect(await staking.channelDisputeEpochs()).eq(newValue)
    })

    it('reject set `channelDisputeEpochs` if not allowed', async function () {
      const newValue = toBN('5')
      const tx = staking.connect(other).setChannelDisputeEpochs(newValue)
      await expect(tx).revertedWith('Only Governor can call')
    })
  })

  describe('curation', function () {
    it('should set `curation`', async function () {
      // Set right in the constructor
      expect(await staking.curation()).eq(curation.address)

      await staking.connect(governor).setCuration(AddressZero)
      expect(await staking.curation()).eq(AddressZero)
    })

    it('reject set `curation` if not allowed', async function () {
      const tx = staking.connect(other).setCuration(AddressZero)
      await expect(tx).revertedWith('Only Governor can call')
    })
  })

  describe('curationPercentage', function () {
    it('should set `curationPercentage`', async function () {
      const newValue = toBN('5')
      await staking.connect(governor).setCurationPercentage(newValue)
      expect(await staking.curationPercentage()).eq(newValue)
    })

    it('reject set `curationPercentage` if out of bounds', async function () {
      const newValue = MAX_PPM.add(toBN('1'))
      const tx = staking.connect(governor).setCurationPercentage(newValue)
      await expect(tx).revertedWith('Curation percentage must be below or equal to MAX_PPM')
    })

    it('reject set `curationPercentage` if not allowed', async function () {
      const tx = staking.connect(other).setCurationPercentage(50)
      await expect(tx).revertedWith('Only Governor can call')
    })
  })

  describe('protocolPercentage', function () {
    it('should set `protocolPercentage`', async function () {
      for (const newValue of [toBN('0'), toBN('5'), MAX_PPM]) {
        await staking.connect(governor).setProtocolPercentage(newValue)
        expect(await staking.protocolPercentage()).eq(newValue)
      }
    })

    it('reject set `protocolPercentage` if out of bounds', async function () {
      const newValue = MAX_PPM.add(toBN('1'))
      const tx = staking.connect(governor).setProtocolPercentage(newValue)
      await expect(tx).revertedWith('Protocol percentage must be below or equal to MAX_PPM')
    })

    it('reject set `protocolPercentage` if not allowed', async function () {
      const tx = staking.connect(other).setProtocolPercentage(50)
      await expect(tx).revertedWith('Only Governor can call')
    })
  })

  describe('maxAllocationEpochs', function () {
    it('should set `maxAllocationEpochs`', async function () {
      const newValue = toBN('5')
      await staking.connect(governor).setMaxAllocationEpochs(newValue)
      expect(await staking.maxAllocationEpochs()).eq(newValue)
    })

    it('reject set `maxAllocationEpochs` if not allowed', async function () {
      const newValue = toBN('5')
      const tx = staking.connect(other).setMaxAllocationEpochs(newValue)
      await expect(tx).revertedWith('Only Governor can call')
    })
  })

  describe('thawingPeriod', function () {
    it('should set `thawingPeriod`', async function () {
      const newValue = toBN('5')
      await staking.connect(governor).setThawingPeriod(newValue)
      expect(await staking.thawingPeriod()).eq(newValue)
    })

    it('reject set `thawingPeriod` if not allowed', async function () {
      const newValue = toBN('5')
      const tx = staking.connect(other).setThawingPeriod(newValue)
      await expect(tx).revertedWith('Only Governor can call')
    })
  })
})
