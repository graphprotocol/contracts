import { constants } from 'ethers'
import { expect } from 'chai'

import { DisputeManager } from '../../build/types/DisputeManager'

import { defaults } from '../lib/deployment'
import { NetworkFixture } from '../lib/fixtures'
import { getAccounts, toBN, Account } from '../lib/testHelpers'

const { AddressZero } = constants

const MAX_PPM = 1000000

describe('DisputeManager:Config', () => {
  let me: Account
  let governor: Account
  let slasher: Account
  let arbitrator: Account

  let fixture: NetworkFixture

  let disputeManager: DisputeManager

  before(async function () {
    ;[me, governor, slasher, arbitrator] = await getAccounts()

    fixture = new NetworkFixture()
    ;({ disputeManager } = await fixture.load(governor.signer, slasher.signer, arbitrator.signer))
  })

  beforeEach(async function () {
    await fixture.setUp()
  })

  afterEach(async function () {
    await fixture.tearDown()
  })

  describe('configuration', () => {
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
        await expect(tx).revertedWith('Only Controller governor')
      })

      it('reject set `arbitrator` to address zero', async function () {
        const tx = disputeManager.connect(governor.signer).setArbitrator(AddressZero)
        await expect(tx).revertedWith('Arbitrator must be set')
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
        await expect(tx).revertedWith('Only Controller governor')
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
        await expect(tx).revertedWith('Only Controller governor')
      })
    })

    describe('slashingPercentage', function () {
      it('should set `slashingPercentage`', async function () {
        const qryNewValue = defaults.dispute.qrySlashingPercentage
        const idxNewValue = defaults.dispute.idxSlashingPercentage

        // Set right in the constructor
        expect(await disputeManager.qrySlashingPercentage()).eq(qryNewValue)
        expect(await disputeManager.idxSlashingPercentage()).eq(idxNewValue)

        // Set new value
        await disputeManager.connect(governor.signer).setSlashingPercentage(0, 0)
        await disputeManager
          .connect(governor.signer)
          .setSlashingPercentage(qryNewValue, idxNewValue)
      })

      it('reject set `slashingPercentage` if out of bounds', async function () {
        const tx1 = disputeManager.connect(governor.signer).setSlashingPercentage(0, MAX_PPM + 1)
        await expect(tx1).revertedWith('Slashing percentage must be below or equal to MAX_PPM')

        const tx2 = disputeManager.connect(governor.signer).setSlashingPercentage(MAX_PPM + 1, 0)
        await expect(tx2).revertedWith('Slashing percentage must be below or equal to MAX_PPM')
      })

      it('reject set `slashingPercentage` if not allowed', async function () {
        const tx = disputeManager.connect(me.signer).setSlashingPercentage(50, 50)
        await expect(tx).revertedWith('Only Controller governor')
      })
    })
  })
})
