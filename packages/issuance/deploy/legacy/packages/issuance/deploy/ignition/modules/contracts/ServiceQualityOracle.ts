import { buildModule } from '@nomicfoundation/hardhat-ignition/modules'

import GraphProxyAdmin2Module from './GraphProxyAdmin2'

// eslint-disable-next-line @typescript-eslint/no-explicit-any
const ServiceQualityOracleModule: any = buildModule('ServiceQualityOracle', (m) => {
  const owner = m.getParameter('owner')
  const graphToken = m.getParameter('graphToken')

  const { graphProxyAdmin2 } = m.useModule(GraphProxyAdmin2Module)

  const implementation = m.contract('ServiceQualityOracle', [graphToken], {
    id: 'ServiceQualityOracleImplementation',
  })

  const initData = m.encodeFunctionCall(implementation, 'initialize', [owner])
  const serviceQualityOracle = m.contract('TransparentUpgradeableProxy', [implementation, graphProxyAdmin2, initData], {
    id: 'ServiceQualityOracle',
  })

  return { serviceQualityOracle, implementation }
})

export default ServiceQualityOracleModule
