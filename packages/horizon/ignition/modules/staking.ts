import { buildModule } from '@nomicfoundation/hardhat-ignition/modules'

import HorizonStakingModule from './horizon/HorizonStaking'

export default buildModule('GraphHorizon_Staking', (m) => {
  const { instance } = m.useModule(HorizonStakingModule)

  return { HorizonStaking: instance }
})
