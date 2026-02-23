// Import Typechain-generated factories with interface metadata (interfaceId and interfaceName)
// Use dynamic import to avoid circular dependency issues with ESM/CJS interop
import { expect } from 'chai'
import { ethers as ethersLib } from 'ethers'

import { deployTestGraphToken, getTestAccounts } from '../common/fixtures'
import { deployDirectAllocation, deployIssuanceAllocator } from './fixtures'

// Standard interface IDs (well-known constants)
// IAccessControl: OpenZeppelin AccessControl interface
const IACCESSCONTROL_INTERFACE_ID = '0x7965db0b'

// Module-level variables for lazy-loaded factories
let interfaceFactories: {
  IIssuanceAllocationAdministration__factory: any
  IIssuanceAllocationData__factory: any
  IIssuanceAllocationDistribution__factory: any
  IIssuanceAllocationStatus__factory: any
  IIssuanceTarget__factory: any
  IPausableControl__factory: any
  ISendTokens__factory: any
}

/**
 * Allocate ERC-165 Interface Compliance Tests
 * Tests interface support for IssuanceAllocator and DirectAllocation contracts
 */
describe('Allocate ERC-165 Interface Compliance', () => {
  let accounts: any
  let contracts: any

  before(async () => {
    // Import directly from dist to avoid ts-node circular dependency issues
    const interfacesTypes = await import('@graphprotocol/interfaces/dist/types/index.js')

    interfaceFactories = {
      IIssuanceAllocationAdministration__factory: interfacesTypes.IIssuanceAllocationAdministration__factory,
      IIssuanceAllocationData__factory: interfacesTypes.IIssuanceAllocationData__factory,
      IIssuanceAllocationDistribution__factory: interfacesTypes.IIssuanceAllocationDistribution__factory,
      IIssuanceAllocationStatus__factory: interfacesTypes.IIssuanceAllocationStatus__factory,
      IIssuanceTarget__factory: interfacesTypes.IIssuanceTarget__factory,
      IPausableControl__factory: interfacesTypes.IPausableControl__factory,
      ISendTokens__factory: interfacesTypes.ISendTokens__factory,
    }

    accounts = await getTestAccounts()

    // Deploy allocate contracts for interface testing
    const graphToken = await deployTestGraphToken()
    const graphTokenAddress = await graphToken.getAddress()

    const issuanceAllocator = await deployIssuanceAllocator(
      graphTokenAddress,
      accounts.governor,
      ethersLib.parseEther('100'),
    )

    const directAllocation = await deployDirectAllocation(graphTokenAddress, accounts.governor)

    contracts = {
      issuanceAllocator,
      directAllocation,
    }
  })

  describe('IssuanceAllocator Interface Compliance', function () {
    it('should support ERC-165 interface', async function () {
      expect(await contracts.issuanceAllocator.supportsInterface('0x01ffc9a7')).to.be.true
    })

    it('should support IIssuanceAllocationDistribution interface', async function () {
      expect(
        await contracts.issuanceAllocator.supportsInterface(
          interfaceFactories.IIssuanceAllocationDistribution__factory.interfaceId,
        ),
      ).to.be.true
    })

    it('should support IIssuanceAllocationAdministration interface', async function () {
      expect(
        await contracts.issuanceAllocator.supportsInterface(
          interfaceFactories.IIssuanceAllocationAdministration__factory.interfaceId,
        ),
      ).to.be.true
    })

    it('should support IIssuanceAllocationStatus interface', async function () {
      expect(
        await contracts.issuanceAllocator.supportsInterface(
          interfaceFactories.IIssuanceAllocationStatus__factory.interfaceId,
        ),
      ).to.be.true
    })

    it('should support IIssuanceAllocationData interface', async function () {
      expect(
        await contracts.issuanceAllocator.supportsInterface(
          interfaceFactories.IIssuanceAllocationData__factory.interfaceId,
        ),
      ).to.be.true
    })

    it('should support IPausableControl interface', async function () {
      expect(
        await contracts.issuanceAllocator.supportsInterface(interfaceFactories.IPausableControl__factory.interfaceId),
      ).to.be.true
    })

    it('should support IAccessControl interface', async function () {
      expect(await contracts.issuanceAllocator.supportsInterface(IACCESSCONTROL_INTERFACE_ID)).to.be.true
    })

    it('should not support random interface', async function () {
      expect(await contracts.issuanceAllocator.supportsInterface('0x12345678')).to.be.false
    })
  })

  describe('DirectAllocation Interface Compliance', function () {
    it('should support ERC-165 interface', async function () {
      expect(await contracts.directAllocation.supportsInterface('0x01ffc9a7')).to.be.true
    })

    it('should support IIssuanceTarget interface', async function () {
      expect(
        await contracts.directAllocation.supportsInterface(interfaceFactories.IIssuanceTarget__factory.interfaceId),
      ).to.be.true
    })

    it('should support ISendTokens interface', async function () {
      expect(await contracts.directAllocation.supportsInterface(interfaceFactories.ISendTokens__factory.interfaceId)).to
        .be.true
    })

    it('should support IPausableControl interface', async function () {
      expect(
        await contracts.directAllocation.supportsInterface(interfaceFactories.IPausableControl__factory.interfaceId),
      ).to.be.true
    })

    it('should support IAccessControl interface', async function () {
      expect(await contracts.directAllocation.supportsInterface(IACCESSCONTROL_INTERFACE_ID)).to.be.true
    })

    it('should not support random interface', async function () {
      expect(await contracts.directAllocation.supportsInterface('0x12345678')).to.be.false
    })
  })
})
