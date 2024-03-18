import consola from 'consola'
import { utils } from 'ethers'

import '@nomiclabs/hardhat-ethers'
import { HardhatRuntimeEnvironment } from 'hardhat/types'
import { DeployFunction, DeployOptions } from 'hardhat-deploy/types'

import { GraphTokenMock } from '../build/typechain/contracts/GraphTokenMock'
import { askConfirm, getDeploymentName, promptContractAddress } from './lib/utils'
import { L2GraphTokenLockManager } from '../build/typechain/contracts/L2GraphTokenLockManager'

const { parseEther, formatEther } = utils

const logger = consola.create({})

const func: DeployFunction = async function (hre: HardhatRuntimeEnvironment) {
  const deploy = (name: string, options: DeployOptions) => hre.deployments.deploy(name, options)
  const { deployer } = await hre.getNamedAccounts()

  // -- Graph Token --

  // Get the token address we will use
  const tokenAddress = await promptContractAddress('L2 GRT', logger)
  if (!tokenAddress) {
    logger.warn('No token address provided')
    process.exit(1)
  }

  const l2Gateway = await promptContractAddress('L2 Gateway', logger)
  if (!l2Gateway) {
    logger.warn('No L2 Gateway address provided')
    process.exit(1)
  }

  const l1TransferTool = await promptContractAddress('L1 Transfer Tool', logger)
  if (!l1TransferTool) {
    logger.warn('No L1 Transfer Tool address provided')
    process.exit(1)
  }

  // -- L2 Token Lock Manager --
  // Get the deployed L2GraphTokenLockWallet master copy address
  const masterCopyDeploy = await hre.deployments.get('L2GraphTokenLockWallet')

  logger.info(`Using L2GraphTokenLockWallet at address: ${masterCopyDeploy.address}`)
  // Deploy the Manager that uses the master copy to clone contracts
  logger.info('Deploying L2GraphTokenLockManager...')
  const managerSaveName = await getDeploymentName('L2GraphTokenLockManager')
  const managerDeploy = await deploy(managerSaveName, {
    from: deployer,
    args: [tokenAddress, masterCopyDeploy.address, l2Gateway, l1TransferTool],
    log: true,
    contract: 'L2GraphTokenLockManager',
  })

  // -- Fund --

  if (await askConfirm('Do you want to fund the L2 manager?')) {
    const fundAmount = parseEther('100000000')
    logger.info(`Funding ${managerDeploy.address} with ${formatEther(fundAmount)} GRT...`)

    // Approve
    const grt = (await hre.ethers.getContractAt('GraphTokenMock', tokenAddress)) as GraphTokenMock
    await grt.approve(managerDeploy.address, fundAmount)

    // Deposit
    const manager = (await hre.ethers.getContractAt(
      'L2GraphTokenLockManager',
      managerDeploy.address,
    )) as L2GraphTokenLockManager
    await manager.deposit(fundAmount)

    logger.success('Done!')
  }
}

func.tags = ['l2-manager', 'l2']

export default func
