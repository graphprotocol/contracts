import { buildModule } from '@nomicfoundation/hardhat-ignition/modules'

import GraphProxyAdmin2Module from './GraphProxyAdmin2'
import IssuanceAllocatorModule from './IssuanceAllocator'
import PilotAllocationModule from './PilotAllocation'
import RewardsEligibilityOracleModule from './RewardsEligibilityOracle'

export default buildModule('GraphIssuance_Deploy', (m) => {
  // Deploy shared GraphProxyAdmin2 first
  const { GraphProxyAdmin2 } = m.useModule(GraphProxyAdmin2Module)

  // Deploy issuance contracts (they will use GraphProxyAdmin2)
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
    GraphProxyAdmin2,
    IssuanceAllocator,
    IssuanceAllocatorImplementation,
    PilotAllocation,
    PilotAllocationImplementation,
    RewardsEligibilityOracle,
    RewardsEligibilityOracleImplementation,
  }
})
