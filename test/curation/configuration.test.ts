import { expect } from 'chai'
import { constants } from 'ethers'

import { Curation } from '../../build/types/Curation'

import { defaults } from '../lib/deployment'
import { NetworkFixture } from '../lib/fixtures'
import { getAccounts, toBN, Account, randomAddress } from '../lib/testHelpers'

const { AddressZero } = constants

const MAX_PPM = 1000000

describe('Curation:Config', () => {
  let me: Account
  let governor: Account

  let fixture: NetworkFixture

  let curation: Curation

  before(async function () {
    ;[me, governor] = await getAccounts()

    fixture = new NetworkFixture()
    ;({ curation } = await fixture.load(governor.signer))
  })

  beforeEach(async function () {
    await fixture.setUp()
  })

  afterEach(async function () {
    await fixture.tearDown()
  })

  describe('defaultReserveRatio', function () {
    it('should set `defaultReserveRatio`', async function () {
      // Set right in the constructor
      expect(await curation.defaultReserveRatio()).eq(defaults.curation.reserveRatio)

      // Can set if allowed
      const newValue = toBN('100')
      await curation.connect(governor.signer).setDefaultReserveRatio(newValue)
      expect(await curation.defaultReserveRatio()).eq(newValue)
    })

    it('reject set `defaultReserveRatio` if out of bounds', async function () {
      const tx1 = curation.connect(governor.signer).setDefaultReserveRatio(0)
      await expect(tx1).revertedWith('Default reserve ratio must be > 0')

      const tx2 = curation.connect(governor.signer).setDefaultReserveRatio(MAX_PPM + 1)
      await expect(tx2).revertedWith('Default reserve ratio cannot be higher than MAX_PPM')
    })

    it('reject set `defaultReserveRatio` if not allowed', async function () {
      const tx = curation.connect(me.signer).setDefaultReserveRatio(defaults.curation.reserveRatio)
      await expect(tx).revertedWith('Only Controller governor')
    })
  })

  describe('minimumCurationDeposit', function () {
    it('should set `minimumCurationDeposit`', async function () {
      // Set right in the constructor
      expect(await curation.minimumCurationDeposit()).eq(defaults.curation.minimumCurationDeposit)

      // Can set if allowed
      const newValue = toBN('100')
      await curation.connect(governor.signer).setMinimumCurationDeposit(newValue)
      expect(await curation.minimumCurationDeposit()).eq(newValue)
    })

    it('reject set `minimumCurationDeposit` if out of bounds', async function () {
      const tx = curation.connect(governor.signer).setMinimumCurationDeposit(0)
      await expect(tx).revertedWith('Minimum curation deposit cannot be 0')
    })

    it('reject set `minimumCurationDeposit` if not allowed', async function () {
      const tx = curation
        .connect(me.signer)
        .setMinimumCurationDeposit(defaults.curation.minimumCurationDeposit)
      await expect(tx).revertedWith('Only Controller governor')
    })
  })

  describe('curationTaxPercentage', function () {
    it('should set `curationTaxPercentage`', async function () {
      const curationTaxPercentage = defaults.curation.curationTaxPercentage

      // Set new value
      await curation.connect(governor.signer).setCurationTaxPercentage(0)
      await curation.connect(governor.signer).setCurationTaxPercentage(curationTaxPercentage)
    })

    it('reject set `curationTaxPercentage` if out of bounds', async function () {
      const tx = curation.connect(governor.signer).setCurationTaxPercentage(MAX_PPM + 1)
      await expect(tx).revertedWith('Curation tax percentage must be below or equal to MAX_PPM')
    })

    it('reject set `curationTaxPercentage` if not allowed', async function () {
      const tx = curation.connect(me.signer).setCurationTaxPercentage(0)
      await expect(tx).revertedWith('Only Controller governor')
    })
  })

  describe('curationTokenMaster', function () {
    it('should set `curationTokenMaster`', async function () {
      const newCurationTokenMaster = curation.address
      await curation.connect(governor.signer).setCurationTokenMaster(newCurationTokenMaster)
    })

    it('reject set `curationTokenMaster` to empty value', async function () {
      const newCurationTokenMaster = AddressZero
      const tx = curation.connect(governor.signer).setCurationTokenMaster(newCurationTokenMaster)
      await expect(tx).revertedWith('Token master must be non-empty')
    })

    it('reject set `curationTokenMaster` to non-contract', async function () {
      const newCurationTokenMaster = randomAddress()
      const tx = curation.connect(governor.signer).setCurationTokenMaster(newCurationTokenMaster)
      await expect(tx).revertedWith('Token master must be a contract')
    })

    it('reject set `curationTokenMaster` if not allowed', async function () {
      const newCurationTokenMaster = curation.address
      const tx = curation.connect(me.signer).setCurationTokenMaster(newCurationTokenMaster)
      await expect(tx).revertedWith('Only Controller governor')
    })
  })
})
