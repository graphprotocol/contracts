/**
 * Example script showing how to deploy issuance contracts using Hardhat Ignition
 *
 * This script demonstrates:
 * 1. Deploying all issuance contracts
 * 2. Accessing deployed contract instances
 * 3. Interacting with deployed contracts
 *
 * Usage:
 *   npx hardhat run ignition/examples/deploy-example.ts --network localhost
 */

import { ethers, ignition } from 'hardhat'

import GraphIssuanceModule from '../modules/deploy'

async function main() {
  console.log('Deploying Graph Issuance contracts...')

  // Deploy all contracts using the main deployment module
  const {
    IssuanceAllocator,
    IssuanceAllocatorImplementation,
    IssuanceAllocatorProxyAdmin,
    DirectAllocation,
    DirectAllocationImplementation,
    DirectAllocationProxyAdmin,
    RewardsEligibilityOracle,
    RewardsEligibilityOracleImplementation,
    RewardsEligibilityOracleProxyAdmin,
  } = await ignition.deploy(GraphIssuanceModule)

  console.log('\n=== Deployment Complete ===\n')

  // Log deployed addresses
  console.log('IssuanceAllocator:')
  console.log('  Proxy:', await IssuanceAllocator.getAddress())
  console.log('  Implementation:', await IssuanceAllocatorImplementation.getAddress())
  console.log('  ProxyAdmin:', await IssuanceAllocatorProxyAdmin.getAddress())

  console.log('\nDirectAllocation:')
  console.log('  Proxy:', await DirectAllocation.getAddress())
  console.log('  Implementation:', await DirectAllocationImplementation.getAddress())
  console.log('  ProxyAdmin:', await DirectAllocationProxyAdmin.getAddress())

  console.log('\nRewardsEligibilityOracle:')
  console.log('  Proxy:', await RewardsEligibilityOracle.getAddress())
  console.log('  Implementation:', await RewardsEligibilityOracleImplementation.getAddress())
  console.log('  ProxyAdmin:', await RewardsEligibilityOracleProxyAdmin.getAddress())

  // Example: Interact with deployed contracts
  console.log('\n=== Contract Interaction Examples ===\n')

  // Get the governor (account 1)
  const [, governor] = await ethers.getSigners()

  // Check IssuanceAllocator state
  const issuancePerBlock = await IssuanceAllocator.getIssuancePerBlock()
  console.log('IssuanceAllocator issuance per block:', issuancePerBlock.toString())

  // Check RewardsEligibilityOracle state
  const eligibilityPeriod = await RewardsEligibilityOracle.getEligibilityPeriod()
  console.log('RewardsEligibilityOracle eligibility period:', eligibilityPeriod.toString(), 'seconds')

  // Check contract ownership
  const allocatorOwner = await IssuanceAllocator.owner()
  console.log('\nIssuanceAllocator owner:', allocatorOwner)
  console.log('Governor address:', governor.address)
  console.log('Owner matches governor:', allocatorOwner === governor.address)

  console.log('\n=== Deployment and verification complete! ===\n')
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error)
    process.exit(1)
  })
