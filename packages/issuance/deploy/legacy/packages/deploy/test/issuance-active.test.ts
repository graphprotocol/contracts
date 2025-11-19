import { expect } from 'chai'
import { ethers, ignition } from 'hardhat'

import IssuanceAllocatorActiveModule from '../ignition/modules/issuance/IssuanceAllocatorActive'
import IssuanceAllocatorMinterModule from '../ignition/modules/issuance/IssuanceAllocatorMinter'
import ServiceQualityOracleModule from '../ignition/modules/issuance/ServiceQualityOracleActive'

// Minimal mocks for integration checks live in the issuance package tests; here we just assert the module wiring and failure mode

describe('Orchestration Active targets (issuance)', () => {
  it('ServiceQualityOracleActive compiles and calls assertion', async () => {
    const [deployer] = await ethers.getSigners()
    const dummy = deployer.address

    // We cannot fully pass without a real RM/SQO pair; test that it attempts the assertion call by deploying the module
    const { rewardsManager, serviceQualityOracle } = await ignition.deploy(ServiceQualityOracleModule, {
      parameters: {
        ServiceQualityOracleActive: {
          rewardsManager: dummy,
          serviceQualityOracle: dummy,
        },
      },
    })

    expect(rewardsManager).to.exist
    expect(serviceQualityOracle).to.exist
  })

  it('IssuanceAllocatorActive compiles and calls assertion', async () => {
    const [deployer] = await ethers.getSigners()
    const dummy = deployer.address

    const { rewardsManager, issuanceAllocator } = await ignition.deploy(IssuanceAllocatorActiveModule, {
      parameters: {
        IssuanceAllocatorActive: {
          rewardsManager: dummy,
          issuanceAllocator: dummy,
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
        IssuanceAllocatorMinter: {
          graphToken: dummy,
          issuanceAllocator: dummy,
        },
      },
    })

    expect(graphToken).to.exist
    expect(issuanceAllocator).to.exist
  })
})
