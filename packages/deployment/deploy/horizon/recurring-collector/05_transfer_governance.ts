import { OZ_PROXY_ADMIN_ABI } from '@graphprotocol/deployment/lib/abis.js'
import { Contracts } from '@graphprotocol/deployment/lib/contract-registry.js'
import { getGovernor } from '@graphprotocol/deployment/lib/controller-utils.js'
import { DeploymentActions } from '@graphprotocol/deployment/lib/deployment-tags.js'
import {
  getProxyAdminAddress,
  requireContract,
  requireDeployer,
} from '@graphprotocol/deployment/lib/issuance-deploy-utils.js'
import { createActionModule } from '@graphprotocol/deployment/lib/script-factories.js'
import { graph, tx } from '@graphprotocol/deployment/rocketh/deploy.js'
import type { PublicClient } from 'viem'
import { encodeFunctionData } from 'viem'

/**
 * Transfer RecurringCollector ProxyAdmin to protocol governor
 *
 * RC doesn't use BaseUpgradeable GOVERNOR_ROLE — only ProxyAdmin needs transfer.
 *
 * Idempotent: checks current owner, skips if already governor.
 *
 * Usage:
 *   pnpm hardhat deploy --tags RecurringCollector,transfer --network <network>
 */
export default createActionModule(Contracts.horizon.RecurringCollector, DeploymentActions.TRANSFER, async (env) => {
  const client = graph.getPublicClient(env) as PublicClient
  const deployer = requireDeployer(env)
  const governor = await getGovernor(env)
  const rc = requireContract(env, Contracts.horizon.RecurringCollector)

  env.showMessage(`\n========== Transfer ${Contracts.horizon.RecurringCollector.name} ==========`)

  // Read ProxyAdmin from ERC1967 slot
  const proxyAdminAddress = await getProxyAdminAddress(client, rc.address)

  const currentOwner = (await client.readContract({
    address: proxyAdminAddress as `0x${string}`,
    abi: OZ_PROXY_ADMIN_ABI,
    functionName: 'owner',
  })) as string

  if (currentOwner.toLowerCase() === governor.toLowerCase()) {
    env.showMessage(`  ✓ ProxyAdmin already owned by governor\n`)
    return
  }

  if (currentOwner.toLowerCase() !== deployer.toLowerCase()) {
    env.showMessage(`  ○ ProxyAdmin owned by ${currentOwner}, not deployer — skipping\n`)
    return
  }

  env.showMessage(`  Transferring ProxyAdmin ownership to governor...`)
  env.showMessage(`    ProxyAdmin: ${proxyAdminAddress}`)
  env.showMessage(`    From: ${deployer}`)
  env.showMessage(`    To: ${governor}`)

  const txFn = tx(env)
  await txFn({
    account: deployer,
    to: proxyAdminAddress as `0x${string}`,
    data: encodeFunctionData({
      abi: OZ_PROXY_ADMIN_ABI,
      functionName: 'transferOwnership',
      args: [governor as `0x${string}`],
    }),
  })

  env.showMessage(`  ✓ ProxyAdmin ownership transferred to governor\n`)
})
