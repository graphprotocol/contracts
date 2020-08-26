import { expect } from 'chai'
import { constants } from 'ethers'

import { Controller } from '../../build/typechain/contracts/Controller'
import { Staking } from '../../build/typechain/contracts/Staking'

import { getAccounts, Account, toGRT } from '../lib/testHelpers'
import { NetworkFixture } from '../lib/fixtures'

describe('Pausing', () => {
  let me: Account
  let governor: Account
  let guardian: Account

  let fixture: NetworkFixture

  let staking: Staking
  let controller: Controller

  const setRecoveryPause = async (account: Account, setValue: boolean) => {
    const tx = controller.connect(account.signer).setRecoveryPaused(setValue)
    await expect(tx).emit(controller, 'RecoveryPauseChanged').withArgs(setValue)
    expect(await controller.recoveryPaused()).eq(setValue)
  }
  const setPause = async (account: Account, setValue: boolean) => {
    const tx = controller.connect(account.signer).setPaused(setValue)
    await expect(tx).emit(controller, 'PauseChanged').withArgs(setValue)
    expect(await controller.paused()).eq(setValue)
  }
  const AddressZero = constants.AddressZero
  before(async function () {
    ;[me, governor, guardian] = await getAccounts()
    fixture = new NetworkFixture()
    ;({ staking, controller } = await fixture.load(governor.signer))
  })

  beforeEach(async function () {
    await fixture.setUp()
  })

  afterEach(async function () {
    await fixture.tearDown()
  })
  it('should set pause guardian', async function () {
    expect(await controller.pauseGuardian()).eq(AddressZero)
    const tx = controller.connect(governor.signer).setPauseGuardian(guardian.address)
    await expect(tx).emit(controller, 'NewPauseGuardian').withArgs(AddressZero, guardian.address)
    expect(await controller.pauseGuardian()).eq(guardian.address)
  })
  it('should fail pause guardian when not governor', async function () {
    const tx = controller.connect(me.signer).setPauseGuardian(guardian.address)
    await expect(tx).revertedWith('Only Governor can call')
  })
  it('should set recoveryPause and unset from governor and guardian', async function () {
    expect(await controller.recoveryPaused()).eq(false)
    // Governor set
    await setRecoveryPause(governor, true)
    // Governor unset
    await setRecoveryPause(governor, false)

    await controller.connect(governor.signer).setPauseGuardian(guardian.address)
    // Guardian set
    await setRecoveryPause(guardian, true)
    // Guardian unset
    await setRecoveryPause(guardian, false)
  })
  it('should fail recovery pause if not guardian or governor', async function () {
    const tx = controller.connect(me.signer).setPauseGuardian(guardian.address)
    await expect(tx).revertedWith('Only Governor can call')
  })
  it('should check that a function fails when recoveryPause is set', async function () {
    await setRecoveryPause(governor, true)

    const tokensToStake = toGRT('100')
    const tx = staking.connect(me.signer).stake(tokensToStake)
    await expect(tx).revertedWith('Recovery-paused')
  })
  it('should set pause and unset from governor and guardian', async function () {
    expect(await controller.paused()).eq(false)
    // Governor set
    await setPause(governor, true)
    // Governor unset
    await setPause(governor, false)

    await controller.connect(governor.signer).setPauseGuardian(guardian.address)
    // Guardian set
    await setPause(guardian, true)
    // Guardian unset
    await setPause(guardian, false)
  })
  it('should fail pause if not guardian or governor', async function () {
    const tx = controller.connect(me.signer).setPaused(true)
    await expect(tx).revertedWith('Only Governor or Guardian can call')
  })
  it('should check that a function fails when pause is set', async function () {
    await setPause(governor, true)

    const tokensToStake = toGRT('100')
    const tx1 = staking.connect(me.signer).stake(tokensToStake)
    await expect(tx1).revertedWith('Paused')

    const tx2 = staking.connect(me.signer).withdraw()
    await expect(tx2).revertedWith('Paused')
  })
})
