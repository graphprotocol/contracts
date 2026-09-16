import { task } from 'hardhat/config'
import { ArgumentType } from 'hardhat/types/arguments'
import type { NewTaskActionFunction } from 'hardhat/types/tasks'
import { createPublicClient, custom, type PublicClient } from 'viem'

import { ACCESS_CONTROL_ENUMERABLE_ABI } from '../lib/abis.js'
import {
  accountHasRole,
  enumerateContractRoles,
  getAdminRoleInfo,
  getRoleHash,
  hasAdminRole,
} from '../lib/contract-checks.js'
import { executeOrSaveGovernance, resolveDeployer } from '../lib/operator-write.js'
import { getContractAddress, resolveContractFromRegistry } from '../lib/task-utils.js'
import { graph } from '../rocketh/deploy.js'

interface TaskArgs {
  contract: string
  address: string
  role: string
  account: string
}

const action: NewTaskActionFunction<TaskArgs> = async (taskArgs, hre) => {
  const contractName = taskArgs.contract || undefined
  const addressArg = taskArgs.address || undefined
  const roleName = taskArgs.role
  const targetAccount = taskArgs.account

  // Validate inputs
  if (!contractName && !addressArg) {
    console.error('\nError: Must provide either --contract or --address')
    return
  }
  if (!roleName) {
    console.error('\nError: Must provide --role (e.g., ORACLE_ROLE)')
    return
  }
  if (!targetAccount) {
    console.error('\nError: Must provide --account (address to revoke role from)')
    return
  }

  // Connect to network
  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  const conn = await (hre as any).network.connect()
  const networkName = conn.networkName

  // Create viem client
  const client = createPublicClient({
    transport: custom(conn.provider),
  }) as PublicClient

  const actualChainId = await client.getChainId()
  await graph.autoDetect()
  const forkChainId = graph.getForkTargetChainId()
  const targetChainId = forkChainId ?? actualChainId

  // Resolve contract address
  let contractAddress: string
  let knownRoles: readonly string[] = ['GOVERNOR_ROLE', 'PAUSE_ROLE', 'OPERATOR_ROLE']

  if (contractName) {
    const resolved = resolveContractFromRegistry(contractName)
    if (resolved) {
      knownRoles = resolved.roles
      if (addressArg) {
        contractAddress = addressArg
      } else {
        const resolvedAddress = getContractAddress(resolved.addressBook, contractName, targetChainId)
        if (!resolvedAddress) {
          console.error(`\nError: Contract '${contractName}' not found in address book for chain ${targetChainId}`)
          return
        }
        contractAddress = resolvedAddress
      }
    } else {
      console.error(`\nError: Contract '${contractName}' not found in registry`)
      return
    }
  } else {
    contractAddress = addressArg!
  }

  // Get role hash
  const roleHash = await getRoleHash(client, contractAddress, roleName)
  if (!roleHash) {
    console.error(`\nError: Role '${roleName}' not found on contract`)
    console.error(`  Available roles: ${knownRoles.join(', ')}`)
    return
  }

  // Check if account has the role
  const hasRole = await accountHasRole(client, contractAddress, roleHash, targetAccount)
  if (!hasRole) {
    console.log(`\n✓ ${targetAccount} does not have ${roleName}`)
    console.log('  No action needed.\n')
    return
  }

  // Get admin role info
  const allRoles = await enumerateContractRoles(client, contractAddress, knownRoles)
  const adminInfo = await getAdminRoleInfo(client, contractAddress, roleHash, allRoles.roles)

  console.log(`\n🔐 Revoke Role: ${roleName}`)
  console.log(`   Contract: ${contractAddress}`)
  console.log(`   Target: ${targetAccount}`)
  console.log(`   Admin role: ${adminInfo.adminRoleName ?? adminInfo.adminRole}`)
  console.log(`   Admin holders: ${adminInfo.adminMembers.length > 0 ? adminInfo.adminMembers.join(', ') : '(none)'}`)

  const { deployer, walletClient } = await resolveDeployer(hre, { networkName, provider: conn.provider })
  const canExecuteDirectly = deployer ? await hasAdminRole(client, contractAddress, roleHash, deployer) : false

  const adminRoleLabel = adminInfo.adminRoleName ?? 'admin role'
  await executeOrSaveGovernance({
    conn: { networkName, provider: conn.provider },
    publicClient: client,
    walletClient,
    canExecuteDirectly,
    to: contractAddress,
    abi: ACCESS_CONTROL_ENUMERABLE_ABI,
    functionName: 'revokeRole',
    args: [roleHash, targetAccount as `0x${string}`],
    roleDescription: adminRoleLabel,
    requirementMessage: `${adminRoleLabel} to revoke`,
    successMessage: `✓ Role revoked successfully`,
    txName: `revoke-${roleName}-from-${targetAccount.slice(0, 8)}`,
    governanceName: `Revoke ${roleName}`,
    governanceDescription: `Revoke ${roleName} from ${targetAccount} on ${contractName ?? contractAddress}`,
  })
}

/**
 * Revoke a role from an account on a BaseUpgradeable contract
 *
 * Examples:
 *   npx hardhat roles:revoke --contract RewardsEligibilityOracleA --role ORACLE_ROLE --account 0x... --network arbitrumSepolia
 */
const revokeRoleTask = task('roles:revoke', 'Revoke a role from an account')
  .addOption({
    name: 'contract',
    description: 'Contract name from registry (e.g., RewardsEligibilityOracleA)',
    type: ArgumentType.STRING,
    defaultValue: '',
  })
  .addOption({
    name: 'address',
    description: 'Contract address (if not using registry lookup)',
    type: ArgumentType.STRING,
    defaultValue: '',
  })
  .addOption({
    name: 'role',
    description: 'Role name (e.g., ORACLE_ROLE, OPERATOR_ROLE)',
    type: ArgumentType.STRING,
    defaultValue: '',
  })
  .addOption({
    name: 'account',
    description: 'Account address to revoke the role from',
    type: ArgumentType.STRING,
    defaultValue: '',
  })
  .setAction(async () => ({ default: action }))
  .build()

export default revokeRoleTask
