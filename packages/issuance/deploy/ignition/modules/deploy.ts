import { buildModule } from '@nomicfoundation/hardhat-ignition/modules'

import IssuanceAllocatorModule from './IssuanceAllocator'
import PilotAllocationModule from './PilotAllocation'
import RewardsEligibilityOracleModule from './RewardsEligibilityOracle'

export default buildModule('GraphIssuance_Deploy', (m) => {
  const { IssuanceAllocator, IssuanceAllocatorImplementation, IssuanceAllocatorProxyAdmin } =
    m.useModule(IssuanceAllocatorModule)

  const { PilotAllocation, PilotAllocationImplementation, PilotAllocationProxyAdmin } =
    m.useModule(PilotAllocationModule)

  const { RewardsEligibilityOracle, RewardsEligibilityOracleImplementation, RewardsEligibilityOracleProxyAdmin } =
    m.useModule(RewardsEligibilityOracleModule)

  const governor = m.getAccount(1)

  // Accept ownership of all contracts
  m.call(IssuanceAllocator, 'acceptOwnership', [], {
    from: governor,
    after: [IssuanceAllocatorModule],
  })

  m.call(PilotAllocation, 'acceptOwnership', [], {
    from: governor,
    after: [PilotAllocationModule],
  })

  m.call(RewardsEligibilityOracle, 'acceptOwnership', [], {
    from: governor,
    after: [RewardsEligibilityOracleModule],
  })

  return {
    IssuanceAllocator,
    IssuanceAllocatorImplementation,
    IssuanceAllocatorProxyAdmin,
    PilotAllocation,
    PilotAllocationImplementation,
    PilotAllocationProxyAdmin,
    RewardsEligibilityOracle,
    RewardsEligibilityOracleImplementation,
    RewardsEligibilityOracleProxyAdmin,
  }
})
