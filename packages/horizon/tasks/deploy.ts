/* eslint-disable no-case-declarations */
import { task, types } from 'hardhat/config'
import { IgnitionHelper } from 'hardhat-graph-protocol/sdk'

import type { AddressBook } from '../../hardhat-graph-protocol/src/sdk/address-book'
import type { HardhatRuntimeEnvironment } from 'hardhat/types'

import DeployModule from '../ignition/modules/deploy'

task('deploy:protocol', 'Deploy a new version of the Graph Protocol Horizon contracts - no data services deployed')
  .setAction(async (_, hre: HardhatRuntimeEnvironment) => {
    const graph = hre.graph()

    // Load configuration for the deployment
    console.log('\n========== ⚙️ Deployment configuration ==========')
    const { config: HorizonConfig, file } = IgnitionHelper.loadConfig('./ignition/configs/', 'horizon', hre.network.name)
    console.log(`Loaded migration configuration from ${file}`)

    // Deploy the contracts
    console.log(`\n========== 🚧 Deploy protocol ==========`)
    const deployment = await hre.ignition.deploy(DeployModule, {
      displayUi: true,
      parameters: HorizonConfig,
    })

    // Save the addresses to the address book
    console.log('\n========== 📖 Updating address book ==========')
    IgnitionHelper.saveToAddressBook(deployment, hre.network.config.chainId, graph.horizon!.addressBook)
    console.log(`Address book at ${graph.horizon!.addressBook.file} updated!`)
  })

task('deploy:migrate', 'Upgrade an existing version of the Graph Protocol v1 to Horizon - no data services deployed')
  .addOptionalParam('step', 'Migration step to run (1, 2, 3 or 4) - runs all if not provided', undefined, types.int)
  .addFlag('patchConfig', 'Patch configuration file using address book values - does not save changes')
  .setAction(async (args, hre: HardhatRuntimeEnvironment) => {
    // Task parameters
    const step: number = args.step ?? 0
    const patchConfig: boolean = args.patchConfig ?? false

    const graph = hre.graph()
    console.log(getHorizonBanner())

    // Migration step to run
    console.log('\n========== 🏗️ Migration steps ==========')
    const validSteps = [0, 1, 2, 3, 4]
    if (!validSteps.includes(step)) {
      console.error(`Error: Invalid migration step provided: ${step}`)
      console.error(`Valid steps are: ${validSteps.join(', ')}`)
      process.exit(1)
    }
    console.log(`Running migration step: ${step}`)

    // Load configuration for the migration
    console.log('\n========== ⚙️ Deployment configuration ==========')
    const { config: HorizonMigrateConfig, file } = IgnitionHelper.loadConfig('./ignition/configs/', 'horizon-migrate', `horizon-${hre.network.name}`)
    console.log(`Loaded migration configuration from ${file}`)

    // Display the deployer -- this also triggers the secure accounts prompt if being used
    console.log('\n========== 🔑 Deployer account ==========')
    const signers = await hre.ethers.getSigners()
    const deployer = signers[0]
    console.log('Using deployer account:', deployer.address)
    const balance = await hre.ethers.provider.getBalance(deployer.address)
    console.log('Deployer balance:', hre.ethers.formatEther(balance), 'ETH')
    if (balance === 0n) {
      console.error('Error: Deployer account has no ETH balance')
      process.exit(1)
    }

    // Run migration step
    console.log(`\n========== 🚧 Running migration: step ${step} ==========`)
    const MigrationModule = require(`../ignition/modules/migrate/migrate-${step}`).default
    const deployment = await hre.ignition.deploy(
      MigrationModule,
      {
        displayUi: true,
        parameters: patchConfig ? _patchStepConfig(step, HorizonMigrateConfig, graph.horizon!.addressBook) : HorizonMigrateConfig,
        deploymentId: `horizon-${hre.network.name}`,
      })

    // Update address book
    console.log('\n========== 📖 Updating address book ==========')
    IgnitionHelper.saveToAddressBook(deployment, hre.network.config.chainId, graph.horizon!.addressBook)
    console.log(`Address book at ${graph.horizon!.addressBook.file} updated!`)

    console.log('\n\n🎉 ✨ 🚀 ✅ Migration successful! 🎉 ✨ 🚀 ✅')
  })

// This function patches the Ignition configuration object using an address book to fill in the gaps
// The resulting configuration is not saved back to the configuration file
// eslint-disable-next-line @typescript-eslint/no-explicit-any
function _patchStepConfig<ChainId extends number, ContractName extends string>(step: number, config: any, addressBook: AddressBook<ChainId, ContractName>): any {
  let patchedConfig = config

  switch (step) {
    case 2:
      const GraphPayments = addressBook.getEntry('GraphPayments')
      const PaymentsEscrow = addressBook.getEntry('PaymentsEscrow')
      patchedConfig = IgnitionHelper.patchConfig(config, {
        HorizonProxiesGovernor: {
          graphPaymentsAddress: GraphPayments.address,
          paymentsEscrowAddress: PaymentsEscrow.address,
        },
      })
      break
    case 4:
      const HorizonStaking = addressBook.getEntry('HorizonStaking')
      const L2Curation = addressBook.getEntry('L2Curation')
      const RewardsManager = addressBook.getEntry('RewardsManager')
      patchedConfig = IgnitionHelper.patchConfig(patchedConfig, {
        HorizonStakingGovernor: {
          horizonStakingImplementationAddress: HorizonStaking.implementation,
        },
        L2CurationGovernor: {
          curationImplementationAddress: L2Curation.implementation,
        },
        RewardsManagerGovernor: {
          rewardsManagerImplementationAddress: RewardsManager.implementation,
        },
      })
      break
  }

  return patchedConfig
}

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
