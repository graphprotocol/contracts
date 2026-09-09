import { type Abi, createWalletClient, custom, encodeFunctionData, type PublicClient, type WalletClient } from 'viem'
import { privateKeyToAccount } from 'viem/accounts'

import { createGovernanceTxBuilder } from './execute-governance.js'
import { getDeployerKeyName, resolveConfigVar } from './task-utils.js'

export interface NetworkConnection {
  networkName: string
  provider: unknown
}

export interface ResolvedDeployer {
  deployer?: string
  walletClient?: WalletClient
}

/**
 * Resolve the deployer private key for the connected network from keystore/env
 * and build a viem walletClient if one is available.
 *
 * Returns `{}` if no key is configured — callers can treat that as "deployer
 * cannot execute directly" and fall through to the governance-TX branch.
 */
export async function resolveDeployer(hre: unknown, conn: NetworkConnection): Promise<ResolvedDeployer> {
  const keyName = getDeployerKeyName(conn.networkName)
  const deployerKey = await resolveConfigVar(hre, keyName)
  if (!deployerKey) return {}
  const account = privateKeyToAccount(deployerKey as `0x${string}`)
  return {
    deployer: account.address,
    // eslint-disable-next-line @typescript-eslint/no-explicit-any
    walletClient: createWalletClient({ account, transport: custom(conn.provider as any) }),
  }
}

export interface ExecuteOrGovernanceOpts {
  conn: NetworkConnection
  publicClient: PublicClient
  walletClient?: WalletClient
  canExecuteDirectly: boolean

  // What to write
  to: string
  abi: Abi
  functionName: string
  args: readonly unknown[]

  // Display
  roleDescription: string // 'OPERATOR_ROLE' or 'admin role' — used in "Deployer has X, executing directly"
  requirementMessage: string // 'OPERATOR_ROLE to enable' / 'OPERATOR_ROLE' — printed as "Requires X"
  successMessage: string // single-line summary printed on receipt success

  // Governance TX file metadata
  txName: string
  governanceName: string
  governanceDescription: string
}

/**
 * Direct-write or governance-TX dispatch for role-protected admin writes.
 *
 * - If `canExecuteDirectly` and a walletClient was supplied, sends the TX and
 *   waits for the receipt.
 * - Otherwise emits a governance-TX JSON via {@link createGovernanceTxBuilder}
 *   so a multisig can execute it later.
 *
 * Callers do their own role check (e.g. `accountHasRole` vs `hasAdminRole`)
 * and current-state read up front; this helper only handles the branching
 * scaffolding that's identical across all admin tasks.
 */
export async function executeOrSaveGovernance(opts: ExecuteOrGovernanceOpts): Promise<void> {
  if (opts.canExecuteDirectly && opts.walletClient) {
    console.log(`\n   Deployer has ${opts.roleDescription}, executing directly...`)

    // eslint-disable-next-line @typescript-eslint/no-explicit-any
    const hash = await (opts.walletClient as any).writeContract({
      address: opts.to as `0x${string}`,
      abi: opts.abi,
      functionName: opts.functionName,
      args: opts.args,
    })
    console.log(`   TX: ${hash}`)

    const receipt = await opts.publicClient.waitForTransactionReceipt({ hash })
    if (receipt.status === 'success') {
      console.log(`\n${opts.successMessage}\n`)
    } else {
      console.error(`\n✗ Transaction failed\n`)
    }
    return
  }

  console.log(`\n   Requires ${opts.requirementMessage}`)
  console.log('   Generating governance TX...')

  const env = {
    name: opts.conn.networkName,
    network: { provider: opts.conn.provider },
    showMessage: console.log,
  }
  const builder = await createGovernanceTxBuilder(env as Parameters<typeof createGovernanceTxBuilder>[0], opts.txName, {
    name: opts.governanceName,
    description: opts.governanceDescription,
  })

  const data = encodeFunctionData({ abi: opts.abi, functionName: opts.functionName, args: opts.args })
  builder.addTx({ to: opts.to, data, value: '0' })

  const txFile = builder.saveToFile()
  console.log(`\n✓ Governance TX saved: ${txFile}`)
  console.log('\nNext steps:')
  console.log('   • Fork testing: npx hardhat deploy:execute-governance --network fork')
  console.log('   • Safe multisig: Upload JSON to Transaction Builder')
  console.log('')
}
