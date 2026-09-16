import { ACCESS_CONTROL_ENUMERABLE_ABI } from '@graphprotocol/deployment/lib/abis.js'
import { getTargetChainIdFromEnv } from '@graphprotocol/deployment/lib/address-book-utils.js'
import { Contracts } from '@graphprotocol/deployment/lib/contract-registry.js'
import { getGovernor, getPauseGuardian } from '@graphprotocol/deployment/lib/controller-utils.js'
import { DeploymentActions } from '@graphprotocol/deployment/lib/deployment-tags.js'
import { requireContract, requireDeployer } from '@graphprotocol/deployment/lib/issuance-deploy-utils.js'
import { checkInnovationAllocationConfigured } from '@graphprotocol/deployment/lib/preconditions.js'
import { createActionModule } from '@graphprotocol/deployment/lib/script-factories.js'
import { graph, read, tx } from '@graphprotocol/deployment/rocketh/deploy.js'
import type { PublicClient } from 'viem'
import { encodeFunctionData } from 'viem'

/**
 * Configure InnovationAllocation (GIP-0089)
 *
 * - Grants GOVERNOR_ROLE to the protocol governor
 * - Grants PAUSE_ROLE to the pause guardian
 * - Grants OPERATOR_ROLE to InnovationOperator (the withdrawing multisig)
 *
 * The deployer holds GOVERNOR_ROLE from 01_deploy and executes these directly.
 * IA.setTargetAllocation is a governance activation step (GIP-0089:allocate),
 * not a configure step.
 *
 * A missing InnovationOperator entry does NOT skip the governor and pause
 * guardian grants — those must land regardless, or a subsequent ,transfer
 * revokes the deployer and leaves the contract with no GOVERNOR_ROLE holder.
 *
 * Idempotent: checks on-chain state, skips grants already in place.
 *
 * Usage:
 *   pnpm hardhat deploy --tags InnovationAllocation,configure --network <network>
 */
export default createActionModule(Contracts.issuance.InnovationAllocation, DeploymentActions.CONFIGURE, async (env) => {
  const client = graph.getPublicClient(env) as PublicClient
  const readFn = read(env)
  const deployer = requireDeployer(env)
  const governor = await getGovernor(env)
  const pauseGuardian = await getPauseGuardian(env)

  // Address-book lookups use the literal entry name and guard with entryExists()
  // first, matching the existing `ab.getEntry('NetworkOperator')` pattern in
  // lib/contract-checks.ts — getEntry() throws on a missing entry, so
  // entryExists() must gate the call. The typed name list comes from toolshed,
  // so no cast is needed.
  const targetChainId = await getTargetChainIdFromEnv(env)
  const issuanceBook = graph.getIssuanceAddressBook(targetChainId)
  const operator = issuanceBook.entryExists('InnovationOperator')
    ? issuanceBook.getEntry('InnovationOperator')?.address
    : undefined

  const innovation = requireContract(env, Contracts.issuance.InnovationAllocation)

  env.showMessage(`\n========== Configure ${Contracts.issuance.InnovationAllocation.name} ==========`)
  env.showMessage(`InnovationAllocation: ${innovation.address}`)
  env.showMessage(`Operator:             ${operator ?? '(InnovationOperator not in address book)'}`)

  // Only a fully-specified target can be "already configured" — without an
  // operator address there is no complete end state to compare against.
  const precondition = operator
    ? await checkInnovationAllocationConfigured(client, innovation.address, governor, pauseGuardian, operator)
    : { done: false }
  if (precondition.done) {
    env.showMessage(`\n✅ ${Contracts.issuance.InnovationAllocation.name} already configured\n`)
    return
  }

  env.showMessage('\n📋 Checking current configuration...\n')

  const GOVERNOR_ROLE = (await readFn(innovation, { functionName: 'GOVERNOR_ROLE' })) as `0x${string}`
  const PAUSE_ROLE = (await readFn(innovation, { functionName: 'PAUSE_ROLE' })) as `0x${string}`
  const OPERATOR_ROLE = (await readFn(innovation, { functionName: 'OPERATOR_ROLE' })) as `0x${string}`

  const hasRoleOnChain = async (role: `0x${string}`, account: string): Promise<boolean> =>
    (await client.readContract({
      address: innovation.address as `0x${string}`,
      abi: ACCESS_CONTROL_ENUMERABLE_ABI,
      functionName: 'hasRole',
      args: [role, account as `0x${string}`],
    })) as boolean

  const governorHasRole = await hasRoleOnChain(GOVERNOR_ROLE, governor)
  env.showMessage(`  Governor GOVERNOR_ROLE: ${governorHasRole ? '✓' : '✗'} (${governor})`)

  const pauseGuardianHasRole = await hasRoleOnChain(PAUSE_ROLE, pauseGuardian)
  env.showMessage(`  PauseGuardian PAUSE_ROLE: ${pauseGuardianHasRole ? '✓' : '✗'} (${pauseGuardian})`)

  const operatorHasRole = operator ? await hasRoleOnChain(OPERATOR_ROLE, operator) : false
  env.showMessage(
    `  Operator OPERATOR_ROLE: ${operator ? (operatorHasRole ? '✓' : '✗') : '○'} ` +
      `(${operator ?? 'InnovationOperator not in address book'})`,
  )

  const deployerHasRole = await hasRoleOnChain(GOVERNOR_ROLE, deployer)
  if (!deployerHasRole) {
    env.showMessage(`\n  ○ Deployer does not have GOVERNOR_ROLE — skipping role grants\n`)
    return
  }

  const txs: Array<{ data: `0x${string}`; label: string }> = []
  const grant = (role: `0x${string}`, account: string, label: string) => {
    txs.push({
      data: encodeFunctionData({
        abi: ACCESS_CONTROL_ENUMERABLE_ABI,
        functionName: 'grantRole',
        args: [role, account as `0x${string}`],
      }),
      label: `grantRole(${label}, ${account})`,
    })
  }

  if (!governorHasRole) grant(GOVERNOR_ROLE, governor, 'GOVERNOR_ROLE')
  if (!pauseGuardianHasRole) grant(PAUSE_ROLE, pauseGuardian, 'PAUSE_ROLE')
  if (operator && !operatorHasRole) grant(OPERATOR_ROLE, operator, 'OPERATOR_ROLE')

  if (txs.length > 0) {
    env.showMessage('\n🔨 Executing role grants as deployer...\n')
    const txFn = tx(env)
    for (const t of txs) {
      await txFn({ account: deployer, to: innovation.address as `0x${string}`, data: t.data })
      env.showMessage(`  ✓ ${t.label}`)
    }
  }

  if (!operator) {
    env.showMessage(`\n❌ InnovationOperator not configured in the issuance address book`)
    env.showMessage(`   Governor and pause guardian roles are in place, but OPERATOR_ROLE is not granted.`)
    env.showMessage(`   Add InnovationOperator to packages/issuance/addresses.json and re-run`)
    env.showMessage(`   before --tags InnovationAllocation,transfer\n`)
    return
  }

  env.showMessage(`\n✅ ${Contracts.issuance.InnovationAllocation.name} configuration complete!\n`)
})
