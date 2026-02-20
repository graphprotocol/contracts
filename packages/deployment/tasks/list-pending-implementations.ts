import path from 'node:path'

import { task } from 'hardhat/config'
import type { NewTaskActionFunction } from 'hardhat/types/tasks'

import type { AddressBookEntry, AddressBookOps } from '../lib/address-book-ops.js'
import {
  getForkTargetChainId,
  getHorizonAddressBook,
  getIssuanceAddressBook,
  getSubgraphServiceAddressBook,
  isForkMode,
} from '../lib/address-book-utils.js'
import { getGovernanceTxDir, hasGovernanceTx } from '../lib/execute-governance.js'

interface AddressBookConfig {
  name: string
  getAddressBook: () => AddressBookOps
}

/**
 * List all contracts with pending implementations
 *
 * Checks all address books (horizon, subgraph-service, issuance) for pending implementations
 * awaiting governance approval.
 *
 * Usage:
 *   npx hardhat deploy:list-pending --network arbitrumOne
 */
const action: NewTaskActionFunction = async (_taskArgs, hre) => {
  // HH v3: Connect to network to get chainId and network name
  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  const conn = await (hre as any).network.connect()
  const networkName = conn.networkName

  // Get target chain ID (fork mode or provider)
  const forkChainId = getForkTargetChainId()
  let targetChainId: number
  if (forkChainId !== null) {
    targetChainId = forkChainId
  } else {
    const chainIdHex = await conn.provider.request({ method: 'eth_chainId' })
    targetChainId = Number(chainIdHex)
  }

  console.log('\n========== Pending Implementations ==========\n')
  if (isForkMode()) {
    console.log(`Network: ${networkName} (fork of chainId ${targetChainId})`)
  } else {
    console.log(`Network: ${networkName} (chainId=${targetChainId})`)
  }

  // Configure all address books to check (using fork-aware helpers)
  const addressBooks: AddressBookConfig[] = [
    {
      name: 'horizon',
      getAddressBook: () => getHorizonAddressBook(targetChainId),
    },
    {
      name: 'subgraph-service',
      getAddressBook: () => getSubgraphServiceAddressBook(targetChainId),
    },
    {
      name: 'issuance',
      getAddressBook: () => getIssuanceAddressBook(targetChainId),
    },
  ]

  let totalPending = 0

  for (const config of addressBooks) {
    let addressBook: AddressBookOps
    try {
      addressBook = config.getAddressBook()
    } catch {
      // Address book doesn't exist or doesn't have entries for this chain
      continue
    }

    const pendingContracts = addressBook.listPendingImplementations()

    if (pendingContracts.length === 0) {
      continue
    }

    console.log(`\n📚 ${config.name}/addresses.json:`)

    for (const contractName of pendingContracts) {
      const entry = addressBook.getEntry(contractName as never) as AddressBookEntry
      const pending = entry.pendingImplementation

      if (!pending) continue

      totalPending++

      console.log(`\n   📦 ${contractName}:`)
      console.log(`      Proxy: ${entry.address}`)
      console.log(`      Current implementation: ${entry.implementation || 'N/A'}`)
      console.log(`      Pending implementation: ${pending.address}`)
      if (pending.deployment?.timestamp) {
        console.log(`      Deployed at: ${pending.deployment.timestamp}`)
      }
      if (pending.deployment?.txHash) {
        console.log(`      Deploy TX: ${pending.deployment.txHash}`)
      }
      if (pending.deployment?.blockNumber) {
        console.log(`      Block number: ${pending.deployment.blockNumber}`)
      }

      // Check for existing governance TX file
      const txName = `upgrade-${contractName}`
      if (hasGovernanceTx(networkName, txName)) {
        const txFile = path.join(getGovernanceTxDir(networkName), `${txName}.json`)
        console.log(`      Governance TX: ${txFile}`)
      }
    }
  }

  if (totalPending === 0) {
    console.log('\n✅ No pending implementations across all address books')
    return
  }

  console.log(`\n📊 Total: ${totalPending} contract(s) with pending implementations`)

  console.log('\n🎯 Next steps:')
  console.log('   1. Generate governance TX (if not already done)')
  console.log('   2. Execute governance via Safe UI')
  console.log('   3. Sync address book with on-chain state:')
  console.log(`      npx hardhat deploy --tags sync --network ${networkName}`)
}

const listPendingTask = task('deploy:list-pending', 'List all contracts with pending implementations')
  .setAction(async () => ({ default: action }))
  .build()

export default listPendingTask
