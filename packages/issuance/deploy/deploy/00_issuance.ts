import { ethers } from 'hardhat'
import type { HardhatRuntimeEnvironment } from 'hardhat/types'

// Minimal PoC: Deploy ProxyAdmin, IssuanceAllocator + RewardsEligibilityOracle implementations,
// and TransparentUpgradeableProxy instances with atomic initialization. Then accept ownership.
//
// Requirements (env):
// - GRAPH_TOKEN: Address of the GRT token on target chain
//
// Usage:
//   pnpm --filter @graphprotocol/issuance-deploy hardhat deploy --tags issuance --network <network>
//
// Notes:
// - Keeps Ignition intact; this file is opt-in via tag "issuance".
// - Writes standard hardhat-deploy artifacts under deployments/<chainId>.

type DeployFunc = ((hre: HardhatRuntimeEnvironment) => Promise<void>) & { tags?: string[] }

const func: DeployFunc = async (hre: HardhatRuntimeEnvironment) => {
  const { deployments, getNamedAccounts, network } = hre
  const { deploy, execute, getArtifact } = deployments
  const { deployer, governor: governorNamed } = await getNamedAccounts()

  const chainId = network.config.chainId
  if (!chainId) throw new Error('Missing chainId in network config')

  // Require GraphToken to be provided via deployments JSON (hardhat-deploy way)
  const graphTokenDep = await deployments.getOrNull('GraphToken')
  if (!graphTokenDep) {
    throw new Error('Missing deployments/<network>/GraphToken.json (required)')
  }
  const GRAPH_TOKEN = graphTokenDep.address

  // Governor account: use named account only
  const governor = governorNamed

  // OpenZeppelin artifacts
  // Rely on node resolution across workspace (already used by Ignition modules)
  const ProxyAdminArtifact = require('@openzeppelin/contracts/build/contracts/ProxyAdmin.json')
  const TransparentUpgradeableProxyArtifact = require('@openzeppelin/contracts/build/contracts/TransparentUpgradeableProxy.json')

  // 1) Proxy Admin (governor as initial owner)
  // Reuse an existing OZ ProxyAdmin from deployments or deploy a new one
  const existingPA = await deployments.getOrNull('GraphIssuanceProxyAdmin')
  const proxyAdminAddress: string = existingPA
    ? existingPA.address
    : (
        await deploy('GraphIssuanceProxyAdmin', {
          from: deployer,
          log: true,
          args: [governor],
          contract: ProxyAdminArtifact,
        })
      ).address

  // Helper to deploy a proxied upgradeable with atomic init
  const deployProxied = async (
    name: string,
    implContractName: string,
    initMethod: string,
    implConstructorArgs: unknown[],
    initArgs: unknown[],
  ) => {
    const implArtifact = await getArtifact(implContractName)
    const impl = await deploy(`${name}_Implementation`, {
      contract: implArtifact,
      from: deployer,
      log: true,
      args: implConstructorArgs,
    })

    const iface = new ethers.utils.Interface(implArtifact.abi)
    const initData = iface.encodeFunctionData(initMethod, initArgs)

    const proxy = await deploy(name, {
      contract: TransparentUpgradeableProxyArtifact,
      from: deployer,
      log: true,
      args: [impl.address, proxyAdminAddress, initData],
    })

    return { impl, proxy }
  }

  // 2) IssuanceAllocator
  const ia = await deployProxied('IssuanceAllocator', 'IssuanceAllocator', 'initialize', [GRAPH_TOKEN], [governor])

  // 3) RewardsEligibilityOracle
  const reo = await deployProxied(
    'RewardsEligibilityOracle',
    'RewardsEligibilityOracle',
    'initialize',
    [GRAPH_TOKEN],
    [governor],
  )

  // Post-deploy governance acceptOwnership calls (idempotent/no-op if already accepted)
  if (ia.proxy.newlyDeployed) {
    await execute('IssuanceAllocator', { from: governor, log: true }, 'acceptOwnership')
  }
  if (reo.proxy.newlyDeployed) {
    await execute('RewardsEligibilityOracle', { from: governor, log: true }, 'acceptOwnership')
  }
}

func.tags = ['issuance']
export default func
