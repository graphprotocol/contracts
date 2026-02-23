/**
 * Allocate-specific test fixtures
 * Deployment and setup functions for allocate contracts
 */

import fs from 'fs'
import { createRequire } from 'module'

import { getEthers, type HardhatEthersSigner } from '../common/ethersHelper'
import { Constants, deployTestGraphToken } from '../common/fixtures'
import { GraphTokenHelper } from '../common/graphTokenHelper'

// Create require for ESM compatibility (to resolve package paths)
const require = createRequire(import.meta.url)

/**
 * Deploy a contract as upgradeable proxy (manual implementation without OZ upgrades plugin)
 * Uses TransparentUpgradeableProxy pattern
 */
async function deployAsProxy(
  contractName: string,
  constructorArgs: unknown[],
  initializerArgs: unknown[],
  admin: HardhatEthersSigner,
) {
  const ethers = await getEthers()

  // Deploy implementation
  const Factory = await ethers.getContractFactory(contractName)
  const implementation = await Factory.deploy(...constructorArgs)
  await implementation.waitForDeployment()

  // Encode initializer call
  const initData = Factory.interface.encodeFunctionData('initialize', initializerArgs)

  // Load TransparentUpgradeableProxy artifact from @openzeppelin/contracts
  const proxyArtifactPath = require.resolve('@openzeppelin/contracts/build/contracts/TransparentUpgradeableProxy.json')
  const ProxyArtifact = JSON.parse(fs.readFileSync(proxyArtifactPath, 'utf8'))

  // Create proxy factory from artifact
  const ProxyFactory = new ethers.ContractFactory(ProxyArtifact.abi, ProxyArtifact.bytecode, admin)
  const proxy = await ProxyFactory.deploy(await implementation.getAddress(), admin.address, initData)
  await proxy.waitForDeployment()

  // Return contract instance attached to proxy address
  return Factory.attach(await proxy.getAddress())
}

/**
 * Deploy the IssuanceAllocator contract with proxy
 * @param {string} graphToken
 * @param {HardhatEthersSigner} governor
 * @param {bigint} issuancePerBlock
 * @returns {Promise<any>}
 */
export async function deployIssuanceAllocator(
  graphToken: string,
  governor: HardhatEthersSigner,
  issuancePerBlock: bigint,
) {
  // Deploy with proxy
  const issuanceAllocator = await deployAsProxy(
    'IssuanceAllocator',
    [graphToken], // constructor args
    [governor.address], // initialize args
    governor,
  )

  // Set issuance per block
  await (issuanceAllocator as any).connect(governor).setIssuancePerBlock(issuancePerBlock)

  return issuanceAllocator
}

/**
 * Deploy the DirectAllocation contract with proxy
 * @param {string} graphToken
 * @param {HardhatEthersSigner} governor
 * @returns {Promise<any>}
 */
export async function deployDirectAllocation(graphToken: string, governor: HardhatEthersSigner) {
  // Deploy with proxy
  return deployAsProxy(
    'DirectAllocation',
    [graphToken], // constructor args
    [governor.address], // initialize args
    governor,
  )
}

/**
 * Deploy allocate-only system (IssuanceAllocator + DirectAllocation targets)
 * This version excludes eligibility contracts for clean separation in tests
 * @param {Object} accounts
 * @param {bigint} [issuancePerBlock=Constants.DEFAULT_ISSUANCE_PER_BLOCK]
 * @returns {Promise<Object>}
 */
export async function deployAllocateSystem(
  accounts: { governor: HardhatEthersSigner },
  issuancePerBlock: bigint = Constants.DEFAULT_ISSUANCE_PER_BLOCK,
) {
  const { governor } = accounts

  // Deploy test GraphToken
  const graphToken = await deployTestGraphToken()
  const graphTokenAddress = await graphToken.getAddress()

  // Deploy IssuanceAllocator
  const issuanceAllocator = await deployIssuanceAllocator(graphTokenAddress, governor, issuancePerBlock)

  // Add the IssuanceAllocator as a minter on the GraphToken
  const graphTokenHelper = new GraphTokenHelper(graphToken as any, governor)
  await graphTokenHelper.addMinter(await issuanceAllocator.getAddress())

  // Deploy DirectAllocation targets
  const target1 = await deployDirectAllocation(graphTokenAddress, governor)
  const target2 = await deployDirectAllocation(graphTokenAddress, governor)

  return {
    graphToken,
    issuanceAllocator,
    target1,
    target2,
  }
}
