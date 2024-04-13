import hardhat from 'hardhat'

import { expect } from 'chai'
import { loadFixture } from '@nomicfoundation/hardhat-toolbox/network-helpers'
import { ZeroAddress } from 'ethers'

const ethers = hardhat.ethers

describe('HorizonStaking', function () {
  async function deployFixture() {
    const [owner] = await ethers.getSigners()
    const ControllerMock = await ethers.getContractFactory('ControllerMock')
    const controller = await ControllerMock.deploy(owner.address)
    await controller.waitForDeployment()
    const HorizonStaking = await ethers.getContractFactory('HorizonStaking')
    const horizonStaking = await HorizonStaking.deploy(ZeroAddress, controller.target)
    await horizonStaking.waitForDeployment()
    return { horizonStaking, owner }
  }

  describe('Deployment', function () {
    it('Should have a constant max verifier cut', async function () {
      const { horizonStaking } = await loadFixture(deployFixture)

      expect(await horizonStaking.MAX_MAX_VERIFIER_CUT()).to.equal(500000)
    })
  })
})
