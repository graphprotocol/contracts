// Import Typechain-generated factories with interface metadata (interfaceId and interfaceName)
import {
  IPausableControl__factory,
  IRewardsEligibility__factory,
  IRewardsEligibilityAdministration__factory,
  IRewardsEligibilityReporting__factory,
  IRewardsEligibilityStatus__factory,
} from '@graphprotocol/interfaces/types'
import { IAccessControl__factory } from '@graphprotocol/issuance/types'

import { deployTestGraphToken, getTestAccounts } from '../common/fixtures'
import { shouldSupportInterfaces } from '../common/testPatterns'
import { deployRewardsEligibilityOracle } from './fixtures'

/**
 * Eligibility ERC-165 Interface Compliance Tests
 * Tests interface support for RewardsEligibilityOracle contract
 */
describe('Eligibility ERC-165 Interface Compliance', () => {
  let accounts: any
  let contracts: any

  before(async () => {
    accounts = await getTestAccounts()

    // Deploy eligibility contracts for interface testing
    const graphToken = await deployTestGraphToken()
    const graphTokenAddress = await graphToken.getAddress()

    const rewardsEligibilityOracle = await deployRewardsEligibilityOracle(graphTokenAddress, accounts.governor)

    contracts = {
      rewardsEligibilityOracle,
    }
  })

  describe(
    'RewardsEligibilityOracle Interface Compliance',
    shouldSupportInterfaces(
      () => contracts.rewardsEligibilityOracle,
      [
        IRewardsEligibility__factory,
        IRewardsEligibilityAdministration__factory,
        IRewardsEligibilityReporting__factory,
        IRewardsEligibilityStatus__factory,
        IPausableControl__factory,
        IAccessControl__factory,
      ],
    ),
  )
})
