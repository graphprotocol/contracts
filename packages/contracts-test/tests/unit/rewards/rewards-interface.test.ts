import { RewardsManager } from '@graphprotocol/contracts'
import { IERC165__factory, IIssuanceTarget__factory, IRewardsManager__factory } from '@graphprotocol/interfaces/types'
import { GraphNetworkContracts, toGRT } from '@graphprotocol/sdk'
import type { SignerWithAddress } from '@nomiclabs/hardhat-ethers/signers'
import { expect } from 'chai'
import { constants } from 'ethers'
import hre from 'hardhat'

import { NetworkFixture } from '../lib/fixtures'

describe.skip('RewardsManager interfaces', () => {
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

  /**
   * Interface ID Stability Tests
   *
   * These tests verify that interface IDs remain stable across builds.
   * Changes to these IDs indicate breaking changes to the interface definitions.
   *
   * If a test fails:
   * 1. Verify the interface change was intentional
   * 2. Understand the impact on deployed contracts
   * 3. Update the expected ID if the change is correct
   * 4. Document the breaking change in release notes
   */
  describe('Interface ID Stability', () => {
    it('IERC165 should have stable interface ID', () => {
      expect(IERC165__factory.interfaceId).to.equal('0x01ffc9a7')
    })

    it('IIssuanceTarget should have stable interface ID', () => {
      expect(IIssuanceTarget__factory.interfaceId).to.equal('0xaee4dc43')
    })

    it('IRewardsManager should have stable interface ID', () => {
      expect(IRewardsManager__factory.interfaceId).to.equal('0xa0a2f219')
    })
  })

  describe('supportsInterface', function () {
    it('should support IIssuanceTarget interface', async function () {
      const supports = await rewardsManager.supportsInterface(IIssuanceTarget__factory.interfaceId)
      expect(supports).to.be.true
    })

    it('should support IRewardsManager interface', async function () {
      const supports = await rewardsManager.supportsInterface(IRewardsManager__factory.interfaceId)
      expect(supports).to.be.true
    })

    it('should support IERC165 interface', async function () {
      const supports = await rewardsManager.supportsInterface(IERC165__factory.interfaceId)
      expect(supports).to.be.true
    })

    it('should return false for unsupported interfaces', async function () {
      // Test with an unknown interface ID
      const unknownInterfaceId = '0x12345678' // Random interface ID
      const supports = await rewardsManager.supportsInterface(unknownInterfaceId)
      expect(supports).to.be.false
    })
  })

  describe('getter functions', function () {
    it('should return zero address for issuance allocator when not set', async function () {
      const allocator = await rewardsManager.getIssuanceAllocator()
      expect(allocator).to.equal(constants.AddressZero)
    })

    it('should return zero address for rewards eligibility oracle when not set', async function () {
      const oracle = await rewardsManager.getRewardsEligibilityOracle()
      expect(oracle).to.equal(constants.AddressZero)
    })

    it('should return zero address for reclaim address when not set', async function () {
      const reclaimAddress = await rewardsManager.getReclaimAddress(constants.HashZero)
      expect(reclaimAddress).to.equal(constants.AddressZero)
    })
  })

  describe('calcRewards', function () {
    it('should calculate rewards correctly', async function () {
      const tokens = toGRT('1000')
      const accRewardsPerAllocatedToken = toGRT('0.5')

      // Expected: (1000 * 0.5 * 1e18) / 1e18 = 500 GRT
      const expectedRewards = toGRT('500')

      const rewards = await rewardsManager.calcRewards(tokens, accRewardsPerAllocatedToken)
      expect(rewards).to.equal(expectedRewards)
    })

    it('should return 0 when tokens is 0', async function () {
      const tokens = toGRT('0')
      const accRewardsPerAllocatedToken = toGRT('0.5')

      const rewards = await rewardsManager.calcRewards(tokens, accRewardsPerAllocatedToken)
      expect(rewards).to.equal(0)
    })

    it('should return 0 when accRewardsPerAllocatedToken is 0', async function () {
      const tokens = toGRT('1000')
      const accRewardsPerAllocatedToken = toGRT('0')

      const rewards = await rewardsManager.calcRewards(tokens, accRewardsPerAllocatedToken)
      expect(rewards).to.equal(0)
    })
  })
})
