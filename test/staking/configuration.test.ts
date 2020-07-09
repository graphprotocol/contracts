import { expect, use } from 'chai'
import { constants } from 'ethers'
import { solidity } from 'ethereum-waffle'

import { Curation } from '../../build/typechain/contracts/Curation'
import { GraphToken } from '../../build/typechain/contracts/GraphToken'
import { Staking } from '../../build/typechain/contracts/Staking'

import { NetworkFixture } from '../lib/fixtures'
import { getAccounts, toBN, Account } from '../lib/testHelpers'

use(solidity)

const { AddressZero } = constants

const MAX_PPM = toBN('1000000')

describe('Staking:Config', () => {
  let me: Account
  let other: Account
  let governor: Account
  let slasher: Account

  let fixture: NetworkFixture

  let curation: Curation
  let grt: GraphToken
  let staking: Staking

  before(async function () {
    ;[me, other, governor, slasher] = await getAccounts()

    fixture = new NetworkFixture()
    ;({ curation, grt, staking } = await fixture.load(governor.signer, slasher.signer))
  })

  beforeEach(async function () {
    await fixture.setUp()
  })

  afterEach(async function () {
    await fixture.tearDown()
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
      await staking.connect(governor.signer).setSlasher(me.address, true)
      expect(await staking.slashers(me.address)).eq(true)
    })

    it('reject set `slasher` if not allowed', async function () {
      const tx = staking.connect(other.signer).setSlasher(me.address, true)
      await expect(tx).revertedWith('Only Governor can call')
    })
  })

  describe('channelDisputeEpochs', function () {
    it('should set `channelDisputeEpochs`', async function () {
      const newValue = toBN('5')
      await staking.connect(governor.signer).setChannelDisputeEpochs(newValue)
      expect(await staking.channelDisputeEpochs()).eq(newValue)
    })

    it('reject set `channelDisputeEpochs` if not allowed', async function () {
      const newValue = toBN('5')
      const tx = staking.connect(other.signer).setChannelDisputeEpochs(newValue)
      await expect(tx).revertedWith('Only Governor can call')
    })
  })

  describe('curation', function () {
    it('should set `curation`', async function () {
      // Set right in the constructor
      expect(await staking.curation()).eq(curation.address)

      await staking.connect(governor.signer).setCuration(AddressZero)
      expect(await staking.curation()).eq(AddressZero)
    })

    it('reject set `curation` if not allowed', async function () {
      const tx = staking.connect(other.signer).setCuration(AddressZero)
      await expect(tx).revertedWith('Only Governor can call')
    })
  })

  describe('curationPercentage', function () {
    it('should set `curationPercentage`', async function () {
      const newValue = toBN('5')
      await staking.connect(governor.signer).setCurationPercentage(newValue)
      expect(await staking.curationPercentage()).eq(newValue)
    })

    it('reject set `curationPercentage` if out of bounds', async function () {
      const newValue = MAX_PPM.add(toBN('1'))
      const tx = staking.connect(governor.signer).setCurationPercentage(newValue)
      await expect(tx).revertedWith('Curation percentage must be below or equal to MAX_PPM')
    })

    it('reject set `curationPercentage` if not allowed', async function () {
      const tx = staking.connect(other.signer).setCurationPercentage(50)
      await expect(tx).revertedWith('Only Governor can call')
    })
  })

  describe('protocolPercentage', function () {
    it('should set `protocolPercentage`', async function () {
      for (const newValue of [toBN('0'), toBN('5'), MAX_PPM]) {
        await staking.connect(governor.signer).setProtocolPercentage(newValue)
        expect(await staking.protocolPercentage()).eq(newValue)
      }
    })

    it('reject set `protocolPercentage` if out of bounds', async function () {
      const newValue = MAX_PPM.add(toBN('1'))
      const tx = staking.connect(governor.signer).setProtocolPercentage(newValue)
      await expect(tx).revertedWith('Protocol percentage must be below or equal to MAX_PPM')
    })

    it('reject set `protocolPercentage` if not allowed', async function () {
      const tx = staking.connect(other.signer).setProtocolPercentage(50)
      await expect(tx).revertedWith('Only Governor can call')
    })
  })

  describe('maxAllocationEpochs', function () {
    it('should set `maxAllocationEpochs`', async function () {
      const newValue = toBN('5')
      await staking.connect(governor.signer).setMaxAllocationEpochs(newValue)
      expect(await staking.maxAllocationEpochs()).eq(newValue)
    })

    it('reject set `maxAllocationEpochs` if not allowed', async function () {
      const newValue = toBN('5')
      const tx = staking.connect(other.signer).setMaxAllocationEpochs(newValue)
      await expect(tx).revertedWith('Only Governor can call')
    })
  })

  describe('thawingPeriod', function () {
    it('should set `thawingPeriod`', async function () {
      const newValue = toBN('5')
      await staking.connect(governor.signer).setThawingPeriod(newValue)
      expect(await staking.thawingPeriod()).eq(newValue)
    })

    it('reject set `thawingPeriod` if not allowed', async function () {
      const newValue = toBN('5')
      const tx = staking.connect(other.signer).setThawingPeriod(newValue)
      await expect(tx).revertedWith('Only Governor can call')
    })
  })
})
