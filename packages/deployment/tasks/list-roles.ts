import { task } from 'hardhat/config'
import { ArgumentType } from 'hardhat/types/arguments'
import type { NewTaskActionFunction } from 'hardhat/types/tasks'
import { createPublicClient, custom, type PublicClient } from 'viem'

import { enumerateContractRoles, type RoleInfo } from '../lib/contract-checks.js'
import { Contracts, type IssuanceContractName } from '../lib/contract-registry.js'
import { getContractAddress, resolveContractFromRegistry } from '../lib/task-utils.js'
import { graph } from '../rocketh/deploy.js'

interface TaskArgs {
  contract: string
  address: string
}

/**
 * Format a bytes32 role hash for display
 */
function formatRoleHash(role: `0x${string}`): string {
  return `${role.slice(0, 10)}...${role.slice(-8)}`
}

/**
 * Get known role name from hash (for admin role display)
 */
function getKnownRoleName(roleHash: `0x${string}`, knownRoles: RoleInfo[]): string | null {
  const match = knownRoles.find((r) => r.role === roleHash)
  return match?.name ?? null
}

/**
 * Print role information in a formatted way
 */
function printRoleInfo(role: RoleInfo, knownRoles: RoleInfo[]): void {
  const adminName = getKnownRoleName(role.adminRole, knownRoles)
  const adminDisplay = adminName ?? formatRoleHash(role.adminRole)

  console.log(`\n  ${role.name} (${role.role})`)
  console.log(`    Admin: ${adminDisplay}`)
  console.log(`    Members (${role.memberCount}):`)

  if (role.members.length === 0) {
    console.log(`      (none)`)
  } else {
    for (const member of role.members) {
      console.log(`      - ${member}`)
    }
  }
}

const action: NewTaskActionFunction<TaskArgs> = async (taskArgs, hre) => {
  // Empty strings treated as not provided
  const contractName = taskArgs.contract || undefined
  const address = taskArgs.address || undefined

  // Validate: must provide either --contract or --address
  if (!contractName && !address) {
    console.error('\nError: Must provide either --contract or --address')
    console.error('  --contract <name>  Contract name from registry (e.g., RewardsEligibilityOracleA)')
    console.error('  --address <addr>   Contract address (requires known role list)\n')
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

  // Determine target chain ID (handle fork mode)
  await graph.autoDetect()
  const forkChainId = graph.getForkTargetChainId()
  const targetChainId = forkChainId ?? actualChainId

  let contractAddress: string
  let roles: readonly string[]

  if (contractName) {
    // Resolve from registry
    const resolved = resolveContractFromRegistry(contractName)
    if (!resolved) {
      console.error(`\nError: Contract '${contractName}' not found in registry or has no roles defined`)
      console.error('\nContracts with role definitions:')
      for (const name of Object.keys(Contracts.issuance)) {
        const meta = Contracts.issuance[name as IssuanceContractName]
        if (meta.roles) {
          console.error(`  - ${name}`)
        }
      }
      console.error()
      return
    }

    roles = resolved.roles

    // Get address from address book
    if (address) {
      // Use provided address
      contractAddress = address
    } else {
      const resolvedAddress = getContractAddress(resolved.addressBook, contractName, targetChainId)
      if (!resolvedAddress) {
        console.error(`\nError: Contract '${contractName}' not found in address book for chain ${targetChainId}`)
        console.error('  Provide --address to specify the contract address manually\n')
        return
      }
      contractAddress = resolvedAddress
    }
  } else {
    // Address-only mode - need to figure out roles
    // For now, use base roles; could be enhanced to detect contract type
    contractAddress = address!
    roles = ['GOVERNOR_ROLE', 'PAUSE_ROLE', 'OPERATOR_ROLE']
    console.log('\nNote: Using base roles only (GOVERNOR, PAUSE, OPERATOR)')
    console.log('      Use --contract <name> to enumerate contract-specific roles\n')
  }

  // Print header
  console.log(`\n🔐 Roles: ${contractName ?? 'Unknown'}`)
  console.log(`   Address: ${contractAddress}`)
  console.log(`   Network: ${networkName} (chainId: ${actualChainId})`)

  // Enumerate roles
  const result = await enumerateContractRoles(client, contractAddress, roles)

  // Print results
  for (const role of result.roles) {
    printRoleInfo(role, result.roles)
  }

  // Print failed roles (if any)
  if (result.failedRoles.length > 0) {
    console.log('\n  ⚠ Failed to read roles:')
    for (const failed of result.failedRoles) {
      console.log(`    - ${failed}`)
    }
  }

  console.log()
}

/**
 * List all role holders for a BaseUpgradeable contract
 *
 * Examples:
 *   npx hardhat roles:list --contract RewardsEligibilityOracleA --network arbitrumSepolia
 *   npx hardhat roles:list --address 0x62c2... --network arbitrumSepolia
 */
const listRolesTask = task('roles:list', 'List all role holders for a contract')
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
  .setAction(async () => ({ default: action }))
  .build()

export default listRolesTask
