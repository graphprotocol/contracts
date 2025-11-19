import { buildModule } from '@nomicfoundation/hardhat-ignition/modules'

const DirectAllocationImplementationModule = buildModule('DirectAllocationImplementation', (m) => {
  const graphToken = m.getParameter('graphToken')

  const implementation = m.contract('DirectAllocation', [graphToken], {
    id: 'DirectAllocationImplementation',
  })

  return { implementation }
})

export default DirectAllocationImplementationModule
