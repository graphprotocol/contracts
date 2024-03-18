import consola from 'consola'

import '@nomiclabs/hardhat-ethers'
import { HardhatRuntimeEnvironment } from 'hardhat/types'
import { DeployFunction } from 'hardhat-deploy/types'

import { getDeploymentName, promptContractAddress } from './lib/utils'
import { ethers, upgrades } from 'hardhat'
import { L1GraphTokenLockTransferTool } from '../build/typechain/contracts/L1GraphTokenLockTransferTool'
import path from 'path'
import { Artifacts } from 'hardhat/internal/artifacts'

const logger = consola.create({})

const ARTIFACTS_PATH = path.resolve('build/artifacts')
const artifacts = new Artifacts(ARTIFACTS_PATH)
const l2TransferToolAbi = artifacts.readArtifactSync('L2GraphTokenLockTransferTool').abi

const func: DeployFunction = async function (hre: HardhatRuntimeEnvironment) {
  // -- Graph Token --

  // Get the addresses we will use
  const tokenAddress = await promptContractAddress('L2 GRT', logger)
  if (!tokenAddress) {
    logger.warn('No token address provided')
    process.exit(1)
  }

  const l2Gateway = await promptContractAddress('L2 token gateway', logger)
  if (!l2Gateway) {
    logger.warn('No L2 gateway address provided')
    process.exit(1)
  }

  const l1Token = await promptContractAddress('L1 GRT', logger)
  if (!l1Token) {
    logger.warn('No L1 GRT address provided')
    process.exit(1)
  }

  // Deploy the L2GraphTokenLockTransferTool with a proxy.
  // hardhat-deploy doesn't get along with constructor arguments in the implementation
  // combined with an OpenZeppelin transparent proxy, so we need to do this using
  // the OpenZeppelin hardhat-upgrades tooling, and save the deployment manually.

  // TODO modify this to use upgradeProxy if a deployment already exists?
  logger.info('Deploying L2GraphTokenLockTransferTool proxy...')
  const transferToolFactory = await ethers.getContractFactory('L2GraphTokenLockTransferTool')
  const transferTool = (await upgrades.deployProxy(transferToolFactory, [], {
    kind: 'transparent',
    unsafeAllow: ['state-variable-immutable', 'constructor'],
    constructorArgs: [tokenAddress, l2Gateway, l1Token],
  })) as L1GraphTokenLockTransferTool

  // Save the deployment
  const deploymentName = await getDeploymentName('L2GraphTokenLockTransferTool')
  await hre.deployments.save(deploymentName, {
    abi: l2TransferToolAbi,
    address: transferTool.address,
    transactionHash: transferTool.deployTransaction.hash,
  })
}

func.tags = ['l2', 'l2-transfer-tool']

export default func
