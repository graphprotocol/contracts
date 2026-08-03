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
  checkConditions,
  type ConfigCondition,
  type ConfigurationStatus,
  type ParamCondition,
  type RoleCondition,
} from './contract-checks.js'
import { createGovernanceTxBuilder, executeTxBatchDirect, saveGovernanceTx } from './execute-governance.js'
import type { TxBuilder } from './tx-builder.js'

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

  /**
   * Skip the on-chain state check and treat every condition as un-applied,
   * emitting a TX for each. Used by sequenced-bundle generation
   * (`GIP_0088_ASSUME_UPGRADED`) where the target proxy isn't upgraded yet, so
   * the getter reads that drive the normal idempotency check would revert
   * against the old implementation. The resulting batch is sequenced-only —
   * valid only after the upgrade bundle executes.
   */
  assumeUndone?: boolean

  /**
   * Optional shared TX builder. When provided, configuration TXs are appended to
   * it and NOT executed or saved here — the caller owns executing/saving the
   * combined batch once. Lets multiple applyConfiguration calls (e.g. across
   * several contracts) contribute to a single governance bundle.
   */
  builder?: TxBuilder
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
  const {
    contractName,
    contractAddress,
    canExecuteDirectly,
    executor,
    assumeUndone,
    builder: externalBuilder,
  } = options

  // 1. Check all conditions — or, in sequenced-generation mode, skip the read and
  // treat every condition as un-applied (the target proxy isn't upgraded yet, so
  // the getter reads would revert). The resulting batch is sequenced-only.
  let status: ConfigurationStatus<T | boolean>
  if (assumeUndone) {
    env.showMessage(
      `⚠ ${contractName}: sequenced generation — skipping on-chain check, emitting all configuration TXs\n`,
    )
    status = {
      allOk: false,
      conditions: conditions.map((c) => ({
        name: c.name,
        ok: false,
        current: false,
        target: false,
        message: `  (assumed un-applied) ${c.name}`,
      })),
    }
  } else {
    env.showMessage(`📋 Checking ${contractName} configuration...\n`)
    status = await checkConditions(client, contractAddress, conditions)

    // Display results
    for (const result of status.conditions) {
      env.showMessage(`  ${result.message}`)
    }
  }

  // 2. If all OK, no-op
  if (status.allOk) {
    env.showMessage(`\n✅ ${contractName} configuration already matches target\n`)
    return { status, changesNeeded: false, executedDirectly: false }
  }

  // 3. Build TX batch for failing conditions
  env.showMessage('\n🔨 Building configuration TX batch...\n')

  const builder = externalBuilder ?? (await createGovernanceTxBuilder(env, `configure-${contractName}`))

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

  // 4/5. When a shared builder was supplied, the caller owns executing/saving the
  // combined batch — return with the TXs appended.
  if (externalBuilder) {
    return { status, changesNeeded: true, executedDirectly: false }
  }

  // Otherwise execute or save based on access.
  if (canExecuteDirectly && executor) {
    env.showMessage('\n🔨 Executing configuration TX batch...\n')
    await executeTxBatchDirect(env, builder, executor)
    env.showMessage(`\n✅ ${contractName} configuration updated\n`)
    return { status, changesNeeded: true, executedDirectly: true }
  } else {
    saveGovernanceTx(env, builder, `${contractName} configuration`)
    return { status, changesNeeded: true, executedDirectly: false }
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
