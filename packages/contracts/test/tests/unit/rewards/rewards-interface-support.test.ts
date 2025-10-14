import { RewardsManager } from '@graphprotocol/contracts'
import { GraphNetworkContracts, toGRT } from '@graphprotocol/sdk'
import type { SignerWithAddress } from '@nomiclabs/hardhat-ethers/signers'
import { expect } from 'chai'
import hre from 'hardhat'

import { NetworkFixture } from '../lib/fixtures'

describe('Rewards - Interface Support', () => {
  const graph = hre.graph()
  let governor: SignerWithAddress

  let fixture: NetworkFixture

  let contracts: GraphNetworkContracts
  let rewardsManager: RewardsManager

  before(async function () {
    ;({ governor } = await graph.getNamedAccounts())

    fixture = new NetworkFixture(graph.provider)
    contracts = await fixture.load(governor)
    rewardsManager = contracts.RewardsManager

    // Set a default issuance per block
    await rewardsManager.connect(governor).setIssuancePerBlock(toGRT('200'))
  })

  beforeEach(async function () {
    await fixture.setUp()
  })

  afterEach(async function () {
    await fixture.tearDown()
  })

  describe('supportsInterface', function () {
    it('should support IIssuanceTarget interface', async function () {
      // Calculate the correct IIssuanceTarget interface ID
      const beforeIssuanceAllocationChangeSelector = hre.ethers.utils
        .id('beforeIssuanceAllocationChange()')
        .slice(0, 10)
      const setIssuanceAllocatorSelector = hre.ethers.utils.id('setIssuanceAllocator(address)').slice(0, 10)
      const interfaceId = hre.ethers.BigNumber.from(beforeIssuanceAllocationChangeSelector)
        .xor(hre.ethers.BigNumber.from(setIssuanceAllocatorSelector))
        .toHexString()

      const supports = await rewardsManager.supportsInterface(interfaceId)
      expect(supports).to.be.true
    })

    it('should support IRewardsManager interface', async function () {
      // Use the auto-generated interface ID from the interfaces package
      const { IRewardsManager } = require('@graphprotocol/interfaces')
      const supports = await rewardsManager.supportsInterface(IRewardsManager)
      expect(supports).to.be.true
    })

    it('should support IERC165 interface', async function () {
      // Test the specific IERC165 interface - registered during initialize()
      const IERC165InterfaceId = '0x01ffc9a7' // This is the standard ERC165 interface ID
      const supports = await rewardsManager.supportsInterface(IERC165InterfaceId)
      expect(supports).to.be.true
    })

    it('should call super.supportsInterface for unknown interfaces', async function () {
      // Test with an unknown interface - this should hit the super.supportsInterface branch
      const unknownInterfaceId = '0x12345678' // Random interface ID
      const supports = await rewardsManager.supportsInterface(unknownInterfaceId)
      expect(supports).to.be.false // Should return false for unknown interface
    })
  })

  describe('interface support (alternate)', function () {
    it('should support ERC165 interface', async function () {
      // Test ERC165 support (registered during initialize())
      expect(await rewardsManager.supportsInterface('0x01ffc9a7')).eq(true) // ERC165
    })

    it('should support IIssuanceTarget interface', async function () {
      // Test IIssuanceTarget interface support
      const { IIssuanceTarget } = require('@graphprotocol/interfaces')
      expect(await rewardsManager.supportsInterface(IIssuanceTarget)).eq(true)
    })

    it('should return false for unsupported interfaces', async function () {
      // Test with a random interface ID that should not be supported
      expect(await rewardsManager.supportsInterface('0x12345678')).eq(false)
    })
  })
})
