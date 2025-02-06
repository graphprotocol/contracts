import hre, { ignition } from 'hardhat'
import { IgnitionHelper } from 'hardhat-graph-protocol/sdk'

import MigrateModuleStep1 from '../ignition/modules/migrate/migrate-1'
import MigrateModuleStep2 from '../ignition/modules/migrate/migrate-2'
import MigrateModuleStep3 from '../ignition/modules/migrate/migrate-3'
import MigrateModuleStep4 from '../ignition/modules/migrate/migrate-4'

async function main() {
  console.log(getHorizonBanner())
  const HorizonMigrateConfig = IgnitionHelper.loadConfig('./ignition/configs/', 'horizon-migrate', `horizon-${hre.network.name}`)

  const signers = await hre.ethers.getSigners()
  const deployer = signers[0]
  const governor = signers[1]

  console.log('Using deployer account:', deployer.address)
  console.log('Using governor account:', governor.address)

  console.log('========== Running migration: step 1 ==========')
  const {
    GraphPaymentsProxy,
    PaymentsEscrowProxy
  } = await ignition.deploy(MigrateModuleStep1, {
    displayUi: true,
    parameters: HorizonMigrateConfig,
    deploymentId: `horizon-${hre.network.name}`,
  })

  let patchedHorizonMigrateConfig = IgnitionHelper.patchConfig(HorizonMigrateConfig, {
    HorizonProxiesGovernor: {
      graphPaymentsAddress: GraphPaymentsProxy.target,
      paymentsEscrowAddress: PaymentsEscrowProxy.target
    }
  })

  console.log('========== Running migration: step 2 ==========')
  await ignition.deploy(MigrateModuleStep2, {
    displayUi: true,
    parameters: patchedHorizonMigrateConfig,
    deploymentId: `horizon-${hre.network.name}`,
    defaultSender: governor.address,
  })

  console.log('========== Running migration: step 3 ==========')
  const deployment = await ignition.deploy(MigrateModuleStep3, {
    displayUi: true,
    parameters: HorizonMigrateConfig,
    deploymentId: `horizon-${hre.network.name}`,
  })

  IgnitionHelper.saveAddressBook(deployment, hre.network.config.chainId)

  patchedHorizonMigrateConfig = IgnitionHelper.patchConfig(patchedHorizonMigrateConfig, {
    HorizonStakingGovernor: {
      horizonStakingImplementationAddress: deployment.HorizonStakingImplementation.target
    },
    L2CurationGovernor: {
      curationImplementationAddress: deployment.L2CurationImplementation.target
    },
    RewardsManagerGovernor: {
      rewardsManagerImplementationAddress: deployment.RewardsManagerImplementation.target
    }
  })

  console.log('========== Running migration: step 4 ==========')
  await ignition.deploy(MigrateModuleStep4, {
    displayUi: true,
    parameters: patchedHorizonMigrateConfig,
    deploymentId: `horizon-${hre.network.name}`,
    defaultSender: governor.address,
  })

  console.log('Migration successful! 🎉')
}

main().catch((error) => {
  console.error(error)
  process.exit(1)
})

function getHorizonBanner(): string {
  return `
██╗  ██╗ ██████╗ ██████╗ ██╗███████╗ ██████╗ ███╗   ██╗
██║  ██║██╔═══██╗██╔══██╗██║╚══███╔╝██╔═══██╗████╗  ██║
███████║██║   ██║██████╔╝██║  ███╔╝ ██║   ██║██╔██╗ ██║
██╔══██║██║   ██║██╔══██╗██║ ███╔╝  ██║   ██║██║╚██╗██║
██║  ██║╚██████╔╝██║  ██║██║███████╗╚██████╔╝██║ ╚████║
╚═╝  ╚═╝ ╚═════╝ ╚═╝  ╚═╝╚═╝╚══════╝ ╚═════╝ ╚═╝  ╚═══╝
                                                        
██╗   ██╗██████╗  ██████╗ ██████╗  █████╗ ██████╗ ███████╗
██║   ██║██╔══██╗██╔════╝ ██╔══██╗██╔══██╗██╔══██╗██╔════╝
██║   ██║██████╔╝██║  ███╗██████╔╝███████║██║  ██║█████╗  
██║   ██║██╔═══╝ ██║   ██║██╔══██╗██╔══██║██║  ██║██╔══╝  
╚██████╔╝██║     ╚██████╔╝██║  ██║██║  ██║██████╔╝███████╗
 ╚═════╝ ╚═╝      ╚═════╝ ╚═╝  ╚═╝╚═╝  ╚═╝╚═════╝ ╚══════╝
`
}
