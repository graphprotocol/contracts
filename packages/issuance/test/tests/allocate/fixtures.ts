/**
 * Allocate-specific test fixtures
 * Deployment and setup functions for allocate contracts
 */

import hre from 'hardhat'

const { ethers } = hre
const { upgrades } = require('hardhat')

import { Constants, deployTestGraphToken } from '../common/fixtures'
import { GraphTokenHelper } from '../common/graphTokenHelper'

/**
 * Deploy the IssuanceAllocator contract with proxy using OpenZeppelin's upgrades library
 * @param {string} graphToken
 * @param {HardhatEthersSigner} governor
 * @param {bigint} issuancePerBlock
 * @returns {Promise<IssuanceAllocator>}
 */
export async function deployIssuanceAllocator(graphToken, governor, issuancePerBlock) {
  // Deploy implementation and proxy using OpenZeppelin's upgrades library
  const IssuanceAllocatorFactory = await ethers.getContractFactory('IssuanceAllocator')

  // Deploy proxy with implementation
  const issuanceAllocatorContract = await upgrades.deployProxy(IssuanceAllocatorFactory, [governor.address], {
    constructorArgs: [graphToken],
    initializer: 'initialize',
  })

  // Get the contract instance
  const issuanceAllocator = issuanceAllocatorContract

  // Set issuance per block
  await issuanceAllocator.connect(governor).setIssuancePerBlock(issuancePerBlock, false)

  return issuanceAllocator
}

/**
 * Deploy the DirectAllocation contract with proxy using OpenZeppelin's upgrades library
 * @param {string} graphToken
 * @param {HardhatEthersSigner} governor
 * @returns {Promise<DirectAllocation>}
 */
export async function deployDirectAllocation(graphToken, governor) {
  // Deploy implementation and proxy using OpenZeppelin's upgrades library
  const DirectAllocationFactory = await ethers.getContractFactory('DirectAllocation')

  // Deploy proxy with implementation
  const directAllocationContract = await upgrades.deployProxy(DirectAllocationFactory, [governor.address], {
    constructorArgs: [graphToken],
    initializer: 'initialize',
  })

  // Return the contract instance
  return directAllocationContract
}

/**
 * Deploy allocate-only system (IssuanceAllocator + DirectAllocation targets)
 * This version excludes eligibility contracts for clean separation in tests
 * @param {TestAccounts} accounts
 * @param {bigint} [issuancePerBlock=Constants.DEFAULT_ISSUANCE_PER_BLOCK]
 * @returns {Promise<Object>}
 */
export async function deployAllocateSystem(accounts, issuancePerBlock = Constants.DEFAULT_ISSUANCE_PER_BLOCK) {
  const { governor } = accounts

  // Deploy test GraphToken
  const graphToken = await deployTestGraphToken()
  const graphTokenAddress = await graphToken.getAddress()

  // Deploy IssuanceAllocator
  const issuanceAllocator = await deployIssuanceAllocator(graphTokenAddress, governor, issuancePerBlock)

  // Add the IssuanceAllocator as a minter on the GraphToken
  const graphTokenHelper = new GraphTokenHelper(graphToken as any, governor)
  await graphTokenHelper.addMinter(await issuanceAllocator.getAddress())

  // Deploy DirectAllocation targets
  const target1 = await deployDirectAllocation(graphTokenAddress, governor)
  const target2 = await deployDirectAllocation(graphTokenAddress, governor)

  return {
    graphToken,
    issuanceAllocator,
    target1,
    target2,
  }
}
