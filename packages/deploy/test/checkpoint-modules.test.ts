import { expect } from 'chai'
import { ethers, ignition } from 'hardhat'

import IssuanceAllocatorActiveModule from '../ignition/modules/issuance/IssuanceAllocatorActive'
import IssuanceAllocatorMinterModule from '../ignition/modules/issuance/IssuanceAllocatorMinter'
import RewardsEligibilityOracleModule from '../ignition/modules/issuance/RewardsEligibilityOracleActive'

// Minimal tests for checkpoint modules - verify they compile and can be deployed
// Full integration tests are in checkpoint-smoke.test.ts and reo-governance-fork.test.ts

describe('Orchestration Active targets (issuance)', () => {
  it('RewardsEligibilityOracleActive compiles and calls assertion', async () => {
    const [deployer] = await ethers.getSigners()
    const dummy = deployer.address

    // We cannot fully pass without a real RM/REO pair; test that it attempts the assertion call by deploying the module
    const { rewardsManager, rewardsEligibilityOracle } = await ignition.deploy(RewardsEligibilityOracleModule, {
      parameters: {
        RewardsManagerRef: {
          rewardsManagerAddress: dummy,
        },
        RewardsEligibilityOracleRef: {
          rewardsEligibilityOracleAddress: dummy,
        },
      },
    })

    expect(rewardsManager).to.exist
    expect(rewardsEligibilityOracle).to.exist
  })

  it('IssuanceAllocatorActive compiles and calls assertion', async () => {
    const [deployer] = await ethers.getSigners()
    const dummy = deployer.address

    const { rewardsManager, issuanceAllocator } = await ignition.deploy(IssuanceAllocatorActiveModule, {
      parameters: {
        RewardsManagerRef: {
          rewardsManagerAddress: dummy,
        },
        IssuanceAllocatorRef: {
          issuanceAllocatorAddress: dummy,
        },
      },
    })

    expect(rewardsManager).to.exist
    expect(issuanceAllocator).to.exist
  })

  it('IssuanceAllocatorMinter compiles and calls assertion', async () => {
    const [deployer] = await ethers.getSigners()
    const dummy = deployer.address

    const { graphToken, issuanceAllocator } = await ignition.deploy(IssuanceAllocatorMinterModule, {
      parameters: {
        GraphTokenRef: {
          graphTokenAddress: dummy,
        },
        IssuanceAllocatorRef: {
          issuanceAllocatorAddress: dummy,
        },
      },
    })

    expect(graphToken).to.exist
    expect(issuanceAllocator).to.exist
  })
})
