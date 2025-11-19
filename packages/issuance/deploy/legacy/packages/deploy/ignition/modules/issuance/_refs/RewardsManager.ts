import { buildModule } from '@nomicfoundation/hardhat-ignition/modules'

export default buildModule('RewardsManagerRef', (m) => {
  const rewardsManager = m.contractAt('RewardsManager', m.getParameter('rewardsManager'))
  return { rewardsManager }
})
