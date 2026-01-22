import { buildModule } from '@nomicfoundation/ignition-core'

import { UpgradeRewardsManagerDeployerModule, UpgradeRewardsManagerGovernorModule } from './RewardsManager'
// import { UpgradeCurationDeployerModule, UpgradeCurationGovernorModule } from './Curation'

export const UpgradeDeployerModule = buildModule('GraphHorizon_Upgrade_Deployer', (m) => {
  const { RewardsManagerProxy, Implementation_RewardsManager } = m.useModule(UpgradeRewardsManagerDeployerModule)
  // const { CurationProxy, Implementation_Curation } = m.useModule(UpgradeCurationDeployerModule)

  return { RewardsManagerProxy, Implementation_RewardsManager }
})

export const UpgradeGovernorModule = buildModule('GraphHorizon_Upgrade_Governor', (m) => {
  const { RewardsManagerV3 } = m.useModule(UpgradeRewardsManagerGovernorModule)
  // const { CurationV3 } = m.useModule(UpgradeCurationGovernorModule)

  return { RewardsManagerV3 }
})
