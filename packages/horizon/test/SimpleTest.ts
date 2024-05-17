import hardhat from 'hardhat'

import { expect } from 'chai'
import { loadFixture } from '@nomicfoundation/hardhat-toolbox/network-helpers'

const ethers = hardhat.ethers

describe('SimpleTest', function () {
  async function deployFixture() {
    const [owner] = await ethers.getSigners()
    const SimpleTest = await ethers.getContractFactory('SimpleTest')
    const simpleTest = await SimpleTest.deploy()
    return { simpleTest, owner }
  }

  describe('Deployment', function () {
    it('Should return 42', async function () {
      const { simpleTest } = await loadFixture(deployFixture)

      expect(await simpleTest.test()).to.equal(42)
    })
  })
})
