/**
 * Apply Configuration Utility
 *
 * Generic utility for checking and applying configuration conditions in deploy mode.
 * Handles the standard pattern: check conditions → generate TXs for gaps → execute or save.
 * Supports both param conditions (getter/setter) and role conditions (hasRole/grantRole).
 */

import type { Environment } from '@rocketh/core/types'
import type { PublicClient } from 'viem'
import { encodeFunctionData } from 'viem'

import {
  type ConfigCondition,
  type ConfigurationStatus,
  type ParamCondition,
  type RoleCondition,
  checkConditions,
} from './contract-checks.js'
import { createGovernanceTxBuilder, executeTxBatchDirect, saveGovernanceTxAndExit } from './execute-governance.js'

/**
 * Options for applyConfiguration
 */
export interface ApplyConfigurationOptions {
  /** Contract name (for messages and TX batch naming) */
  contractName: string

  /** Contract address */
  contractAddress: string

  /** Whether the caller can execute directly (has required role) */
  canExecuteDirectly: boolean

  /** Account to execute from (if canExecuteDirectly) */
  executor?: string
}

/**
 * Result of applyConfiguration
 */
export interface ApplyConfigurationResult<T = bigint> {
  /** Status of all conditions (T | boolean due to mixed param/role conditions) */
  status: ConfigurationStatus<T | boolean>

  /** Whether any changes were made/proposed */
  changesNeeded: boolean

  /** Whether changes were executed directly (vs saved for governance) */
  executedDirectly: boolean
}

/**
 * Apply configuration conditions in deploy mode
 *
 * Standard flow:
 * 1. Check all conditions against on-chain state
 * 2. If all OK, return (no-op)
 * 3. Build TX batch for conditions that need updating
 * 4. If canExecuteDirectly: execute TXs and return
 * 5. If not: save TX batch for governance and exit
 *
 * @example
 * ```typescript
 * const conditions = createREOConditions()
 * const result = await applyConfiguration(env, client, conditions, {
 *   contractName: 'RewardsEligibilityOracle',
 *   contractAddress: reoAddress,
 *   canExecuteDirectly: deployerHasGovernorRole,
 *   executor: deployer,
 * })
 * ```
 */
export async function applyConfiguration<T>(
  env: Environment,
  client: PublicClient,
  conditions: ConfigCondition<T>[],
  options: ApplyConfigurationOptions,
): Promise<ApplyConfigurationResult<T>> {
  const { contractName, contractAddress, canExecuteDirectly, executor } = options

  // 1. Check all conditions
  env.showMessage(`📋 Checking ${contractName} configuration...\n`)

  const status = await checkConditions(client, contractAddress, conditions)

  // Display results
  for (const result of status.conditions) {
    env.showMessage(`  ${result.message}`)
  }

  // 2. If all OK, no-op
  if (status.allOk) {
    env.showMessage(`\n✅ ${contractName} configuration already matches target\n`)
    return { status, changesNeeded: false, executedDirectly: false }
  }

  // 3. Build TX batch for failing conditions
  env.showMessage('\n🔨 Building configuration TX batch...\n')

  const builder = await createGovernanceTxBuilder(env, `configure-${contractName}`)

  const failingConditions = conditions.filter((_, i) => !status.conditions[i].ok)

  for (const condition of failingConditions) {
    if (condition.type === 'role') {
      // Role condition: fetch role bytes32, then grantRole or revokeRole
      const roleCondition = condition as RoleCondition
      const action = roleCondition.action ?? 'grant'
      const role = (await client.readContract({
        address: contractAddress as `0x${string}`,
        abi: roleCondition.abi,
        functionName: roleCondition.roleGetter,
      })) as `0x${string}`

      const functionName = action === 'grant' ? 'grantRole' : 'revokeRole'
      const data = encodeFunctionData({
        abi: roleCondition.abi,
        functionName,
        args: [role, roleCondition.targetAccount as `0x${string}`],
      })
      builder.addTx({ to: contractAddress, value: '0', data })

      const formatAccount = roleCondition.formatAccount ?? ((a) => a)
      env.showMessage(`  + ${functionName}(${roleCondition.roleGetter}, ${formatAccount(roleCondition.targetAccount)})`)
    } else {
      // Param condition: simple setter call
      const paramCondition = condition as ParamCondition<T>
      const data = encodeFunctionData({
        abi: paramCondition.abi,
        functionName: paramCondition.setter,
        args: [paramCondition.target],
      })
      builder.addTx({ to: contractAddress, value: '0', data })

      const format = paramCondition.format ?? String
      env.showMessage(`  + ${paramCondition.setter}(${format(paramCondition.target)})`)
    }
  }

  // 4/5. Execute or save based on access
  if (canExecuteDirectly && executor) {
    env.showMessage('\n🔨 Executing configuration TX batch...\n')
    await executeTxBatchDirect(env, builder, executor)
    env.showMessage(`\n✅ ${contractName} configuration updated\n`)
    return { status, changesNeeded: true, executedDirectly: true }
  } else {
    // Never returns - exits with code 1
    saveGovernanceTxAndExit(env, builder, `${contractName} configuration`)
    // TypeScript doesn't know saveGovernanceTxAndExit never returns
    throw new Error('unreachable')
  }
}

/**
 * Check configuration status only (no TX generation)
 *
 * Use this for status checks outside of deploy mode.
 */
export async function checkConfigurationStatus<T>(
  client: PublicClient,
  contractAddress: string,
  conditions: ConfigCondition<T>[],
): Promise<ConfigurationStatus<T | boolean>> {
  return checkConditions(client, contractAddress, conditions)
}
