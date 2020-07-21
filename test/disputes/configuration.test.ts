import { expect } from 'chai'

import { DisputeManager } from '../../build/typechain/contracts/DisputeManager'
import { GraphToken } from '../../build/typechain/contracts/GraphToken'
import { Staking } from '../../build/typechain/contracts/Staking'

import { defaults } from '../lib/deployment'
import { NetworkFixture } from '../lib/fixtures'
import { getAccounts, toBN, Account } from '../lib/testHelpers'

const MAX_PPM = 1000000

describe('DisputeManager:Config', () => {
  let me: Account
  let governor: Account
  let slasher: Account
  let arbitrator: Account

  let fixture: NetworkFixture

  let disputeManager: DisputeManager
  let grt: GraphToken
  let staking: Staking

  before(async function () {
    ;[me, governor, slasher, arbitrator] = await getAccounts()

    fixture = new NetworkFixture()
    ;({ disputeManager, grt, staking } = await fixture.load(
      governor.signer,
      slasher.signer,
      arbitrator.signer,
    ))
  })

  beforeEach(async function () {
    await fixture.setUp()
  })

  afterEach(async function () {
    await fixture.tearDown()
  })

  describe('configuration', () => {
    it('should set `governor`', async function () {
      // Set right in the constructor
      expect(await disputeManager.governor()).eq(governor.address)
    })

    it('should set `graphToken`', async function () {
      // Set right in the constructor
      expect(await disputeManager.token()).eq(grt.address)
    })

    describe('arbitrator', function () {
      it('should set `arbitrator`', async function () {
        // Set right in the constructor
        expect(await disputeManager.arbitrator()).eq(arbitrator.address)

        // Can set if allowed
        await disputeManager.connect(governor.signer).setArbitrator(me.address)
        expect(await disputeManager.arbitrator()).eq(me.address)
      })

      it('reject set `arbitrator` if not allowed', async function () {
        const tx = disputeManager.connect(me.signer).setArbitrator(arbitrator.address)
        await expect(tx).revertedWith('Only Governor can call')
      })
    })

    describe('minimumDeposit', function () {
      it('should set `minimumDeposit`', async function () {
        const oldValue = defaults.dispute.minimumDeposit
        const newValue = toBN('1')

        // Set right in the constructor
        expect(await disputeManager.minimumDeposit()).eq(oldValue)

        // Set new value
        await disputeManager.connect(governor.signer).setMinimumDeposit(newValue)
        expect(await disputeManager.minimumDeposit()).eq(newValue)
      })

      it('reject set `minimumDeposit` if not allowed', async function () {
        const newValue = toBN('1')
        const tx = disputeManager.connect(me.signer).setMinimumDeposit(newValue)
        await expect(tx).revertedWith('Only Governor can call')
      })
    })

    describe('fishermanRewardPercentage', function () {
      it('should set `fishermanRewardPercentage`', async function () {
        const newValue = defaults.dispute.fishermanRewardPercentage

        // Set right in the constructor
        expect(await disputeManager.fishermanRewardPercentage()).eq(newValue)

        // Set new value
        await disputeManager.connect(governor.signer).setFishermanRewardPercentage(0)
        await disputeManager.connect(governor.signer).setFishermanRewardPercentage(newValue)
      })

      it('reject set `fishermanRewardPercentage` if out of bounds', async function () {
        const tx = disputeManager.connect(governor.signer).setFishermanRewardPercentage(MAX_PPM + 1)
        await expect(tx).revertedWith('Reward percentage must be below or equal to MAX_PPM')
      })

      it('reject set `fishermanRewardPercentage` if not allowed', async function () {
        const tx = disputeManager.connect(me.signer).setFishermanRewardPercentage(50)
        await expect(tx).revertedWith('Only Governor can call')
      })
    })

    describe('slashingPercentage', function () {
      it('should set `slashingPercentage`', async function () {
        const newValue = defaults.dispute.slashingPercentage

        // Set right in the constructor
        expect(await disputeManager.slashingPercentage()).eq(newValue.toString())

        // Set new value
        await disputeManager.connect(governor.signer).setSlashingPercentage(0)
        await disputeManager.connect(governor.signer).setSlashingPercentage(newValue)
      })

      it('reject set `slashingPercentage` if out of bounds', async function () {
        const tx = disputeManager.connect(governor.signer).setSlashingPercentage(MAX_PPM + 1)
        await expect(tx).revertedWith('Slashing percentage must be below or equal to MAX_PPM')
      })

      it('reject set `slashingPercentage` if not allowed', async function () {
        const tx = disputeManager.connect(me.signer).setSlashingPercentage(50)
        await expect(tx).revertedWith('Only Governor can call')
      })
    })

    describe('staking', function () {
      it('should set `staking`', async function () {
        // Set right in the constructor
        expect(await disputeManager.staking()).eq(staking.address)

        // Can set if allowed
        await disputeManager.connect(governor.signer).setStaking(grt.address)
        expect(await disputeManager.staking()).eq(grt.address)
      })

      it('reject set `staking` if not allowed', async function () {
        const tx = disputeManager.connect(me.signer).setStaking(grt.address)
        await expect(tx).revertedWith('Only Governor can call')
      })
    })
  })
})
