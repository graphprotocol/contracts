import hre from 'hardhat'
import { constants } from 'ethers'
import { expect } from 'chai'

import { DisputeManager } from '../../../build/types/DisputeManager'

import { NetworkFixture } from '../lib/fixtures'
import { GraphNetworkContracts, toBN } from '@graphprotocol/sdk'
import { SignerWithAddress } from '@nomiclabs/hardhat-ethers/signers'

const { AddressZero } = constants

const MAX_PPM = 1000000

describe('DisputeManager:Config', () => {
  let me: SignerWithAddress
  let governor: SignerWithAddress
  let slasher: SignerWithAddress
  let arbitrator: SignerWithAddress

  const graph = hre.graph()
  const defaults = graph.graphConfig.defaults
  let fixture: NetworkFixture

  let contracts: GraphNetworkContracts
  let disputeManager: DisputeManager

  before(async function () {
    ;[me, slasher] = await graph.getTestAccounts()
    ;({ governor, arbitrator } = await graph.getNamedAccounts())

    fixture = new NetworkFixture(graph.provider)
    contracts = await fixture.load(governor)
    disputeManager = contracts.DisputeManager as DisputeManager
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
        await disputeManager.connect(governor).setArbitrator(me.address)
        expect(await disputeManager.arbitrator()).eq(me.address)
      })

      it('reject set `arbitrator` if not allowed', async function () {
        const tx = disputeManager.connect(me).setArbitrator(arbitrator.address)
        await expect(tx).revertedWith('Only Controller governor')
      })

      it('reject set `arbitrator` to address zero', async function () {
        const tx = disputeManager.connect(governor).setArbitrator(AddressZero)
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
        await disputeManager.connect(governor).setMinimumDeposit(newValue)
        expect(await disputeManager.minimumDeposit()).eq(newValue)
      })

      it('reject set `minimumDeposit` if not allowed', async function () {
        const newValue = toBN('1')
        const tx = disputeManager.connect(me).setMinimumDeposit(newValue)
        await expect(tx).revertedWith('Only Controller governor')
      })
    })

    describe('fishermanRewardPercentage', function () {
      it('should set `fishermanRewardPercentage`', async function () {
        const newValue = defaults.dispute.fishermanRewardPercentage

        // Set right in the constructor
        expect(await disputeManager.fishermanRewardPercentage()).eq(newValue)

        // Set new value
        await disputeManager.connect(governor).setFishermanRewardPercentage(0)
        await disputeManager.connect(governor).setFishermanRewardPercentage(newValue)
      })

      it('reject set `fishermanRewardPercentage` if out of bounds', async function () {
        const tx = disputeManager.connect(governor).setFishermanRewardPercentage(MAX_PPM + 1)
        await expect(tx).revertedWith('Reward percentage must be below or equal to MAX_PPM')
      })

      it('reject set `fishermanRewardPercentage` if not allowed', async function () {
        const tx = disputeManager.connect(me).setFishermanRewardPercentage(50)
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
        await disputeManager.connect(governor).setSlashingPercentage(0, 0)
        await disputeManager.connect(governor).setSlashingPercentage(qryNewValue, idxNewValue)
      })

      it('reject set `slashingPercentage` if out of bounds', async function () {
        const tx1 = disputeManager.connect(governor).setSlashingPercentage(0, MAX_PPM + 1)
        await expect(tx1).revertedWith('Slashing percentage must be below or equal to MAX_PPM')

        const tx2 = disputeManager.connect(governor).setSlashingPercentage(MAX_PPM + 1, 0)
        await expect(tx2).revertedWith('Slashing percentage must be below or equal to MAX_PPM')
      })

      it('reject set `slashingPercentage` if not allowed', async function () {
        const tx = disputeManager.connect(me).setSlashingPercentage(50, 50)
        await expect(tx).revertedWith('Only Controller governor')
      })
    })
  })
})
