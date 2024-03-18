import { greTask } from '@graphprotocol/sdk/gre'
import { deploy, DeployType, GraphNetworkAddressBook } from '@graphprotocol/sdk'

greTask('contract:upgrade', 'Upgrades a contract')
  .addParam('contract', 'Name of the contract to upgrade')
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
    const { contract: implementation } = await deploy(
      DeployType.DeployImplementationAndSave,
      deployer,
      {
        name: taskArgs.contract,
        args: taskArgs.init || [],
      },
      new GraphNetworkAddressBook(taskArgs.addressBook, graph.chainId),
    )
    console.log(`New implementation deployed at ${implementation.address}`)

    // Upgrade proxy and accept implementation
    await GraphProxyAdmin.connect(governor).upgrade(contract.address, implementation.address)
    await GraphProxyAdmin.connect(governor).acceptProxy(implementation.address, contract.address)
    console.log(`Proxy upgraded to ${implementation.address}`)
  })
