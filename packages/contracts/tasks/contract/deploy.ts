import { confirm, deploy, DeployType } from '@graphprotocol/sdk'
import { greTask } from '@graphprotocol/sdk/gre'

greTask('contract:deploy', 'Deploy a contract')
  .addPositionalParam('contract', 'Name of the contract to deploy')
  .addOptionalPositionalParam(
    'init',
    'Initialization arguments for the contract constructor. Provide arguments as comma-separated values',
  )
  .addParam('deployType', 'Choose deploy, deploy-save, deploy-with-proxy, deploy-with-proxy-save')
  .addFlag('skipConfirmation', 'Skip confirmation prompt on write actions')
  .addFlag('buildAcceptTx', '...')
  .setAction(async (taskArgs, hre) => {
    const graph = hre.graph(taskArgs)
    const deployer = await graph.getDeployer()

    if (!Object.values(DeployType).includes(taskArgs.deployType)) {
      throw new Error(`Deploy type ${taskArgs.deployType} not supported`)
    }

    console.log(`Deploying ${taskArgs.contract}...`)
    console.log(`Init: ${taskArgs.init}`)
    console.log(`Deploy type: ${taskArgs.deployType}`)
    console.log(`Deployer: ${deployer.address}`)
    console.log(`Chain ID: ${graph.chainId}`)

    const sure = await confirm(
      `Are you sure to deploy ${taskArgs.contract}?`,
      taskArgs.skipConfirmation,
    )
    if (!sure) return

    const deployment = await deploy(
      taskArgs.deployType,
      deployer,
      {
        name: taskArgs.contract,
        args: taskArgs.init?.split(',') || [],
      },
      graph.addressBook,
    )
    console.log(`Contract deployed at ${deployment.contract.address}`)
  })
