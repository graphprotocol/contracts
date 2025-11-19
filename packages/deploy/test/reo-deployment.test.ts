import { expect } from 'chai'
import { ethers, ignition } from 'hardhat'

import RewardsEligibilityOracleModule from '../../issuance/deploy/ignition/modules/RewardsEligibilityOracle'

describe('RewardsEligibilityOracle Deployment', function () {
  it('deploys proxy and implementation; initializes roles and defaults', async () => {
    const [deployer, governor] = await ethers.getSigners()

    const mockGraphTokenAddress = deployer.address

    const { RewardsEligibilityOracle, RewardsEligibilityOracleImplementation } = await ignition.deploy(
      RewardsEligibilityOracleModule,
      {
        parameters: {
          RewardsEligibilityOracle: {
            graphTokenAddress: mockGraphTokenAddress,
          },
        },
        defaultSender: deployer.address,
      },
    )

    expect(RewardsEligibilityOracle.target).to.be.properAddress
    expect(RewardsEligibilityOracleImplementation.target).to.be.properAddress

    const REO = await ethers.getContractFactory('RewardsEligibilityOracle')
    const reo = REO.attach(RewardsEligibilityOracle.target)

    // Governor role granted
    const governorRole = await reo.GOVERNOR_ROLE()
    expect(await reo.hasRole(governorRole, governor.address)).to.be.true

    // Default params
    // checkingActive defaults to false -> isAllowed ignores and returns true
    expect(await reo.isAllowed(ethers.ZeroAddress)).to.equal(true)

    // Setters callable by OPERATOR only
    const operatorRole = await reo.OPERATOR_ROLE()
    await expect(reo.connect(deployer).setQualityChecking(true)).to.be.revertedWithCustomError(
      reo,
      'AccessControlUnauthorizedAccount',
    )
    await expect(reo.connect(deployer).setAllowedPeriod(123)).to.be.reverted
    await expect(reo.connect(deployer).setOracleUpdateTimeout(456)).to.be.reverted

    // Grant operator and set values
    await (await reo.connect(governor).grantRole(operatorRole, deployer.address)).wait()
    await (await reo.connect(deployer).setQualityChecking(true)).wait()
    await (await reo.connect(deployer).setAllowedPeriod(123)).wait()
    await (await reo.connect(deployer).setOracleUpdateTimeout(456)).wait()
  })
})
