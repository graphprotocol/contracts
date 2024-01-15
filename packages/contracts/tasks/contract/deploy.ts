import { task } from 'hardhat/config'

import { DeployType, GraphNetworkAddressBook, confirm, deploy } from '@graphprotocol/sdk'
import { GRE_TASK_PARAMS } from '@graphprotocol/sdk/gre'

task('contract:deploy', 'Deploy a contract')
  .addPositionalParam('contract', 'Name of the contract to deploy')
  .addPositionalParam(
    'init',
    'Initialization arguments for the contract constructor. Provide arguments as comma-separated values',
  )
  .addParam(
    'addressBook',
    GRE_TASK_PARAMS.addressBook.description,
    GRE_TASK_PARAMS.addressBook.default,
  )
  .addParam(
    'graphConfig',
    GRE_TASK_PARAMS.graphConfig.description,
    GRE_TASK_PARAMS.graphConfig.default,
  )
  .addParam('deployType', 'Choose deploy, deploy-save, deploy-with-proxy, deploy-with-proxy-save')
  .addFlag('disableSecureAccounts', 'Disable secure accounts on GRE')
  .addFlag('skipConfirmation', GRE_TASK_PARAMS.skipConfirmation.description)
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
        args: taskArgs.init.split(',') || [],
      },
      new GraphNetworkAddressBook(taskArgs.addressBook, graph.chainId),
    )
    console.log(`Contract deployed at ${deployment.contract.address}`)
  })
