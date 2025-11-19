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

    // Minimal mocks inline
    const RMFactory = await ethers.getContractFactory(`
      contract MockRM {
        address public rewardsEligibilityOracle;
        address public issuanceAllocator;
        function setRewardsEligibilityOracle(address a) external { rewardsEligibilityOracle = a; }
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

    const expectedREO = deployer.address
    const expectedIA = ethers.Wallet.createRandom().address

    await (await rm.setRewardsEligibilityOracle(expectedREO)).wait()
    await (await rm.setIssuanceAllocator(expectedIA)).wait()

    // Assert: REO Active passes
    await ignition.deploy(RewardsEligibilityOracleActive, {
      parameters: {
        RewardsEligibilityOracleActive: {
          rewardsManager: await rm.getAddress(),
          rewardsEligibilityOracle: expectedREO,
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
