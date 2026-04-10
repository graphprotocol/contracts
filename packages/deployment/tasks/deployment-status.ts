import { task } from 'hardhat/config'
import { ArgumentType } from 'hardhat/types/arguments'
import type { NewTaskActionFunction } from 'hardhat/types/tasks'
import { createPublicClient, custom, http, type PublicClient } from 'viem'

import { CONTROLLER_ABI } from '../lib/abis.js'
import { autoDetectForkNetwork } from '../lib/address-book-utils.js'
import { formatAddress } from '../lib/contract-checks.js'
import { type AddressBookType, getContractsByAddressBook } from '../lib/contract-registry.js'
import {
  getIssuanceAllocatorChecks,
  getReclaimAddressChecks,
  getRewardsEligibilityOracleChecks,
  getRewardsManagerChecks,
  type IntegrationCheck,
} from '../lib/status-detail.js'
import { getContractStatusLine, type ProxyAdminOwnershipContext } from '../lib/sync-utils.js'
import { graph } from '../rocketh/deploy.js'

/** Get deployable contract names for an address book (requires explicit deployable: true) */
function getDeployableContracts(addressBook: AddressBookType): string[] {
  return getContractsByAddressBook(addressBook)
    .filter(([_, meta]) => meta.deployable === true)
    .map(([name]) => name)
}

/**
 * Get non-deployable contract names for an address book.
 *
 * Includes prerequisites (`prerequisite: true`), address-only entries
 * (`addressOnly: true`) and pure registry placeholders (`{}`). The status task
 * surfaces these as context — they're contracts the deployment depends on but
 * doesn't manage. Entries not present in the on-chain address book are filtered
 * out at print time so the listing only shows what actually exists for the
 * network.
 */
function getPrerequisiteContracts(addressBook: AddressBookType): string[] {
  return getContractsByAddressBook(addressBook)
    .filter(([_, meta]) => meta.deployable !== true)
    .map(([name]) => name)
}

function printCheck(check: IntegrationCheck): void {
  const icon = check.ok === null ? '○' : check.ok ? '✓' : '✗'
  console.log(`        ${icon} ${check.label}`)
}

function printWarnings(warnings: string[] | undefined): void {
  if (!warnings) return
  for (const warning of warnings) {
    console.log(`      ⚠ ${warning}`)
  }
}

/** Print proxy admin detail in verbose/component mode */
function printProxyAdminDetail(result: {
  proxyAdminOwner?: string
  proxyAdminAddress?: string
  proxyAdminOwnerAddress?: string
}): void {
  if (!result.proxyAdminAddress) return
  const ownerLabel =
    result.proxyAdminOwner === 'governor'
      ? 'governor ✓'
      : result.proxyAdminOwner === 'deployer'
        ? 'deployer ⚠'
        : 'not governor ⚠'
  const ownerAddr = result.proxyAdminOwnerAddress ? ` ${result.proxyAdminOwnerAddress}` : ''
  console.log(`        ProxyAdmin: ${result.proxyAdminAddress}`)
  console.log(`        ProxyAdmin owner:${ownerAddr} (${ownerLabel})`)
}

/**
 * Print prerequisite contracts (non-deployable registry entries) in a dim format.
 *
 * Shown after the deployable contracts in each address book section. Skips
 * entries that aren't present in the address book — placeholders that are in
 * the registry for type completeness but aren't configured for the network are
 * silent rather than printed as `(not deployed)`.
 *
 * In default mode each entry is one line: `·   Name @ 0x1234...5678`. In
 * verbose mode the full `getContractStatusLine` output is shown so users can
 * drill into proxy detail for prerequisites that have it.
 */
async function printPrerequisites(
  client: PublicClient | undefined,
  addressBookType: AddressBookType,
  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  addressBook: any,
  matchesComponent: (name: string) => boolean,
  verbose: boolean,
  ownershipCtx: ProxyAdminOwnershipContext | undefined,
): Promise<void> {
  const names = getPrerequisiteContracts(addressBookType).filter(matchesComponent)
  // Filter to entries actually present in the address book — placeholders that
  // aren't configured for this network shouldn't add noise.
  const present = names.filter((name) => addressBook.entryExists(name))
  if (present.length === 0) return

  for (const name of present) {
    if (verbose) {
      const result = await getContractStatusLine(client, addressBookType, addressBook, name, undefined, ownershipCtx)
      console.log(`  · ${result.line}`)
      printWarnings(result.warnings)
      printProxyAdminDetail(result)
    } else {
      const entry = addressBook.getEntry(name)
      const addr = entry?.address ? formatAddress(entry.address) : '(no address)'
      console.log(`  ·   ${name} @ ${addr}`)
    }
  }
}

interface TaskArgs {
  package: string
  verbose: boolean
  component: string
}

const action: NewTaskActionFunction<TaskArgs> = async (taskArgs, hre) => {
  // HH v3: Connect to network to get chainId and network name
  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  const conn = await (hre as any).network.connect()
  const networkName = conn.networkName
  const packageFilter = taskArgs.package.toLowerCase()
  const verbose = taskArgs.verbose
  const componentFilter = taskArgs.component?.toLowerCase() || ''
  const showDetail = verbose || !!componentFilter

  // Get configured chain ID from network config (always available)
  const configuredChainId = conn.networkConfig?.chainId as number | undefined

  // Default RPC URLs for read-only access (no accounts needed)
  const DEFAULT_RPC_URLS: Record<string, string> = {
    arbitrumOne: 'https://arb1.arbitrum.io/rpc',
    arbitrumSepolia: 'https://sepolia-rollup.arbitrum.io/rpc',
  }

  // Get RPC URL: prefer env var, then default
  const envRpcUrl =
    networkName === 'arbitrumSepolia'
      ? process.env.ARBITRUM_SEPOLIA_RPC
      : networkName === 'arbitrumOne'
        ? process.env.ARBITRUM_ONE_RPC
        : undefined
  const rpcUrl = envRpcUrl || DEFAULT_RPC_URLS[networkName]

  // Get viem public client for on-chain checks
  // Use direct HTTP transport to RPC URL (bypasses Hardhat's account resolution)
  let client: PublicClient | undefined
  let actualChainId: number | undefined
  let providerError: string | undefined

  if (rpcUrl) {
    // Create read-only client directly to RPC (no accounts needed)
    try {
      client = createPublicClient({
        transport: http(rpcUrl),
      }) as PublicClient
      actualChainId = await client.getChainId()
    } catch (e) {
      client = undefined
      const errMsg = e instanceof Error ? e.message : String(e)
      providerError = errMsg.split('\n')[0]
    }
  } else {
    // No RPC URL available - try Hardhat's provider (may fail if accounts not configured)
    try {
      if (conn.provider) {
        client = createPublicClient({
          transport: custom(conn.provider),
        }) as PublicClient
        actualChainId = await client.getChainId()
      }
    } catch (e) {
      // Provider failed - disable on-chain checks
      client = undefined

      // Extract error message (may be nested in viem error or cause chain)
      let errMsg = e instanceof Error ? e.message : String(e)
      const cause = e instanceof Error ? (e as Error & { cause?: Error }).cause : undefined
      if (cause?.message) {
        errMsg = cause.message
      }

      providerError = errMsg.split('\n')[0]
    }
  }

  // Auto-detect fork network from anvil if on localhost without FORK_NETWORK
  if (configuredChainId === 31337 && !process.env.FORK_NETWORK && !process.env.HARDHAT_FORK) {
    const detected = await autoDetectForkNetwork()
    if (detected) {
      console.log(`🔍 Auto-detected fork network: ${detected}`)
    }
  }

  // Determine target chain ID: use fork target, then configured, then actual, then fallback
  const forkChainId = graph.getForkTargetChainId()
  const isForkMode = forkChainId !== null
  const targetChainId = forkChainId ?? configuredChainId ?? actualChainId ?? 31337

  // Show status header with chain info
  if (isForkMode) {
    console.log(`\n🔍 Status: ${networkName} (fork of chainId ${targetChainId})\n`)
  } else if (actualChainId && actualChainId !== targetChainId) {
    console.log(`\n🔍 Status: ${networkName} (chainId: ${actualChainId})`)
    console.log(`⚠️  Warning: Connected chain (${actualChainId}) differs from target (${targetChainId})`)
    console.log(`   Address book lookups use chainId ${targetChainId}\n`)
  } else {
    console.log(`\n🔍 Status: ${networkName} (chainId: ${targetChainId})\n`)
  }

  // Show provider warning if we couldn't connect (but continue with address book lookups)
  if (providerError) {
    console.log(`⚠️  Provider unavailable: ${providerError}`)
    console.log(`   On-chain checks disabled. Set the missing variable or use --network hardhat for local testing.\n`)
  }

  // Get address books
  const horizonAddressBook = graph.getHorizonAddressBook(targetChainId)
  const subgraphServiceAddressBook = graph.getSubgraphServiceAddressBook(targetChainId)
  const issuanceAddressBook = graph.getIssuanceAddressBook(targetChainId)

  // Resolve governor/deployer for proxy admin ownership checks
  let ownershipCtx: ProxyAdminOwnershipContext | undefined
  if (client) {
    try {
      const controllerAddress = horizonAddressBook.entryExists('Controller')
        ? horizonAddressBook.getEntry('Controller')?.address
        : null
      if (controllerAddress) {
        const governor = (await client.readContract({
          address: controllerAddress as `0x${string}`,
          abi: CONTROLLER_ABI,
          functionName: 'getGovernor',
        })) as string

        if (governor) {
          // Deployer is best-effort: available when provider has accounts (fork/local)
          let deployer: string | undefined
          try {
            const accounts = (await conn.provider?.request({ method: 'eth_accounts' })) as string[] | undefined
            if (accounts && accounts.length > 0) {
              deployer = accounts[0]
            }
          } catch {
            // No accounts available (read-only provider) — that's fine
          }
          ownershipCtx = { governor, deployer }
        }
      }
    } catch {
      // Controller not available — skip ownership checks
    }
  }

  // Helper to check if a contract name matches the component filter
  const matchesComponent = (name: string) => !componentFilter || name.toLowerCase().includes(componentFilter)

  // Show ownership context in verbose mode
  if (verbose && ownershipCtx) {
    console.log(`  Governor: ${ownershipCtx.governor}`)
    if (ownershipCtx.deployer) {
      console.log(`  Deployer: ${ownershipCtx.deployer}`)
    }
    console.log()
  }

  // Horizon contracts (deploy targets + prerequisites)
  if (packageFilter === 'all' || packageFilter === 'horizon') {
    const contracts = getDeployableContracts('horizon').filter(matchesComponent)
    if (contracts.length > 0 || showDetail) {
      console.log('📦 Horizon')
      for (const name of contracts) {
        const result = await getContractStatusLine(client, 'horizon', horizonAddressBook, name, undefined, ownershipCtx)
        console.log(`  ${result.line}`)
        printWarnings(result.warnings)

        if (showDetail) {
          printProxyAdminDetail(result)

          // Integration checks for RewardsManager (only if deployed)
          if (name === 'RewardsManager' && client && result.exists) {
            const checks = await getRewardsManagerChecks(client, horizonAddressBook)
            for (const check of checks) {
              printCheck(check)
            }
          }
        }
      }
      if (showDetail) {
        await printPrerequisites(client, 'horizon', horizonAddressBook, matchesComponent, verbose, ownershipCtx)
      }
    }
  }

  // SubgraphService contracts
  if (packageFilter === 'all' || packageFilter === 'subgraph-service') {
    const contracts = getDeployableContracts('subgraph-service').filter(matchesComponent)
    if (contracts.length > 0 || showDetail) {
      console.log('\n📦 SubgraphService')
      for (const name of contracts) {
        const result = await getContractStatusLine(
          client,
          'subgraph-service',
          subgraphServiceAddressBook,
          name,
          undefined,
          ownershipCtx,
        )
        console.log(`  ${result.line}`)
        printWarnings(result.warnings)
        if (showDetail) {
          printProxyAdminDetail(result)
        }
      }
      if (showDetail) {
        await printPrerequisites(
          client,
          'subgraph-service',
          subgraphServiceAddressBook,
          matchesComponent,
          verbose,
          ownershipCtx,
        )
      }
    }
  }

  // Issuance contracts
  if (packageFilter === 'all' || packageFilter === 'issuance') {
    const contracts = getDeployableContracts('issuance').filter(matchesComponent)
    if (contracts.length > 0 || showDetail) {
      console.log('\n📦 Issuance')
      for (const name of contracts) {
        const result = await getContractStatusLine(
          client,
          'issuance',
          issuanceAddressBook,
          name,
          undefined,
          ownershipCtx,
        )
        console.log(`  ${result.line}`)
        printWarnings(result.warnings)

        if (showDetail) {
          printProxyAdminDetail(result)

          // Integration checks for IssuanceAllocator (only if deployed)
          if (name === 'IssuanceAllocator' && client && result.exists) {
            const checks = await getIssuanceAllocatorChecks(client, horizonAddressBook, issuanceAddressBook)
            for (const check of checks) {
              printCheck(check)
            }
          }

          // Integration checks for REO instances (only if deployed)
          if (
            (name === 'RewardsEligibilityOracleA' || name === 'RewardsEligibilityOracleB') &&
            client &&
            result.exists
          ) {
            const checks = await getRewardsEligibilityOracleChecks(
              client,
              horizonAddressBook,
              issuanceAddressBook,
              name,
            )
            for (const check of checks) {
              printCheck(check)
            }
          }

          // Integration checks for reclaim address (only if deployed)
          if (name === 'ReclaimedRewards' && client && result.exists) {
            const checks = await getReclaimAddressChecks(client, horizonAddressBook, issuanceAddressBook)
            for (const check of checks) {
              printCheck(check)
            }
          }
        }
      }
      if (showDetail) {
        await printPrerequisites(client, 'issuance', issuanceAddressBook, matchesComponent, verbose, ownershipCtx)
      }
    }
  }

  // Legend for icons (shown when proxy admin warnings are present or in verbose mode)
  if (verbose) {
    console.log(
      '\n  Legend: ✓ ok  △ code changed  ◷ pending upgrade  ↑ upgraded  ↻ synced  🔑 ProxyAdmin not on governor',
    )
  }

  console.log()
}

const deployStatusTask = task('deploy:status', 'Show deployment and integration status')
  .addOption({
    name: 'package',
    description: 'Show only specific package (horizon|subgraph-service|issuance|all)',
    type: ArgumentType.STRING,
    defaultValue: 'all',
  })
  .addOption({
    name: 'verbose',
    description: 'Show full detail including proxy admin ownership, addresses, and legend',
    type: ArgumentType.FLAG,
    defaultValue: false,
  })
  .addOption({
    name: 'component',
    description: 'Filter to contracts matching this name (case-insensitive substring match)',
    type: ArgumentType.STRING,
    defaultValue: '',
  })
  .setAction(async () => ({ default: action }))
  .build()

export default deployStatusTask
