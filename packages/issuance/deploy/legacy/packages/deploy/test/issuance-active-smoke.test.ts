import { expect } from 'chai'
import { ethers, ignition } from 'hardhat'

import IssuanceAllocatorActive from '../ignition/modules/issuance/IssuanceAllocatorActive'
import IssuanceAllocatorMinter from '../ignition/modules/issuance/IssuanceAllocatorMinter'
import ServiceQualityOracleActive from '../ignition/modules/issuance/ServiceQualityOracleActive'

// This smoke test simulates governance by directly setting values on minimal mocks,
// then ensures Active modules no longer revert when addresses match.

describe('Orchestration Active smoke', () => {
  it('SQO/IA integration checks pass after simulating governance', async () => {
    const [deployer] = await ethers.getSigners()

    // Minimal mocks inline
    const RMFactory = await ethers.getContractFactory(`
      contract MockRM {
        address public serviceQualityOracle;
        address public issuanceAllocator;
        function setServiceQualityOracle(address a) external { serviceQualityOracle = a; }
        function setIssuanceAllocator(address a) external { issuanceAllocator = a; }
      }
    `)
    const rm = await RMFactory.deploy()

    const GTFactory = await ethers.getContractFactory(`
      interface IGraphToken { function isMinter(address) external view returns (bool); }
      contract MockGT is IGraphToken {
        mapping(address => bool) public minter;
        function setMinter(address m, bool v) external { minter[m] = v; }
        function isMinter(address a) external view returns (bool) { return minter[a]; }
      }
    `)
    const gt = await GTFactory.deploy()

    const expectedSQO = deployer.address
    const expectedIA = ethers.Wallet.createRandom().address

    await (await rm.setServiceQualityOracle(expectedSQO)).wait()
    await (await rm.setIssuanceAllocator(expectedIA)).wait()

    // Assert: SQO Active passes
    await ignition.deploy(ServiceQualityOracleActive, {
      parameters: {
        ServiceQualityOracleActive: {
          rewardsManager: await rm.getAddress(),
          serviceQualityOracle: expectedSQO,
        },
      },
    })

    // Assert: IA Active passes
    await ignition.deploy(IssuanceAllocatorActive, {
      parameters: {
        IssuanceAllocatorActive: {
          rewardsManager: await rm.getAddress(),
          issuanceAllocator: expectedIA,
        },
      },
    })

    // Grant IA minter and assert IssuanceAllocatorMinter passes
    await (await gt.setMinter(expectedIA, true)).wait()
    await ignition.deploy(IssuanceAllocatorMinter, {
      parameters: {
        IssuanceAllocatorMinter: {
          graphToken: await gt.getAddress(),
          issuanceAllocator: expectedIA,
        },
      },
    })

    expect(true).to.equal(true)
  })
})
