import { expect } from 'chai'
import { utils } from 'ethers'

import { Controller } from '../../build/typechain/contracts/Controller'
import { EpochManager } from '../../build/typechain/contracts/EpochManager'

import { getAccounts, Account } from '../lib/testHelpers'
import { NetworkFixture } from '../lib/fixtures'

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
  it('should set contract proxy and test get contract proxy', async function () {
    // Set right in the constructor
    expect(await epochManager.controller()).eq(controller.address)

    // Test the controller
    const id = utils.id('EpochManager')
    const tx = controller.connect(governor.signer).setContractProxy(id, newMockEpochManager.address)
    await expect(tx).emit(controller, 'SetContractProxy').withArgs(id, newMockEpochManager.address)
    expect(await controller.getContractProxy(id)).eq(newMockEpochManager.address)
  })
  it('should fail to set contract proxy if not governor', async function () {
    // Test the controller
    const id = utils.id('EpochManager')
    const tx = controller.connect(me.signer).setContractProxy(id, newMockEpochManager.address)
    await expect(tx).revertedWith('Only Governor can call')
  })
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
  it('should fail setting controller when not called from Controller', async function () {
    const tx = epochManager.connect(me.signer).setController(mockController.address)
    await expect(tx).revertedWith('Caller must be Controller')
  })
})
