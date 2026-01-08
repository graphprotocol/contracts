// Import Typechain-generated factories with interface metadata (interfaceId and interfaceName)
import {
  IIssuanceAllocationAdministration__factory,
  IIssuanceAllocationData__factory,
  IIssuanceAllocationDistribution__factory,
  IIssuanceAllocationStatus__factory,
  IIssuanceTarget__factory,
  IPausableControl__factory,
  ISendTokens__factory,
} from '@graphprotocol/interfaces/types'
import { IAccessControl__factory } from '@graphprotocol/issuance/types'
import { ethers } from 'hardhat'

import { deployTestGraphToken, getTestAccounts } from '../common/fixtures'
import { deployDirectAllocation, deployIssuanceAllocator } from './fixtures'
import { shouldSupportInterfaces } from './testPatterns'

/**
 * Allocate ERC-165 Interface Compliance Tests
 * Tests interface support for IssuanceAllocator and DirectAllocation contracts
 */
describe('Allocate ERC-165 Interface Compliance', () => {
  let accounts: any
  let contracts: any

  before(async () => {
    accounts = await getTestAccounts()

    // Deploy allocate contracts for interface testing
    const graphToken = await deployTestGraphToken()
    const graphTokenAddress = await graphToken.getAddress()

    const issuanceAllocator = await deployIssuanceAllocator(
      graphTokenAddress,
      accounts.governor,
      ethers.parseEther('100'),
    )

    const directAllocation = await deployDirectAllocation(graphTokenAddress, accounts.governor)

    contracts = {
      issuanceAllocator,
      directAllocation,
    }
  })

  describe(
    'IssuanceAllocator Interface Compliance',
    shouldSupportInterfaces(
      () => contracts.issuanceAllocator,
      [
        IIssuanceAllocationDistribution__factory,
        IIssuanceAllocationAdministration__factory,
        IIssuanceAllocationStatus__factory,
        IIssuanceAllocationData__factory,
        IPausableControl__factory,
        IAccessControl__factory,
      ],
    ),
  )

  describe(
    'DirectAllocation Interface Compliance',
    shouldSupportInterfaces(
      () => contracts.directAllocation,
      [IIssuanceTarget__factory, ISendTokens__factory, IPausableControl__factory, IAccessControl__factory],
    ),
  )
})
