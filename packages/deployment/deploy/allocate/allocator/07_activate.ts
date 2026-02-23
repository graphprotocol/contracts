import { GRAPH_TOKEN_ABI, ISSUANCE_TARGET_ABI, REWARDS_MANAGER_ABI } from '@graphprotocol/deployment/lib/abis.js'
import { getTargetChainIdFromEnv } from '@graphprotocol/deployment/lib/address-book-utils.js'
import { requireRewardsManagerUpgraded } from '@graphprotocol/deployment/lib/contract-checks.js'
import { Contracts } from '@graphprotocol/deployment/lib/contract-registry.js'
import { getGovernor } from '@graphprotocol/deployment/lib/controller-utils.js'
import { ComponentTags, Tags } from '@graphprotocol/deployment/lib/deployment-tags.js'
import { createGovernanceTxBuilder, saveGovernanceTxAndExit } from '@graphprotocol/deployment/lib/execute-governance.js'
import { requireContracts, requireDeployer } from '@graphprotocol/deployment/lib/issuance-deploy-utils.js'
import { graph } from '@graphprotocol/deployment/rocketh/deploy.js'
import type { DeployScriptModule } from '@rocketh/core/types'
import type { PublicClient } from 'viem'
import { encodeFunctionData } from 'viem'

/**
 * Activate ${Contracts.issuance.IssuanceAllocator.name} in the protocol (governance account)
 *
 * Steps 8-10 from IssuanceAllocator.md:
 * - Configure RewardsManager to use IssuanceAllocator
 * - Grant minter role to IssuanceAllocator on GraphToken
 * - (Optional) Set default target for unallocated issuance
 *
 * Idempotent: checks on-chain state, skips if already activated.
 * Generates Safe TX batch for governance execution.
 * Does NOT execute - governance must execute via Safe or deploy:execute-governance.
 *
 * Usage:
 *   pnpm hardhat deploy --tags issuance-activation --network <network>
 */
const func: DeployScriptModule = async (env) => {
  const deployer = requireDeployer(env)

  // Get protocol governor from Controller
  const governor = await getGovernor(env)

  const [issuanceAllocator, rewardsManager, graphToken] = requireContracts(env, [
    Contracts.issuance.IssuanceAllocator,
    Contracts.horizon.RewardsManager,
    Contracts.horizon.L2GraphToken,
  ])

  const iaAddress = issuanceAllocator.address
  const rmAddress = rewardsManager.address
  const gtAddress = graphToken.address

  // Create viem client for direct contract calls
  const client = graph.getPublicClient(env) as PublicClient

  // Check if RewardsManager supports IIssuanceTarget (has been upgraded)
  // Throws error if not upgraded
  await requireRewardsManagerUpgraded(client, rmAddress, env)

  const targetChainId = await getTargetChainIdFromEnv(env)

  env.showMessage(`\n========== Activate ${Contracts.issuance.IssuanceAllocator.name} ==========`)
  env.showMessage(`Network: ${env.name} (chainId=${targetChainId})`)
  env.showMessage(`Deployer: ${deployer}`)
  env.showMessage(`Protocol Governor (from Controller): ${governor}`)
  env.showMessage(`${Contracts.issuance.IssuanceAllocator.name}: ${iaAddress}`)
  env.showMessage(`${Contracts.horizon.RewardsManager.name}: ${rmAddress}`)
  env.showMessage(`${Contracts.horizon.L2GraphToken.name}: ${gtAddress}\n`)

  // Check current state
  env.showMessage('📋 Checking current activation state...\n')

  const checks = {
    iaIntegrated: false,
    iaMinter: false,
  }

  // Step 8: Check RM.getIssuanceAllocator() == IA
  // Note: Use viem directly because synced deployments have empty ABIs
  const currentIA = (await client.readContract({
    address: rmAddress as `0x${string}`,
    abi: REWARDS_MANAGER_ABI,
    functionName: 'getIssuanceAllocator',
  })) as string
  checks.iaIntegrated = currentIA.toLowerCase() === iaAddress.toLowerCase()
  env.showMessage(`  IA integrated: ${checks.iaIntegrated ? '✓' : '✗'} (current: ${currentIA})`)

  // Step 9: Check GraphToken.isMinter(IA)
  checks.iaMinter = (await client.readContract({
    address: gtAddress as `0x${string}`,
    abi: GRAPH_TOKEN_ABI,
    functionName: 'isMinter',
    args: [iaAddress as `0x${string}`],
  })) as boolean
  env.showMessage(`  IA minter: ${checks.iaMinter ? '✓' : '✗'}`)

  // All checks passed?
  const allPassed = Object.values(checks).every(Boolean)
  if (allPassed) {
    env.showMessage(`\n✅ ${Contracts.issuance.IssuanceAllocator.name} already activated\n`)
    return
  }

  // Build TX batch for missing activation steps
  env.showMessage('\n🔨 Building activation TX batch...\n')

  const builder = await createGovernanceTxBuilder(env, `activate-${Contracts.issuance.IssuanceAllocator.name}`)

  // Step 8: RM.setIssuanceAllocator(IA)
  if (!checks.iaIntegrated) {
    const data = encodeFunctionData({
      abi: ISSUANCE_TARGET_ABI,
      functionName: 'setIssuanceAllocator',
      args: [iaAddress as `0x${string}`],
    })
    builder.addTx({ to: rmAddress, value: '0', data })
    env.showMessage(`  + RewardsManager.setIssuanceAllocator(${iaAddress})`)
  }

  // Step 9: GraphToken.addMinter(IA)
  if (!checks.iaMinter) {
    const data = encodeFunctionData({
      abi: GRAPH_TOKEN_ABI,
      functionName: 'addMinter',
      args: [iaAddress as `0x${string}`],
    })
    builder.addTx({ to: gtAddress, value: '0', data })
    env.showMessage(`  + GraphToken.addMinter(${iaAddress})`)
  }

  saveGovernanceTxAndExit(env, builder, `${Contracts.issuance.IssuanceAllocator.name} activation`)
}

func.tags = Tags.issuanceActivation
func.dependencies = [ComponentTags.VERIFY_GOVERNANCE, ComponentTags.REWARDS_MANAGER_DEPLOY] // Run after governance transfer and verification (steps 6-7)

export default func
