import hardhat from 'hardhat'

import { expect } from 'chai'
import { loadFixture } from '@nomicfoundation/hardhat-toolbox/network-helpers'
import { ZeroAddress } from 'ethers'
import { IHorizonStaking } from '../typechain-types'

const ethers = hardhat.ethers

describe('HorizonStaking', function () {
  async function deployFixture() {
    const [owner] = await ethers.getSigners()
    const ControllerMock = await ethers.getContractFactory('ControllerMock')
    const controller = await ControllerMock.deploy(owner.address)
    await controller.waitForDeployment()
    const ExponentialRebates = await ethers.getContractFactory('ExponentialRebates')
    const exponentialRebates = await ExponentialRebates.deploy()
    await exponentialRebates.waitForDeployment()
    const HorizonStakingExtension = await ethers.getContractFactory('HorizonStakingExtension')
    const horizonStakingExtension = await HorizonStakingExtension.deploy(controller.target, ZeroAddress, exponentialRebates.target)
    await horizonStakingExtension.waitForDeployment()
    const HorizonStaking = await ethers.getContractFactory('HorizonStaking')
    const horizonStakingContract = await HorizonStaking.deploy(controller.target, horizonStakingExtension.target, ZeroAddress)
    await horizonStakingContract.waitForDeployment()
    const horizonStaking = (await ethers.getContractAt('IHorizonStaking', horizonStakingContract.target)) as unknown as IHorizonStaking
    return { horizonStaking, owner }
  }

  describe('Verifier allowlist', function () {
    it('adds a verifier to the allowlist', async function () {
      const { horizonStaking, owner } = await loadFixture(deployFixture)
      const verifier = ethers.Wallet.createRandom().address
      await horizonStaking.connect(owner).allowVerifier(verifier)
      expect(await horizonStaking.isAllowedVerifier(owner, verifier)).to.be.true
    })
  })
})
