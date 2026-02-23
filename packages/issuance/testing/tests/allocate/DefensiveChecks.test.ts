import fs from 'fs'
import { createRequire } from 'module'

import { getEthers, type HardhatEthersSigner } from '../common/ethersHelper'
import { deployTestGraphToken, getTestAccounts } from '../common/fixtures'

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

describe('IssuanceAllocator - Defensive Checks', function () {
  let accounts: any
  let issuanceAllocator: any
  let graphToken: any

  beforeEach(async function () {
    accounts = await getTestAccounts()
    graphToken = await deployTestGraphToken()

    // Deploy test harness using manual proxy deployment
    issuanceAllocator = await deployAsProxy(
      'IssuanceAllocatorTestHarness',
      [await graphToken.getAddress()], // constructor args
      [accounts.governor.address], // initialize args
      accounts.governor,
    )

    // Add IssuanceAllocator as minter
    await graphToken.connect(accounts.governor).addMinter(await issuanceAllocator.getAddress())
  })

  describe('_distributePendingProportionally defensive checks', function () {
    it('should return early when allocatedRate is 0', async function () {
      // Call exposed function with allocatedRate = 0
      // This should return early without reverting
      await issuanceAllocator.exposedDistributePendingProportionally(
        100, // available
        0, // allocatedRate = 0 (defensive check)
        1000, // toBlockNumber
      )
    })

    it('should return early when available is 0', async function () {
      // Call exposed function with available = 0
      // This should return early without reverting
      await issuanceAllocator.exposedDistributePendingProportionally(
        0, // available = 0 (defensive check)
        100, // allocatedRate
        1000, // toBlockNumber
      )
    })

    it('should return early when both are 0', async function () {
      // Call exposed function with both = 0
      // This should return early without reverting
      await issuanceAllocator.exposedDistributePendingProportionally(
        0, // available = 0
        0, // allocatedRate = 0
        1000, // toBlockNumber
      )
    })
  })
})
