import { existsSync } from 'node:fs'

import {
  getForkNetwork,
  getForkStateDir,
  getIssuanceAddressBookPath,
} from '@graphprotocol/deployment/lib/address-book-utils.js'
import {
  type AddressBookType,
  getContractMetadata,
  getContractsByAddressBook,
} from '@graphprotocol/deployment/lib/contract-registry.js'
import { SpecialTags } from '@graphprotocol/deployment/lib/deployment-tags.js'
import {
  type AddressBookGroup,
  buildContractSpec,
  type ContractSpec,
  syncContractGroups,
} from '@graphprotocol/deployment/lib/sync-utils.js'
import { graph } from '@graphprotocol/deployment/rocketh/deploy.js'
import type { DeployScriptModule } from '@rocketh/core/types'

// Sync - Synchronization between on-chain state and address books
//
// For each address book (Horizon, SubgraphService, Issuance):
// - Sync proxy implementations with on-chain state
// - Import contract addresses into rocketh deployment records
// - Validate prerequisites exist on-chain

// Helper to filter deployable contracts from registry
function getDeployableContracts(addressBook: AddressBookType) {
  return getContractsByAddressBook(addressBook)
    .filter(([_, metadata]) => metadata.deployable !== false)
    .map(([name]) => name)
}

const func: DeployScriptModule = async (env) => {
  // Get chainId from provider (will be 31337 in fork mode)
  const chainIdHex = await env.network.provider.request({ method: 'eth_chainId' })
  const providerChainId = Number(chainIdHex)

  // Determine target chain ID for address book lookups
  const forkNetwork = getForkNetwork()
  const isForking = graph.isForkMode()
  const forkChainId = graph.getForkTargetChainId()
  const targetChainId = forkChainId ?? providerChainId

  // Check for common misconfiguration: localhost without FORK_NETWORK
  if (providerChainId === 31337 && !forkNetwork) {
    throw new Error(
      `Running on localhost (chainId 31337) without FORK_NETWORK set.\n\n` +
        `If you're testing against a forked network, set the environment variable:\n` +
        `  export FORK_NETWORK=arbitrumSepolia\n` +
        `  npx hardhat deploy --tags sync --network localhost\n\n` +
        `Or use ephemeral fork mode:\n` +
        `  HARDHAT_FORK=arbitrumSepolia npx hardhat deploy --tags sync`,
    )
  }

  if (forkNetwork) {
    const forkStateDir = getForkStateDir(env.name, forkNetwork)
    env.showMessage(`\n🔄 Sync: ${forkNetwork} fork (chainId: ${targetChainId})`)
    env.showMessage(`   Using fork-local address books (${forkStateDir}/)`)
  } else {
    env.showMessage(`\n🔄 Sync: ${env.name} (chainId: ${providerChainId})`)
  }

  // Get address books (automatically uses fork-local copies in fork mode)
  const horizonAddressBook = graph.getHorizonAddressBook(targetChainId)
  const ssAddressBook = graph.getSubgraphServiceAddressBook(targetChainId)

  // Build contract groups
  const groups: AddressBookGroup[] = []

  // --- Horizon contracts ---
  const horizonContracts: ContractSpec[] = getDeployableContracts('horizon').map((name) => {
    const metadata = getContractMetadata('horizon', name)
    if (!metadata) throw new Error(`Contract ${name} not found in horizon registry`)
    return buildContractSpec('horizon', name, metadata, horizonAddressBook, targetChainId)
  })
  groups.push({ label: 'Horizon', contracts: horizonContracts, addressBook: horizonAddressBook })

  // --- SubgraphService contracts ---
  const ssContracts: ContractSpec[] = getDeployableContracts('subgraph-service').map((name) => {
    const metadata = getContractMetadata('subgraph-service', name)
    if (!metadata) throw new Error(`Contract ${name} not found in subgraph-service registry`)
    return buildContractSpec('subgraph-service', name, metadata, ssAddressBook, targetChainId)
  })
  groups.push({ label: 'SubgraphService', contracts: ssContracts, addressBook: ssAddressBook })

  // --- Issuance contracts ---
  // Show all issuance contracts from registry (even if not deployed yet)
  const issuanceBookPath = getIssuanceAddressBookPath()
  const issuanceAddressBook = existsSync(issuanceBookPath) ? graph.getIssuanceAddressBook(targetChainId) : null

  if (issuanceAddressBook) {
    // Show all deployable issuance contracts from registry (even if not deployed yet)
    const issuanceContracts: ContractSpec[] = getDeployableContracts('issuance').map((name) => {
      const metadata = getContractMetadata('issuance', name)
      if (!metadata) throw new Error(`Contract ${name} not found in issuance registry`)
      return buildContractSpec('issuance', name, metadata, issuanceAddressBook, targetChainId)
    })

    if (issuanceContracts.length > 0) {
      groups.push({ label: 'Issuance', contracts: issuanceContracts, addressBook: issuanceAddressBook })
    }
  }

  // Sync all contract groups
  const result = await syncContractGroups(env, groups)

  if (!result.success) {
    env.showMessage(`\n❌ Sync failed: address book does not match chain state.\n`)
    env.showMessage(`The following contracts are in address book but have no code on-chain:`)
    env.showMessage(`  ${result.failures.join(', ')}\n`)
    if (isForking) {
      env.showMessage(`This is likely because the fork was restarted.\n`)
      env.showMessage(`To fix, reset fork state and re-run:`)
      env.showMessage(`  npx hardhat deploy:reset-fork --network localhost`)
    } else {
      env.showMessage(`Possible causes:`)
      env.showMessage(`  1. Address book has incorrect addresses for this network`)
      env.showMessage(`  2. Running against wrong network`)
    }
    process.exit(1)
  }

  env.showMessage(`\n✅ Sync complete: ${result.totalSynced} contracts synced\n`)
}

func.tags = [SpecialTags.SYNC]
export default func
