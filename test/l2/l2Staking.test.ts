import { expect } from 'chai'
import { ethers, ContractTransaction, BigNumber } from 'ethers'
import { defaultAbiCoder, parseEther } from 'ethers/lib/utils'

import {
  getAccounts,
  Account,
  toGRT,
  getL2SignerFromL1,
  setAccountBalance,
  latestBlock,
  advanceBlocks,
  deriveChannelKey,
  randomHexBytes,
  advanceToNextEpoch,
} from '../lib/testHelpers'
import { L2FixtureContracts, NetworkFixture } from '../lib/fixtures'
import { toBN } from '../lib/testHelpers'

import { IL2Staking } from '../../build/types/IL2Staking'
import { L2GraphTokenGateway } from '../../build/types/L2GraphTokenGateway'
import { GraphToken } from '../../build/types/GraphToken'

const { AddressZero } = ethers.constants

const subgraphDeploymentID = randomHexBytes()
const channelKey = deriveChannelKey()
const allocationID = channelKey.address
const metadata = randomHexBytes(32)

describe('L2Staking', () => {
  let me: Account
  let other: Account
  let another: Account
  let governor: Account
  let mockRouter: Account
  let mockL1GRT: Account
  let mockL1Gateway: Account
  let mockL1GNS: Account
  let mockL1Staking: Account
  let fixture: NetworkFixture

  let fixtureContracts: L2FixtureContracts
  let l2GraphTokenGateway: L2GraphTokenGateway
  let staking: IL2Staking
  let grt: GraphToken

  const tokens10k = toGRT('10000')
  const tokens100k = toGRT('100000')
  const tokens1m = toGRT('1000000')

  // Allocate with test values
  const allocate = async (tokens: BigNumber) => {
    return staking
      .connect(me.signer)
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
    const mockL1GatewayL2Alias = await getL2SignerFromL1(mockL1Gateway.address)
    // Eth for gas:
    await setAccountBalance(await mockL1GatewayL2Alias.getAddress(), parseEther('1'))

    const tx = l2GraphTokenGateway
      .connect(mockL1GatewayL2Alias)
      .finalizeInboundTransfer(mockL1GRT.address, from, to, amount, callhookData)
    return tx
  }

  before(async function () {
    ;[
      me,
      other,
      another,
      governor,
      mockRouter,
      mockL1GRT,
      mockL1Gateway,
      mockL1GNS,
      mockL1Staking,
    ] = await getAccounts()

    fixture = new NetworkFixture()
    fixtureContracts = await fixture.loadL2(governor.signer)
    ;({ l2GraphTokenGateway, staking, grt } = fixtureContracts)

    await grt.connect(governor.signer).mint(me.address, tokens1m)
    await grt.connect(me.signer).approve(staking.address, tokens1m)
    await grt.connect(governor.signer).mint(other.address, tokens1m)
    await grt.connect(other.signer).approve(staking.address, tokens1m)
    await fixture.configureL2Bridge(
      governor.signer,
      fixtureContracts,
      mockRouter.address,
      mockL1GRT.address,
      mockL1Gateway.address,
      mockL1GNS.address,
      mockL1Staking.address,
    )
  })

  beforeEach(async function () {
    await fixture.setUp()
  })

  afterEach(async function () {
    await fixture.tearDown()
  })

  describe('receive()', function () {
    it('should not allow receiving ETH', async function () {
      const tx = me.signer.sendTransaction({
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
      const tx = staking
        .connect(me.signer)
        .onTokenTransfer(mockL1GNS.address, tokens100k, callhookData)
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
        mockL1Staking.address,
        staking.address,
        tokens100k,
        callhookData,
      )

      await expect(tx)
        .emit(l2GraphTokenGateway, 'DepositFinalized')
        .withArgs(mockL1GRT.address, mockL1Staking.address, staking.address, tokens100k)
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
        mockL1Staking.address,
        staking.address,
        tokens100k,
        callhookData,
      )
      const tx = gatewayFinalizeTransfer(
        mockL1Staking.address,
        staking.address,
        tokens100k,
        callhookData,
      )

      await expect(tx)
        .emit(l2GraphTokenGateway, 'DepositFinalized')
        .withArgs(mockL1GRT.address, mockL1Staking.address, staking.address, tokens100k)
      await expect(tx).emit(staking, 'StakeDeposited').withArgs(me.address, tokens100k)
      expect(await staking.getIndexerStakedTokens(me.address)).to.equal(tokens100k.add(tokens100k))
    })
    it('adds stake to an existing indexer that was staked in L2 (without changing delegation params)', async function () {
      const functionData = defaultAbiCoder.encode(['tuple(address)'], [[me.address]])

      const callhookData = defaultAbiCoder.encode(
        ['uint8', 'bytes'],
        [toBN(0), functionData], // code = 1 means RECEIVE_INDEXER_CODE
      )
      await staking.connect(me.signer).stake(tokens100k)
      await staking.connect(me.signer).setDelegationParameters(1000, 1000, 1000)
      const tx = gatewayFinalizeTransfer(
        mockL1Staking.address,
        staking.address,
        tokens100k,
        callhookData,
      )

      await expect(tx)
        .emit(l2GraphTokenGateway, 'DepositFinalized')
        .withArgs(mockL1GRT.address, mockL1Staking.address, staking.address, tokens100k)
      await expect(tx).emit(staking, 'StakeDeposited').withArgs(me.address, tokens100k)
      expect(await staking.getIndexerStakedTokens(me.address)).to.equal(tokens100k.add(tokens100k))
      const delegationPool = await staking.delegationPools(me.address)
      expect(delegationPool.indexingRewardCut).eq(toBN(1000))
      expect(delegationPool.queryFeeCut).eq(toBN(1000))
    })
  })

  describe('receiving delegation from L1 (onTokenTransfer)', function () {
    it('adds delegation for a new delegator', async function () {
      await staking.connect(me.signer).stake(tokens100k)

      const functionData = defaultAbiCoder.encode(
        ['tuple(address,address)'],
        [[me.address, other.address]],
      )

      const callhookData = defaultAbiCoder.encode(
        ['uint8', 'bytes'],
        [toBN(1), functionData], // code = 1 means RECEIVE_DELEGATION_CODE
      )
      const tx = gatewayFinalizeTransfer(
        mockL1Staking.address,
        staking.address,
        tokens10k,
        callhookData,
      )

      await expect(tx)
        .emit(l2GraphTokenGateway, 'DepositFinalized')
        .withArgs(mockL1GRT.address, mockL1Staking.address, staking.address, tokens10k)
      const expectedShares = tokens10k
      await expect(tx)
        .emit(staking, 'StakeDelegated')
        .withArgs(me.address, other.address, tokens10k, expectedShares)
      const delegation = await staking.getDelegation(me.address, other.address)
      expect(delegation.shares).to.equal(expectedShares)
    })
    it('adds delegation for an existing delegator', async function () {
      await staking.connect(me.signer).stake(tokens100k)
      await staking.connect(other.signer).delegate(me.address, tokens10k)

      const functionData = defaultAbiCoder.encode(
        ['tuple(address,address)'],
        [[me.address, other.address]],
      )

      const callhookData = defaultAbiCoder.encode(
        ['uint8', 'bytes'],
        [toBN(1), functionData], // code = 1 means RECEIVE_DELEGATION_CODE
      )
      const tx = gatewayFinalizeTransfer(
        mockL1Staking.address,
        staking.address,
        tokens10k,
        callhookData,
      )

      await expect(tx)
        .emit(l2GraphTokenGateway, 'DepositFinalized')
        .withArgs(mockL1GRT.address, mockL1Staking.address, staking.address, tokens10k)
      const expectedNewShares = tokens10k
      const expectedTotalShares = tokens10k.mul(2)
      await expect(tx)
        .emit(staking, 'StakeDelegated')
        .withArgs(me.address, other.address, tokens10k, expectedNewShares)
      const delegation = await staking.getDelegation(me.address, other.address)
      expect(delegation.shares).to.equal(expectedTotalShares)
    })
    it('returns delegation to the delegator if it would produce no shares', async function () {
      await fixtureContracts.rewardsManager
        .connect(governor.signer)
        .setIssuancePerBlock(toGRT('114'))

      await staking.connect(me.signer).stake(tokens100k)
      await staking.connect(me.signer).delegate(me.address, toBN(1)) // 1 weiGRT == 1 share

      await staking.connect(me.signer).setDelegationParameters(1000, 1000, 1000)
      await grt.connect(me.signer).approve(fixtureContracts.curation.address, tokens10k)
      await fixtureContracts.curation.connect(me.signer).mint(subgraphDeploymentID, tokens10k, 0)

      await allocate(tokens100k)
      await advanceToNextEpoch(fixtureContracts.epochManager)
      await advanceToNextEpoch(fixtureContracts.epochManager)
      await staking.connect(me.signer).closeAllocation(allocationID, randomHexBytes(32))
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
        mockL1Staking.address,
        staking.address,
        toBN(1), // Less than 1 share!
        callhookData,
      )

      await expect(tx)
        .emit(l2GraphTokenGateway, 'DepositFinalized')
        .withArgs(mockL1GRT.address, mockL1Staking.address, staking.address, toBN(1))
      const delegation = await staking.getDelegation(me.address, other.address)
      await expect(tx)
        .emit(staking, 'TransferredDelegationReturnedToDelegator')
        .withArgs(me.address, other.address, toBN(1))

      expect(delegation.shares).to.equal(0)
      const delegatorGRTBalanceAfter = await grt.balanceOf(other.address)
      expect(delegatorGRTBalanceAfter.sub(delegatorGRTBalanceBefore)).to.equal(toBN(1))
    })
  })
  describe('onTokenTransfer with invalid messages', function () {
    it('reverts if the code is invalid', async function () {
      // This should never really happen unless the Arbitrum bridge is compromised,
      // so we test it anyway to ensure it's a well-defined behavior.
      // code 2 does not exist:
      const callhookData = defaultAbiCoder.encode(['uint8', 'bytes'], [toBN(2), '0x12345678'])
      const tx = gatewayFinalizeTransfer(
        mockL1Staking.address,
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
        mockL1Staking.address,
        staking.address,
        toGRT('1'),
        callhookData,
      )
      await expect(tx).reverted // abi.decode will fail with no reason
    })
  })
})
