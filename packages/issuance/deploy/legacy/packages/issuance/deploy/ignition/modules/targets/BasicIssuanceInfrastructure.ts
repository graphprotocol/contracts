import { buildModule } from '@nomicfoundation/hardhat-ignition/modules'

import GraphProxyAdmin2Module from '../contracts/GraphProxyAdmin2'
import IssuanceAllocatorModule from '../contracts/IssuanceAllocator'

// eslint-disable-next-line @typescript-eslint/no-explicit-any
const BasicIssuanceInfrastructureTarget: any = buildModule('BasicIssuanceInfrastructure', (m) => {
  const { graphProxyAdmin2 } = m.useModule(GraphProxyAdmin2Module)
  const { issuanceAllocator, implementation } = m.useModule(IssuanceAllocatorModule)

  return {
    graphProxyAdmin2,
    issuanceAllocator,
    implementation,
    status: 'basic-infrastructure-deployed',
  }
})

export default BasicIssuanceInfrastructureTarget
