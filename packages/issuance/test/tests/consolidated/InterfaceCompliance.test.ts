// Import generated interface IDs from the interfaces package
import {
  IAccessControl,
  IIssuanceAllocationAdministration,
  IIssuanceAllocationData,
  IIssuanceAllocationDistribution,
  IIssuanceAllocationStatus,
  IIssuanceTarget,
  IPausableControl,
  IRewardsEligibility,
  IRewardsEligibilityAdministration,
  IRewardsEligibilityReporting,
  IRewardsEligibilityStatus,
  ISendTokens,
} from '@graphprotocol/interfaces'
import { ethers } from 'hardhat'

import { shouldSupportInterfaces } from '../../utils/testPatterns'
import {
  deployDirectAllocation,
  deployIssuanceAllocator,
  deployRewardsEligibilityOracle,
  deployTestGraphToken,
  getTestAccounts,
} from '../helpers/fixtures'

/**
 * Consolidated ERC-165 Interface Compliance Tests
 * Tests interface support across all contracts to reduce duplication
 */
describe('ERC-165 Interface Compliance', () => {
  let accounts: any
  let contracts: any

  before(async () => {
    accounts = await getTestAccounts()

    // Deploy all contracts for interface testing
    const graphToken = await deployTestGraphToken()
    const graphTokenAddress = await graphToken.getAddress()

    const issuanceAllocator = await deployIssuanceAllocator(
      graphTokenAddress,
      accounts.governor,
      ethers.parseEther('100'),
    )

    const directAllocation = await deployDirectAllocation(graphTokenAddress, accounts.governor)
    const rewardsEligibilityOracle = await deployRewardsEligibilityOracle(graphTokenAddress, accounts.governor)

    contracts = {
      issuanceAllocator,
      directAllocation,
      rewardsEligibilityOracle,
    }
  })

  describe(
    'IssuanceAllocator Interface Compliance',
    shouldSupportInterfaces(
      () => contracts.issuanceAllocator,
      [
        { id: IIssuanceAllocationDistribution, name: 'IIssuanceAllocationDistribution' },
        { id: IIssuanceAllocationAdministration, name: 'IIssuanceAllocationAdministration' },
        { id: IIssuanceAllocationStatus, name: 'IIssuanceAllocationStatus' },
        { id: IIssuanceAllocationData, name: 'IIssuanceAllocationData' },
        { id: IPausableControl, name: 'IPausableControl' },
        { id: IAccessControl, name: 'IAccessControl' },
      ],
    ),
  )

  describe(
    'DirectAllocation Interface Compliance',
    shouldSupportInterfaces(
      () => contracts.directAllocation,
      [
        { id: IIssuanceTarget, name: 'IIssuanceTarget' },
        { id: ISendTokens, name: 'ISendTokens' },
        { id: IPausableControl, name: 'IPausableControl' },
        { id: IAccessControl, name: 'IAccessControl' },
      ],
    ),
  )

  describe(
    'RewardsEligibilityOracle Interface Compliance',
    shouldSupportInterfaces(
      () => contracts.rewardsEligibilityOracle,
      [
        { id: IRewardsEligibility, name: 'IRewardsEligibility' },
        { id: IRewardsEligibilityAdministration, name: 'IRewardsEligibilityAdministration' },
        { id: IRewardsEligibilityReporting, name: 'IRewardsEligibilityReporting' },
        { id: IRewardsEligibilityStatus, name: 'IRewardsEligibilityStatus' },
        { id: IPausableControl, name: 'IPausableControl' },
        { id: IAccessControl, name: 'IAccessControl' },
      ],
    ),
  )
})
