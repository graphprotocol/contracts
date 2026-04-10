import { Contracts } from '@graphprotocol/deployment/lib/contract-registry.js'
import { deployImplementation, getImplementationConfig } from '@graphprotocol/deployment/lib/deploy-implementation.js'
import { ComponentTags, DeploymentActions, shouldSkipAction } from '@graphprotocol/deployment/lib/deployment-tags.js'
import { syncComponentsFromRegistry } from '@graphprotocol/deployment/lib/sync-utils.js'
import { graph } from '@graphprotocol/deployment/rocketh/deploy.js'
import type { DeployScriptModule } from '@rocketh/core/types'

// PaymentsEscrow Implementation Deployment
//
// Deploys a new PaymentsEscrow implementation if artifact bytecode differs from on-chain.
//
// Workflow:
// 1. Read current immutable values from on-chain contract
// 2. Compare artifact bytecode with on-chain bytecode (accounting for immutables)
// 3. If different, deploy new implementation
// 4. Store as "pendingImplementation" in horizon/addresses.json
// 5. Upgrade task (separate) handles TX generation and execution

const func: DeployScriptModule = async (env) => {
  if (shouldSkipAction(DeploymentActions.DEPLOY)) return
  await syncComponentsFromRegistry(env, [Contracts.horizon.Controller, Contracts.horizon.PaymentsEscrow])

  const controllerDep = env.getOrNull('Controller')
  const escrowDep = env.getOrNull('PaymentsEscrow')

  if (!controllerDep || !escrowDep) {
    throw new Error('Missing required contract deployments (Controller, PaymentsEscrow) after sync.')
  }

  // Read current immutable value from on-chain contract
  const client = graph.getPublicClient(env)
  const thawingPeriod = await client.readContract({
    address: escrowDep.address as `0x${string}`,
    abi: [
      {
        name: 'WITHDRAW_ESCROW_THAWING_PERIOD',
        type: 'function',
        inputs: [],
        outputs: [{ name: '', type: 'uint256' }],
        stateMutability: 'view',
      },
    ],
    functionName: 'WITHDRAW_ESCROW_THAWING_PERIOD',
  })

  env.showMessage(`   PaymentsEscrow WITHDRAW_ESCROW_THAWING_PERIOD: ${thawingPeriod}`)

  await deployImplementation(
    env,
    getImplementationConfig('horizon', 'PaymentsEscrow', {
      constructorArgs: [controllerDep.address, thawingPeriod],
    }),
  )
}

func.tags = [ComponentTags.PAYMENTS_ESCROW]
func.skip = async () => shouldSkipAction(DeploymentActions.DEPLOY)
export default func
