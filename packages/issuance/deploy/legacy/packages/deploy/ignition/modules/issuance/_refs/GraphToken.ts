import { buildModule } from '@nomicfoundation/hardhat-ignition/modules'

export default buildModule('GraphTokenRef', (m) => {
  const graphToken = m.contractAt('IGraphToken', m.getParameter('graphToken'))
  return { graphToken }
})
