import { Contracts } from '@graphprotocol/deployment/lib/contract-registry.js'
import { ComponentTags, Tags } from '@graphprotocol/deployment/lib/deployment-tags.js'
import { upgradeImplementation } from '@graphprotocol/deployment/lib/upgrade-implementation.js'
import type { DeployScriptModule } from '@rocketh/core/types'

// RewardsManager Upgrade
//
// Generates governance TX batch and executes upgrade.
//
// Workflow:
// 1. Check for pending implementation in address book
// 2. Generate governance TX (upgrade + acceptProxy)
// 3. Fork mode: execute via governor impersonation
// 4. Production: output TX file for Safe execution
//
// Usage:
//   FORK_NETWORK=arbitrumSepolia npx hardhat deploy --tags rewards-manager-upgrade --network localhost

const func: DeployScriptModule = async (env) => {
  await upgradeImplementation(env, Contracts.horizon.RewardsManager)
}

func.tags = Tags.rewardsManagerUpgrade
func.dependencies = [ComponentTags.REWARDS_MANAGER_DEPLOY]

export default func
