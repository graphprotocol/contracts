import { expect, use } from 'chai'
import { solidity } from 'ethereum-waffle'

import { Curation } from '../../build/typechain/contracts/Curation'
import { GraphToken } from '../../build/typechain/contracts/GraphToken'
import { Staking } from '../../build/typechain/contracts/Staking'

import { NetworkFixture } from '../lib/fixtures'
import { defaults, getAccounts, toBN, Account } from '../lib/testHelpers'

use(solidity)

const MAX_PPM = 1000000

describe('Curation:Config', () => {
  let me: Account
  let governor: Account

  let fixture: NetworkFixture

  let curation: Curation
  let grt: GraphToken
  let staking: Staking

  before(async function () {
    ;[me, governor] = await getAccounts()

    fixture = new NetworkFixture()
    ;({ curation, grt, staking } = await fixture.load(governor.signer))
  })

  beforeEach(async function () {
    await fixture.setUp()
  })

  afterEach(async function () {
    await fixture.tearDown()
  })

  it('should set `governor`', async function () {
    // Set right in the constructor
    expect(await curation.governor()).eq(governor.address)
  })

  it('should set `graphToken`', async function () {
    // Set right in the constructor
    expect(await curation.token()).eq(grt.address)
  })

  describe('staking', function () {
    it('should set `staking`', async function () {
      // Set right in the constructor
      expect(await curation.staking()).eq(staking.address)

      // Can set if allowed
      await curation.connect(governor.signer).setStaking(me.address)
      expect(await curation.staking()).eq(me.address)
    })

    it('reject set `staking` if not allowed', async function () {
      const tx = curation.connect(me.signer).setStaking(staking.address)
      await expect(tx).revertedWith('Only Governor can call')
    })
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
      await expect(tx).revertedWith('Only Governor can call')
    })
  })

  describe('minimumCurationStake', function () {
    it('should set `minimumCurationStake`', async function () {
      // Set right in the constructor
      expect(await curation.minimumCurationStake()).eq(defaults.curation.minimumCurationStake)

      // Can set if allowed
      const newValue = toBN('100')
      await curation.connect(governor.signer).setMinimumCurationStake(newValue)
      expect(await curation.minimumCurationStake()).eq(newValue)
    })

    it('reject set `minimumCurationStake` if out of bounds', async function () {
      const tx = curation.connect(governor.signer).setMinimumCurationStake(0)
      await expect(tx).revertedWith('Minimum curation stake cannot be 0')
    })

    it('reject set `minimumCurationStake` if not allowed', async function () {
      const tx = curation
        .connect(me.signer)
        .setMinimumCurationStake(defaults.curation.minimumCurationStake)
      await expect(tx).revertedWith('Only Governor can call')
    })
  })

  describe('withdrawalFeePercentage', function () {
    it('should set `withdrawalFeePercentage`', async function () {
      const withdrawalFeePercentage = defaults.curation.withdrawalFeePercentage

      // Set new value
      await curation.connect(governor.signer).setWithdrawalFeePercentage(0)
      await curation.connect(governor.signer).setWithdrawalFeePercentage(withdrawalFeePercentage)
    })

    it('reject set `withdrawalFeePercentage` if out of bounds', async function () {
      const tx = curation.connect(governor.signer).setWithdrawalFeePercentage(MAX_PPM + 1)
      await expect(tx).revertedWith('Withdrawal fee percentage must be below or equal to MAX_PPM')
    })

    it('reject set `withdrawalFeePercentage` if not allowed', async function () {
      const tx = curation.connect(me.signer).setWithdrawalFeePercentage(0)
      await expect(tx).revertedWith('Only Governor can call')
    })
  })
})
