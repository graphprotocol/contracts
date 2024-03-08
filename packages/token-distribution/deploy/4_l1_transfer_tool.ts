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
const l1TransferToolAbi = artifacts.readArtifactSync('L1GraphTokenLockTransferTool').abi

const func: DeployFunction = async function (hre: HardhatRuntimeEnvironment) {
  const { deployer } = await hre.getNamedAccounts()

  // Get the addresses we will use
  const tokenAddress = await promptContractAddress('L1 GRT', logger)
  if (!tokenAddress) {
    logger.warn('No token address provided')
    process.exit(1)
  }

  const l2Implementation = await promptContractAddress('L2GraphTokenLockWallet implementation', logger)
  if (!l2Implementation) {
    logger.warn('No L2 implementation address provided')
    process.exit(1)
  }

  const l1Gateway = await promptContractAddress('L1 token gateway', logger)
  if (!l1Gateway) {
    logger.warn('No L1 gateway address provided')
    process.exit(1)
  }

  const l1Staking = await promptContractAddress('L1 Staking', logger)
  if (!l1Staking) {
    logger.warn('No L1 Staking address provided')
    process.exit(1)
  }

  let owner = await promptContractAddress('owner (optional)', logger)
  if (!owner) {
    owner = deployer
    logger.warn(`No owner address provided, will use the deployer address as owner: ${owner}`)
  }

  // Deploy the L1GraphTokenLockTransferTool with a proxy.
  // hardhat-deploy doesn't get along with constructor arguments in the implementation
  // combined with an OpenZeppelin transparent proxy, so we need to do this using
  // the OpenZeppelin hardhat-upgrades tooling, and save the deployment manually.

  // TODO modify this to use upgradeProxy if a deployment already exists?
  logger.info('Deploying L1GraphTokenLockTransferTool proxy...')
  const transferToolFactory = await ethers.getContractFactory('L1GraphTokenLockTransferTool')
  const transferTool = (await upgrades.deployProxy(transferToolFactory, [owner], {
    kind: 'transparent',
    unsafeAllow: ['state-variable-immutable', 'constructor'],
    constructorArgs: [tokenAddress, l2Implementation, l1Gateway, l1Staking],
  })) as L1GraphTokenLockTransferTool

  // Save the deployment
  const deploymentName = await getDeploymentName('L1GraphTokenLockTransferTool')
  await hre.deployments.save(deploymentName, {
    abi: l1TransferToolAbi,
    address: transferTool.address,
    transactionHash: transferTool.deployTransaction.hash,
  })
}

func.tags = ['l1', 'l1-transfer-tool']

export default func
