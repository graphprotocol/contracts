import hre from 'hardhat'
import { expect } from 'chai'
import { constants } from 'ethers'

import { NetworkFixture } from '../lib/fixtures'
import { GraphNetworkContracts, randomAddress, toBN } from '@graphprotocol/sdk'

import type { SignerWithAddress } from '@nomiclabs/hardhat-ethers/signers'

const { AddressZero } = constants

const MAX_PPM = 1000000

describe('Curation:Config', () => {
  let me: SignerWithAddress
  let governor: SignerWithAddress

  let fixture: NetworkFixture

  let contracts: GraphNetworkContracts

  const graph = hre.graph()
  const defaults = graph.graphConfig.defaults

  before(async function () {
    [me] = await graph.getTestAccounts()
    ;({ governor } = await graph.getNamedAccounts())
    fixture = new NetworkFixture(graph.provider)
    contracts = await fixture.load(governor)
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
      expect(await contracts.Curation.defaultReserveRatio()).eq(defaults.curation.reserveRatio)

      // Can set if allowed
      const newValue = toBN('100')
      await contracts.Curation.connect(governor).setDefaultReserveRatio(newValue)
      expect(await contracts.Curation.defaultReserveRatio()).eq(newValue)
    })

    it('reject set `defaultReserveRatio` if out of bounds', async function () {
      const tx1 = contracts.Curation.connect(governor).setDefaultReserveRatio(0)
      await expect(tx1).revertedWith('Default reserve ratio must be > 0')

      const tx2 = contracts.Curation.connect(governor).setDefaultReserveRatio(MAX_PPM + 1)
      await expect(tx2).revertedWith('Default reserve ratio cannot be higher than MAX_PPM')
    })

    it('reject set `defaultReserveRatio` if not allowed', async function () {
      const tx = contracts.Curation.connect(me).setDefaultReserveRatio(
        defaults.curation.reserveRatio,
      )
      await expect(tx).revertedWith('Only Controller governor')
    })
  })

  describe('minimumCurationDeposit', function () {
    it('should set `minimumCurationDeposit`', async function () {
      // Set right in the constructor
      expect(await contracts.Curation.minimumCurationDeposit()).eq(
        defaults.curation.minimumCurationDeposit,
      )

      // Can set if allowed
      const newValue = toBN('100')
      await contracts.Curation.connect(governor).setMinimumCurationDeposit(newValue)
      expect(await contracts.Curation.minimumCurationDeposit()).eq(newValue)
    })

    it('reject set `minimumCurationDeposit` if out of bounds', async function () {
      const tx = contracts.Curation.connect(governor).setMinimumCurationDeposit(0)
      await expect(tx).revertedWith('Minimum curation deposit cannot be 0')
    })

    it('reject set `minimumCurationDeposit` if not allowed', async function () {
      const tx = contracts.Curation.connect(me).setMinimumCurationDeposit(
        defaults.curation.minimumCurationDeposit,
      )
      await expect(tx).revertedWith('Only Controller governor')
    })
  })

  describe('curationTaxPercentage', function () {
    it('should set `curationTaxPercentage`', async function () {
      const curationTaxPercentage = defaults.curation.curationTaxPercentage

      // Set new value
      await contracts.Curation.connect(governor).setCurationTaxPercentage(0)
      await contracts.Curation.connect(governor).setCurationTaxPercentage(curationTaxPercentage)
    })

    it('reject set `curationTaxPercentage` if out of bounds', async function () {
      const tx = contracts.Curation.connect(governor).setCurationTaxPercentage(MAX_PPM + 1)
      await expect(tx).revertedWith('Curation tax percentage must be below or equal to MAX_PPM')
    })

    it('reject set `curationTaxPercentage` if not allowed', async function () {
      const tx = contracts.Curation.connect(me).setCurationTaxPercentage(0)
      await expect(tx).revertedWith('Only Controller governor')
    })
  })

  describe('curationTokenMaster', function () {
    it('should set `curationTokenMaster`', async function () {
      const newCurationTokenMaster = contracts.Curation.address
      await contracts.Curation.connect(governor).setCurationTokenMaster(newCurationTokenMaster)
    })

    it('reject set `curationTokenMaster` to empty value', async function () {
      const newCurationTokenMaster = AddressZero
      const tx = contracts.Curation.connect(governor).setCurationTokenMaster(newCurationTokenMaster)
      await expect(tx).revertedWith('Token master must be non-empty')
    })

    it('reject set `curationTokenMaster` to non-contract', async function () {
      const newCurationTokenMaster = randomAddress()
      const tx = contracts.Curation.connect(governor).setCurationTokenMaster(newCurationTokenMaster)
      await expect(tx).revertedWith('Token master must be a contract')
    })

    it('reject set `curationTokenMaster` if not allowed', async function () {
      const newCurationTokenMaster = contracts.Curation.address
      const tx = contracts.Curation.connect(me).setCurationTokenMaster(newCurationTokenMaster)
      await expect(tx).revertedWith('Only Controller governor')
    })
  })
})
