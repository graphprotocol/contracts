import { loadConfig, saveToAddressBook } from '@graphprotocol/toolshed/hardhat'
import { task, types } from 'hardhat/config'
import type { HardhatRuntimeEnvironment } from 'hardhat/types'

import DeployModule from '../ignition/modules/deploy'

task('deploy:protocol', 'Deploy a new version of the Graph Protocol Horizon contracts - no data services deployed')
  .addOptionalParam(
    'horizonConfig',
    'Name of the Horizon configuration file to use. Format is "protocol.<name>.json5", file must be in the "ignition/configs/" directory. Defaults to network name.',
    undefined,
    types.string,
  )
  .addOptionalParam('accountIndex', 'Derivation path index for the account to use', 0, types.int)
  .setAction(async (args, hre: HardhatRuntimeEnvironment) => {
    const graph = hre.graph({ createAddressBook: true })

    // Load configuration for the deployment
    console.log('\n========== ⚙️ Deployment configuration ==========')
    const { config: HorizonConfig, file } = loadConfig(
      './ignition/configs/',
      'protocol',
      args.horizonConfig ?? hre.network.name,
    )
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
    // @ts-expect-error - @graphprotocol/toolshed/hardhat exports ts files so types mismatch here
    saveToAddressBook(deployment, graph.horizon.addressBook)
    console.log(`Address book at ${graph.horizon.addressBook.file} updated!`)

    console.log('\n\n🎉 ✨ 🚀 ✅ Deployment complete! 🎉 ✨ 🚀 ✅')
  })
