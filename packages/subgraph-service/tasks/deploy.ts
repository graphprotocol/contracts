/* eslint-disable no-case-declarations */
import { loadConfig, patchConfig, saveToAddressBook } from '@graphprotocol/toolshed/hardhat'
import { task, types } from 'hardhat/config'
import { printHorizonBanner } from '@graphprotocol/toolshed/utils'
import { ZERO_ADDRESS } from '@graphprotocol/toolshed'

import type { AddressBook } from '@graphprotocol/toolshed/deployments'
import type { HardhatRuntimeEnvironment } from 'hardhat/types'

import Deploy1Module from '../ignition/modules/deploy/deploy-1'
import Deploy2Module from '../ignition/modules/deploy/deploy-2'
import HorizonModule from '@graphprotocol/horizon/ignition/modules/deploy'

// Horizon needs the SubgraphService proxy address before it can be deployed
// But SubgraphService and DisputeManager implementations need Horizon...
// So the deployment order is:
// - Deploy SubgraphService and DisputeManager proxies
// - Deploy Horizon
// - Deploy SubgraphService and DisputeManager implementations
task('deploy:protocol', 'Deploy a new version of the Graph Protocol Horizon contracts - with Subgraph Service')
  .addOptionalParam('subgraphServiceConfig', 'Name of the Subgraph Service configuration file to use. Format is "protocol.<name>.json5", file must be in the "ignition/configs/" directory. Defaults to network name.', undefined, types.string)
  .addOptionalParam('horizonConfig', 'Name of the Horizon configuration file to use. Format is "protocol.<name>.json5", file must be in the "ignition/configs/" directory in the horizon package. Defaults to network name.', undefined, types.string)
  .setAction(async (args, hre: HardhatRuntimeEnvironment) => {
    const graph = hre.graph()

    // Load configuration files for the deployment
    console.log('\n========== ⚙️ Deployment configuration ==========')
    const { config: HorizonConfig, file: horizonFile } = loadConfig('./node_modules/@graphprotocol/horizon/ignition/configs', 'protocol', args.horizonConfig ?? hre.network.name)
    const { config: SubgraphServiceConfig, file: subgraphServiceFile } = loadConfig('./ignition/configs/', 'protocol', args.subgraphServiceConfig ?? hre.network.name)
    console.log(`Loaded Horizon migration configuration from ${horizonFile}`)
    console.log(`Loaded Subgraph Service migration configuration from ${subgraphServiceFile}`)

    // Display the deployer -- this also triggers the secure accounts prompt if being used
    console.log('\n========== 🔑 Deployer account ==========')
    const deployer = await graph.accounts.getDeployer(args.deployerIndex)
    console.log('Using deployer account:', deployer.address)
    const balance = await hre.ethers.provider.getBalance(deployer.address)
    console.log('Deployer balance:', hre.ethers.formatEther(balance), 'ETH')
    if (balance === 0n) {
      console.error('Error: Deployer account has no ETH balance')
      process.exit(1)
    }

    // 1. Deploy SubgraphService and DisputeManager proxies
    console.log(`\n========== 🚧 SubgraphService and DisputeManager proxies ==========`)
    const proxiesDeployment = await hre.ignition.deploy(Deploy1Module, {
      displayUi: true,
      parameters: SubgraphServiceConfig,
    })

    // 2. Deploy Horizon
    console.log(`\n========== 🚧 Deploy Horizon ==========`)
    const horizonDeployment = await hre.ignition.deploy(HorizonModule, {
      displayUi: true,
      parameters: patchConfig(HorizonConfig, {
        $global: {
          // The naming convention in the horizon package is slightly different
          subgraphServiceAddress: proxiesDeployment.Transparent_Proxy_SubgraphService.target as string,
        },
      }),
    })

    // 3. Deploy SubgraphService and DisputeManager implementations
    console.log(`\n========== 🚧 Deploy SubgraphService implementations and upgrade them ==========`)
    const subgraphServiceDeployment = await hre.ignition.deploy(Deploy2Module, {
      displayUi: true,
      parameters: patchConfig(SubgraphServiceConfig, {
        $global: {
          controllerAddress: horizonDeployment.Controller.target as string,
          curationProxyAddress: horizonDeployment.Graph_Proxy_L2Curation.target as string,
          curationImplementationAddress: horizonDeployment.Implementation_L2Curation.target as string,
          disputeManagerProxyAddress: proxiesDeployment.Transparent_Proxy_DisputeManager.target as string,
          disputeManagerProxyAdminAddress: proxiesDeployment.Transparent_ProxyAdmin_DisputeManager.target as string,
          subgraphServiceProxyAddress: proxiesDeployment.Transparent_Proxy_SubgraphService.target as string,
          subgraphServiceProxyAdminAddress: proxiesDeployment.Transparent_ProxyAdmin_SubgraphService.target as string,
          graphTallyCollectorAddress: horizonDeployment.GraphTallyCollector.target as string,
        },
      }),
    })

    // Save the addresses to the address book
    console.log('\n========== 📖 Updating address book ==========')
    saveToAddressBook(horizonDeployment, graph.horizon.addressBook)
    saveToAddressBook(proxiesDeployment, graph.subgraphService.addressBook)
    saveToAddressBook(subgraphServiceDeployment, graph.subgraphService.addressBook)
    console.log(`Address book at ${graph.horizon.addressBook.file} updated!`)
    console.log(`Address book at ${graph.subgraphService.addressBook.file} updated!`)
    console.log('Note that Horizon deployment addresses are updated in the Horizon address book')

    console.log('\n\n🎉 ✨ 🚀 ✅ Deployment complete! 🎉 ✨ 🚀 ✅')
  })

task('deploy:migrate', 'Deploy the Subgraph Service on an existing Horizon deployment')
  .addOptionalParam('step', 'Migration step to run (1, 2)', undefined, types.int)
  .addOptionalParam('subgraphServiceConfig', 'Name of the Subgraph Service configuration file to use. Format is "migrate.<name>.json5", file must be in the "ignition/configs/" directory. Defaults to network name.', undefined, types.string)
  .addFlag('patchConfig', 'Patch configuration file using address book values - does not save changes')
  .setAction(async (args, hre: HardhatRuntimeEnvironment) => {
    // Task parameters
    const step: number = args.step ?? 0
    const patchConfig: boolean = args.patchConfig ?? false

    const graph = hre.graph()
    printHorizonBanner()

    // Migration step to run
    console.log('\n========== 🏗️ Migration steps ==========')
    const validSteps = [1, 2]
    if (!validSteps.includes(step)) {
      console.error(`Error: Invalid migration step provided: ${step}`)
      console.error(`Valid steps are: ${validSteps.join(', ')}`)
      process.exit(1)
    }
    console.log(`Running migration step: ${step}`)

    // Load configuration for the migration
    console.log('\n========== ⚙️ Deployment configuration ==========')
    const { config: SubgraphServiceMigrateConfig, file } = loadConfig('./ignition/configs/', 'migrate', args.subgraphServiceConfig ?? hre.network.name)
    console.log(`Loaded migration configuration from ${file}`)

    // Display the deployer -- this also triggers the secure accounts prompt if being used
    console.log('\n========== 🔑 Deployer account ==========')
    const deployer = await graph.accounts.getDeployer(args.deployerIndex)
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
        parameters: patchConfig ? _patchStepConfig(step, SubgraphServiceMigrateConfig, graph.subgraphService.addressBook, graph.horizon.addressBook) : SubgraphServiceMigrateConfig,
        deploymentId: `subgraph-service-${hre.network.name}`,
      })

    // Update address book
    console.log('\n========== 📖 Updating address book ==========')
    saveToAddressBook(deployment, graph.subgraphService.addressBook)
    console.log(`Address book at ${graph.subgraphService.addressBook.file} updated!`)

    console.log('\n\n🎉 ✨ 🚀 ✅ Migration complete! 🎉 ✨ 🚀 ✅')
  })

// This function patches the Ignition configuration object using an address book to fill in the gaps
// The resulting configuration is not saved back to the configuration file

function _patchStepConfig<ChainId extends number, ContractName extends string, HorizonContractName extends string>(
  step: number,
  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  config: any,
  addressBook: AddressBook<ChainId, ContractName>,
  horizonAddressBook: AddressBook<ChainId, HorizonContractName>,
  // eslint-disable-next-line @typescript-eslint/no-explicit-any
): any {
  let patchedConfig = config

  switch (step) {
    case 2:
      const SubgraphService = addressBook.getEntry('SubgraphService')
      const DisputeManager = addressBook.getEntry('DisputeManager')
      const GraphTallyCollector = horizonAddressBook.getEntry('GraphTallyCollector')

      patchedConfig = patchConfig(config, {
        $global: {
          disputeManagerProxyAddress: DisputeManager.address,
          disputeManagerProxyAdminAddress: DisputeManager.proxyAdmin ?? ZERO_ADDRESS,
          subgraphServiceProxyAddress: SubgraphService.address,
        },
        SubgraphService: {
          subgraphServiceProxyAdminAddress: SubgraphService.proxyAdmin ?? ZERO_ADDRESS,
          graphTallyCollectorAddress: GraphTallyCollector.address,
        },
      })
      break
  }

  return patchedConfig
}
