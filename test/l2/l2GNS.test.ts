import { expect } from 'chai'
import { ethers, ContractTransaction, BigNumber, Event } from 'ethers'
import { defaultAbiCoder, parseUnits } from 'ethers/lib/utils'

import { getAccounts, randomHexBytes, Account, toGRT, getL2SignerFromL1 } from '../lib/testHelpers'
import { L2FixtureContracts, NetworkFixture } from '../lib/fixtures'
import { toBN } from '../lib/testHelpers'

import { L2GNS } from '../../build/types/L2GNS'
import { L2GraphToken } from '../../build/types/L2GraphToken'
import { L2GraphTokenGateway } from '../../build/types/L2GraphTokenGateway'
import {
  buildSubgraph,
  buildSubgraphID,
  DEFAULT_RESERVE_RATIO,
  publishNewSubgraph,
  PublishSubgraph,
} from '../lib/gnsUtils'

const { HashZero } = ethers.constants

describe('L2GNS', () => {
  let me: Account
  let other: Account
  let governor: Account
  let tokenSender: Account
  let l1Receiver: Account
  let l2Receiver: Account
  let mockRouter: Account
  let mockL1GRT: Account
  let mockL1Gateway: Account
  let mockL1GNS: Account
  let pauseGuardian: Account
  let fixture: NetworkFixture

  let fixtureContracts: L2FixtureContracts
  let l2GraphTokenGateway: L2GraphTokenGateway
  let gns: L2GNS

  let newSubgraph0: PublishSubgraph

  const gatewayFinalizeTransfer = async function (
    from: string,
    to: string,
    amount: BigNumber,
    callhookData: string,
  ): Promise<ContractTransaction> {
    const mockL1GatewayL2Alias = await getL2SignerFromL1(mockL1Gateway.address)
    // Eth for gas:
    await me.signer.sendTransaction({
      to: await mockL1GatewayL2Alias.getAddress(),
      value: parseUnits('1', 'ether'),
    })
    const data = defaultAbiCoder.encode(['bytes', 'bytes'], ['0x', callhookData])
    const tx = l2GraphTokenGateway
      .connect(mockL1GatewayL2Alias)
      .finalizeInboundTransfer(mockL1GRT.address, from, to, amount, data)
    return tx
  }

  before(async function () {
    newSubgraph0 = buildSubgraph()
    ;[
      me,
      other,
      governor,
      tokenSender,
      l1Receiver,
      mockRouter,
      mockL1GRT,
      mockL1Gateway,
      l2Receiver,
      pauseGuardian,
      mockL1GNS,
    ] = await getAccounts()

    fixture = new NetworkFixture()
    fixtureContracts = await fixture.loadL2(governor.signer)
    ;({ l2GraphTokenGateway, gns } = fixtureContracts)

    await fixture.configureL2Bridge(
      governor.signer,
      fixtureContracts,
      mockRouter.address,
      mockL1GRT.address,
      mockL1Gateway.address,
      mockL1GNS.address,
    )
  })

  describe('receiving a subgraph from L1 (onTokenTransfer)', function () {
    it('cannot be called by someone other than the L2GraphTokenGateway', async function () {
      const l1SubgraphId = await buildSubgraphID(me.address, toBN('1'), 1)
      const curatedTokens = toGRT('1337')
      const lockBlockhash = randomHexBytes(32)
      const metadata = randomHexBytes()
      const nSignal = toBN('4567')
      const callhookData = defaultAbiCoder.encode(
        ['uint256', 'address', 'bytes32', 'uint256', 'uint32', 'bytes32'],
        [l1SubgraphId, me.address, lockBlockhash, nSignal, DEFAULT_RESERVE_RATIO, metadata],
      )
      const tx = gns
        .connect(me.signer)
        .onTokenTransfer(mockL1GNS.address, curatedTokens, callhookData)
      await expect(tx).revertedWith('ONLY_GATEWAY')
    })
    it('rejects calls if the L1 sender is not the L1GNS', async function () {
      const l1SubgraphId = await buildSubgraphID(me.address, toBN('1'), 1)
      const curatedTokens = toGRT('1337')
      const lockBlockhash = randomHexBytes(32)
      const metadata = randomHexBytes()
      const nSignal = toBN('4567')
      const callhookData = defaultAbiCoder.encode(
        ['uint256', 'address', 'bytes32', 'uint256', 'uint32', 'bytes32'],
        [l1SubgraphId, me.address, lockBlockhash, nSignal, DEFAULT_RESERVE_RATIO, metadata],
      )
      const tx = gatewayFinalizeTransfer(me.address, gns.address, curatedTokens, callhookData)

      await expect(tx).revertedWith('ONLY_L1_GNS_THROUGH_BRIDGE')
    })
    it('creates a subgraph in a disabled state', async function () {
      const l1SubgraphId = await buildSubgraphID(me.address, toBN('1'), 1)
      const curatedTokens = toGRT('1337')
      const lockBlockhash = randomHexBytes(32)
      const metadata = randomHexBytes()
      const nSignal = toBN('4567')
      const callhookData = defaultAbiCoder.encode(
        ['uint256', 'address', 'bytes32', 'uint256', 'uint32', 'bytes32'],
        [l1SubgraphId, me.address, lockBlockhash, nSignal, DEFAULT_RESERVE_RATIO, metadata],
      )
      const tx = gatewayFinalizeTransfer(
        mockL1GNS.address,
        gns.address,
        curatedTokens,
        callhookData,
      )

      await expect(tx)
        .emit(l2GraphTokenGateway, 'DepositFinalized')
        .withArgs(mockL1GRT.address, mockL1GNS.address, gns.address, curatedTokens)
      await expect(tx).emit(gns, 'SubgraphReceivedFromL1').withArgs(l1SubgraphId)
      await expect(tx).emit(gns, 'SubgraphMetadataUpdated').withArgs(l1SubgraphId, metadata)

      const migrationData = await gns.subgraphL2MigrationData(l1SubgraphId)
      const subgraphData = await gns.subgraphs(l1SubgraphId)

      expect(migrationData.lockedAtBlock).eq(0) // We don't use this in L2
      expect(migrationData.tokens).eq(curatedTokens)
      expect(migrationData.lockedAtBlockHash).eq(lockBlockhash)
      expect(migrationData.l1Done).eq(true) // We don't use this in L2
      expect(migrationData.l2Done).eq(false)
      expect(migrationData.deprecated).eq(false) // We don't use this in L2

      expect(subgraphData.vSignal).eq(0)
      expect(subgraphData.nSignal).eq(nSignal)
      expect(subgraphData.subgraphDeploymentID).eq(HashZero)
      expect(subgraphData.reserveRatio).eq(DEFAULT_RESERVE_RATIO)
      expect(subgraphData.disabled).eq(true)
      expect(subgraphData.withdrawableGRT).eq(0) // Important so that it's not the same as a deprecated subgraph!

      expect(await gns.ownerOf(l1SubgraphId)).eq(me.address)
    })
    it('does not conflict with a locally created subgraph', async function () {
      const l2Subgraph = await publishNewSubgraph(me, newSubgraph0, gns)

      const l1SubgraphId = await buildSubgraphID(me.address, toBN('0'), 1)
      const curatedTokens = toGRT('1337')
      const lockBlockhash = randomHexBytes(32)
      const metadata = randomHexBytes()
      const nSignal = toBN('4567')
      const callhookData = defaultAbiCoder.encode(
        ['uint256', 'address', 'bytes32', 'uint256', 'uint32', 'bytes32'],
        [l1SubgraphId, me.address, lockBlockhash, nSignal, DEFAULT_RESERVE_RATIO, metadata],
      )
      const tx = gatewayFinalizeTransfer(
        mockL1GNS.address,
        gns.address,
        curatedTokens,
        callhookData,
      )

      await expect(tx)
        .emit(l2GraphTokenGateway, 'DepositFinalized')
        .withArgs(mockL1GRT.address, mockL1GNS.address, gns.address, curatedTokens)
      await expect(tx).emit(gns, 'SubgraphReceivedFromL1').withArgs(l1SubgraphId)
      await expect(tx).emit(gns, 'SubgraphMetadataUpdated').withArgs(l1SubgraphId, metadata)

      const migrationData = await gns.subgraphL2MigrationData(l1SubgraphId)
      const subgraphData = await gns.subgraphs(l1SubgraphId)

      expect(migrationData.lockedAtBlock).eq(0) // We don't use this in L2
      expect(migrationData.tokens).eq(curatedTokens)
      expect(migrationData.lockedAtBlockHash).eq(lockBlockhash)
      expect(migrationData.l1Done).eq(true) // We don't use this in L2
      expect(migrationData.l2Done).eq(false)
      expect(migrationData.deprecated).eq(false) // We don't use this in L2

      expect(subgraphData.vSignal).eq(0)
      expect(subgraphData.nSignal).eq(nSignal)
      expect(subgraphData.subgraphDeploymentID).eq(HashZero)
      expect(subgraphData.reserveRatio).eq(DEFAULT_RESERVE_RATIO)
      expect(subgraphData.disabled).eq(true)
      expect(subgraphData.withdrawableGRT).eq(0) // Important so that it's not the same as a deprecated subgraph!

      expect(await gns.ownerOf(l1SubgraphId)).eq(me.address)

      expect(l2Subgraph.id).not.eq(l1SubgraphId)
      const l2SubgraphData = await gns.subgraphs(l2Subgraph.id)
      expect(l2SubgraphData.vSignal).eq(0)
      expect(l2SubgraphData.nSignal).eq(0)
      expect(l2SubgraphData.subgraphDeploymentID).eq(l2Subgraph.subgraphDeploymentID)
      expect(l2SubgraphData.reserveRatio).eq(DEFAULT_RESERVE_RATIO)
      expect(l2SubgraphData.disabled).eq(false)
      expect(l2SubgraphData.withdrawableGRT).eq(0)
    })
  })

  describe('finishing a subgraph migration from L1', function () {
    it('publishes the migrated subgraph and mints signal with no tax')
    it('cannot be called by someone other than the subgraph owner')
    it('rejects calls for a subgraph that was not migrated')
    it('rejects calls to a pre-curated subgraph deployment')
    it('rejects calls if the subgraph deployment ID is zero')
  })

  describe('claiming a curator balance using a proof', function () {
    it('verifies a proof and assigns a curator balance')
    it('adds the balance to any existing balance for the curator')
    it('rejects calls with an invalid proof')
    it('rejects calls for a subgraph that was not migrated')
    it('rejects calls if the balance was already claimed')
    it('rejects calls with proof from a different curator')
    it('rejects calls with proof from a different contract')
    it('rejects calls with a proof from a different block')
  })
  describe('claiming a curator balance with a message from L1', function () {
    it('assigns a curator balance to a beneficiary')
    it('adds the balance to any existing balance for the beneficiary')
    it('can only be called from the gateway')
    it('rejects calls for a subgraph that was not migrated')
    it('rejects calls if the balance was already claimed')
  })
})
