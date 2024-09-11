import { buildModule } from '@nomicfoundation/hardhat-ignition/modules'

import GraphTokenModule from './staking/GraphToken'

export default buildModule('GraphHorizon_Staking', (m) => {
  const { GraphToken } = m.useModule(GraphTokenModule)

  return { GraphToken }
})
