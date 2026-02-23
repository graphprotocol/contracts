import { deployImplementation, getImplementationConfig } from '@graphprotocol/deployment/lib/deploy-implementation.js'
import { SpecialTags, Tags } from '@graphprotocol/deployment/lib/deployment-tags.js'
import type { DeployScriptModule } from '@rocketh/core/types'

// SubgraphService Implementation Deployment
//
// Deploys a new SubgraphService implementation if artifact bytecode differs from on-chain.
//
// Workflow:
// 1. Compare artifact bytecode with on-chain bytecode (accounting for immutables)
// 2. If different, deploy new implementation
// 3. Store as "pendingImplementation" in subgraph-service/addresses.json
// 4. Upgrade task (separate) handles TX generation and execution

const func: DeployScriptModule = async (env) => {
  // Get constructor args from imported deployments
  const controllerDep = env.getOrNull('Controller')
  const disputeManagerDep = env.getOrNull('DisputeManager')
  const graphTallyCollectorDep = env.getOrNull('GraphTallyCollector')
  const curationDep = env.getOrNull('L2Curation')

  if (!controllerDep || !disputeManagerDep || !graphTallyCollectorDep || !curationDep) {
    throw new Error(
      'Missing required contract deployments (Controller, DisputeManager, GraphTallyCollector, L2Curation). ' +
        'The sync step should have imported these.',
    )
  }

  await deployImplementation(
    env,
    getImplementationConfig('subgraph-service', 'SubgraphService', {
      constructorArgs: [
        controllerDep.address,
        disputeManagerDep.address,
        graphTallyCollectorDep.address,
        curationDep.address,
      ],
    }),
  )
}

func.tags = Tags.subgraphServiceDeploy
func.dependencies = [SpecialTags.SYNC]
export default func
