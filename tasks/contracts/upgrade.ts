import { task } from 'hardhat/config'

import { cliOpts } from '../../cli/defaults'
import { deployContractImplementationAndSave } from '../../cli/network'
import { getAddressBook } from '../../cli/address-book'

task('contracts:upgrade', 'Upgrades a contract')
  .addParam('contract', 'Name of the contract to upgrade')
  .addFlag('disableSecureAccounts', 'Disable secure accounts on GRE')
  .addOptionalParam('graphConfig', cliOpts.graphConfig.description, cliOpts.graphConfig.default)
  .addOptionalParam('addressBook', cliOpts.addressBook.description, cliOpts.addressBook.default)
  .addOptionalVariadicPositionalParam(
    'init',
    'Initialization arguments for the contract constructor',
  )
  .setAction(async (taskArgs, hre) => {
    const graph = hre.graph(taskArgs)

    const { GraphProxyAdmin } = graph.contracts
    const { governor } = await graph.getNamedAccounts()
    const deployer = await graph.getDeployer()

    const contract = graph.contracts[taskArgs.contract]
    if (!contract) {
      throw new Error(`Contract ${taskArgs.contract} not found in address book`)
    }
    console.log(`Upgrading ${taskArgs.contract}...`)

    // Deploy new implementation
    const implementation = await deployContractImplementationAndSave(
      taskArgs.contract,
      taskArgs.init || [],
      deployer,
      getAddressBook(taskArgs.addressBook, graph.chainId.toString()),
    )
    console.log(`New implementation deployed at ${implementation.address}`)

    // Upgrade proxy and accept implementation
    await GraphProxyAdmin.connect(governor).upgrade(contract.address, implementation.address)
    await GraphProxyAdmin.connect(governor).acceptProxy(implementation.address, contract.address)
    console.log(`Proxy upgraded to ${implementation.address}`)
  })
