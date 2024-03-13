import consola from 'consola'
import { utils } from 'ethers'

import '@nomiclabs/hardhat-ethers'
import { HardhatRuntimeEnvironment } from 'hardhat/types'
import { DeployFunction, DeployOptions } from 'hardhat-deploy/types'

import { GraphTokenMock } from '../build/typechain/contracts/GraphTokenMock'
import { GraphTokenLockManager } from '../build/typechain/contracts/GraphTokenLockManager'
import { askConfirm, getDeploymentName, promptContractAddress } from './lib/utils'

const { parseEther, formatEther } = utils

const logger = consola.create({})

const func: DeployFunction = async function (hre: HardhatRuntimeEnvironment) {
  const deploy = (name: string, options: DeployOptions) => hre.deployments.deploy(name, options)
  const { deployer } = await hre.getNamedAccounts()

  // -- Graph Token --

  // Get the token address we will use
  const tokenAddress = await promptContractAddress('L1 GRT', logger)
  if (!tokenAddress) {
    logger.warn('No token address provided')
    process.exit(1)
  }

  // -- Token Lock Manager --

  // Deploy the master copy of GraphTokenLockWallet
  logger.info('Deploying GraphTokenLockWallet master copy...')
  const masterCopySaveName = await getDeploymentName('GraphTokenLockWallet')
  const masterCopyDeploy = await deploy(masterCopySaveName, {
    from: deployer,
    log: true,
    contract: 'GraphTokenLockWallet',
  })

  // Deploy the Manager that uses the master copy to clone contracts
  logger.info('Deploying GraphTokenLockManager...')
  const managerSaveName = await getDeploymentName('GraphTokenLockManager')
  const managerDeploy = await deploy(managerSaveName, {
    from: deployer,
    args: [tokenAddress, masterCopyDeploy.address],
    log: true,
    contract: 'GraphTokenLockManager',
  })

  // -- Fund --

  if (await askConfirm('Do you want to fund the manager?')) {
    const fundAmount = parseEther('100000000')
    logger.info(`Funding ${managerDeploy.address} with ${formatEther(fundAmount)} GRT...`)

    // Approve
    const grt = (await hre.ethers.getContractAt('GraphTokenMock', tokenAddress)) as GraphTokenMock
    await grt.approve(managerDeploy.address, fundAmount)

    // Deposit
    const manager = (await hre.ethers.getContractAt(
      'GraphTokenLockManager',
      managerDeploy.address,
    )) as GraphTokenLockManager
    await manager.deposit(fundAmount)

    logger.success('Done!')
  }
}

func.tags = ['manager', 'l1', 'l1-manager', 'l1-wallet']

export default func
