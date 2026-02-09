import { configVariable, task } from 'hardhat/config'
import { ArgumentType } from 'hardhat/types/arguments'
import type { NewTaskActionFunction } from 'hardhat/types/tasks'
import {
  createPublicClient,
  createWalletClient,
  custom,
  encodeFunctionData,
  type PublicClient,
  type WalletClient,
} from 'viem'
import { privateKeyToAccount } from 'viem/accounts'

import { ACCESS_CONTROL_ENUMERABLE_ABI } from '../lib/abis.js'
import {
  accountHasRole,
  enumerateContractRoles,
  getAdminRoleInfo,
  getRoleHash,
  hasAdminRole,
} from '../lib/contract-checks.js'
import { type AddressBookType, CONTRACT_REGISTRY } from '../lib/contract-registry.js'
import { createGovernanceTxBuilder } from '../lib/execute-governance.js'
import { graph } from '../rocketh/deploy.js'

interface TaskArgs {
  contract: string
  address: string
  role: string
  account: string
}

/**
 * Convert network name to env var prefix: arbitrumSepolia → ARBITRUM_SEPOLIA
 */
function networkToEnvPrefix(networkName: string): string {
  return networkName.replace(/([a-z])([A-Z])/g, '$1_$2').toUpperCase()
}

/**
 * Resolve a configuration variable using Hardhat's hook chain (keystore + env fallback)
 */
async function resolveConfigVar(hre: unknown, name: string): Promise<string | undefined> {
  try {
    const variable = configVariable(name)
    // eslint-disable-next-line @typescript-eslint/no-explicit-any
    const hooks = (hre as any).hooks

    const value = await hooks.runHandlerChain(
      'configurationVariables',
      'fetchValue',
      [variable],
      async (_context: unknown, v: { name: string }) => {
        const envValue = process.env[v.name]
        if (typeof envValue !== 'string') {
          throw new Error(`Variable ${v.name} not found`)
        }
        return envValue
      },
    )
    return value
  } catch {
    return undefined
  }
}

/**
 * Resolve contract from registry by name
 */
function resolveContractFromRegistry(
  contractName: string,
): { addressBook: AddressBookType; roles: readonly string[] } | null {
  for (const [book, contracts] of Object.entries(CONTRACT_REGISTRY)) {
    const contract = contracts[contractName as keyof typeof contracts] as { roles?: readonly string[] } | undefined
    if (contract?.roles) {
      return { addressBook: book as AddressBookType, roles: contract.roles }
    }
  }
  return null
}

/**
 * Get contract address from address book
 */
function getContractAddress(addressBook: AddressBookType, contractName: string, chainId: number): string | null {
  const book =
    addressBook === 'issuance'
      ? graph.getIssuanceAddressBook(chainId)
      : addressBook === 'horizon'
        ? graph.getHorizonAddressBook(chainId)
        : graph.getSubgraphServiceAddressBook(chainId)

  if (!book.entryExists(contractName)) {
    return null
  }

  return book.getEntry(contractName)?.address ?? null
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
    console.error('\nError: Must provide --account (address to grant role to)')
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

  // Check if account already has the role
  const alreadyHasRole = await accountHasRole(client, contractAddress, roleHash, targetAccount)
  if (alreadyHasRole) {
    console.log(`\n✓ ${targetAccount} already has ${roleName}`)
    console.log('  No action needed.\n')
    return
  }

  // Get admin role info
  const allRoles = await enumerateContractRoles(client, contractAddress, knownRoles)
  const adminInfo = await getAdminRoleInfo(client, contractAddress, roleHash, allRoles.roles)

  console.log(`\n🔐 Grant Role: ${roleName}`)
  console.log(`   Contract: ${contractAddress}`)
  console.log(`   Target: ${targetAccount}`)
  console.log(`   Admin role: ${adminInfo.adminRoleName ?? adminInfo.adminRole}`)
  console.log(`   Admin holders: ${adminInfo.adminMembers.length > 0 ? adminInfo.adminMembers.join(', ') : '(none)'}`)

  // Get deployer account (from keystore or env var)
  const keyName = `${networkToEnvPrefix(networkName === 'fork' ? (process.env.HARDHAT_FORK ?? 'arbitrumSepolia') : networkName)}_DEPLOYER_KEY`
  const deployerKey = await resolveConfigVar(hre, keyName)

  let deployer: string | undefined
  let walletClient: WalletClient | undefined

  if (deployerKey) {
    const account = privateKeyToAccount(deployerKey as `0x${string}`)
    deployer = account.address
    walletClient = createWalletClient({
      account,
      transport: custom(conn.provider),
    })
  }

  // Check if deployer has admin role
  const canExecuteDirectly = deployer ? await hasAdminRole(client, contractAddress, roleHash, deployer) : false

  if (canExecuteDirectly && walletClient && deployer) {
    console.log(`\n   Deployer has ${adminInfo.adminRoleName ?? 'admin role'}, executing directly...`)

    // Execute directly
    const hash = await walletClient.writeContract({
      address: contractAddress as `0x${string}`,
      abi: ACCESS_CONTROL_ENUMERABLE_ABI,
      functionName: 'grantRole',
      args: [roleHash, targetAccount as `0x${string}`],
    })

    console.log(`   TX: ${hash}`)

    // Wait for confirmation
    const receipt = await client.waitForTransactionReceipt({ hash })
    if (receipt.status === 'success') {
      console.log(`\n✓ Role granted successfully\n`)
    } else {
      console.error(`\n✗ Transaction failed\n`)
    }
  } else {
    // Generate governance TX
    console.log(`\n   Requires ${adminInfo.adminRoleName ?? 'admin role'} to grant`)
    console.log('   Generating governance TX...')

    // Create a minimal environment for the TxBuilder
    const env = {
      name: networkName,
      network: { provider: conn.provider },
      showMessage: console.log,
    }

    const txName = `grant-${roleName}-to-${targetAccount.slice(0, 8)}`
    const builder = await createGovernanceTxBuilder(env as Parameters<typeof createGovernanceTxBuilder>[0], txName, {
      name: `Grant ${roleName}`,
      description: `Grant ${roleName} to ${targetAccount} on ${contractName ?? contractAddress}`,
    })

    // Encode the grantRole call
    const data = encodeFunctionData({
      abi: ACCESS_CONTROL_ENUMERABLE_ABI,
      functionName: 'grantRole',
      args: [roleHash, targetAccount as `0x${string}`],
    })

    builder.addTx({
      to: contractAddress,
      data,
      value: '0',
    })

    const txFile = builder.saveToFile()
    console.log(`\n✓ Governance TX saved: ${txFile}`)
    console.log('\nNext steps:')
    console.log('   • Fork testing: npx hardhat deploy:execute-governance --network fork')
    console.log('   • Safe multisig: Upload JSON to Transaction Builder')
    console.log('')
  }
}

/**
 * Grant a role to an account on a BaseUpgradeable contract
 *
 * Examples:
 *   npx hardhat roles:grant --contract RewardsEligibilityOracle --role ORACLE_ROLE --account 0x... --network arbitrumSepolia
 */
const grantRoleTask = task('roles:grant', 'Grant a role to an account')
  .addOption({
    name: 'contract',
    description: 'Contract name from registry (e.g., RewardsEligibilityOracle)',
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
    description: 'Account address to grant the role to',
    type: ArgumentType.STRING,
    defaultValue: '',
  })
  .setAction(async () => ({ default: action }))
  .build()

export default grantRoleTask
