import { buildModule } from '@nomicfoundation/hardhat-ignition/modules'

import GraphProxyAdmin2Module from './GraphProxyAdmin2'

// eslint-disable-next-line @typescript-eslint/no-explicit-any
const IssuanceAllocatorModule: any = buildModule('IssuanceAllocator', (m) => {
  const owner = m.getParameter('owner')
  const graphToken = m.getParameter('graphToken')

  const { graphProxyAdmin2 } = m.useModule(GraphProxyAdmin2Module)

  const implementation = m.contract('IssuanceAllocator', [graphToken], {
    id: 'IssuanceAllocatorImplementation',
  })

  const initData = m.encodeFunctionCall(implementation, 'initialize', [owner])
  const issuanceAllocator = m.contract('TransparentUpgradeableProxy', [implementation, graphProxyAdmin2, initData], {
    id: 'IssuanceAllocator',
  })

  return { issuanceAllocator, implementation }
})

export default IssuanceAllocatorModule
