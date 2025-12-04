import type { HardhatRuntimeEnvironment } from 'hardhat/types'

// RewardsManager upgrade orchestrated via hardhat-deploy with minimal custom code.
// Assumptions:
// - RewardsManager is an EXISTING legacy GraphProxy at a known address provided via
//   hardhat-deploy deployments JSON `deployments/<network>/RewardsManager.json`.
// - GraphProxyAdmin (legacy) is provided via `deployments/<network>/GraphProxyAdmin.json` (or GraphLegacyProxyAdmin.json).
// - We rely on hardhat-deploy to deploy a new implementation only when the artifact changed;
//   then we compare current implementation address and call `upgrade` if needed.
// - No env/config params here; addresses come from deployments JSON (the hardhat-deploy way).

type DeployFunc = ((hre: HardhatRuntimeEnvironment) => Promise<void>) & { tags?: string[]; dependencies?: string[] }

const func: DeployFunc = async (hre: HardhatRuntimeEnvironment) => {
  const { deployments, getNamedAccounts, network } = hre
  const { getOrNull, deploy, log, getArtifact, read, execute } = deployments
  const { deployer, governor } = await getNamedAccounts()

  if (!network.config.chainId) throw new Error('Missing chainId in network config')

  // 1) Load existing RewardsManager proxy from deployments
  const rewardsManagerDep = await getOrNull('RewardsManager')
  if (!rewardsManagerDep) {
    throw new Error(
      'Missing deployments/<network>/RewardsManager.json. Provide the existing proxy address via hardhat-deploy deployments.',
    )
  }

  const adminPrimary = await getOrNull('GraphProxyAdmin')
  const adminLegacy = adminPrimary ? undefined : await getOrNull('GraphLegacyProxyAdmin')
  if (!adminPrimary && !adminLegacy) {
    throw new Error(
      'Missing deployments/<network>/GraphProxyAdmin.json (or GraphLegacyProxyAdmin.json). Provide legacy admin via deployments.',
    )
  }

  const proxyAddress = rewardsManagerDep.address
  const adminName = adminPrimary ? 'GraphProxyAdmin' : 'GraphLegacyProxyAdmin'

  // 2) Deploy (or reuse) the latest implementation with hardhat-deploy
  // If bytecode is unchanged, hardhat-deploy will skip and return the existing deployment
  const RewardsManagerArtifact = await getArtifact('RewardsManager')
  const impl = await deploy('RewardsManager_Implementation', {
    from: deployer,
    log: true,
    contract: RewardsManagerArtifact,
    args: [],
  })

  // 3) Compare addresses: if current implementation matches, no-op; else upgrade
  const currentImpl: string = await read(adminName, 'getProxyImplementation', proxyAddress)
  if (currentImpl?.toLowerCase() === impl.address.toLowerCase()) {
    log(`RewardsManager implementation already up-to-date at ${currentImpl}`)
    return
  }

  log(`Upgrading RewardsManager proxy @ ${proxyAddress} to implementation ${impl.address}`)
  await execute(adminName, { from: governor, log: true }, 'upgrade', proxyAddress, impl.address)
  log('RewardsManager upgraded successfully')
}

func.tags = ['rewards-manager']
export default func
