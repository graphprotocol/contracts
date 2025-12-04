import type { HardhatRuntimeEnvironment } from 'hardhat/types'
import { ethers } from 'hardhat'

// RewardsManager upgrade orchestrated via hardhat-deploy.
// Assumptions:
// - RewardsManager is an EXISTING legacy GraphProxy at a known address, provided via
//   hardhat-deploy deployments JSON (per-network) named `RewardsManager.json`.
// - GraphProxyAdmin that controls RewardsManager is also provided via deployments as `GraphProxyAdmin.json`.
// - This script compiles/loads the latest RewardsManager implementation artifact from contracts package,
//   deploys a new implementation when runtime bytecode differs, and performs
//   GraphProxyAdmin.upgrade(proxy, newImpl) from the `governor` named account.
// - No environment params are used here; addresses must come from per-network deployments JSON.

type DeployFunc = ((hre: HardhatRuntimeEnvironment) => Promise<void>) & { tags?: string[]; dependencies?: string[] }

const func: DeployFunc = async (hre: HardhatRuntimeEnvironment) => {
  const { deployments, getNamedAccounts, network, ethers: hhEthers } = hre
  const { getOrNull, deploy, log } = deployments
  const { deployer, governor } = await getNamedAccounts()

  if (!network.config.chainId) throw new Error('Missing chainId in network config')

  // 1) Load existing RewardsManager proxy from deployments
  const rewardsManagerDep = await getOrNull('RewardsManager')
  if (!rewardsManagerDep) {
    throw new Error(
      'Missing deployments/<network>/RewardsManager.json. Provide the existing proxy address via hardhat-deploy deployments.'
    )
  }

  const graphProxyAdminDep = (await getOrNull('GraphProxyAdmin')) || (await getOrNull('GraphLegacyProxyAdmin'))
  if (!graphProxyAdminDep) {
    throw new Error(
      'Missing deployments/<network>/GraphProxyAdmin.json (or GraphLegacyProxyAdmin.json). Provide legacy admin via deployments.'
    )
  }

  const proxyAddress = rewardsManagerDep.address
  const adminAddress = graphProxyAdminDep.address

  // 2) Load ABIs and Artifacts from monorepo packages
  const IGraphProxyAdminArtifact = require('../../interfaces/artifacts/contracts/contracts/upgrades/IGraphProxyAdmin.sol/IGraphProxyAdmin.json')
  const RewardsManagerArtifact = require('../../contracts/artifacts/contracts/rewards/RewardsManager.sol/RewardsManager.json')

  // 3) Resolve current implementation via GraphProxyAdmin
  const admin = new ethers.Contract(adminAddress, IGraphProxyAdminArtifact.abi, await hhEthers.getSigner(governor))
  const currentImpl: string = await admin.getProxyImplementation(proxyAddress)

  // 4) Compare runtime bytecode with compiled artifact's deployedBytecode
  const onchainCode = await hhEthers.provider.getCode(currentImpl)
  const compiledRuntime = RewardsManagerArtifact.deployedBytecode as string

  const normalize = (hex: string) => hex?.toLowerCase().replace(/^0x/, '')
  const equalBytecode = normalize(onchainCode) === normalize(compiledRuntime)

  if (equalBytecode) {
    log(`RewardsManager implementation already up-to-date at ${currentImpl}`)
    return
  }

  // 5) Deploy new implementation (no constructor args; initialization happens via upgrade if needed)
  const impl = await deploy('RewardsManager_Implementation', {
    from: deployer,
    log: true,
    // Use artifact object directly to avoid relying on this package's compiler paths
    contract: RewardsManagerArtifact,
    args: [],
  })

  // 6) Upgrade via GraphProxyAdmin using the governor named account
  log(`Upgrading RewardsManager proxy @ ${proxyAddress} to implementation ${impl.address}`)
  const tx = await admin.upgrade(proxyAddress, impl.address)
  log(`tx: ${tx.hash}`)
  await tx.wait()

  log('RewardsManager upgraded successfully')
}

func.tags = ['rewards-manager']
export default func
