import { connectGraphHorizon, connectGraphIssuance } from '@graphprotocol/toolshed/deployments'
import type { Provider } from 'ethers'
import { task } from 'hardhat/config'
import type { HardhatRuntimeEnvironment } from 'hardhat/types'
import path from 'path'

import { EnhancedIssuanceAddressBook } from '../lib/enhanced-address-book'

interface ContractStatus {
  name: string
  address: string
  isProxy: boolean
  implementation?: string
  pendingImplementation?: string
  verified?: boolean
  package: 'horizon' | 'issuance'
}

task('issuance:deployment-status', 'Show comprehensive deployment status for all contracts')
  .addOptionalParam('verify', 'Verify on-chain state matches address book', 'false')
  .addOptionalParam('package', 'Show only specific package (horizon|issuance|all)', 'all')
  .setAction(async (taskArgs, hre: HardhatRuntimeEnvironment) => {
    const { ethers } = hre
    const chainId = Number(hre.network.config.chainId ?? (await ethers.provider.getNetwork()).chainId)
    const provider = hre.ethers.provider
    const shouldVerify = taskArgs.verify === 'true'
    const packageFilter = taskArgs.package.toLowerCase()

    console.log('\n========== Deployment Status ==========\n')
    console.log(`Network: ${hre.network.name} (chainId=${chainId})`)
    console.log(`Verification: ${shouldVerify ? 'Enabled' : 'Disabled'}`)
    console.log()

    const statuses: ContractStatus[] = []

    // Load Horizon contracts if requested
    if (packageFilter === 'all' || packageFilter === 'horizon') {
      console.log('🏗️  Horizon Contracts:\n')
      try {
        const horizonContracts = connectGraphHorizon(chainId, provider)

        // RewardsManager
        if (horizonContracts.RewardsManager) {
          const status = await getContractStatus(
            'RewardsManager',
            horizonContracts.RewardsManager.target.toString(),
            provider,
            shouldVerify,
            'horizon',
          )
          statuses.push(status)
          printContractStatus(status)
        }

        // GraphProxyAdmin
        if (horizonContracts.GraphProxyAdmin) {
          const status = await getContractStatus(
            'GraphProxyAdmin',
            horizonContracts.GraphProxyAdmin.target.toString(),
            provider,
            shouldVerify,
            'horizon',
          )
          statuses.push(status)
          printContractStatus(status)
        }

        console.log()
      } catch (error) {
        console.log(`⚠️  Could not load Horizon contracts: ${(error as Error).message}\n`)
      }
    }

    // Load Issuance contracts if requested
    if (packageFilter === 'all' || packageFilter === 'issuance') {
      console.log('🎯 Issuance Contracts:\n')
      try {
        const issuanceContracts = connectGraphIssuance(chainId, provider)
        const issuanceAddressBookPath = path.resolve(__dirname, '../../issuance/addresses.json')
        const addressBook = new EnhancedIssuanceAddressBook(issuanceAddressBookPath, Number(chainId))

        // RewardsEligibilityOracle
        if (issuanceContracts.RewardsEligibilityOracle) {
          const pending = addressBook.getPendingImplementation('RewardsEligibilityOracle')
          const status = await getContractStatus(
            'RewardsEligibilityOracle',
            issuanceContracts.RewardsEligibilityOracle.target.toString(),
            provider,
            shouldVerify,
            'issuance',
            pending,
          )
          statuses.push(status)
          printContractStatus(status)
        }

        // IssuanceAllocator
        if (issuanceContracts.IssuanceAllocator) {
          const pending = addressBook.getPendingImplementation('IssuanceAllocator')
          const status = await getContractStatus(
            'IssuanceAllocator',
            issuanceContracts.IssuanceAllocator.target.toString(),
            provider,
            shouldVerify,
            'issuance',
            pending,
          )
          statuses.push(status)
          printContractStatus(status)
        }

        // PilotAllocation (if exists in address book)
        // Note: PilotAllocation uses DirectAllocation implementation but is a separate deployment
        // PilotAllocation is not part of GraphIssuanceContractName type, so we access it directly
        try {
          // eslint-disable-next-line @typescript-eslint/no-explicit-any
          const pilotEntry = addressBook.getEntry('PilotAllocation' as any)
          if (pilotEntry?.address) {
            // eslint-disable-next-line @typescript-eslint/no-explicit-any
            const pending = addressBook.getPendingImplementation('PilotAllocation' as any)
            const status = await getContractStatus(
              'PilotAllocation',
              pilotEntry.address,
              provider,
              shouldVerify,
              'issuance',
              pending,
            )
            statuses.push(status)
            printContractStatus(status)
          }
        } catch {
          // PilotAllocation not in address book for this network, skip
        }

        console.log()
      } catch (error) {
        console.log(`⚠️  Could not load Issuance contracts: ${(error as Error).message}\n`)
      }
    }

    // Print summary
    printSummary(statuses)
  })

async function getContractStatus(
  name: string,
  address: string,
  provider: Provider,
  verify: boolean,
  pkg: 'horizon' | 'issuance',
  pendingImplementation?: string,
): Promise<ContractStatus> {
  const status: ContractStatus = {
    name,
    address,
    isProxy: false,
    package: pkg,
    pendingImplementation,
  }

  // Check if contract is a proxy by trying to read implementation slot
  if (verify) {
    try {
      // EIP-1967 storage slot for implementation
      const implSlot = '0x360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc'
      const implBytes = await provider.getStorage(address, implSlot)

      // If slot has non-zero value, it's a proxy
      if (implBytes !== '0x' + '0'.repeat(64)) {
        status.isProxy = true
        status.implementation = '0x' + implBytes.slice(-40)
        status.verified = true
      }
    } catch (_error) {
      status.verified = false
    }
  } else {
    // Assume it's a proxy if name suggests it (heuristic)
    status.isProxy =
      name.includes('Manager') ||
      name.includes('Oracle') ||
      name.includes('Allocator') ||
      name.includes('Allocation')
    status.implementation = 'Not verified'
  }

  return status
}

function printContractStatus(status: ContractStatus): void {
  const icon = status.pendingImplementation ? '🟡' : '✅'
  console.log(`${icon} ${status.name}${status.isProxy ? ' (Proxy)' : ''}`)
  console.log(`   Address: ${status.address}`)

  if (status.isProxy && status.implementation) {
    console.log(`   Implementation: ${status.implementation}`)
  }

  if (status.pendingImplementation) {
    console.log(`   🟡 Pending: ${status.pendingImplementation}`)
    console.log(`   Status: ⏳ Upgrade pending`)
  } else {
    console.log(`   Status: ✅ Active`)
  }

  console.log()
}

function printSummary(statuses: ContractStatus[]): void {
  console.log('========== Summary ==========\n')

  const horizonCount = statuses.filter((s) => s.package === 'horizon').length
  const issuanceCount = statuses.filter((s) => s.package === 'issuance').length
  const pendingCount = statuses.filter((s) => s.pendingImplementation).length
  const proxyCount = statuses.filter((s) => s.isProxy).length

  console.log(`📊 Statistics:`)
  console.log(`   Total contracts: ${statuses.length}`)
  console.log(`   Horizon: ${horizonCount} | Issuance: ${issuanceCount}`)
  console.log(`   Proxies: ${proxyCount}`)
  console.log(`   Pending upgrades: ${pendingCount}`)

  if (pendingCount > 0) {
    console.log(`\n⚠️  Action Required:`)
    console.log(`   ${pendingCount} contract(s) have pending implementations`)
    console.log(`   Run: npx hardhat issuance:list-pending --network ${process.env.HARDHAT_NETWORK || 'hardhat'}`)
  } else {
    console.log(`\n✅ All contracts are up to date`)
  }

  console.log()
}
