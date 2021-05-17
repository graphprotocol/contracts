import { expect } from 'chai'
import { constants, utils } from 'ethers'

import { Controller } from '../../build/types/Controller'
import { EpochManager } from '../../build/types/EpochManager'

import { getAccounts, Account } from '../lib/testHelpers'
import { NetworkFixture } from '../lib/fixtures'

const { AddressZero } = constants

describe('Managed', () => {
  let me: Account
  let governor: Account
  let mockController: Account
  let newMockEpochManager: Account

  let fixture: NetworkFixture

  let epochManager: EpochManager
  let controller: Controller

  before(async function () {
    ;[me, governor, mockController, newMockEpochManager] = await getAccounts()

    // We just run the fixures to set up a contract with  Managed, as this
    // is cleaner and easier for us to test
    fixture = new NetworkFixture()
    ;({ epochManager, controller } = await fixture.load(governor.signer))
  })

  beforeEach(async function () {
    await fixture.setUp()
  })

  afterEach(async function () {
    await fixture.tearDown()
  })

  describe('setContractProxy()', function () {
    it('should set contract proxy and test get contract proxy', async function () {
      // Set right in the constructor
      expect(await epochManager.controller()).eq(controller.address)

      // Test the controller
      const id = utils.id('EpochManager')
      const tx = controller
        .connect(governor.signer)
        .setContractProxy(id, newMockEpochManager.address)
      await expect(tx)
        .emit(controller, 'SetContractProxy')
        .withArgs(id, newMockEpochManager.address)
      expect(await controller.getContractProxy(id)).eq(newMockEpochManager.address)
    })

    it('reject set contract proxy to address zero', async function () {
      const id = utils.id('EpochManager')
      const tx = controller.connect(governor.signer).setContractProxy(id, AddressZero)
      await expect(tx).revertedWith('Contract address must be set')
    })

    it('reject set contract proxy if not governor', async function () {
      const id = utils.id('EpochManager')
      const tx = controller.connect(me.signer).setContractProxy(id, newMockEpochManager.address)
      await expect(tx).revertedWith('Only Governor can call')
    })
  })

  describe('unsetContractProxy()', function () {
    it('should unset contract proxy', async function () {
      // Set contract
      const id = utils.id('EpochManager')
      await controller.connect(governor.signer).setContractProxy(id, newMockEpochManager.address)
      expect(await controller.getContractProxy(id)).eq(newMockEpochManager.address)

      // Unset contract
      const tx = controller.connect(governor.signer).unsetContractProxy(id)
      await expect(tx).emit(controller, 'SetContractProxy').withArgs(id, AddressZero)
      expect(await controller.getContractProxy(id)).eq(AddressZero)
    })

    it('reject to call if not authorized caller', async function () {
      // Unset contract
      const id = utils.id('EpochManager')
      const tx = controller.connect(me.signer).unsetContractProxy(id)
      await expect(tx).revertedWith('Only Governor can call')
    })
  })

  describe('updateController()', function () {
    it('should update controller on a manager', async function () {
      const tx = controller
        .connect(governor.signer)
        .updateController(utils.id('EpochManager'), mockController.address)
      await expect(tx).emit(epochManager, 'SetController').withArgs(mockController.address)
      expect(await epochManager.controller()).eq(mockController.address)
    })

    it('should fail updating controller when not called by governor', async function () {
      const tx = controller
        .connect(me.signer)
        .updateController(utils.id('EpochManager'), mockController.address)
      await expect(tx).revertedWith('Only Governor can call')
    })

    it('reject update controller to address zero', async function () {
      const tx = controller
        .connect(governor.signer)
        .updateController(utils.id('EpochManager'), AddressZero)
      await expect(tx).revertedWith('Controller must be set')
    })
  })

  describe('setController()', function () {
    it('should fail setting controller when not called from Controller', async function () {
      const tx = epochManager.connect(me.signer).setController(mockController.address)
      await expect(tx).revertedWith('Caller must be Controller')
    })
  })

  describe('setPauseGuardian()', function () {
    it('should set the pause guardian', async function () {
      const tx = controller.connect(governor.signer).setPauseGuardian(me.address)
      await expect(tx).emit(controller, 'NewPauseGuardian').withArgs(AddressZero, me.address)
      expect(await controller.pauseGuardian()).eq(me.address)
    })

    it('reject to call if not authorized caller', async function () {
      const tx = controller.connect(me.signer).setPauseGuardian(me.address)
      await expect(tx).revertedWith('Only Governor can call')
    })

    it('reject set pause guardian to address zero', async function () {
      const tx = controller.connect(governor.signer).setPauseGuardian(AddressZero)
      await expect(tx).revertedWith('PauseGuardian must be set')
    })
  })
})
