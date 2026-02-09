import { deployImplementation, getImplementationConfig } from '@graphprotocol/deployment/lib/deploy-implementation.js'
import { SpecialTags, Tags } from '@graphprotocol/deployment/lib/deployment-tags.js'
import type { DeployScriptModule } from '@rocketh/core/types'

// RewardsManager Implementation Deployment
//
// Deploys a new RewardsManager implementation if artifact bytecode differs from on-chain.
//
// Workflow:
// 1. Compare artifact bytecode with on-chain bytecode (accounting for immutables)
// 2. If different, deploy new implementation
// 3. Store as "pendingImplementation" in horizon/addresses.json
// 4. Upgrade task (separate) handles TX generation and execution

const func: DeployScriptModule = async (env) => {
  await deployImplementation(env, getImplementationConfig('horizon', 'RewardsManager'))
}

func.tags = Tags.rewardsManagerDeploy
func.dependencies = [SpecialTags.SYNC]
export default func
