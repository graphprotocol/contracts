import { ethers } from 'hardhat'
import type { HardhatRuntimeEnvironment } from 'hardhat/types'

import { loadParams } from './lib/params'

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

  const params = await loadParams(hre)

  const isAddressCompat = (addr: string | undefined): addr is string => {
    if (!addr) return false
    try {
      const e = ethers as unknown as {
        utils?: { getAddress?: (a: string) => string }
        getAddress?: (a: string) => string
      }
      if (e.utils && typeof e.utils.getAddress === 'function') {
        e.utils.getAddress(addr)
        return true
      }
      if (typeof e.getAddress === 'function') {
        e.getAddress(addr)
        return true
      }
      return false
    } catch {
      return false
    }
  }
  const GRAPH_TOKEN = params.graphToken
  if (!isAddressCompat(GRAPH_TOKEN)) {
    throw new Error('GraphToken address not provided. Set GRAPH_TOKEN env var or config/<network>.json')
  }

  // Governor account: env override wins, else named account
  const governor = params.governor ?? governorNamed

  // OpenZeppelin artifacts
  // Rely on node resolution across workspace (already used by Ignition modules)
  const ProxyAdminArtifact = require('@openzeppelin/contracts/build/contracts/ProxyAdmin.json')
  const TransparentUpgradeableProxyArtifact = require('@openzeppelin/contracts/build/contracts/TransparentUpgradeableProxy.json')

  // 1) Proxy Admin (governor as initial owner)
  // Either reuse an existing OZ ProxyAdmin (graphIssuanceProxyAdmin/config) or deploy a new one
  let proxyAdminAddress: string
  if (isAddressCompat(params.graphIssuanceProxyAdmin)) {
    proxyAdminAddress = params.graphIssuanceProxyAdmin
  } else {
    const pa = await deploy('GraphIssuanceProxyAdmin', {
      from: deployer,
      log: true,
      args: [governor],
      contract: ProxyAdminArtifact,
    })
    proxyAdminAddress = pa.address
  }

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
