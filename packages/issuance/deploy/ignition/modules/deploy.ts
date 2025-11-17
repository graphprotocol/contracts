import { buildModule } from '@nomicfoundation/hardhat-ignition/modules'

import DirectAllocationModule from './DirectAllocation'
import IssuanceAllocatorModule from './IssuanceAllocator'
import RewardsEligibilityOracleModule from './RewardsEligibilityOracle'

export default buildModule('GraphIssuance_Deploy', (m) => {
  const { IssuanceAllocator, IssuanceAllocatorImplementation, IssuanceAllocatorProxyAdmin } =
    m.useModule(IssuanceAllocatorModule)

  const { DirectAllocation, DirectAllocationImplementation, DirectAllocationProxyAdmin } =
    m.useModule(DirectAllocationModule)

  const { RewardsEligibilityOracle, RewardsEligibilityOracleImplementation, RewardsEligibilityOracleProxyAdmin } =
    m.useModule(RewardsEligibilityOracleModule)

  const governor = m.getAccount(1)

  // Accept ownership of all contracts
  m.call(IssuanceAllocator, 'acceptOwnership', [], {
    from: governor,
    after: [IssuanceAllocatorModule],
  })

  m.call(DirectAllocation, 'acceptOwnership', [], {
    from: governor,
    after: [DirectAllocationModule],
  })

  m.call(RewardsEligibilityOracle, 'acceptOwnership', [], {
    from: governor,
    after: [RewardsEligibilityOracleModule],
  })

  return {
    IssuanceAllocator,
    IssuanceAllocatorImplementation,
    IssuanceAllocatorProxyAdmin,
    DirectAllocation,
    DirectAllocationImplementation,
    DirectAllocationProxyAdmin,
    RewardsEligibilityOracle,
    RewardsEligibilityOracleImplementation,
    RewardsEligibilityOracleProxyAdmin,
  }
})

