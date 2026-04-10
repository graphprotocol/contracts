import { ACCESS_CONTROL_ENUMERABLE_ABI, ISSUANCE_TARGET_ABI } from '@graphprotocol/deployment/lib/abis.js'
import { supportsInterface } from '@graphprotocol/deployment/lib/contract-checks.js'
import { Contracts } from '@graphprotocol/deployment/lib/contract-registry.js'
import { getGovernor, getPauseGuardian } from '@graphprotocol/deployment/lib/controller-utils.js'
import { ComponentTags, DeploymentActions } from '@graphprotocol/deployment/lib/deployment-tags.js'
import { requireContract, requireDeployer } from '@graphprotocol/deployment/lib/issuance-deploy-utils.js'
import { checkRAMConfigured } from '@graphprotocol/deployment/lib/preconditions.js'
import { createActionModule } from '@graphprotocol/deployment/lib/script-factories.js'
import { graph, tx } from '@graphprotocol/deployment/rocketh/deploy.js'
import type { PublicClient } from 'viem'
import { encodeFunctionData, keccak256, toHex } from 'viem'

/**
 * Configure RecurringAgreementManager
 *
 * Grants:
 * - COLLECTOR_ROLE to RecurringCollector
 * - DATA_SERVICE_ROLE to SubgraphService
 * - GOVERNOR_ROLE to protocol governor
 * - PAUSE_ROLE to pause guardian
 *
 * Sets:
 * - IssuanceAllocator as RAM's issuance source
 *
 * Idempotent: checks on-chain state, skips if already configured.
 *
 * Usage:
 *   pnpm hardhat deploy --tags RecurringAgreementManager:configure --network <network>
 */
export default createActionModule(
  Contracts.issuance.RecurringAgreementManager,
  DeploymentActions.CONFIGURE,
  async (env) => {
    const client = graph.getPublicClient(env) as PublicClient
    const governor = await getGovernor(env)
    const pauseGuardian = await getPauseGuardian(env)

    const ram = requireContract(env, Contracts.issuance.RecurringAgreementManager)
    const rc = requireContract(env, Contracts.horizon.RecurringCollector)
    const ss = requireContract(env, Contracts['subgraph-service'].SubgraphService)
    const ia = requireContract(env, Contracts.issuance.IssuanceAllocator)

    env.showMessage(`\n========== Configure ${Contracts.issuance.RecurringAgreementManager.name} ==========`)
    env.showMessage(`RAM: ${ram.address}`)
    env.showMessage(`RC:  ${rc.address}`)
    env.showMessage(`SS:  ${ss.address}`)
    env.showMessage(`IA:  ${ia.address}`)

    // Check if already configured (shared precondition check)
    const precondition = await checkRAMConfigured(
      client,
      ram.address,
      rc.address,
      ss.address,
      ia.address,
      governor,
      pauseGuardian,
    )
    if (precondition.done) {
      env.showMessage(`\n✅ ${Contracts.issuance.RecurringAgreementManager.name} already configured\n`)
      return
    }

    // Role constants
    const COLLECTOR_ROLE = keccak256(toHex('COLLECTOR_ROLE'))
    const DATA_SERVICE_ROLE = keccak256(toHex('DATA_SERVICE_ROLE'))
    const GOVERNOR_ROLE = keccak256(toHex('GOVERNOR_ROLE'))
    const PAUSE_ROLE = keccak256(toHex('PAUSE_ROLE'))

    // Check what still needs configuring
    env.showMessage('\n📋 Checking current configuration...\n')

    const rcHasCollectorRole = (await client.readContract({
      address: ram.address as `0x${string}`,
      abi: ACCESS_CONTROL_ENUMERABLE_ABI,
      functionName: 'hasRole',
      args: [COLLECTOR_ROLE, rc.address as `0x${string}`],
    })) as boolean
    env.showMessage(`  RC COLLECTOR_ROLE: ${rcHasCollectorRole ? '✓' : '✗'}`)

    const ssHasDataServiceRole = (await client.readContract({
      address: ram.address as `0x${string}`,
      abi: ACCESS_CONTROL_ENUMERABLE_ABI,
      functionName: 'hasRole',
      args: [DATA_SERVICE_ROLE, ss.address as `0x${string}`],
    })) as boolean
    env.showMessage(`  SS DATA_SERVICE_ROLE: ${ssHasDataServiceRole ? '✓' : '✗'}`)

    // Check role grants
    const governorHasRole = (await client.readContract({
      address: ram.address as `0x${string}`,
      abi: ACCESS_CONTROL_ENUMERABLE_ABI,
      functionName: 'hasRole',
      args: [GOVERNOR_ROLE, governor as `0x${string}`],
    })) as boolean
    env.showMessage(`  Governor GOVERNOR_ROLE: ${governorHasRole ? '✓' : '✗'}`)

    const pauseGuardianHasRole = (await client.readContract({
      address: ram.address as `0x${string}`,
      abi: ACCESS_CONTROL_ENUMERABLE_ABI,
      functionName: 'hasRole',
      args: [PAUSE_ROLE, pauseGuardian as `0x${string}`],
    })) as boolean
    env.showMessage(`  PauseGuardian PAUSE_ROLE: ${pauseGuardianHasRole ? '✓' : '✗'}`)

    // Determine executor: deployer (fresh) or governor (prod)
    const deployer = requireDeployer(env)
    const deployerIsGovernor = (await client.readContract({
      address: ram.address as `0x${string}`,
      abi: ACCESS_CONTROL_ENUMERABLE_ABI,
      functionName: 'hasRole',
      args: [GOVERNOR_ROLE, deployer as `0x${string}`],
    })) as boolean

    if (!deployerIsGovernor) {
      env.showMessage(`\n  ○ Deployer does not have GOVERNOR_ROLE — skipping (governance TX in upgrade step)\n`)
      return
    }

    // Build TX list for missing configuration
    const txs: Array<{ to: string; data: `0x${string}`; label: string }> = []

    if (!rcHasCollectorRole) {
      txs.push({
        to: ram.address,
        data: encodeFunctionData({
          abi: ACCESS_CONTROL_ENUMERABLE_ABI,
          functionName: 'grantRole',
          args: [COLLECTOR_ROLE, rc.address as `0x${string}`],
        }),
        label: `grantRole(COLLECTOR_ROLE, ${rc.address})`,
      })
    }

    if (!ssHasDataServiceRole) {
      txs.push({
        to: ram.address,
        data: encodeFunctionData({
          abi: ACCESS_CONTROL_ENUMERABLE_ABI,
          functionName: 'grantRole',
          args: [DATA_SERVICE_ROLE, ss.address as `0x${string}`],
        }),
        label: `grantRole(DATA_SERVICE_ROLE, ${ss.address})`,
      })
    }

    if (!governorHasRole) {
      txs.push({
        to: ram.address,
        data: encodeFunctionData({
          abi: ACCESS_CONTROL_ENUMERABLE_ABI,
          functionName: 'grantRole',
          args: [GOVERNOR_ROLE, governor as `0x${string}`],
        }),
        label: `grantRole(GOVERNOR_ROLE, ${governor})`,
      })
    }

    if (!pauseGuardianHasRole) {
      txs.push({
        to: ram.address,
        data: encodeFunctionData({
          abi: ACCESS_CONTROL_ENUMERABLE_ABI,
          functionName: 'grantRole',
          args: [PAUSE_ROLE, pauseGuardian as `0x${string}`],
        }),
        label: `grantRole(PAUSE_ROLE, ${pauseGuardian})`,
      })
    }

    // Check issuance allocator — skip if IA doesn't support the interface yet (pending upgrade)
    let iaConfigured = false
    try {
      const currentIA = (await client.readContract({
        address: ram.address as `0x${string}`,
        abi: ISSUANCE_TARGET_ABI,
        functionName: 'getIssuanceAllocator',
      })) as string
      iaConfigured = currentIA.toLowerCase() === ia.address.toLowerCase()
      env.showMessage(`  IssuanceAllocator: ${iaConfigured ? '✓' : '✗'} (current: ${currentIA})`)
    } catch {
      env.showMessage(`  IssuanceAllocator: ✗ (getter not available)`)
    }

    if (!iaConfigured) {
      const IISSUANCE_ALLOCATION_DISTRIBUTION_ID = '0x79da37fc' // type(IIssuanceAllocationDistribution).interfaceId
      const iaSupported = await supportsInterface(client, ia.address, IISSUANCE_ALLOCATION_DISTRIBUTION_ID)
      if (iaSupported) {
        txs.push({
          to: ram.address,
          data: encodeFunctionData({
            abi: ISSUANCE_TARGET_ABI,
            functionName: 'setIssuanceAllocator',
            args: [ia.address as `0x${string}`],
          }),
          label: `setIssuanceAllocator(${ia.address})`,
        })
      } else {
        env.showMessage(`  ○ IA does not yet support IIssuanceAllocationDistribution — skipping setIssuanceAllocator`)
      }
    }

    if (txs.length === 0) return

    env.showMessage('\n🔨 Executing configuration as deployer...\n')
    const txFn = tx(env)
    for (const t of txs) {
      await txFn({ account: deployer, to: t.to as `0x${string}`, data: t.data })
      env.showMessage(`  ✓ ${t.label}`)
    }
    env.showMessage(`\n✅ ${Contracts.issuance.RecurringAgreementManager.name} configuration complete!\n`)
  },
  {
    extraDependencies: [
      ComponentTags.RECURRING_COLLECTOR,
      ComponentTags.SUBGRAPH_SERVICE,
      ComponentTags.ISSUANCE_ALLOCATOR,
    ],
    prerequisites: [
      Contracts.horizon.RecurringCollector,
      Contracts['subgraph-service'].SubgraphService,
      Contracts.issuance.IssuanceAllocator,
    ],
  },
)
