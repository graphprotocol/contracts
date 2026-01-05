import type { HardhatRuntimeEnvironment } from 'hardhat/types'
import type { DeployFunction } from 'hardhat-deploy/types'

/**
 * Deploy GraphIssuanceProxyAdmin - shared ProxyAdmin for all issuance contracts
 *
 * This deploys OpenZeppelin's ProxyAdmin contract that manages upgrades for all
 * issuance-related proxies (IssuanceAllocator, PilotAllocation, RewardsEligibilityOracle).
 *
 * The ProxyAdmin is owned by governance and can upgrade all issuance contract
 * implementations via governance transactions.
 *
 * Deployment strategy:
 * - First run: Deploy ProxyAdmin with governor as owner
 * - Subsequent runs: Reuse existing deployment (no changes)
 *
 * Usage:
 *   pnpm hardhat deploy --tags proxy-admin --network <network>
 */
const func: DeployFunction = async (hre: HardhatRuntimeEnvironment) => {
  const { deployments, getNamedAccounts } = hre
  const { deploy, log } = deployments
  const { deployer, governor } = await getNamedAccounts()

  // Check if GraphIssuanceProxyAdmin already exists (for reuse or upgrade scenarios)
  const existing = await deployments.getOrNull('GraphIssuanceProxyAdmin')
  if (existing) {
    log(`GraphIssuanceProxyAdmin already deployed at ${existing.address}`)
    return
  }

  // Deploy ProxyAdmin with governor as initial owner
  // OpenZeppelin ProxyAdmin constructor: constructor(address initialOwner)
  const result = await deploy('GraphIssuanceProxyAdmin', {
    from: deployer,
    contract: 'ProxyAdmin',
    args: [governor],
    log: true,
    waitConfirmations: 1,
  })

  if (result.newlyDeployed) {
    log(`GraphIssuanceProxyAdmin deployed at ${result.address} with owner ${governor}`)
  }
}

func.tags = ['proxy-admin', 'issuance-core']
func.id = 'GraphIssuanceProxyAdmin'

export default func
