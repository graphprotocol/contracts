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
  const { deploy, execute } = deployments
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

  // hardhat-deploy proxy options (cast to bypass strict typing in this workspace)
  const proxyOpts = {
    owner: governor,
    proxyContract: 'OpenZeppelinTransparentProxy',
    execute: {
      init: {
        methodName: 'initialize',
        args: [governor],
      },
    },
  } as unknown as never

  // 1) Deploy proxied contracts using hardhat-deploy proxy pattern
  const ia = await deploy('IssuanceAllocator', {
    contract: 'IssuanceAllocator',
    from: deployer,
    log: true,
    args: [GRAPH_TOKEN],
    proxy: proxyOpts,
  })

  const reo = await deploy('RewardsEligibilityOracle', {
    contract: 'RewardsEligibilityOracle',
    from: deployer,
    log: true,
    args: [GRAPH_TOKEN],
    proxy: proxyOpts,
  })

  // Post-deploy governance acceptOwnership calls (idempotent/no-op if already accepted)
  if (ia.newlyDeployed) {
    await execute('IssuanceAllocator', { from: governor, log: true }, 'acceptOwnership')
  }
  if (reo.newlyDeployed) {
    await execute('RewardsEligibilityOracle', { from: governor, log: true }, 'acceptOwnership')
  }
}

func.tags = ['issuance']
export default func
