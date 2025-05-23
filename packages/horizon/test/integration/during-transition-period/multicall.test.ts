import hre from 'hardhat'

import { ONE_MILLION, PaymentTypes } from '@graphprotocol/toolshed'
import { ethers } from 'hardhat'
import { expect } from 'chai'
import { setGRTBalance } from '@graphprotocol/toolshed/hardhat'

import type { HardhatEthersSigner } from '@nomicfoundation/hardhat-ethers/signers'

describe('Service Provider', () => {
  let snapshotId: string

  const maxVerifierCut = 50_000n
  const thawingPeriod = 2419200n

  const graph = hre.graph()
  const horizonStaking = graph.horizon.contracts.HorizonStaking
  const graphToken = graph.horizon.contracts.L2GraphToken

  const subgraphServiceAddress = '0x0000000000000000000000000000000000000000'
  beforeEach(async () => {
    // Take a snapshot before each test
    snapshotId = await ethers.provider.send('evm_snapshot', [])
  })

  afterEach(async () => {
    // Revert to the snapshot after each test
    await ethers.provider.send('evm_revert', [snapshotId])
  })

  describe(('New Protocol Users'), () => {
    let serviceProvider: HardhatEthersSigner

    before(async () => {
      [,,serviceProvider] = await graph.accounts.getTestAccounts()
      await setGRTBalance(graph.provider, graphToken.target, serviceProvider.address, ONE_MILLION)
    })

    it('should allow multicalling stake+provision calls', async () => {
      const tokensToStake = ethers.parseEther('1000')
      const tokensToProvision = ethers.parseEther('100')

      // check state before
      const beforeProvision = await horizonStaking.getProvision(serviceProvider.address, subgraphServiceAddress)
      expect(beforeProvision.tokens).to.equal(0)
      expect(beforeProvision.maxVerifierCut).to.equal(0)
      expect(beforeProvision.thawingPeriod).to.equal(0)
      expect(beforeProvision.createdAt).to.equal(0)

      // multicall
      await graphToken.connect(serviceProvider).approve(horizonStaking.target, tokensToStake)
      const stakeCalldata = horizonStaking.interface.encodeFunctionData('stake', [tokensToStake])
      const provisionCalldata = horizonStaking.interface.encodeFunctionData('provision', [
        serviceProvider.address,
        subgraphServiceAddress,
        tokensToProvision,
        maxVerifierCut,
        thawingPeriod,
      ])
      await horizonStaking.connect(serviceProvider).multicall([stakeCalldata, provisionCalldata])

      // check state after
      const block = await graph.provider.getBlock('latest')
      const afterProvision = await horizonStaking.getProvision(serviceProvider.address, subgraphServiceAddress)
      expect(afterProvision.tokens).to.equal(tokensToProvision)
      expect(afterProvision.maxVerifierCut).to.equal(maxVerifierCut)
      expect(afterProvision.thawingPeriod).to.equal(thawingPeriod)
      expect(afterProvision.createdAt).to.equal(block?.timestamp)
    })

    it('should allow multicalling delegation parameter set calls', async () => {
      // check state before
      const beforeIndexingRewards = await horizonStaking.getDelegationFeeCut(serviceProvider.address, subgraphServiceAddress, PaymentTypes.IndexingRewards)
      const beforeQueryFee = await horizonStaking.getDelegationFeeCut(serviceProvider.address, subgraphServiceAddress, PaymentTypes.QueryFee)
      expect(beforeIndexingRewards).to.equal(0)
      expect(beforeQueryFee).to.equal(0)

      // multicall
      const indexingRewardsCalldata = horizonStaking.interface.encodeFunctionData('setDelegationFeeCut', [
        serviceProvider.address,
        subgraphServiceAddress,
        PaymentTypes.IndexingRewards,
        10_000n,
      ])
      const queryFeeCalldata = horizonStaking.interface.encodeFunctionData('setDelegationFeeCut', [
        serviceProvider.address,
        subgraphServiceAddress,
        PaymentTypes.QueryFee,
        12_345n,
      ])
      await horizonStaking.connect(serviceProvider).multicall([indexingRewardsCalldata, queryFeeCalldata])

      // check state after
      const afterIndexingRewards = await horizonStaking.getDelegationFeeCut(serviceProvider.address, subgraphServiceAddress, PaymentTypes.IndexingRewards)
      const afterQueryFee = await horizonStaking.getDelegationFeeCut(serviceProvider.address, subgraphServiceAddress, PaymentTypes.QueryFee)
      expect(afterIndexingRewards).to.equal(10_000n)
      expect(afterQueryFee).to.equal(12_345n)
    })
  })
})
