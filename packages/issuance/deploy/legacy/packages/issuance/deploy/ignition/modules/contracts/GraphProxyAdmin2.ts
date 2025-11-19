import { buildModule } from '@nomicfoundation/hardhat-ignition/modules'

const GraphProxyAdmin2Module = buildModule('GraphProxyAdmin2', (m) => {
  const owner = m.getParameter('owner')

  const graphProxyAdmin2 = m.contract('ProxyAdmin', [owner], {
    id: 'GraphProxyAdmin2',
  })

  return { graphProxyAdmin2 }
})

export default GraphProxyAdmin2Module
