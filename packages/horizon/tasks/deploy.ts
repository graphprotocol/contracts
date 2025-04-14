/* eslint-disable no-case-declarations */
import { loadConfig, patchConfig, saveToAddressBook } from '@graphprotocol/toolshed/hardhat'
import { task, types } from 'hardhat/config'
import { ZERO_ADDRESS } from '@graphprotocol/toolshed'

import type { AddressBook } from '@graphprotocol/toolshed/deployments'
import type { HardhatRuntimeEnvironment } from 'hardhat/types'

import DeployModule from '../ignition/modules/deploy'
import { printHorizonBanner } from '@graphprotocol/toolshed/utils'

task('deploy:protocol', 'Deploy a new version of the Graph Protocol Horizon contracts - no data services deployed')
  .addOptionalParam('horizonConfig', 'Name of the Horizon configuration file to use. Format is "protocol.<name>.json5", file must be in the "ignition/configs/" directory. Defaults to network name.', undefined, types.string)
  .addOptionalParam('accountIndex', 'Derivation path index for the account to use', 0, types.int)
  .setAction(async (args, hre: HardhatRuntimeEnvironment) => {
    const graph = hre.graph()

    // Load configuration for the deployment
    console.log('\n========== ⚙️ Deployment configuration ==========')
    const { config: HorizonConfig, file } = loadConfig('./ignition/configs/', 'protocol', args.horizonConfig ?? hre.network.name)
    console.log(`Loaded migration configuration from ${file}`)

    // Display the deployer -- this also triggers the secure accounts prompt if being used
    console.log('\n========== 🔑 Deployer account ==========')
    const deployer = await graph.accounts.getDeployer(args.accountIndex)
    console.log('Using deployer account:', deployer.address)
    const balance = await hre.ethers.provider.getBalance(deployer.address)
    console.log('Deployer balance:', hre.ethers.formatEther(balance), 'ETH')
    if (balance === 0n) {
      console.error('Error: Deployer account has no ETH balance')
      process.exit(1)
    }

    // Deploy the contracts
    console.log(`\n========== 🚧 Deploy protocol ==========`)
    const deployment = await hre.ignition.deploy(DeployModule, {
      displayUi: true,
      parameters: HorizonConfig,
      defaultSender: deployer.address,
    })

    // Save the addresses to the address book
    console.log('\n========== 📖 Updating address book ==========')
    saveToAddressBook(deployment, graph.horizon.addressBook)
    console.log(`Address book at ${graph.horizon.addressBook.file} updated!`)

    console.log('\n\n🎉 ✨ 🚀 ✅ Deployment complete! 🎉 ✨ 🚀 ✅')
  })

task('deploy:migrate', 'Upgrade an existing version of the Graph Protocol v1 to Horizon - no data services deployed')
  .addOptionalParam('horizonConfig', 'Name of the Horizon configuration file to use. Format is "migrate.<name>.json5", file must be in the "ignition/configs/" directory. Defaults to network name.', undefined, types.string)
  .addOptionalParam('step', 'Migration step to run (1, 2, 3 or 4)', undefined, types.int)
  .addOptionalParam('accountIndex', 'Derivation path index for the account to use', 0, types.int)
  .addFlag('patchConfig', 'Patch configuration file using address book values - does not save changes')
  .addFlag('hideBanner', 'Hide the banner display')
  .setAction(async (args, hre: HardhatRuntimeEnvironment) => {
    // Task parameters
    const step: number = args.step ?? 0
    const patchConfig: boolean = args.patchConfig ?? false

    const graph = hre.graph()
    if (!args.hideBanner) {
      printHorizonBanner()
    }

    // Migration step to run
    console.log('\n========== 🏗️ Migration steps ==========')
    const validSteps = [1, 2, 3, 4]
    if (!validSteps.includes(step)) {
      console.error(`Error: Invalid migration step provided: ${step}`)
      console.error(`Valid steps are: ${validSteps.join(', ')}`)
      process.exit(1)
    }
    console.log(`Running migration step: ${step}`)

    // Load configuration for the migration
    console.log('\n========== ⚙️ Deployment configuration ==========')
    const { config: HorizonMigrateConfig, file } = loadConfig('./ignition/configs/', 'migrate', args.horizonConfig ?? hre.network.name)
    console.log(`Loaded migration configuration from ${file}`)

    // Display the deployer -- this also triggers the secure accounts prompt if being used
    console.log('\n========== 🔑 Deployer account ==========')
    const deployer = await graph.accounts.getDeployer(args.accountIndex)
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
        parameters: patchConfig ? _patchStepConfig(step, HorizonMigrateConfig, graph.horizon.addressBook, graph.subgraphService.addressBook) : HorizonMigrateConfig,
        deploymentId: `horizon-${hre.network.name}`,
        defaultSender: deployer.address,
      },
    )

    // Update address book
    console.log('\n========== 📖 Updating address book ==========')
    saveToAddressBook(deployment, graph.horizon.addressBook)
    console.log(`Address book at ${graph.horizon.addressBook.file} updated!`)

    console.log(`\n\n🎉 ✨ 🚀 ✅ Migration step ${step} complete! 🎉 ✨ 🚀 ✅\n`)
  })

// This function patches the Ignition configuration object using an address book to fill in the gaps
// The resulting configuration is not saved back to the configuration file
// eslint-disable-next-line @typescript-eslint/no-explicit-any
function _patchStepConfig<ChainId extends number, ContractName extends string, HorizonContractName extends string>(
  step: number,
  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  config: any,
  horizonAddressBook: AddressBook<ChainId, ContractName>,
  subgraphServiceAddressBook: AddressBook<ChainId, HorizonContractName>,
  // eslint-disable-next-line @typescript-eslint/no-explicit-any
): any {
  let patchedConfig = config

  switch (step) {
    case 2:
      const GraphPayments = horizonAddressBook.getEntry('GraphPayments')
      const PaymentsEscrow = horizonAddressBook.getEntry('PaymentsEscrow')
      patchedConfig = patchConfig(config, {
        $global: {
          graphPaymentsAddress: GraphPayments.address,
          paymentsEscrowAddress: PaymentsEscrow.address,
        },
      })
      break
    case 3:
      patchedConfig = patchConfig(patchedConfig, {
        $global: {
          subgraphServiceAddress: subgraphServiceAddressBook.entryExists('SubgraphService')
            ? subgraphServiceAddressBook.getEntry('SubgraphService').address
            : ZERO_ADDRESS,
        },
      })
      break
    case 4:
      const HorizonStaking = horizonAddressBook.getEntry('HorizonStaking')
      const L2Curation = horizonAddressBook.getEntry('L2Curation')
      const RewardsManager = horizonAddressBook.getEntry('RewardsManager')
      patchedConfig = patchConfig(patchedConfig, {
        $global: {
          subgraphServiceAddress: subgraphServiceAddressBook.entryExists('SubgraphService')
            ? subgraphServiceAddressBook.getEntry('SubgraphService').address
            : ZERO_ADDRESS,
          horizonStakingImplementationAddress: HorizonStaking.implementation ?? ZERO_ADDRESS,
          curationImplementationAddress: L2Curation.implementation ?? ZERO_ADDRESS,
          rewardsManagerImplementationAddress: RewardsManager.implementation ?? ZERO_ADDRESS,
        },
      })
      break
  }

  return patchedConfig
}
