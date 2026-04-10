/**
 * Deploy Script Factories - Create deployment modules with standard framework plumbing
 *
 * Two flavors:
 *
 * **Contract-based** (component lifecycle):
 *   Derive tags from registry componentTag. Action-verb skip gating.
 *   Post-action sync. Use for standard deploy/upgrade/configure/transfer steps.
 *
 * **Tag-based** (goals, multi-contract status, standalone actions):
 *   Accept a tag string directly. Skip when no --tags specified.
 *   Custom execute callback handles all logic.
 *
 * Skip gating uses func.skip (checked by rocketh's executor via patch)
 * with early returns as a safety net.
 */

import type { DeployScriptModule, Environment } from '@rocketh/core/types'

import type { RegistryEntry } from './contract-registry.js'
import { deployImplementation, getImplementationConfig } from './deploy-implementation.js'
import { DeploymentActions, noTagsRequested, shouldSkipAction } from './deployment-tags.js'
import { requireUpgradeExecuted } from './execute-governance.js'
import { deployProxyContract } from './issuance-deploy-utils.js'
import { showDetailedComponentStatus } from './status-detail.js'
import { syncComponentFromRegistry, syncComponentsFromRegistry } from './sync-utils.js'
import type { ImplementationUpgradeOverrides } from './upgrade-implementation.js'
import { upgradeImplementation } from './upgrade-implementation.js'

/**
 * Require that the registry entry has a componentTag, throwing a clear error if not.
 */
function requireComponentTag(contract: RegistryEntry): string {
  if (!contract.componentTag) {
    throw new Error(
      `Contract '${contract.name}' has no componentTag in the registry. ` +
        `Add a componentTag to use script factories.`,
    )
  }
  return contract.componentTag
}

/**
 * Create a standard upgrade deploy script module.
 *
 * Generates a governance TX to upgrade the contract's proxy to its pending implementation.
 * Tags and dependencies are derived from the contract's componentTag.
 *
 * @example Standard single-contract upgrade:
 * ```typescript
 * import { Contracts } from '@graphprotocol/deployment/lib/contract-registry.js'
 * import { createUpgradeModule } from '@graphprotocol/deployment/lib/script-factories.js'
 *
 * export default createUpgradeModule(Contracts.horizon.PaymentsEscrow)
 * ```
 *
 * @example Upgrade with implementation name override:
 * ```typescript
 * export default createUpgradeModule(Contracts.issuance.SomeProxy, {
 *   overrides: { implementationName: 'DifferentImpl' },
 * })
 * ```
 */
export function createUpgradeModule(
  contract: RegistryEntry,
  options?: {
    overrides?: ImplementationUpgradeOverrides
    extraDependencies?: string[]
    /** Additional contracts to sync alongside `contract` before the upgrade runs. */
    prerequisites?: RegistryEntry[]
  },
): DeployScriptModule {
  const tag = requireComponentTag(contract)

  const func: DeployScriptModule = async (env) => {
    if (shouldSkipAction(DeploymentActions.UPGRADE)) return
    await syncComponentsFromRegistry(env, [contract, ...(options?.prerequisites ?? [])])
    await upgradeImplementation(env, contract, options?.overrides)
    await syncComponentFromRegistry(env, contract)
  }

  func.tags = [tag]
  func.dependencies = options?.extraDependencies ?? []
  func.skip = async () => shouldSkipAction(DeploymentActions.UPGRADE)

  return func
}

/**
 * Create a standard end/complete deploy script module.
 *
 * Gates on `--tags ...,all`. Verifies the upgrade governance TX has been
 * executed and shows a ready message. The actual lifecycle actions a component
 * needs are encoded in its dependency chain via the component tag, not in this
 * factory.
 *
 * @example
 * ```typescript
 * export default createEndModule(Contracts.horizon.PaymentsEscrow)
 * ```
 */
export function createEndModule(contract: RegistryEntry): DeployScriptModule {
  const tag = requireComponentTag(contract)

  const func: DeployScriptModule = async (env) => {
    if (shouldSkipAction(DeploymentActions.ALL)) return
    requireUpgradeExecuted(env, contract.name)
    env.showMessage(`\n✓ ${contract.name} ready`)
  }

  func.tags = [tag]
  func.dependencies = []
  func.skip = async () => shouldSkipAction(DeploymentActions.ALL)

  return func
}

/**
 * Create a status deploy script module.
 *
 * Syncs the component with on-chain state and shows its current status.
 * Tagged with the bare component name so `--tags IssuanceAllocator` is a
 * safe, read-only operation.
 *
 * @example Single contract (default status display):
 * ```typescript
 * export default createStatusModule(Contracts.horizon.PaymentsEscrow)
 * ```
 *
 * @example Custom status with tag (multi-contract or cross-component):
 * ```typescript
 * export default createStatusModule(GoalTags.GIP_0088, async (env) => {
 *   // custom multi-phase status display
 * })
 * ```
 */
export function createStatusModule(contract: RegistryEntry): DeployScriptModule
export function createStatusModule(tag: string, execute: (env: Environment) => Promise<void>): DeployScriptModule
export function createStatusModule(
  contractOrTag: RegistryEntry | string,
  execute?: (env: Environment) => Promise<void>,
): DeployScriptModule {
  const tag = typeof contractOrTag === 'string' ? contractOrTag : requireComponentTag(contractOrTag)

  const func: DeployScriptModule = async (env) => {
    if (noTagsRequested()) return
    if (execute) {
      await execute(env)
    } else {
      await showDetailedComponentStatus(env, contractOrTag as RegistryEntry)
    }
  }

  func.tags = [tag]
  func.dependencies = []
  func.skip = async () => noTagsRequested()

  return func
}

// ============================================================================
// Action Factories (custom logic with standard framework plumbing)
// ============================================================================

/**
 * Create a deploy script module for a custom action.
 *
 * Two forms:
 *
 * **Contract-based** (component lifecycle steps):
 * Uses action verb gating (`shouldSkipAction`) and post-action sync.
 * Requires both component tag AND action verb in `--tags`.
 *
 * **Tag-based** (goal scripts, standalone actions):
 * Uses tag gating (`noTagsRequested`). The tag in `--tags` is sufficient.
 * No post-action sync — the execute callback handles everything.
 *
 * @example Contract-based configure:
 * ```typescript
 * export default createActionModule(
 *   Contracts.horizon.RecurringCollector,
 *   DeploymentActions.CONFIGURE,
 *   async (env) => { ... },
 * )
 * ```
 *
 * @example Tag-based goal action:
 * ```typescript
 * export default createActionModule(
 *   GoalTags.GIP_0088_ISSUANCE_CONNECT,
 *   async (env) => { ... },
 *   { dependencies: [ComponentTags.ISSUANCE_ALLOCATOR] },
 * )
 * ```
 */
export function createActionModule(
  contract: RegistryEntry,
  action: (typeof DeploymentActions)[keyof typeof DeploymentActions],
  execute: (env: Environment) => Promise<void>,
  options?: { extraDependencies?: string[]; prerequisites?: RegistryEntry[] },
): DeployScriptModule
export function createActionModule(
  tag: string,
  execute: (env: Environment) => Promise<void>,
  options?: { dependencies?: string[] },
): DeployScriptModule
export function createActionModule(
  contractOrTag: RegistryEntry | string,
  actionOrExecute: (typeof DeploymentActions)[keyof typeof DeploymentActions] | ((env: Environment) => Promise<void>),
  executeOrOptions?: ((env: Environment) => Promise<void>) | { dependencies?: string[] },
  maybeOptions?: { extraDependencies?: string[]; prerequisites?: RegistryEntry[] },
): DeployScriptModule {
  if (typeof contractOrTag === 'string') {
    // Tag-based: (tag, execute, options?)
    const tag = contractOrTag
    const execute = actionOrExecute as (env: Environment) => Promise<void>
    const options = executeOrOptions as { dependencies?: string[] } | undefined

    const func: DeployScriptModule = async (env) => {
      if (shouldSkipAction(tag)) return
      await execute(env)
    }

    func.tags = [tag]
    func.dependencies = options?.dependencies ?? []
    func.skip = async () => shouldSkipAction(tag)

    return func
  }

  // Contract-based: (contract, action, execute, options?)
  const tag = requireComponentTag(contractOrTag)
  const action = actionOrExecute as string
  const execute = executeOrOptions as (env: Environment) => Promise<void>

  const func: DeployScriptModule = async (env) => {
    if (shouldSkipAction(action)) return
    await syncComponentsFromRegistry(env, [contractOrTag, ...(maybeOptions?.prerequisites ?? [])])
    await execute(env)
    await syncComponentFromRegistry(env, contractOrTag)
  }

  func.tags = [tag]
  func.dependencies = maybeOptions?.extraDependencies ?? []
  func.skip = async () => shouldSkipAction(action)

  return func
}

// ============================================================================
// Deploy Factories
// ============================================================================

/**
 * Options shared by deploy factories
 */
interface DeployModuleOptions {
  /** Additional tags beyond the derived deploy action tag */
  extraTags?: string[]
  /** Additional rocketh dependency tags */
  extraDependencies?: string[]
  /**
   * Additional registry entries to sync immediately before the action runs.
   * Use for contracts read via `env.getOrNull(...)` inside `resolveArgs` /
   * `resolveConstructorArgs` (e.g. Controller, shared implementations).
   */
  prerequisites?: RegistryEntry[]
}

/**
 * Create a deploy module for prerequisite contracts (existing proxy, new implementation).
 *
 * Uses `deployImplementation` + `getImplementationConfig` to deploy a new implementation
 * and store it as pendingImplementation for governance upgrade.
 *
 * @param contract - Registry entry (must have prerequisite: true, artifact, proxyType)
 * @param resolveConstructorArgs - Optional callback to resolve constructor args from env.
 *   Called with the deployment environment. Return the args array.
 *   Omit for contracts with no constructor args (e.g., RewardsManager).
 *
 * @example No constructor args:
 * ```typescript
 * export default createImplementationDeployModule(Contracts.horizon.RewardsManager)
 * ```
 *
 * @example With synced dependency args:
 * ```typescript
 * export default createImplementationDeployModule(
 *   Contracts['subgraph-service'].DisputeManager,
 *   (env) => {
 *     const controller = env.getOrNull('Controller')
 *     if (!controller) throw new Error('Missing Controller')
 *     return [controller.address]
 *   },
 * )
 * ```
 */
export function createImplementationDeployModule(
  contract: RegistryEntry,
  resolveConstructorArgs?: (env: Environment) => Promise<unknown[]> | unknown[],
  options?: DeployModuleOptions,
): DeployScriptModule {
  const tag = requireComponentTag(contract)

  const func: DeployScriptModule = async (env) => {
    if (shouldSkipAction(DeploymentActions.DEPLOY)) return
    await syncComponentsFromRegistry(env, [contract, ...(options?.prerequisites ?? [])])
    const constructorArgs = resolveConstructorArgs ? await resolveConstructorArgs(env) : undefined
    await deployImplementation(
      env,
      getImplementationConfig(contract.addressBook, contract.name, constructorArgs ? { constructorArgs } : undefined),
    )
    await syncComponentFromRegistry(env, contract)
  }

  func.tags = [tag, ...(options?.extraTags ?? [])]
  func.dependencies = options?.extraDependencies ?? []
  func.skip = async () => shouldSkipAction(DeploymentActions.DEPLOY)

  return func
}

/**
 * Create a deploy module for new contracts (fresh proxy + implementation).
 *
 * Uses `deployProxyContract` to deploy an OZ v5 TransparentUpgradeableProxy with
 * atomic initialization. On subsequent runs, deploys new implementation and stores
 * as pendingImplementation.
 *
 * @param contract - Registry entry (must have deployable: true, artifact, proxyType)
 * @param resolveArgs - Optional callback to resolve constructor and initialize args.
 *   Omit initializeArgs to use default [governor].
 *
 * @example With graphToken constructor and deployer init:
 * ```typescript
 * export default createProxyDeployModule(
 *   Contracts.issuance.RewardsEligibilityOracleA,
 *   (env) => ({
 *     constructorArgs: [requireGraphToken(env).address],
 *     initializeArgs: [requireDeployer(env)],
 *   }),
 * )
 * ```
 *
 * @example With default initialize args [governor]:
 * ```typescript
 * export default createProxyDeployModule(
 *   Contracts.issuance.RecurringAgreementManager,
 *   (env) => ({
 *     constructorArgs: [requireGraphToken(env).address, paymentsEscrow.address],
 *   }),
 * )
 * ```
 */
export function createProxyDeployModule(
  contract: RegistryEntry,
  resolveArgs?: (env: Environment) => Promise<ProxyDeployArgs> | ProxyDeployArgs,
  options?: DeployModuleOptions,
): DeployScriptModule {
  const tag = requireComponentTag(contract)

  const func: DeployScriptModule = async (env) => {
    if (shouldSkipAction(DeploymentActions.DEPLOY)) return
    await syncComponentsFromRegistry(env, [contract, ...(options?.prerequisites ?? [])])
    const args = resolveArgs ? await resolveArgs(env) : {}
    await deployProxyContract(env, {
      contract,
      constructorArgs: args.constructorArgs,
      initializeArgs: args.initializeArgs,
    })
    await syncComponentFromRegistry(env, contract)
  }

  func.tags = [tag, ...(options?.extraTags ?? [])]
  func.dependencies = options?.extraDependencies ?? []
  func.skip = async () => shouldSkipAction(DeploymentActions.DEPLOY)

  return func
}

interface ProxyDeployArgs {
  constructorArgs?: unknown[]
  initializeArgs?: unknown[]
}
