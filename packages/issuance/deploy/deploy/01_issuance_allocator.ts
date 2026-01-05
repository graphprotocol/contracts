import type { HardhatRuntimeEnvironment } from 'hardhat/types'
import type { DeployFunction } from 'hardhat-deploy/types'

/**
 * Deploy IssuanceAllocator - Token allocation contract with transparent proxy
 *
 * This deploys IssuanceAllocator as an upgradeable contract using OpenZeppelin's
 * TransparentUpgradeableProxy pattern. The contract is initialized atomically
 * during proxy deployment to prevent front-running attacks.
 *
 * Architecture:
 * - Implementation: IssuanceAllocator contract with GRT token constructor arg
 * - Proxy: TransparentUpgradeableProxy with atomic initialization
 * - Admin: GraphIssuanceProxyAdmin (deployed in 00_proxy_admin.ts)
 *
 * Deployment strategy:
 * - First run: Deploy implementation + proxy with atomic init
 * - Subsequent runs:
 *   - If implementation unchanged: No-op (reuse existing)
 *   - If implementation changed: Deploy new implementation, proxy remains
 *   - Upgrades must be done via governance (see upgrade tasks)
 *
 * Requirements:
 * - GraphToken address must be provided via deployments JSON
 * - GraphIssuanceProxyAdmin must exist
 * - Governor account for initialization
 *
 * Usage:
 *   pnpm hardhat deploy --tags issuance-allocator --network <network>
 */
const func: DeployFunction = async (hre: HardhatRuntimeEnvironment) => {
  const { deployments, getNamedAccounts } = hre
  const { deploy, log } = deployments
  const { deployer, governor } = await getNamedAccounts()

  // Require GraphToken from deployments JSON (hardhat-deploy convention)
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

  log(`Deploying IssuanceAllocator with GraphToken: ${graphToken}`)

  // Deploy using hardhat-deploy's proxy option for TransparentUpgradeableProxy
  // This handles implementation deployment, proxy deployment, and atomic initialization
  // Uses our custom GraphIssuanceProxyAdmin via viaAdminContract
  const result = await deploy('IssuanceAllocator', {
    from: deployer,
    contract: 'IssuanceAllocator',
    args: [graphToken], // Constructor args for implementation
    log: true,
    waitConfirmations: 1,
    proxy: {
      owner: governor, // Owner of the ProxyAdmin
      viaAdminContract: 'GraphIssuanceProxyAdmin', // Use our custom ProxyAdmin
      proxyContract: 'OpenZeppelinTransparentProxy',
      execute: {
        // Atomic initialization during proxy deployment
        init: {
          methodName: 'initialize',
          args: [governor],
        },
      },
    },
  })

  if (result.newlyDeployed) {
    log(`IssuanceAllocator proxy deployed at ${result.address}`)
    log(`IssuanceAllocator implementation at ${result.implementation}`)
    log(`Note: Ownership must be accepted by governor via acceptOwnership()`)
  } else {
    log(`IssuanceAllocator proxy already exists at ${result.address}`)
    if (result.implementation) {
      log(`Current implementation: ${result.implementation}`)
    }
  }
}

func.tags = ['issuance-allocator', 'issuance-core', 'issuance']
func.dependencies = ['proxy-admin'] // Requires GraphIssuanceProxyAdmin
func.id = 'IssuanceAllocator'

export default func
