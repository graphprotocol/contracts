import { Contracts } from '@graphprotocol/deployment/lib/contract-registry.js'
import { getResolvedSettingsForEnv } from '@graphprotocol/deployment/lib/deployment-config.js'
import { ComponentTags, DeploymentActions, shouldSkipAction } from '@graphprotocol/deployment/lib/deployment-tags.js'
import { deployProxyContract } from '@graphprotocol/deployment/lib/issuance-deploy-utils.js'
import { syncComponentsFromRegistry } from '@graphprotocol/deployment/lib/sync-utils.js'
import type { DeployScriptModule } from '@rocketh/core/types'

/**
 * Deploy RecurringCollector proxy and implementation
 *
 * Deploys OZ v5 TransparentUpgradeableProxy with atomic initialization.
 * Deployer is the initial ProxyAdmin owner; ownership is transferred to
 * the protocol governor in a separate governance step.
 *
 * RecurringCollector constructor takes (controller, revokeSignerThawingPeriod).
 * initialize(eip712Name, eip712Version) sets up EIP-712 domain and pausability.
 *
 * On subsequent runs (proxy already deployed), deploys new implementation
 * and stores it as pendingImplementation for governance upgrade.
 *
 * Usage:
 *   pnpm hardhat deploy --tags RecurringCollector:deploy --network <network>
 */
const func: DeployScriptModule = async (env) => {
  if (shouldSkipAction(DeploymentActions.DEPLOY)) return
  await syncComponentsFromRegistry(env, [Contracts.horizon.Controller, Contracts.horizon.RecurringCollector])

  const controllerDep = env.getOrNull('Controller')
  if (!controllerDep) {
    throw new Error('Missing Controller deployment after sync.')
  }

  const settings = await getResolvedSettingsForEnv(env)
  const { revokeSignerThawingPeriod, eip712Name, eip712Version } = settings.recurringCollector

  env.showMessage(`\n📦 Deploying ${Contracts.horizon.RecurringCollector.name}`)

  await deployProxyContract(env, {
    contract: Contracts.horizon.RecurringCollector,
    constructorArgs: [controllerDep.address, revokeSignerThawingPeriod],
    initializeArgs: [eip712Name, eip712Version],
  })
}

func.tags = [ComponentTags.RECURRING_COLLECTOR]
func.skip = async () => shouldSkipAction(DeploymentActions.DEPLOY)

export default func
