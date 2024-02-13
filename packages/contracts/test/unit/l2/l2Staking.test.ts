import hre from 'hardhat'
import { expect } from 'chai'
import { ethers, ContractTransaction, BigNumber } from 'ethers'
import { defaultAbiCoder, parseEther } from 'ethers/lib/utils'

import { NetworkFixture } from '../lib/fixtures'

import { IL2Staking } from '../../../build/types/IL2Staking'
import { L2GraphTokenGateway } from '../../../build/types/L2GraphTokenGateway'
import { GraphToken } from '../../../build/types/GraphToken'
import {
  GraphNetworkContracts,
  deriveChannelKey,
  helpers,
  randomHexBytes,
  toBN,
  toGRT,
} from '@graphprotocol/sdk'
import { SignerWithAddress } from '@nomiclabs/hardhat-ethers/signers'
import { L1GNS, L1GraphTokenGateway, L1Staking } from '../../../build/types'

const { AddressZero } = ethers.constants

const subgraphDeploymentID = randomHexBytes()
const channelKey = deriveChannelKey()
const allocationID = channelKey.address
const metadata = randomHexBytes(32)

describe('L2Staking', () => {
  const graph = hre.graph()
  let me: SignerWithAddress
  let other: SignerWithAddress
  let governor: SignerWithAddress

  let fixture: NetworkFixture

  let fixtureContracts: GraphNetworkContracts
  let l1MockContracts: GraphNetworkContracts
  let l1GRTMock: GraphToken
  let l1StakingMock: L1Staking
  let l1GNSMock: L1GNS
  let l1GRTGatewayMock: L1GraphTokenGateway
  let l2GraphTokenGateway: L2GraphTokenGateway
  let staking: IL2Staking
  let grt: GraphToken

  const tokens10k = toGRT('10000')
  const tokens100k = toGRT('100000')
  const tokens1m = toGRT('1000000')

  // Allocate with test values
  const allocate = async (tokens: BigNumber) => {
    return staking
      .connect(me)
      .allocateFrom(
        me.address,
        subgraphDeploymentID,
        tokens,
        allocationID,
        metadata,
        await channelKey.generateProof(me.address),
      )
  }

  const gatewayFinalizeTransfer = async function (
    from: string,
    to: string,
    amount: BigNumber,
    callhookData: string,
  ): Promise<ContractTransaction> {
    const mockL1GatewayL2Alias = await helpers.getL2SignerFromL1(l1GRTGatewayMock.address)
    // Eth for gas:
    await helpers.setBalance(await mockL1GatewayL2Alias.getAddress(), parseEther('1'))

    const tx = l2GraphTokenGateway
      .connect(mockL1GatewayL2Alias)
      .finalizeInboundTransfer(l1GRTMock.address, from, to, amount, callhookData)
    return tx
  }

  before(async function () {
    ;[me, other] = await graph.getTestAccounts()
    ;({ governor } = await graph.getNamedAccounts())

    fixture = new NetworkFixture(graph.provider)

    // Deploy L2
    fixtureContracts = await fixture.load(governor, true)
    grt = fixtureContracts.GraphToken as GraphToken
    staking = fixtureContracts.Staking as IL2Staking
    l2GraphTokenGateway = fixtureContracts.L2GraphTokenGateway as L2GraphTokenGateway

    // Deploy L1 mock
    l1MockContracts = await fixture.loadMock(false)
    l1GRTMock = l1MockContracts.GraphToken as GraphToken
    l1StakingMock = l1MockContracts.L1Staking as L1Staking
    l1GNSMock = l1MockContracts.L1GNS as L1GNS
    l1GRTGatewayMock = l1MockContracts.L1GraphTokenGateway as L1GraphTokenGateway

    // Deploy L2 arbitrum bridge
    await fixture.loadL2ArbitrumBridge(governor)

    // Configure L2 bridge
    await fixture.configureL2Bridge(governor, fixtureContracts, l1MockContracts)

    await grt.connect(governor).mint(me.address, tokens1m)
    await grt.connect(me).approve(staking.address, tokens1m)
    await grt.connect(governor).mint(other.address, tokens1m)
    await grt.connect(other).approve(staking.address, tokens1m)
  })

  beforeEach(async function () {
    await fixture.setUp()
  })

  afterEach(async function () {
    await fixture.tearDown()
  })

  describe('receive()', function () {
    it('should not allow receiving ETH', async function () {
      const tx = me.sendTransaction({
        to: staking.address,
        value: parseEther('1'),
      })
      await expect(tx).revertedWith('RECEIVE_ETH_NOT_ALLOWED')
    })
  })
  describe('receiving indexer stake from L1 (onTokenTransfer)', function () {
    it('cannot be called by someone other than the L2GraphTokenGateway', async function () {
      const functionData = defaultAbiCoder.encode(['tuple(address)'], [[me.address]])

      const callhookData = defaultAbiCoder.encode(
        ['uint8', 'bytes'],
        [toBN(0), functionData], // code = 1 means RECEIVE_INDEXER_CODE
      )
      const tx = staking.connect(me).onTokenTransfer(l1GNSMock.address, tokens100k, callhookData)
      await expect(tx).revertedWith('ONLY_GATEWAY')
    })
    it('rejects calls if the L1 sender is not the L1Staking', async function () {
      const functionData = defaultAbiCoder.encode(['tuple(address)'], [[me.address]])

      const callhookData = defaultAbiCoder.encode(
        ['uint8', 'bytes'],
        [toBN(0), functionData], // code = 1 means RECEIVE_INDEXER_CODE
      )
      const tx = gatewayFinalizeTransfer(me.address, staking.address, tokens100k, callhookData)

      await expect(tx).revertedWith('ONLY_L1_STAKING_THROUGH_BRIDGE')
    })
    it('adds stake to a new indexer', async function () {
      const functionData = defaultAbiCoder.encode(['tuple(address)'], [[me.address]])

      const callhookData = defaultAbiCoder.encode(
        ['uint8', 'bytes'],
        [toBN(0), functionData], // code = 1 means RECEIVE_INDEXER_CODE
      )
      const tx = gatewayFinalizeTransfer(
        l1StakingMock.address,
        staking.address,
        tokens100k,
        callhookData,
      )

      await expect(tx)
        .emit(l2GraphTokenGateway, 'DepositFinalized')
        .withArgs(l1GRTMock.address, l1StakingMock.address, staking.address, tokens100k)
      await expect(tx).emit(staking, 'StakeDeposited').withArgs(me.address, tokens100k)
      expect(await staking.getIndexerStakedTokens(me.address)).to.equal(tokens100k)
      const delegationPool = await staking.delegationPools(me.address)
      expect(delegationPool.indexingRewardCut).eq(toBN(1000000)) // 1 in PPM
      expect(delegationPool.queryFeeCut).eq(toBN(1000000)) // 1 in PPM
    })
    it('adds stake to an existing indexer that was already transferred', async function () {
      const functionData = defaultAbiCoder.encode(['tuple(address)'], [[me.address]])

      const callhookData = defaultAbiCoder.encode(
        ['uint8', 'bytes'],
        [toBN(0), functionData], // code = 1 means RECEIVE_INDEXER_CODE
      )
      await gatewayFinalizeTransfer(
        l1StakingMock.address,
        staking.address,
        tokens100k,
        callhookData,
      )
      const tx = gatewayFinalizeTransfer(
        l1StakingMock.address,
        staking.address,
        tokens100k,
        callhookData,
      )

      await expect(tx)
        .emit(l2GraphTokenGateway, 'DepositFinalized')
        .withArgs(l1GRTMock.address, l1StakingMock.address, staking.address, tokens100k)
      await expect(tx).emit(staking, 'StakeDeposited').withArgs(me.address, tokens100k)
      expect(await staking.getIndexerStakedTokens(me.address)).to.equal(tokens100k.add(tokens100k))
    })
    it('adds stake to an existing indexer that was staked in L2 (without changing delegation params)', async function () {
      const functionData = defaultAbiCoder.encode(['tuple(address)'], [[me.address]])

      const callhookData = defaultAbiCoder.encode(
        ['uint8', 'bytes'],
        [toBN(0), functionData], // code = 1 means RECEIVE_INDEXER_CODE
      )
      await staking.connect(me).stake(tokens100k)
      await staking.connect(me).setDelegationParameters(1000, 1000, 1000)
      const tx = gatewayFinalizeTransfer(
        l1StakingMock.address,
        staking.address,
        tokens100k,
        callhookData,
      )

      await expect(tx)
        .emit(l2GraphTokenGateway, 'DepositFinalized')
        .withArgs(l1GRTMock.address, l1StakingMock.address, staking.address, tokens100k)
      await expect(tx).emit(staking, 'StakeDeposited').withArgs(me.address, tokens100k)
      expect(await staking.getIndexerStakedTokens(me.address)).to.equal(tokens100k.add(tokens100k))
      const delegationPool = await staking.delegationPools(me.address)
      expect(delegationPool.indexingRewardCut).eq(toBN(1000))
      expect(delegationPool.queryFeeCut).eq(toBN(1000))
    })
  })

  describe('receiving delegation from L1 (onTokenTransfer)', function () {
    it('adds delegation for a new delegator', async function () {
      await staking.connect(me).stake(tokens100k)

      const functionData = defaultAbiCoder.encode(
        ['tuple(address,address)'],
        [[me.address, other.address]],
      )

      const callhookData = defaultAbiCoder.encode(
        ['uint8', 'bytes'],
        [toBN(1), functionData], // code = 1 means RECEIVE_DELEGATION_CODE
      )
      const tx = gatewayFinalizeTransfer(
        l1StakingMock.address,
        staking.address,
        tokens10k,
        callhookData,
      )

      await expect(tx)
        .emit(l2GraphTokenGateway, 'DepositFinalized')
        .withArgs(l1GRTMock.address, l1StakingMock.address, staking.address, tokens10k)
      const expectedShares = tokens10k
      await expect(tx)
        .emit(staking, 'StakeDelegated')
        .withArgs(me.address, other.address, tokens10k, expectedShares)
      const delegation = await staking.getDelegation(me.address, other.address)
      expect(delegation.shares).to.equal(expectedShares)
    })
    it('adds delegation for an existing delegator', async function () {
      await staking.connect(me).stake(tokens100k)
      await staking.connect(other).delegate(me.address, tokens10k)

      const functionData = defaultAbiCoder.encode(
        ['tuple(address,address)'],
        [[me.address, other.address]],
      )

      const callhookData = defaultAbiCoder.encode(
        ['uint8', 'bytes'],
        [toBN(1), functionData], // code = 1 means RECEIVE_DELEGATION_CODE
      )
      const tx = gatewayFinalizeTransfer(
        l1StakingMock.address,
        staking.address,
        tokens10k,
        callhookData,
      )

      await expect(tx)
        .emit(l2GraphTokenGateway, 'DepositFinalized')
        .withArgs(l1GRTMock.address, l1StakingMock.address, staking.address, tokens10k)
      const expectedNewShares = tokens10k
      const expectedTotalShares = tokens10k.mul(2)
      await expect(tx)
        .emit(staking, 'StakeDelegated')
        .withArgs(me.address, other.address, tokens10k, expectedNewShares)
      const delegation = await staking.getDelegation(me.address, other.address)
      expect(delegation.shares).to.equal(expectedTotalShares)
    })
    it('returns delegation to the delegator if it would produce no shares', async function () {
      await fixtureContracts.RewardsManager.connect(governor).setIssuancePerBlock(toGRT('114'))

      await staking.connect(me).stake(tokens100k)
      // Initialize the delegation pool to allow delegating less than 1 GRT
      await staking.connect(me).delegate(me.address, tokens10k)

      await staking.connect(me).setDelegationParameters(1000, 1000, 1000)
      await grt.connect(me).approve(fixtureContracts.Curation.address, tokens10k)
      await fixtureContracts.Curation.connect(me).mint(subgraphDeploymentID, tokens10k, 0)

      await allocate(tokens100k)
      await helpers.mineEpoch(fixtureContracts.EpochManager)
      await helpers.mineEpoch(fixtureContracts.EpochManager)
      await staking.connect(me).closeAllocation(allocationID, randomHexBytes(32))
      // Now there are some rewards sent to delegation pool, so 1 weiGRT is less than 1 share

      const functionData = defaultAbiCoder.encode(
        ['tuple(address,address)'],
        [[me.address, other.address]],
      )

      const callhookData = defaultAbiCoder.encode(
        ['uint8', 'bytes'],
        [toBN(1), functionData], // code = 1 means RECEIVE_DELEGATION_CODE
      )
      const delegatorGRTBalanceBefore = await grt.balanceOf(other.address)
      const tx = gatewayFinalizeTransfer(
        l1StakingMock.address,
        staking.address,
        toBN(1), // Less than 1 share!
        callhookData,
      )

      await expect(tx)
        .emit(l2GraphTokenGateway, 'DepositFinalized')
        .withArgs(l1GRTMock.address, l1StakingMock.address, staking.address, toBN(1))
      const delegation = await staking.getDelegation(me.address, other.address)
      await expect(tx)
        .emit(staking, 'TransferredDelegationReturnedToDelegator')
        .withArgs(me.address, other.address, toBN(1))

      expect(delegation.shares).to.equal(0)
      const delegatorGRTBalanceAfter = await grt.balanceOf(other.address)
      expect(delegatorGRTBalanceAfter.sub(delegatorGRTBalanceBefore)).to.equal(toBN(1))
    })
    it('returns delegation to the delegator if it initializes the pool with less than the minimum delegation', async function () {
      await fixtureContracts.RewardsManager.connect(governor).setIssuancePerBlock(toGRT('114'))

      await staking.connect(me).stake(tokens100k)

      await staking.connect(me).setDelegationParameters(1000, 1000, 1000)
      await grt.connect(me).approve(fixtureContracts.Curation.address, tokens10k)
      await fixtureContracts.Curation.connect(me).mint(subgraphDeploymentID, tokens10k, 0)

      await allocate(tokens100k)
      await helpers.mineEpoch(fixtureContracts.EpochManager, 2)
      await staking.connect(me).closeAllocation(allocationID, randomHexBytes(32))
      // Now there are some rewards sent to delegation pool, so 1 weiGRT is less than 1 share

      const functionData = defaultAbiCoder.encode(
        ['tuple(address,address)'],
        [[me.address, other.address]],
      )

      const callhookData = defaultAbiCoder.encode(
        ['uint8', 'bytes'],
        [toBN(1), functionData], // code = 1 means RECEIVE_DELEGATION_CODE
      )
      const delegatorGRTBalanceBefore = await grt.balanceOf(other.address)
      const tx = gatewayFinalizeTransfer(
        l1StakingMock.address,
        staking.address,
        toGRT('0.1'), // Less than 1 GRT!
        callhookData,
      )

      await expect(tx)
        .emit(l2GraphTokenGateway, 'DepositFinalized')
        .withArgs(l1GRTMock.address, l1StakingMock.address, staking.address, toGRT('0.1'))
      const delegation = await staking.getDelegation(me.address, other.address)
      await expect(tx)
        .emit(staking, 'TransferredDelegationReturnedToDelegator')
        .withArgs(me.address, other.address, toGRT('0.1'))

      expect(delegation.shares).to.equal(0)
      const delegatorGRTBalanceAfter = await grt.balanceOf(other.address)
      expect(delegatorGRTBalanceAfter.sub(delegatorGRTBalanceBefore)).to.equal(toGRT('0.1'))
    })
    it('returns delegation under the minimum if the pool is initialized', async function () {
      await staking.connect(me).stake(tokens100k)

      // Initialize the delegation pool to allow delegating less than 1 GRT
      await staking.connect(me).delegate(me.address, tokens10k)

      const functionData = defaultAbiCoder.encode(
        ['tuple(address,address)'],
        [[me.address, other.address]],
      )

      const callhookData = defaultAbiCoder.encode(
        ['uint8', 'bytes'],
        [toBN(1), functionData], // code = 1 means RECEIVE_DELEGATION_CODE
      )
      const delegatorGRTBalanceBefore = await grt.balanceOf(other.address)
      const tx = gatewayFinalizeTransfer(
        l1StakingMock.address,
        staking.address,
        toGRT('0.1'),
        callhookData,
      )

      await expect(tx)
        .emit(l2GraphTokenGateway, 'DepositFinalized')
        .withArgs(l1GRTMock.address, l1StakingMock.address, staking.address, toGRT('0.1'))

      const delegation = await staking.getDelegation(me.address, other.address)
      await expect(tx)
        .emit(staking, 'TransferredDelegationReturnedToDelegator')
        .withArgs(me.address, other.address, toGRT('0.1'))

      expect(delegation.shares).to.equal(0)
      const delegatorGRTBalanceAfter = await grt.balanceOf(other.address)
      expect(delegatorGRTBalanceAfter.sub(delegatorGRTBalanceBefore)).to.equal(toGRT('0.1'))
    })
  })
  describe('onTokenTransfer with invalid messages', function () {
    it('reverts if the code is invalid', async function () {
      // This should never really happen unless the Arbitrum bridge is compromised,
      // so we test it anyway to ensure it's a well-defined behavior.
      // code 2 does not exist:
      const callhookData = defaultAbiCoder.encode(['uint8', 'bytes'], [toBN(2), '0x12345678'])
      const tx = gatewayFinalizeTransfer(
        l1StakingMock.address,
        staking.address,
        toGRT('1'),
        callhookData,
      )
      await expect(tx).revertedWith('INVALID_CODE')
    })
    it('reverts if the message encoding is invalid', async function () {
      // This should never really happen unless the Arbitrum bridge is compromised,
      // so we test it anyway to ensure it's a well-defined behavior.
      const callhookData = defaultAbiCoder.encode(['address', 'uint128'], [AddressZero, toBN(2)])
      const tx = gatewayFinalizeTransfer(
        l1StakingMock.address,
        staking.address,
        toGRT('1'),
        callhookData,
      )
      await expect(tx).reverted // abi.decode will fail with no reason
    })
  })
})
