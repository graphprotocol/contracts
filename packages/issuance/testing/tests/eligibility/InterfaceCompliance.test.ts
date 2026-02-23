// Use dynamic import for ESM/CJS interop
import { expect } from 'chai'

import { deployTestGraphToken, getTestAccounts } from '../common/fixtures'
import { deployRewardsEligibilityOracle } from './fixtures'

// Standard interface IDs (well-known constants)
// IAccessControl: OpenZeppelin AccessControl interface
const IACCESSCONTROL_INTERFACE_ID = '0x7965db0b'

// Module-level variables for lazy-loaded factories
let factories: {
  IPausableControl__factory: any
  IRewardsEligibility__factory: any
  IRewardsEligibilityAdministration__factory: any
  IRewardsEligibilityReporting__factory: any
  IRewardsEligibilityStatus__factory: any
}

/**
 * Eligibility ERC-165 Interface Compliance Tests
 * Tests interface support for RewardsEligibilityOracle contract
 */
describe('Eligibility ERC-165 Interface Compliance', () => {
  let accounts: any
  let contracts: any

  before(async () => {
    // Import directly from dist to avoid ts-node circular dependency issues
    const interfacesTypes = await import('@graphprotocol/interfaces/dist/types/index.js')

    factories = {
      IPausableControl__factory: interfacesTypes.IPausableControl__factory,
      IRewardsEligibility__factory: interfacesTypes.IRewardsEligibility__factory,
      IRewardsEligibilityAdministration__factory: interfacesTypes.IRewardsEligibilityAdministration__factory,
      IRewardsEligibilityReporting__factory: interfacesTypes.IRewardsEligibilityReporting__factory,
      IRewardsEligibilityStatus__factory: interfacesTypes.IRewardsEligibilityStatus__factory,
    }

    accounts = await getTestAccounts()

    // Deploy eligibility contracts for interface testing
    const graphToken = await deployTestGraphToken()
    const graphTokenAddress = await graphToken.getAddress()

    const rewardsEligibilityOracle = await deployRewardsEligibilityOracle(graphTokenAddress, accounts.governor)

    contracts = {
      rewardsEligibilityOracle,
    }
  })

  describe('RewardsEligibilityOracle Interface Compliance', function () {
    it('should support ERC-165 interface', async function () {
      expect(await contracts.rewardsEligibilityOracle.supportsInterface('0x01ffc9a7')).to.be.true
    })

    it('should support IRewardsEligibility interface', async function () {
      expect(
        await contracts.rewardsEligibilityOracle.supportsInterface(factories.IRewardsEligibility__factory.interfaceId),
      ).to.be.true
    })

    it('should support IRewardsEligibilityAdministration interface', async function () {
      expect(
        await contracts.rewardsEligibilityOracle.supportsInterface(
          factories.IRewardsEligibilityAdministration__factory.interfaceId,
        ),
      ).to.be.true
    })

    it('should support IRewardsEligibilityReporting interface', async function () {
      expect(
        await contracts.rewardsEligibilityOracle.supportsInterface(
          factories.IRewardsEligibilityReporting__factory.interfaceId,
        ),
      ).to.be.true
    })

    it('should support IRewardsEligibilityStatus interface', async function () {
      expect(
        await contracts.rewardsEligibilityOracle.supportsInterface(
          factories.IRewardsEligibilityStatus__factory.interfaceId,
        ),
      ).to.be.true
    })

    it('should support IPausableControl interface', async function () {
      expect(
        await contracts.rewardsEligibilityOracle.supportsInterface(factories.IPausableControl__factory.interfaceId),
      ).to.be.true
    })

    it('should support IAccessControl interface', async function () {
      expect(await contracts.rewardsEligibilityOracle.supportsInterface(IACCESSCONTROL_INTERFACE_ID)).to.be.true
    })

    it('should not support random interface', async function () {
      expect(await contracts.rewardsEligibilityOracle.supportsInterface('0x12345678')).to.be.false
    })
  })
})
