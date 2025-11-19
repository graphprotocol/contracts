import { expect } from 'chai'
import { ethers, ignition } from 'hardhat'

import ServiceQualityOracleModule from '../ignition/modules/contracts/ServiceQualityOracle'

describe('ServiceQualityOracle Deployment', function () {
  it('deploys proxy and implementation; initializes roles and defaults', async () => {
    const [deployer, governor] = await ethers.getSigners()

    const mockGraphTokenAddress = deployer.address

    const { serviceQualityOracle, implementation } = await ignition.deploy(ServiceQualityOracleModule, {
      parameters: {
        GraphProxyAdmin2: {
          owner: governor.address,
        },
        ServiceQualityOracle: {
          owner: governor.address,
          graphToken: mockGraphTokenAddress,
        },
      },
    })

    expect(serviceQualityOracle.target).to.be.properAddress
    expect(implementation.target).to.be.properAddress

    const SQO = await ethers.getContractFactory('ServiceQualityOracle')
    const sqo = SQO.attach(serviceQualityOracle.target)

    // Governor role granted
    const governorRole = await sqo.GOVERNOR_ROLE()
    expect(await sqo.hasRole(governorRole, governor.address)).to.be.true

    // Default params
    // checkingActive defaults to false -> isAllowed ignores and returns true
    expect(await sqo.isAllowed(ethers.ZeroAddress)).to.equal(true)

    // Setters callable by OPERATOR only
    const operatorRole = await sqo.OPERATOR_ROLE()
    await expect(sqo.connect(deployer).setQualityChecking(true)).to.be.revertedWithCustomError(
      sqo,
      'AccessControlUnauthorizedAccount',
    )
    await expect(sqo.connect(deployer).setAllowedPeriod(123)).to.be.reverted
    await expect(sqo.connect(deployer).setOracleUpdateTimeout(456)).to.be.reverted

    // Grant operator and set values
    await (await sqo.connect(governor).grantRole(operatorRole, deployer.address)).wait()
    await (await sqo.connect(deployer).setQualityChecking(true)).wait()
    await (await sqo.connect(deployer).setAllowedPeriod(123)).wait()
    await (await sqo.connect(deployer).setOracleUpdateTimeout(456)).wait()
  })
})
