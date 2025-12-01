import { expect } from 'chai'
import { ethers, ignition } from 'hardhat'

import IssuanceAllocatorActive from '../ignition/modules/issuance/IssuanceAllocatorActive'
import IssuanceAllocatorMinter from '../ignition/modules/issuance/IssuanceAllocatorMinter'
import RewardsEligibilityOracleActive from '../ignition/modules/issuance/RewardsEligibilityOracleActive'

// This smoke test simulates governance by directly setting values on minimal mocks,
// then ensures Active modules no longer revert when addresses match.

describe('Orchestration Active smoke', () => {
  it('REO/IA integration checks pass after simulating governance', async () => {
    const [deployer] = await ethers.getSigners()

    // Deploy mock contracts
    const RMFactory = await ethers.getContractFactory('MockRM')
    const rm = await RMFactory.deploy()

    const GTFactory = await ethers.getContractFactory('MockGraphTokenWithMinter')
    const gt = await GTFactory.deploy()

    const expectedREO = deployer.address
    const expectedIA = ethers.Wallet.createRandom().address

    await (await rm.setRewardsEligibilityOracle(expectedREO)).wait()
    await (await rm.setIssuanceAllocator(expectedIA)).wait()

    // Assert: REO Active passes
    const rmAddress = await rm.getAddress()
    await ignition.deploy(RewardsEligibilityOracleActive, {
      parameters: {
        RewardsManagerRef: {
          rewardsManagerAddress: rmAddress,
        },
        RewardsEligibilityOracleRef: {
          rewardsEligibilityOracleAddress: expectedREO,
        },
      },
    })

    // Assert: IA Active passes
    await ignition.deploy(IssuanceAllocatorActive, {
      parameters: {
        RewardsManagerRef: {
          rewardsManagerAddress: rmAddress,
        },
        IssuanceAllocatorRef: {
          issuanceAllocatorAddress: expectedIA,
        },
      },
    })

    // Grant IA minter and assert IssuanceAllocatorMinter passes
    await (await gt.setMinter(expectedIA, true)).wait()
    const gtAddress = await gt.getAddress()
    await ignition.deploy(IssuanceAllocatorMinter, {
      parameters: {
        GraphTokenRef: {
          graphTokenAddress: gtAddress,
        },
        IssuanceAllocatorRef: {
          issuanceAllocatorAddress: expectedIA,
        },
      },
    })

    expect(true).to.equal(true)
  })
})
