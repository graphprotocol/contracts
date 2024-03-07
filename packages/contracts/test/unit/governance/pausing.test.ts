import hre from 'hardhat'
import { expect } from 'chai'

import { Controller } from '../../../build/types/Controller'
import { IStaking } from '../../../build/types/IStaking'

import { NetworkFixture } from '../lib/fixtures'
import { GraphNetworkContracts, toGRT } from '@graphprotocol/sdk'
import { SignerWithAddress } from '@nomiclabs/hardhat-ethers/signers'

describe('Pausing', () => {
  const graph = hre.graph()
  let me: SignerWithAddress
  let governor: SignerWithAddress
  let guardian: SignerWithAddress

  let fixture: NetworkFixture

  let contracts: GraphNetworkContracts
  let staking: IStaking
  let controller: Controller

  const setPartialPause = async (account: SignerWithAddress, setValue: boolean) => {
    const tx = controller.connect(account).setPartialPaused(setValue)
    await expect(tx).emit(controller, 'PartialPauseChanged').withArgs(setValue)
    expect(await controller.partialPaused()).eq(setValue)
  }
  const setPause = async (account: SignerWithAddress, setValue: boolean) => {
    const tx = controller.connect(account).setPaused(setValue)
    await expect(tx).emit(controller, 'PauseChanged').withArgs(setValue)
    expect(await controller.paused()).eq(setValue)
  }
  before(async function () {
    [me] = await graph.getTestAccounts()
    ;({ governor, pauseGuardian: guardian } = await graph.getNamedAccounts())
    fixture = new NetworkFixture(graph.provider)
    contracts = await fixture.load(governor)
    staking = contracts.Staking as IStaking
    controller = contracts.Controller
  })

  beforeEach(async function () {
    await fixture.setUp()
  })

  afterEach(async function () {
    await fixture.tearDown()
  })
  it('should set pause guardian', async function () {
    const currentGuardian = await controller.pauseGuardian()
    expect(await controller.pauseGuardian()).eq(currentGuardian)
    const tx = controller.connect(governor).setPauseGuardian(guardian.address)
    await expect(tx)
      .emit(controller, 'NewPauseGuardian')
      .withArgs(currentGuardian, guardian.address)
    expect(await controller.pauseGuardian()).eq(guardian.address)
  })
  it('should fail pause guardian when not governor', async function () {
    const tx = controller.connect(me).setPauseGuardian(guardian.address)
    await expect(tx).revertedWith('Only Governor can call')
  })
  it('should set partialPaused and unset from governor and guardian', async function () {
    expect(await controller.partialPaused()).eq(false)
    // Governor set
    await setPartialPause(governor, true)
    // Governor unset
    await setPartialPause(governor, false)

    await controller.connect(governor).setPauseGuardian(guardian.address)
    // Guardian set
    await setPartialPause(guardian, true)
    // Guardian unset
    await setPartialPause(guardian, false)
  })
  it('should fail partial pause if not guardian or governor', async function () {
    const tx = controller.connect(me).setPartialPaused(true)
    await expect(tx).revertedWith('Only Governor or Guardian can call')
  })
  it('should check that a function fails when partialPause is set', async function () {
    await setPartialPause(governor, true)

    const tokensToStake = toGRT('100')
    const tx = staking.connect(me).stake(tokensToStake)
    await expect(tx).revertedWith('Partial-paused')
  })
  it('should set pause and unset from governor and guardian', async function () {
    expect(await controller.paused()).eq(false)
    // Governor set
    await setPause(governor, true)
    // Governor unset
    await setPause(governor, false)

    await controller.connect(governor).setPauseGuardian(guardian.address)
    // Guardian set
    await setPause(guardian, true)
    // Guardian unset
    await setPause(guardian, false)
  })
  it('should fail pause if not guardian or governor', async function () {
    const tx = controller.connect(me).setPaused(true)
    await expect(tx).revertedWith('Only Governor or Guardian can call')
  })
  it('should check that a function fails when pause is set', async function () {
    await setPause(governor, true)

    const tokensToStake = toGRT('100')
    const tx1 = staking.connect(me).stake(tokensToStake)
    await expect(tx1).revertedWith('Paused')

    const tx2 = staking.connect(me).withdraw()
    await expect(tx2).revertedWith('Paused')
  })
})
