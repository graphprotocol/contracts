import { buildModule } from '@nomicfoundation/hardhat-ignition/modules'

import GraphIssuanceProxyAdminModule from './GraphIssuanceProxyAdmin'
import IssuanceAllocatorModule from './IssuanceAllocator'
import PilotAllocationModule from './PilotAllocation'
import RewardsEligibilityOracleModule from './RewardsEligibilityOracle'

export default buildModule('GraphIssuance_Deploy', (m) => {
  // Deploy shared GraphIssuanceProxyAdmin first
  const { GraphIssuanceProxyAdmin } = m.useModule(GraphIssuanceProxyAdminModule)

  // Deploy issuance contracts (they will use GraphIssuanceProxyAdmin)
  const { IssuanceAllocator, IssuanceAllocatorImplementation } = m.useModule(IssuanceAllocatorModule)

  const { PilotAllocation, PilotAllocationImplementation } = m.useModule(PilotAllocationModule)

  const { RewardsEligibilityOracle, RewardsEligibilityOracleImplementation } = m.useModule(
    RewardsEligibilityOracleModule,
  )

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
    GraphIssuanceProxyAdmin,
    IssuanceAllocator,
    IssuanceAllocatorImplementation,
    PilotAllocation,
    PilotAllocationImplementation,
    RewardsEligibilityOracle,
    RewardsEligibilityOracleImplementation,
  }
})
