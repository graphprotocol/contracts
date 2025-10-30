import ControllerArtifact from '@graphprotocol/contracts/artifacts/contracts/governance/Controller.sol/Controller.json'
import { buildModule } from '@nomicfoundation/hardhat-ignition/modules'
import { ethers } from 'ethers'

import { MigrateHorizonStakingGovernorModule } from '../core/HorizonStaking'
import { MigrateCurationGovernorModule } from '../periphery/Curation'
import { MigrateRewardsManagerGovernorModule } from '../periphery/RewardsManager'

export default buildModule('GraphHorizon_Migrate_4', (m) => {
  m.useModule(MigrateCurationGovernorModule)
  m.useModule(MigrateRewardsManagerGovernorModule)
  m.useModule(MigrateHorizonStakingGovernorModule)

  // Patch controller to override old dispute manager address
  const disputeManagerAddress = m.getParameter('disputeManagerAddress')
  const controllerAddress = m.getParameter('controllerAddress')
  const Controller = m.contractAt('Controller', ControllerArtifact, controllerAddress)
  m.call(Controller, 'setContractProxy', [ethers.keccak256(ethers.toUtf8Bytes('DisputeManager')), disputeManagerAddress], {
    id: 'setContractProxy_DisputeManager',
  })

  return {}
})
