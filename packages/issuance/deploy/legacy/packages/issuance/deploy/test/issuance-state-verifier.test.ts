import { expect } from 'chai'
import type { Contract } from 'ethers'
import { ethers } from 'hardhat'

describe('IssuanceStateVerifier', function () {
  let verifier: Contract

  beforeEach(async () => {
    const Verifier = await ethers.getContractFactory('IssuanceStateVerifier')
    verifier = await Verifier.deploy()
  })

  it('assertServiceQualityOracleSet passes when RM.sqo == expected', async () => {
    const RM = await ethers.getContractFactory('MockRewardsManager')
    const rm = await RM.deploy()

    const [deployer] = await ethers.getSigners()
    const expected = deployer.address
    await (await rm.setServiceQualityOracle(expected)).wait()

    await expect(verifier.assertServiceQualityOracleSet(await rm.getAddress(), expected)).to.not.be.reverted
  })

  it('assertServiceQualityOracleSet reverts when mismatch', async () => {
    const RM = await ethers.getContractFactory('MockRewardsManager')
    const rm = await RM.deploy()

    const [a, b] = await ethers.getSigners()
    await (await rm.setServiceQualityOracle(a.address)).wait()

    await expect(
      verifier.assertServiceQualityOracleSet(await rm.getAddress(), b.address),
    ).to.be.revertedWithCustomError(verifier, 'ValueMismatch')
  })

  it('assertIssuanceAllocatorSet passes when RM.ia == expected', async () => {
    const RM = await ethers.getContractFactory('MockRewardsManager')
    const rm = await RM.deploy()

    const [deployer] = await ethers.getSigners()
    const expected = deployer.address
    await (await rm.setIssuanceAllocator(expected)).wait()

    await expect(verifier.assertIssuanceAllocatorSet(await rm.getAddress(), expected)).to.not.be
  })

  it('assertIssuanceAllocatorSet reverts when mismatch', async () => {
    const RM = await ethers.getContractFactory('MockRewardsManager')
    const rm = await RM.deploy()

    const [a, b] = await ethers.getSigners()
    await (await rm.setIssuanceAllocator(a.address)).wait()

    await expect(verifier.assertIssuanceAllocatorSet(await rm.getAddress(), b.address)).to.be.revertedWithCustomError(
      verifier,
      'ValueMismatch',
    )
  })

  it('assertMinterRole passes when token has minter', async () => {
    const GT = await ethers.getContractFactory('MockGraphToken')
    const gt = await GT.deploy()

    const [deployer] = await ethers.getSigners()
    await (await gt.setMinter(deployer.address, true)).wait()

    await expect(verifier.assertMinterRole(await gt.getAddress(), deployer.address)).to.not.be.reverted
  })

  it('assertMinterRole reverts when not a minter', async () => {
    const GT = await ethers.getContractFactory('MockGraphToken')
    const gt = await GT.deploy()

    const [a, b] = await ethers.getSigners()
    await (await gt.setMinter(a.address, true)).wait()

    await expect(verifier.assertMinterRole(await gt.getAddress(), b.address)).to.be.revertedWithCustomError(
      verifier,
      'MinterRoleNotGranted',
    )
  })
})
