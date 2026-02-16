/**
 * Signal-specific test fixtures
 * Deployment and setup functions for IndexingSignal contracts
 */

import fs from 'fs'
import { createRequire } from 'module'
import { ethers as ethersLib } from 'ethers'

import { getEthers, type HardhatEthersSigner } from '../common/ethersHelper'
import { deployTestGraphToken, getTestAccounts, type TestAccounts } from '../common/fixtures'
import { GraphTokenHelper } from '../common/graphTokenHelper'

// Create require for ESM compatibility
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
 * Deploy a MockRewardsManager
 */
export async function deployMockRewardsManager() {
  const ethers = await getEthers()
  const Factory = await ethers.getContractFactory('MockRewardsManager')
  const mock = await Factory.deploy()
  await mock.waitForDeployment()
  return mock
}

/**
 * Deploy the IndexingSignal contract with proxy
 */
export async function deployIndexingSignal(
  graphTokenAddress: string,
  rewardsManagerAddress: string,
  curationAddress: string,
  escrowRouterAddress: string,
  graphPaymentsAddress: string,
  governor: HardhatEthersSigner,
  minimumIndexerCount: number,
) {
  return deployAsProxy(
    'IndexingSignalTestHarness',
    [graphTokenAddress, rewardsManagerAddress, curationAddress, escrowRouterAddress, graphPaymentsAddress], // constructor args
    [governor.address, minimumIndexerCount], // initialize args
    governor,
  )
}

/**
 * Standard test subgraph deployment IDs
 */
export const SUBGRAPH_IDS = {
  SUBGRAPH_A: ethersLib.keccak256(ethersLib.toUtf8Bytes('subgraph-a')),
  SUBGRAPH_B: ethersLib.keccak256(ethersLib.toUtf8Bytes('subgraph-b')),
}

/**
 * Role constants for IndexingSignal
 */
export const ROLES = {
  GOVERNOR_ROLE: ethersLib.keccak256(ethersLib.toUtf8Bytes('GOVERNOR_ROLE')),
  INDEXER_SET_OPERATOR_ROLE: ethersLib.keccak256(ethersLib.toUtf8Bytes('INDEXER_SET_OPERATOR_ROLE')),
  PAUSE_ROLE: ethersLib.keccak256(ethersLib.toUtf8Bytes('PAUSE_ROLE')),
}

/**
 * Default issuance per block for tests
 */
export const DEFAULT_ISSUANCE_PER_BLOCK = ethersLib.parseEther('100')

/**
 * Deployed system for IndexingSignal tests
 */
export interface IndexingSignalSystem {
  graphToken: any
  graphTokenHelper: GraphTokenHelper
  mockRewardsManager: any
  indexingSignal: any
  curationAddress: string
  accounts: TestAccounts
  addresses: {
    graphToken: string
    mockRewardsManager: string
    indexingSignal: string
    curation: string
  }
}

/**
 * Deploy complete IndexingSignal system for testing
 */
export async function deployIndexingSignalSystem(
  minimumIndexerCount = 3,
  issuancePerBlock = DEFAULT_ISSUANCE_PER_BLOCK,
): Promise<IndexingSignalSystem> {
  const accounts = await getTestAccounts()
  const { governor } = accounts

  // Deploy GraphToken
  const graphToken = await deployTestGraphToken()
  const graphTokenAddress = await graphToken.getAddress()
  const graphTokenHelper = new GraphTokenHelper(graphToken as any, governor)

  // Deploy MockRewardsManager
  const mockRewardsManager = await deployMockRewardsManager()
  const rewardsManagerAddress = await mockRewardsManager.getAddress()
  await (mockRewardsManager as any).setAllocatedIssuancePerBlock(issuancePerBlock)

  // Use a dedicated signer address as "curation" — just needs to hold GRT
  // We use a deterministic address; any EOA can be the curation contract for testing
  const ethers = await getEthers()
  const signers = await ethers.getSigners()
  const curationSigner = signers[8] // Use signer index 8 to avoid conflict with test accounts
  const curationAddress = curationSigner.address

  // Use dedicated signer addresses as mock escrow router and graph payments
  const escrowRouterSigner = signers[9]
  const graphPaymentsSigner = signers[10]
  const escrowRouterAddress = escrowRouterSigner.address
  const graphPaymentsAddress = graphPaymentsSigner.address

  // Deploy IndexingSignal
  const indexingSignal = await deployIndexingSignal(
    graphTokenAddress,
    rewardsManagerAddress,
    curationAddress,
    escrowRouterAddress,
    graphPaymentsAddress,
    governor,
    minimumIndexerCount,
  )
  const indexingSignalAddress = await indexingSignal.getAddress()

  // Grant minter role to IndexingSignal so it can mint GRT on collect
  await graphTokenHelper.addMinter(indexingSignalAddress)

  // Grant INDEXER_SET_OPERATOR_ROLE to operator
  await (indexingSignal as any).connect(governor).grantRole(ROLES.INDEXER_SET_OPERATOR_ROLE, accounts.operator.address)

  return {
    graphToken,
    graphTokenHelper,
    mockRewardsManager,
    indexingSignal,
    curationAddress,
    accounts,
    addresses: {
      graphToken: graphTokenAddress,
      mockRewardsManager: rewardsManagerAddress,
      indexingSignal: indexingSignalAddress,
      curation: curationAddress,
    },
  }
}
