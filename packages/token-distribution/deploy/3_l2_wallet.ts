import consola from 'consola'
import '@nomiclabs/hardhat-ethers'
import { HardhatRuntimeEnvironment } from 'hardhat/types'
import { DeployFunction, DeployOptions } from 'hardhat-deploy/types'

import { getDeploymentName } from './lib/utils'

const logger = consola.create({})

const func: DeployFunction = async function (hre: HardhatRuntimeEnvironment) {
  const deploy = (name: string, options: DeployOptions) => hre.deployments.deploy(name, options)
  const { deployer } = await hre.getNamedAccounts()

  // Deploy the master copy of GraphTokenLockWallet
  logger.info('Deploying L2GraphTokenLockWallet master copy...')
  const masterCopySaveName = await getDeploymentName('L2GraphTokenLockWallet')
  await deploy(masterCopySaveName, {
    from: deployer,
    log: true,
    contract: 'L2GraphTokenLockWallet',
  })
}

func.tags = ['l2-wallet', 'l2']

export default func
