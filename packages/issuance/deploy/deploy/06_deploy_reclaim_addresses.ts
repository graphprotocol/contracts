import type { HardhatRuntimeEnvironment } from 'hardhat/types'
import type { DeployFunction } from 'hardhat-deploy/types'

/**
 * Deploy DirectAllocation instances as reclaim addresses
 *
 * This script deploys DirectAllocation instances that can be used as:
 * - Reclaim addresses for token recovery
 * - General allocation targets
 * - Test allocation recipients
 *
 * DirectAllocation instances are simple proxy contracts using the DirectAllocation
 * implementation. They receive tokens via allocator-minting from IssuanceAllocator
 * and can reclaim tokens to a designated recipient.
 *
 * Configuration:
 * - Reclaim addresses are defined in deployment parameters or environment
 * - Each instance is deployed as a TransparentUpgradeableProxy
 * - All instances share the same DirectAllocation implementation
 * - Instances can be configured as allocation targets via IssuanceAllocator.setTargetAllocation()
 *
 * Naming convention:
 * - ReclaimAddress_<identifier> (e.g., ReclaimAddress_Treasury, ReclaimAddress_Test)
 *
 * Requirements:
 * - GraphToken must be deployed
 * - GraphIssuanceProxyAdmin must exist
 * - Governor account for initialization
 *
 * Usage:
 *   pnpm hardhat deploy --tags reclaim-addresses --network <network>
 */
const func: DeployFunction = async (hre: HardhatRuntimeEnvironment) => {
  const { deployments, getNamedAccounts } = hre
  const { deploy, log } = deployments
  const { deployer, governor } = await getNamedAccounts()

  // Require GraphToken from deployments JSON
  const graphTokenDep = await deployments.getOrNull('GraphToken')
  if (!graphTokenDep) {
    throw new Error(
      'Missing deployments/<network>/GraphToken.json. ' +
        'Create this file with the GraphToken address for your network.',
    )
  }
  const graphToken = graphTokenDep.address

  // Require GraphIssuanceProxyAdmin
  const proxyAdmin = await deployments.get('GraphIssuanceProxyAdmin')

  // Define reclaim addresses to deploy
  // These can be configured via deployment parameters or environment variables
  const reclaimAddresses = [
    {
      identifier: 'Treasury',
      recipient: governor, // Default to governor, can be configured
    },
    // Add more reclaim addresses as needed:
    // {
    //   identifier: 'CommunityPool',
    //   recipient: '0x...',
    // },
  ]

  log('Deploying DirectAllocation reclaim addresses...')

  for (const { identifier, recipient } of reclaimAddresses) {
    const deploymentName = `ReclaimAddress_${identifier}`

    log(`\nDeploying ${deploymentName}`)
    log(`  Recipient: ${recipient}`)
    log(`  GraphToken: ${graphToken}`)

    // Deploy DirectAllocation implementation (shared across all instances)
    const directAllocationImpl = await deploy('DirectAllocation_Implementation', {
      contract: 'DirectAllocation',
      from: deployer,
      args: [graphToken],
      log: true,
      skipIfAlreadyDeployed: true,
    })

    // Deploy proxy for this reclaim address
    const result = await deploy(deploymentName, {
      contract: 'TransparentUpgradeableProxy',
      from: deployer,
      args: [
        directAllocationImpl.address,
        proxyAdmin.address,
        // Initialize with recipient address
        directAllocationImpl.abi.find((f: any) => f.name === 'initialize')
          ? hre.ethers.AbiCoder.defaultAbiCoder().encode(['address'], [recipient])
          : '0x',
      ],
      log: true,
    })

    if (result.newlyDeployed) {
      log(`✓ ${deploymentName} deployed at ${result.address}`)
      log(`  Implementation: ${directAllocationImpl.address}`)
      log(`  Recipient: ${recipient}`)
    } else {
      log(`✓ ${deploymentName} already deployed at ${result.address}`)
    }
  }

  log('\nReclaim addresses deployment complete')
  log('To configure as allocation targets, use IssuanceAllocator.setTargetAllocation()')
}

func.tags = ['reclaim-addresses', 'direct-allocation']
func.dependencies = ['proxy-admin']
func.runAtTheEnd = true

export default func
