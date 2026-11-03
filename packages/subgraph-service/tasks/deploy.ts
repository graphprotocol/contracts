import { HorizonModule } from '@graphprotocol/horizon/ignition'
import { loadConfig, patchConfig, saveToAddressBook } from '@graphprotocol/toolshed/hardhat'
import { task, types } from 'hardhat/config'
import type { HardhatRuntimeEnvironment } from 'hardhat/types'

import Deploy1Module from '../ignition/modules/deploy/deploy-1'
import Deploy2Module from '../ignition/modules/deploy/deploy-2'

// Horizon needs the SubgraphService proxy address before it can be deployed
// But SubgraphService and DisputeManager implementations need Horizon...
// So the deployment order is:
// - Deploy SubgraphService and DisputeManager proxies
// - Deploy Horizon
// - Deploy SubgraphService and DisputeManager implementations
task('deploy:protocol', 'Deploy a new version of the Graph Protocol Horizon contracts - with Subgraph Service')
  .addOptionalParam(
    'subgraphServiceConfig',
    'Name of the Subgraph Service configuration file to use. Format is "protocol.<name>.json5", file must be in the "ignition/configs/" directory. Defaults to network name.',
    undefined,
    types.string,
  )
  .addOptionalParam(
    'horizonConfig',
    'Name of the Horizon configuration file to use. Format is "protocol.<name>.json5", file must be in the "ignition/configs/" directory in the horizon package. Defaults to network name.',
    undefined,
    types.string,
  )
  .setAction(async (args, hre: HardhatRuntimeEnvironment) => {
    const graph = hre.graph({ createAddressBook: true })

    // Load configuration files for the deployment
    console.log('\n========== ⚙️ Deployment configuration ==========')
    const { config: HorizonConfig, file: horizonFile } = loadConfig(
      './node_modules/@graphprotocol/horizon/ignition/configs',
      'protocol',
      args.horizonConfig ?? hre.network.name,
    )
    const { config: SubgraphServiceConfig, file: subgraphServiceFile } = loadConfig(
      './ignition/configs/',
      'protocol',
      args.subgraphServiceConfig ?? hre.network.name,
    )
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
          recurringCollectorAddress: horizonDeployment.Transparent_Proxy_RecurringCollector.target as string,
          gnsProxyAddress: horizonDeployment.Graph_Proxy_L2GNS.target as string,
          gnsImplementationAddress: horizonDeployment.Implementation_L2GNS.target as string,
          subgraphNFTAddress: horizonDeployment.SubgraphNFT.target as string,
        },
      }),
    })

    // Save the addresses to the address book
    console.log('\n========== 📖 Updating address book ==========')
    // @ts-expect-error - @graphprotocol/toolshed/hardhat exports ts files so types mismatch here
    saveToAddressBook(horizonDeployment, graph.horizon.addressBook)
    // @ts-expect-error - @graphprotocol/toolshed/hardhat exports ts files so types mismatch here
    saveToAddressBook(proxiesDeployment, graph.subgraphService.addressBook)
    // @ts-expect-error - @graphprotocol/toolshed/hardhat exports ts files so types mismatch here
    saveToAddressBook(subgraphServiceDeployment, graph.subgraphService.addressBook)
    console.log(`Address book at ${graph.horizon.addressBook.file} updated!`)
    console.log(`Address book at ${graph.subgraphService.addressBook.file} updated!`)
    console.log('Note that Horizon deployment addresses are updated in the Horizon address book')

    console.log('\n\n🎉 ✨ 🚀 ✅ Deployment complete! 🎉 ✨ 🚀 ✅')
  })
