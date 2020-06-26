import { expect } from 'chai'

import { Curation } from '../../build/typechain/contracts/Curation'
import { GraphToken } from '../../build/typechain/contracts/GraphToken'

import { defaults, provider, toBN } from '../lib/testHelpers'
import { loadFixture } from './fixture.test'

const MAX_PPM = 1000000

describe('Curation', () => {
  const [me, governor, staking] = provider().getWallets()

  let curation: Curation
  let grt: GraphToken

  beforeEach(async function() {
    ;({ curation, grt } = await loadFixture(governor, staking))
  })

  describe('configuration', function() {
    it('should set `governor`', async function() {
      // Set right in the constructor
      expect(await curation.governor()).eq(governor.address)
    })

    it('should set `graphToken`', async function() {
      // Set right in the constructor
      expect(await curation.token()).eq(grt.address)
    })

    describe('staking', function() {
      it('should set `staking`', async function() {
        // Set right in the constructor
        expect(await curation.staking()).eq(staking.address)

        // Can set if allowed
        await curation.connect(governor).setStaking(me.address)
        expect(await curation.staking()).eq(me.address)
      })

      it('reject set `staking` if not allowed', async function() {
        const tx = curation.connect(me).setStaking(staking.address)
        await expect(tx).revertedWith('Only Governor can call')
      })
    })

    describe('defaultReserveRatio', function() {
      it('should set `defaultReserveRatio`', async function() {
        // Set right in the constructor
        expect(await curation.defaultReserveRatio()).eq(defaults.curation.reserveRatio)

        // Can set if allowed
        const newValue = toBN('100')
        await curation.connect(governor).setDefaultReserveRatio(newValue)
        expect(await curation.defaultReserveRatio()).eq(newValue)
      })

      it('reject set `defaultReserveRatio` if out of bounds', async function() {
        const tx1 = curation.connect(governor).setDefaultReserveRatio(0)
        await expect(tx1).revertedWith('Default reserve ratio must be > 0')

        const tx2 = curation.connect(governor).setDefaultReserveRatio(MAX_PPM + 1)
        await expect(tx2).revertedWith('Default reserve ratio cannot be higher than MAX_PPM')
      })

      it('reject set `defaultReserveRatio` if not allowed', async function() {
        const tx = curation.connect(me).setDefaultReserveRatio(defaults.curation.reserveRatio)
        await expect(tx).revertedWith('Only Governor can call')
      })
    })

    describe('minimumCurationStake', function() {
      it('should set `minimumCurationStake`', async function() {
        // Set right in the constructor
        expect(await curation.minimumCurationStake()).eq(defaults.curation.minimumCurationStake)

        // Can set if allowed
        const newValue = toBN(100)
        await curation.connect(governor).setMinimumCurationStake(newValue)
        expect(await curation.minimumCurationStake()).eq(newValue)
      })

      it('reject set `minimumCurationStake` if out of bounds', async function() {
        const tx = curation.connect(governor).setMinimumCurationStake(0)
        await expect(tx).revertedWith('Minimum curation stake cannot be 0')
      })

      it('reject set `minimumCurationStake` if not allowed', async function() {
        const tx = curation
          .connect(me)
          .setMinimumCurationStake(defaults.curation.minimumCurationStake)
        await expect(tx).revertedWith('Only Governor can call')
      })
    })

    describe('withdrawalFeePercentage', function() {
      it('should set `withdrawalFeePercentage`', async function() {
        const withdrawalFeePercentage = defaults.curation.withdrawalFeePercentage

        // Set new value
        await curation.connect(governor).setWithdrawalFeePercentage(0)
        await curation.connect(governor).setWithdrawalFeePercentage(withdrawalFeePercentage)
      })

      it('reject set `withdrawalFeePercentage` if out of bounds', async function() {
        const tx = curation.connect(governor).setWithdrawalFeePercentage(MAX_PPM + 1)
        await expect(tx).revertedWith('Withdrawal fee percentage must be below or equal to MAX_PPM')
      })

      it('reject set `withdrawalFeePercentage` if not allowed', async function() {
        const tx = curation.connect(me).setWithdrawalFeePercentage(0)
        await expect(tx).revertedWith('Only Governor can call')
      })
    })
  })
})
