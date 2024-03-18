/* eslint-disable no-secrets/no-secrets */
import hre from 'hardhat'
import { expect } from 'chai'
import { BigNumber, ContractTransaction, ethers } from 'ethers'
import { defaultAbiCoder, parseEther } from 'ethers/lib/utils'

import { NetworkFixture } from '../lib/fixtures'

import { L2GNS } from '../../../build/types/L2GNS'
import { L2GraphTokenGateway } from '../../../build/types/L2GraphTokenGateway'
import {
  burnSignal,
  DEFAULT_RESERVE_RATIO,
  deprecateSubgraph,
  mintSignal,
  publishNewSubgraph,
  publishNewVersion,
} from '../lib/gnsUtils'
import { L2Curation } from '../../../build/types/L2Curation'
import { GraphToken } from '../../../build/types/GraphToken'
import {
  buildSubgraph,
  buildSubgraphId,
  deriveChannelKey,
  GraphNetworkContracts,
  helpers,
  PublishSubgraph,
  randomHexBytes,
  Subgraph,
  toBN,
  toGRT,
} from '@graphprotocol/sdk'
import { SignerWithAddress } from '@nomiclabs/hardhat-ethers/signers'
import { IL2Staking } from '../../../build/types/IL2Staking'
import { L1GNS, L1GraphTokenGateway } from '../../../build/types'

const { HashZero } = ethers.constants

interface L1SubgraphParams {
  l1SubgraphId: string
  curatedTokens: BigNumber
  subgraphMetadata: string
  versionMetadata: string
}

describe('L2GNS', () => {
  const graph = hre.graph()
  let me: SignerWithAddress
  let attacker: SignerWithAddress
  let other: SignerWithAddress
  let governor: SignerWithAddress
  let fixture: NetworkFixture

  let fixtureContracts: GraphNetworkContracts
  let l1MockContracts: GraphNetworkContracts
  let l1GRTMock: GraphToken
  let l1GNSMock: L1GNS
  let l1GRTGatewayMock: L1GraphTokenGateway
  let l2GraphTokenGateway: L2GraphTokenGateway
  let gns: L2GNS
  let curation: L2Curation
  let grt: GraphToken
  let staking: IL2Staking

  let newSubgraph0: PublishSubgraph
  let newSubgraph1: PublishSubgraph

  const tokens1000 = toGRT('1000')
  const tokens10000 = toGRT('10000')
  const tokens100000 = toGRT('100000')
  const curationTaxPercentage = 50000

  const gatewayFinalizeTransfer = async function (
    from: string,
    to: string,
    amount: BigNumber,
    callhookData: string,
  ): Promise<ContractTransaction> {
    const l1GRTGatewayMockL2Alias = await helpers.getL2SignerFromL1(l1GRTGatewayMock.address)
    // Eth for gas:
    await helpers.setBalance(await l1GRTGatewayMockL2Alias.getAddress(), parseEther('1'))

    const tx = l2GraphTokenGateway
      .connect(l1GRTGatewayMockL2Alias)
      .finalizeInboundTransfer(l1GRTMock.address, from, to, amount, callhookData)
    return tx
  }

  const defaultL1SubgraphParams = async function (): Promise<L1SubgraphParams> {
    return {
      l1SubgraphId: await buildSubgraphId(me.address, toBN('1'), graph.chainId),
      curatedTokens: toGRT('1337'),
      subgraphMetadata: randomHexBytes(),
      versionMetadata: randomHexBytes(),
    }
  }
  const transferMockSubgraphFromL1 = async function (
    l1SubgraphId: string,
    curatedTokens: BigNumber,
    subgraphMetadata: string,
    versionMetadata: string,
  ) {
    const callhookData = defaultAbiCoder.encode(
      ['uint8', 'uint256', 'address'],
      [toBN(0), l1SubgraphId, me.address],
    )
    await gatewayFinalizeTransfer(l1GNSMock.address, gns.address, curatedTokens, callhookData)

    const l2SubgraphId = await gns.getAliasedL2SubgraphID(l1SubgraphId)
    await gns
      .connect(me)
      .finishSubgraphTransferFromL1(
        l2SubgraphId,
        newSubgraph0.subgraphDeploymentID,
        subgraphMetadata,
        versionMetadata,
      )
  }

  before(async function () {
    newSubgraph0 = buildSubgraph()
    ;[me, attacker, other] = await graph.getTestAccounts()
    ;({ governor } = await graph.getNamedAccounts())

    fixture = new NetworkFixture(graph.provider)

    // Deploy L2
    fixtureContracts = await fixture.load(governor, true)
    l2GraphTokenGateway = fixtureContracts.L2GraphTokenGateway
    gns = fixtureContracts.L2GNS
    staking = fixtureContracts.L2Staking as unknown as IL2Staking
    curation = fixtureContracts.L2Curation
    grt = fixtureContracts.GraphToken as GraphToken

    // Deploy L1 mock
    l1MockContracts = await fixture.loadMock(false)
    l1GRTMock = l1MockContracts.GraphToken as GraphToken
    l1GNSMock = l1MockContracts.L1GNS
    l1GRTGatewayMock = l1MockContracts.L1GraphTokenGateway

    // Deploy L2 arbitrum bridge
    await fixture.loadL2ArbitrumBridge(governor)

    // Configure L2 bridge
    await fixture.configureL2Bridge(governor, fixtureContracts, l1MockContracts)

    await grt.connect(governor).mint(me.address, toGRT('10000'))
  })

  beforeEach(async function () {
    await fixture.setUp()
  })

  afterEach(async function () {
    await fixture.tearDown()
  })

  // Adapted from the L1 GNS tests but allowing curating to a pre-curated subgraph deployment
  describe('publishNewVersion', function () {
    let subgraph: Subgraph

    beforeEach(async () => {
      newSubgraph0 = buildSubgraph()
      newSubgraph1 = buildSubgraph()
      // Give some funds to the signers and approve gns contract to use funds on signers behalf
      await grt.connect(governor).mint(me.address, tokens100000)
      await grt.connect(governor).mint(other.address, tokens100000)
      await grt.connect(me).approve(gns.address, tokens100000)
      await grt.connect(me).approve(curation.address, tokens100000)
      await grt.connect(other).approve(gns.address, tokens100000)
      await grt.connect(other).approve(curation.address, tokens100000)
      // Update curation tax to test the functionality of it in disableNameSignal()
      await curation.connect(governor).setCurationTaxPercentage(curationTaxPercentage)
      subgraph = await publishNewSubgraph(me, newSubgraph0, gns, graph.chainId)
      await mintSignal(me, subgraph.id, tokens10000, gns, curation)
    })

    it('should publish a new version on an existing subgraph', async function () {
      await publishNewVersion(me, subgraph.id, newSubgraph1, gns, curation)
    })

    it('should publish a new version on an existing subgraph when owner tax is zero', async function () {
      await gns.connect(governor).setOwnerTaxPercentage(0)
      await publishNewVersion(me, subgraph.id, newSubgraph1, gns, curation)
    })

    it('should publish a new version on an existing subgraph with no current signal', async function () {
      const emptySignalSubgraph = await publishNewSubgraph(me, buildSubgraph(), gns, graph.chainId)
      await publishNewVersion(me, emptySignalSubgraph.id, newSubgraph1, gns, curation)
    })

    it('should reject a new version with the same subgraph deployment ID', async function () {
      const tx = gns
        .connect(me)
        .publishNewVersion(
          subgraph.id,
          newSubgraph0.subgraphDeploymentID,
          newSubgraph0.versionMetadata,
        )
      await expect(tx).revertedWith(
        'GNS: Cannot publish a new version with the same subgraph deployment ID',
      )
    })

    it('should reject publishing a version to a subgraph that does not exist', async function () {
      const tx = gns
        .connect(me)
        .publishNewVersion(
          randomHexBytes(32),
          newSubgraph1.subgraphDeploymentID,
          newSubgraph1.versionMetadata,
        )
      await expect(tx).revertedWith('ERC721: owner query for nonexistent token')
    })

    it('reject if not the owner', async function () {
      const tx = gns
        .connect(other)
        .publishNewVersion(
          subgraph.id,
          newSubgraph1.subgraphDeploymentID,
          newSubgraph1.versionMetadata,
        )
      await expect(tx).revertedWith('GNS: Must be authorized')
    })

    it('should NOT fail when upgrade tries to point to a pre-curated', async function () {
      // Curate directly to the deployment
      await curation.connect(me).mint(newSubgraph1.subgraphDeploymentID, tokens1000, 0)

      await publishNewVersion(me, subgraph.id, newSubgraph1, gns, curation)
    })

    it('should upgrade version when there is no signal with no signal migration', async function () {
      await burnSignal(me, subgraph.id, gns, curation)
      const tx = gns
        .connect(me)
        .publishNewVersion(
          subgraph.id,
          newSubgraph1.subgraphDeploymentID,
          newSubgraph1.versionMetadata,
        )
      await expect(tx)
        .emit(gns, 'SubgraphVersionUpdated')
        .withArgs(subgraph.id, newSubgraph1.subgraphDeploymentID, newSubgraph1.versionMetadata)
    })

    it('should fail when subgraph is deprecated', async function () {
      await deprecateSubgraph(me, subgraph.id, gns, curation, grt)
      const tx = gns
        .connect(me)
        .publishNewVersion(
          subgraph.id,
          newSubgraph1.subgraphDeploymentID,
          newSubgraph1.versionMetadata,
        )
      // NOTE: deprecate burns the Subgraph NFT, when someone wants to publish a new version it won't find it
      await expect(tx).revertedWith('ERC721: owner query for nonexistent token')
    })
  })

  describe('receiving a subgraph from L1 (onTokenTransfer)', function () {
    it('cannot be called by someone other than the L2GraphTokenGateway', async function () {
      const { l1SubgraphId, curatedTokens } = await defaultL1SubgraphParams()
      const callhookData = defaultAbiCoder.encode(
        ['uint8', 'uint256', 'address'],
        [toBN(0), l1SubgraphId, me.address],
      )
      const tx = gns.connect(me).onTokenTransfer(l1GNSMock.address, curatedTokens, callhookData)
      await expect(tx).revertedWith('ONLY_GATEWAY')
    })
    it('rejects calls if the L1 sender is not the L1GNS', async function () {
      const { l1SubgraphId, curatedTokens } = await defaultL1SubgraphParams()
      const callhookData = defaultAbiCoder.encode(
        ['uint8', 'uint256', 'address'],
        [toBN(0), l1SubgraphId, me.address],
      )
      const tx = gatewayFinalizeTransfer(me.address, gns.address, curatedTokens, callhookData)

      await expect(tx).revertedWith('ONLY_L1_GNS_THROUGH_BRIDGE')
    })
    it('creates a subgraph in a disabled state', async function () {
      const { l1SubgraphId, curatedTokens } = await defaultL1SubgraphParams()
      const callhookData = defaultAbiCoder.encode(
        ['uint8', 'uint256', 'address'],
        [toBN(0), l1SubgraphId, me.address],
      )
      const tx = gatewayFinalizeTransfer(
        l1GNSMock.address,
        gns.address,
        curatedTokens,
        callhookData,
      )

      const l2SubgraphId = await gns.getAliasedL2SubgraphID(l1SubgraphId)

      await expect(tx)
        .emit(l2GraphTokenGateway, 'DepositFinalized')
        .withArgs(l1GRTMock.address, l1GNSMock.address, gns.address, curatedTokens)
      await expect(tx)
        .emit(gns, 'SubgraphReceivedFromL1')
        .withArgs(l1SubgraphId, l2SubgraphId, me.address, curatedTokens)

      const transferData = await gns.subgraphL2TransferData(l2SubgraphId)
      const subgraphData = await gns.subgraphs(l2SubgraphId)

      expect(transferData.tokens).eq(curatedTokens)
      expect(transferData.l2Done).eq(false)
      expect(transferData.subgraphReceivedOnL2BlockNumber).eq(await helpers.latestBlock())

      expect(subgraphData.vSignal).eq(0)
      expect(subgraphData.nSignal).eq(0)
      expect(subgraphData.subgraphDeploymentID).eq(HashZero)
      expect(subgraphData.__DEPRECATED_reserveRatio).eq(DEFAULT_RESERVE_RATIO)
      expect(subgraphData.disabled).eq(true)
      expect(subgraphData.withdrawableGRT).eq(0) // Important so that it's not the same as a deprecated subgraph!

      expect(await gns.ownerOf(l2SubgraphId)).eq(me.address)
    })
    it('does not conflict with a locally created subgraph', async function () {
      const l2Subgraph = await publishNewSubgraph(me, newSubgraph0, gns, graph.chainId)

      const { l1SubgraphId, curatedTokens } = await defaultL1SubgraphParams()
      const callhookData = defaultAbiCoder.encode(
        ['uint8', 'uint256', 'address'],
        [toBN(0), l1SubgraphId, me.address],
      )
      const tx = gatewayFinalizeTransfer(
        l1GNSMock.address,
        gns.address,
        curatedTokens,
        callhookData,
      )

      const l2SubgraphId = await gns.getAliasedL2SubgraphID(l1SubgraphId)

      await expect(tx)
        .emit(l2GraphTokenGateway, 'DepositFinalized')
        .withArgs(l1GRTMock.address, l1GNSMock.address, gns.address, curatedTokens)
      await expect(tx)
        .emit(gns, 'SubgraphReceivedFromL1')
        .withArgs(l1SubgraphId, l2SubgraphId, me.address, curatedTokens)

      const transferData = await gns.subgraphL2TransferData(l2SubgraphId)
      const subgraphData = await gns.subgraphs(l2SubgraphId)

      expect(transferData.tokens).eq(curatedTokens)
      expect(transferData.l2Done).eq(false)
      expect(transferData.subgraphReceivedOnL2BlockNumber).eq(await helpers.latestBlock())

      expect(subgraphData.vSignal).eq(0)
      expect(subgraphData.nSignal).eq(0)
      expect(subgraphData.subgraphDeploymentID).eq(HashZero)
      expect(subgraphData.__DEPRECATED_reserveRatio).eq(DEFAULT_RESERVE_RATIO)
      expect(subgraphData.disabled).eq(true)
      expect(subgraphData.withdrawableGRT).eq(0) // Important so that it's not the same as a deprecated subgraph!

      expect(await gns.ownerOf(l2SubgraphId)).eq(me.address)

      expect(l2Subgraph.id).not.eq(l2SubgraphId)
      const l2SubgraphData = await gns.subgraphs(l2Subgraph.id)
      expect(l2SubgraphData.vSignal).eq(0)
      expect(l2SubgraphData.nSignal).eq(0)
      expect(l2SubgraphData.subgraphDeploymentID).eq(l2Subgraph.subgraphDeploymentID)
      expect(l2SubgraphData.__DEPRECATED_reserveRatio).eq(DEFAULT_RESERVE_RATIO)
      expect(l2SubgraphData.disabled).eq(false)
      expect(l2SubgraphData.withdrawableGRT).eq(0)
    })
  })

  describe('finishing a subgraph transfer from L1', function () {
    it('publishes the transferred subgraph and mints signal with no tax', async function () {
      const { l1SubgraphId, curatedTokens, subgraphMetadata, versionMetadata }
        = await defaultL1SubgraphParams()
      const callhookData = defaultAbiCoder.encode(
        ['uint8', 'uint256', 'address'],
        [toBN(0), l1SubgraphId, me.address],
      )
      await gatewayFinalizeTransfer(l1GNSMock.address, gns.address, curatedTokens, callhookData)
      // Calculate expected signal before minting
      const expectedSignal = await curation.tokensToSignalNoTax(
        newSubgraph0.subgraphDeploymentID,
        curatedTokens,
      )
      const l2SubgraphId = await gns.getAliasedL2SubgraphID(l1SubgraphId)
      const tx = gns
        .connect(me)
        .finishSubgraphTransferFromL1(
          l2SubgraphId,
          newSubgraph0.subgraphDeploymentID,
          subgraphMetadata,
          versionMetadata,
        )
      await expect(tx)
        .emit(gns, 'SubgraphPublished')
        .withArgs(l2SubgraphId, newSubgraph0.subgraphDeploymentID, DEFAULT_RESERVE_RATIO)
      await expect(tx).emit(gns, 'SubgraphMetadataUpdated').withArgs(l2SubgraphId, subgraphMetadata)
      await expect(tx)
        .emit(gns, 'SubgraphUpgraded')
        .withArgs(l2SubgraphId, expectedSignal, curatedTokens, newSubgraph0.subgraphDeploymentID)
      await expect(tx)
        .emit(gns, 'SubgraphVersionUpdated')
        .withArgs(l2SubgraphId, newSubgraph0.subgraphDeploymentID, versionMetadata)
      await expect(tx).emit(gns, 'SubgraphL2TransferFinalized').withArgs(l2SubgraphId)

      const subgraphAfter = await gns.subgraphs(l2SubgraphId)
      const transferDataAfter = await gns.subgraphL2TransferData(l2SubgraphId)
      expect(subgraphAfter.vSignal).eq(expectedSignal)
      expect(transferDataAfter.l2Done).eq(true)
      expect(subgraphAfter.disabled).eq(false)
      expect(subgraphAfter.subgraphDeploymentID).eq(newSubgraph0.subgraphDeploymentID)
      const expectedNSignal = await gns.vSignalToNSignal(l2SubgraphId, expectedSignal)
      expect(await gns.getCuratorSignal(l2SubgraphId, me.address)).eq(expectedNSignal)
      await expect(tx)
        .emit(gns, 'SignalMinted')
        .withArgs(l2SubgraphId, me.address, expectedNSignal, expectedSignal, curatedTokens)
    })
    it('protects the owner against a rounding attack', async function () {
      const { l1SubgraphId, curatedTokens, subgraphMetadata, versionMetadata }
        = await defaultL1SubgraphParams()
      const collectTokens = curatedTokens.mul(20)

      await staking.connect(governor).setCurationPercentage(100000)

      // Set up an indexer account with some stake
      await grt.connect(governor).mint(attacker.address, toGRT('1000000'))
      // Curate 1 wei GRT by minting 1 GRT and burning most of it
      await grt.connect(attacker).approve(curation.address, toBN(1))
      await curation.connect(attacker).mint(newSubgraph0.subgraphDeploymentID, toBN(1), 0)

      // Check this actually gave us 1 wei signal
      expect(await curation.getCurationPoolTokens(newSubgraph0.subgraphDeploymentID)).eq(1)
      await grt.connect(attacker).approve(staking.address, toGRT('1000000'))
      await staking.connect(attacker).stake(toGRT('100000'))
      const channelKey = deriveChannelKey()
      // Allocate to the same deployment ID
      await staking
        .connect(attacker)
        .allocateFrom(
          attacker.address,
          newSubgraph0.subgraphDeploymentID,
          toGRT('100000'),
          channelKey.address,
          randomHexBytes(32),
          await channelKey.generateProof(attacker.address),
        )
      // Spoof some query fees, 10% of which will go to the Curation pool
      await staking.connect(attacker).collect(collectTokens, channelKey.address)
      // The curation pool now has 1 wei shares and a lot of tokens, so the rounding attack is prepared
      // But L2GNS will protect the owner by sending the tokens
      const callhookData = defaultAbiCoder.encode(
        ['uint8', 'uint256', 'address'],
        [toBN(0), l1SubgraphId, me.address],
      )
      await gatewayFinalizeTransfer(l1GNSMock.address, gns.address, curatedTokens, callhookData)

      const l2SubgraphId = await gns.getAliasedL2SubgraphID(l1SubgraphId)
      const tx = gns
        .connect(me)
        .finishSubgraphTransferFromL1(
          l2SubgraphId,
          newSubgraph0.subgraphDeploymentID,
          subgraphMetadata,
          versionMetadata,
        )
      await expect(tx)
        .emit(gns, 'SubgraphPublished')
        .withArgs(l2SubgraphId, newSubgraph0.subgraphDeploymentID, DEFAULT_RESERVE_RATIO)
      await expect(tx).emit(gns, 'SubgraphMetadataUpdated').withArgs(l2SubgraphId, subgraphMetadata)
      await expect(tx).emit(gns, 'CuratorBalanceReturnedToBeneficiary')
      await expect(tx)
        .emit(gns, 'SubgraphUpgraded')
        .withArgs(l2SubgraphId, 0, 0, newSubgraph0.subgraphDeploymentID)
      await expect(tx)
        .emit(gns, 'SubgraphVersionUpdated')
        .withArgs(l2SubgraphId, newSubgraph0.subgraphDeploymentID, versionMetadata)
      await expect(tx).emit(gns, 'SubgraphL2TransferFinalized').withArgs(l2SubgraphId)
    })
    it('cannot be called by someone other than the subgraph owner', async function () {
      const { l1SubgraphId, curatedTokens, subgraphMetadata, versionMetadata }
        = await defaultL1SubgraphParams()
      const callhookData = defaultAbiCoder.encode(
        ['uint8', 'uint256', 'address'],
        [toBN(0), l1SubgraphId, me.address],
      )
      await gatewayFinalizeTransfer(l1GNSMock.address, gns.address, curatedTokens, callhookData)
      const l2SubgraphId = await gns.getAliasedL2SubgraphID(l1SubgraphId)
      const tx = gns
        .connect(other)
        .finishSubgraphTransferFromL1(
          l2SubgraphId,
          newSubgraph0.subgraphDeploymentID,
          subgraphMetadata,
          versionMetadata,
        )
      await expect(tx).revertedWith('GNS: Must be authorized')
    })
    it('rejects calls for a subgraph that does not exist', async function () {
      const l1SubgraphId = await buildSubgraphId(me.address, toBN('1'), graph.chainId)
      const metadata = randomHexBytes()
      const l2SubgraphId = await gns.getAliasedL2SubgraphID(l1SubgraphId)
      const tx = gns
        .connect(me)
        .finishSubgraphTransferFromL1(
          l2SubgraphId,
          newSubgraph0.subgraphDeploymentID,
          metadata,
          metadata,
        )
      await expect(tx).revertedWith('ERC721: owner query for nonexistent token')
    })
    it('rejects calls for a subgraph that was not transferred from L1', async function () {
      const l2Subgraph = await publishNewSubgraph(me, newSubgraph0, gns, graph.chainId)
      const metadata = randomHexBytes()

      const tx = gns
        .connect(me)
        .finishSubgraphTransferFromL1(
          l2Subgraph.id,
          newSubgraph0.subgraphDeploymentID,
          metadata,
          metadata,
        )
      await expect(tx).revertedWith('INVALID_SUBGRAPH')
    })
    it('accepts calls to a pre-curated subgraph deployment', async function () {
      const { l1SubgraphId, curatedTokens, subgraphMetadata, versionMetadata }
        = await defaultL1SubgraphParams()
      const callhookData = defaultAbiCoder.encode(
        ['uint8', 'uint256', 'address'],
        [toBN(0), l1SubgraphId, me.address],
      )
      await gatewayFinalizeTransfer(l1GNSMock.address, gns.address, curatedTokens, callhookData)
      const l2SubgraphId = await gns.getAliasedL2SubgraphID(l1SubgraphId)

      // Calculate expected signal before minting
      const expectedSignal = await curation.tokensToSignalNoTax(
        newSubgraph0.subgraphDeploymentID,
        curatedTokens,
      )
      await grt.connect(me).approve(curation.address, toGRT('100'))
      await curation.connect(me).mint(newSubgraph0.subgraphDeploymentID, toGRT('100'), toBN('0'))

      expect(await curation.getCurationPoolTokens(newSubgraph0.subgraphDeploymentID)).eq(
        toGRT('100'),
      )
      const tx = gns
        .connect(me)
        .finishSubgraphTransferFromL1(
          l2SubgraphId,
          newSubgraph0.subgraphDeploymentID,
          subgraphMetadata,
          versionMetadata,
        )
      await expect(tx)
        .emit(gns, 'SubgraphPublished')
        .withArgs(l2SubgraphId, newSubgraph0.subgraphDeploymentID, DEFAULT_RESERVE_RATIO)
      await expect(tx).emit(gns, 'SubgraphMetadataUpdated').withArgs(l2SubgraphId, subgraphMetadata)
      await expect(tx)
        .emit(gns, 'SubgraphUpgraded')
        .withArgs(l2SubgraphId, expectedSignal, curatedTokens, newSubgraph0.subgraphDeploymentID)
      await expect(tx)
        .emit(gns, 'SubgraphVersionUpdated')
        .withArgs(l2SubgraphId, newSubgraph0.subgraphDeploymentID, versionMetadata)
      await expect(tx).emit(gns, 'SubgraphL2TransferFinalized').withArgs(l2SubgraphId)

      const subgraphAfter = await gns.subgraphs(l2SubgraphId)
      const transferDataAfter = await gns.subgraphL2TransferData(l2SubgraphId)
      expect(subgraphAfter.vSignal).eq(expectedSignal)
      expect(transferDataAfter.l2Done).eq(true)
      expect(subgraphAfter.disabled).eq(false)
      expect(subgraphAfter.subgraphDeploymentID).eq(newSubgraph0.subgraphDeploymentID)
      expect(await curation.getCurationPoolTokens(newSubgraph0.subgraphDeploymentID)).eq(
        toGRT('100').add(curatedTokens),
      )
    })
    it('rejects calls if the subgraph deployment ID is zero', async function () {
      const metadata = randomHexBytes()
      const { l1SubgraphId, curatedTokens } = await defaultL1SubgraphParams()
      const callhookData = defaultAbiCoder.encode(
        ['uint8', 'uint256', 'address'],
        [toBN(0), l1SubgraphId, me.address],
      )
      await gatewayFinalizeTransfer(l1GNSMock.address, gns.address, curatedTokens, callhookData)
      const l2SubgraphId = await gns.getAliasedL2SubgraphID(l1SubgraphId)
      const tx = gns
        .connect(me)
        .finishSubgraphTransferFromL1(l2SubgraphId, HashZero, metadata, metadata)
      await expect(tx).revertedWith('GNS: deploymentID != 0')
    })
    it('rejects calls if the subgraph transfer was already finished', async function () {
      const metadata = randomHexBytes()
      const { l1SubgraphId, curatedTokens } = await defaultL1SubgraphParams()
      const callhookData = defaultAbiCoder.encode(
        ['uint8', 'uint256', 'address'],
        [toBN(0), l1SubgraphId, me.address],
      )
      await gatewayFinalizeTransfer(l1GNSMock.address, gns.address, curatedTokens, callhookData)
      const l2SubgraphId = await gns.getAliasedL2SubgraphID(l1SubgraphId)
      await gns
        .connect(me)
        .finishSubgraphTransferFromL1(
          l2SubgraphId,
          newSubgraph0.subgraphDeploymentID,
          metadata,
          metadata,
        )

      const tx = gns
        .connect(me)
        .finishSubgraphTransferFromL1(
          l2SubgraphId,
          newSubgraph0.subgraphDeploymentID,
          metadata,
          metadata,
        )
      await expect(tx).revertedWith('ALREADY_DONE')
    })
  })
  describe('claiming a curator balance with a message from L1 (onTokenTransfer)', function () {
    it('assigns a curator balance to a beneficiary', async function () {
      const l1GNSMockL2Alias = await helpers.getL2SignerFromL1(l1GNSMock.address)
      // Eth for gas:
      await helpers.setBalance(await l1GNSMockL2Alias.getAddress(), parseEther('1'))

      const { l1SubgraphId, curatedTokens, subgraphMetadata, versionMetadata }
        = await defaultL1SubgraphParams()
      await transferMockSubgraphFromL1(
        l1SubgraphId,
        curatedTokens,
        subgraphMetadata,
        versionMetadata,
      )
      const l2SubgraphId = await gns.getAliasedL2SubgraphID(l1SubgraphId)
      const l2OwnerSignalBefore = await gns.getCuratorSignal(l2SubgraphId, me.address)

      const newCuratorTokens = toGRT('10')
      const callhookData = defaultAbiCoder.encode(
        ['uint8', 'uint256', 'address'],
        [toBN(1), l1SubgraphId, other.address],
      )
      const tx = await gatewayFinalizeTransfer(
        l1GNSMock.address,
        gns.address,
        newCuratorTokens,
        callhookData,
      )

      await expect(tx)
        .emit(gns, 'CuratorBalanceReceived')
        .withArgs(l1SubgraphId, l2SubgraphId, other.address, newCuratorTokens)

      const l2NewCuratorSignal = await gns.getCuratorSignal(l2SubgraphId, other.address)
      const expectedNewCuratorSignal = await gns.vSignalToNSignal(
        l2SubgraphId,
        await curation.tokensToSignalNoTax(newSubgraph0.subgraphDeploymentID, newCuratorTokens),
      )
      const l2OwnerSignalAfter = await gns.getCuratorSignal(l2SubgraphId, me.address)
      expect(l2OwnerSignalAfter).eq(l2OwnerSignalBefore)
      expect(l2NewCuratorSignal).eq(expectedNewCuratorSignal)
    })
    it('adds the signal to any existing signal for the beneficiary', async function () {
      const l1GNSMockL2Alias = await helpers.getL2SignerFromL1(l1GNSMock.address)
      // Eth for gas:
      await helpers.setBalance(await l1GNSMockL2Alias.getAddress(), parseEther('1'))

      const { l1SubgraphId, curatedTokens, subgraphMetadata, versionMetadata }
        = await defaultL1SubgraphParams()
      await transferMockSubgraphFromL1(
        l1SubgraphId,
        curatedTokens,
        subgraphMetadata,
        versionMetadata,
      )

      const l2SubgraphId = await gns.getAliasedL2SubgraphID(l1SubgraphId)
      await grt.connect(governor).mint(other.address, toGRT('10'))
      await grt.connect(other).approve(gns.address, toGRT('10'))
      await gns.connect(other).mintSignal(l2SubgraphId, toGRT('10'), toBN(0))
      const prevSignal = await gns.getCuratorSignal(l2SubgraphId, other.address)

      const newCuratorTokens = toGRT('10')
      const callhookData = defaultAbiCoder.encode(
        ['uint8', 'uint256', 'address'],
        [toBN(1), l1SubgraphId, other.address],
      )
      const tx = await gatewayFinalizeTransfer(
        l1GNSMock.address,
        gns.address,
        newCuratorTokens,
        callhookData,
      )

      await expect(tx)
        .emit(gns, 'CuratorBalanceReceived')
        .withArgs(l1SubgraphId, l2SubgraphId, other.address, newCuratorTokens)

      const expectedNewCuratorSignal = await gns.vSignalToNSignal(
        l2SubgraphId,
        await curation.tokensToSignalNoTax(newSubgraph0.subgraphDeploymentID, newCuratorTokens),
      )
      const l2CuratorBalance = await gns.getCuratorSignal(l2SubgraphId, other.address)
      expect(l2CuratorBalance).eq(prevSignal.add(expectedNewCuratorSignal))
    })
    it('cannot be called by someone other than the L2GraphTokenGateway', async function () {
      const { l1SubgraphId, curatedTokens, subgraphMetadata, versionMetadata }
        = await defaultL1SubgraphParams()
      await transferMockSubgraphFromL1(
        l1SubgraphId,
        curatedTokens,
        subgraphMetadata,
        versionMetadata,
      )
      const callhookData = defaultAbiCoder.encode(
        ['uint8', 'uint256', 'address'],
        [toBN(1), l1SubgraphId, me.address],
      )
      const tx = gns.connect(me).onTokenTransfer(l1GNSMock.address, toGRT('1'), callhookData)
      await expect(tx).revertedWith('ONLY_GATEWAY')
    })
    it('rejects calls if the L1 sender is not the L1GNS', async function () {
      const { l1SubgraphId, curatedTokens, subgraphMetadata, versionMetadata }
        = await defaultL1SubgraphParams()
      await transferMockSubgraphFromL1(
        l1SubgraphId,
        curatedTokens,
        subgraphMetadata,
        versionMetadata,
      )
      const callhookData = defaultAbiCoder.encode(
        ['uint8', 'uint256', 'address'],
        [toBN(1), l1SubgraphId, me.address],
      )
      const tx = gatewayFinalizeTransfer(me.address, gns.address, toGRT('1'), callhookData)

      await expect(tx).revertedWith('ONLY_L1_GNS_THROUGH_BRIDGE')
    })
    it('if a subgraph does not exist, it returns the tokens to the beneficiary', async function () {
      const l1GNSMockL2Alias = await helpers.getL2SignerFromL1(l1GNSMock.address)
      // Eth for gas:
      await helpers.setBalance(await l1GNSMockL2Alias.getAddress(), parseEther('1'))

      const { l1SubgraphId } = await defaultL1SubgraphParams()

      const callhookData = defaultAbiCoder.encode(
        ['uint8', 'uint256', 'address'],
        [toBN(1), l1SubgraphId, me.address],
      )
      const curatorTokensBefore = await grt.balanceOf(me.address)
      const gnsBalanceBefore = await grt.balanceOf(gns.address)
      const tx = gatewayFinalizeTransfer(l1GNSMock.address, gns.address, toGRT('1'), callhookData)
      await expect(tx)
        .emit(gns, 'CuratorBalanceReturnedToBeneficiary')
        .withArgs(l1SubgraphId, me.address, toGRT('1'))
      const curatorTokensAfter = await grt.balanceOf(me.address)
      expect(curatorTokensAfter).eq(curatorTokensBefore.add(toGRT('1')))
      const gnsBalanceAfter = await grt.balanceOf(gns.address)
      // gatewayFinalizeTransfer will mint the tokens that are sent to the curator,
      // so the GNS balance should be the same
      expect(gnsBalanceAfter).eq(gnsBalanceBefore)
    })
    it('for an L2-native subgraph, it sends the tokens to the beneficiary', async function () {
      // This should never really happen unless there's a clash in subgraph IDs (which should
      // also never happen), but we test it anyway to ensure it's a well-defined behavior
      const l1GNSMockL2Alias = await helpers.getL2SignerFromL1(l1GNSMock.address)
      // Eth for gas:
      await helpers.setBalance(await l1GNSMockL2Alias.getAddress(), parseEther('1'))

      const l2Subgraph = await publishNewSubgraph(me, newSubgraph0, gns, graph.chainId)

      const callhookData = defaultAbiCoder.encode(
        ['uint8', 'uint256', 'address'],
        [toBN(1), l2Subgraph.id, me.address],
      )
      const curatorTokensBefore = await grt.balanceOf(me.address)
      const gnsBalanceBefore = await grt.balanceOf(gns.address)
      const tx = gatewayFinalizeTransfer(l1GNSMock.address, gns.address, toGRT('1'), callhookData)
      await expect(tx)
        .emit(gns, 'CuratorBalanceReturnedToBeneficiary')
        .withArgs(l2Subgraph.id, me.address, toGRT('1'))
      const curatorTokensAfter = await grt.balanceOf(me.address)
      expect(curatorTokensAfter).eq(curatorTokensBefore.add(toGRT('1')))
      const gnsBalanceAfter = await grt.balanceOf(gns.address)
      // gatewayFinalizeTransfer will mint the tokens that are sent to the curator,
      // so the GNS balance should be the same
      expect(gnsBalanceAfter).eq(gnsBalanceBefore)
    })
    it('if a subgraph transfer was not finished, it returns the tokens to the beneficiary', async function () {
      const l1GNSMockL2Alias = await helpers.getL2SignerFromL1(l1GNSMock.address)
      // Eth for gas:
      await helpers.setBalance(await l1GNSMockL2Alias.getAddress(), parseEther('1'))

      const { l1SubgraphId, curatedTokens } = await defaultL1SubgraphParams()
      const callhookDataSG = defaultAbiCoder.encode(
        ['uint8', 'uint256', 'address'],
        [toBN(0), l1SubgraphId, me.address],
      )
      await gatewayFinalizeTransfer(l1GNSMock.address, gns.address, curatedTokens, callhookDataSG)

      // At this point the SG exists, but transfer is not finished

      const callhookData = defaultAbiCoder.encode(
        ['uint8', 'uint256', 'address'],
        [toBN(1), l1SubgraphId, me.address],
      )
      const curatorTokensBefore = await grt.balanceOf(me.address)
      const gnsBalanceBefore = await grt.balanceOf(gns.address)
      const tx = gatewayFinalizeTransfer(l1GNSMock.address, gns.address, toGRT('1'), callhookData)
      await expect(tx)
        .emit(gns, 'CuratorBalanceReturnedToBeneficiary')
        .withArgs(l1SubgraphId, me.address, toGRT('1'))
      const curatorTokensAfter = await grt.balanceOf(me.address)
      expect(curatorTokensAfter).eq(curatorTokensBefore.add(toGRT('1')))
      const gnsBalanceAfter = await grt.balanceOf(gns.address)
      // gatewayFinalizeTransfer will mint the tokens that are sent to the curator,
      // so the GNS balance should be the same
      expect(gnsBalanceAfter).eq(gnsBalanceBefore)
    })

    it('protects the curator against a rounding attack', async function () {
      // Transfer a subgraph from L1 with only 1 wei GRT of curated signal
      const { l1SubgraphId, subgraphMetadata, versionMetadata } = await defaultL1SubgraphParams()
      const curatedTokens = toBN('1')
      await transferMockSubgraphFromL1(
        l1SubgraphId,
        curatedTokens,
        subgraphMetadata,
        versionMetadata,
      )
      // Prepare the rounding attack by setting up an indexer and collecting a lot of query fees
      const curatorTokens = toGRT('10000')
      const collectTokens = curatorTokens.mul(20)
      await staking.connect(governor).setCurationPercentage(100000)
      // Set up an indexer account with some stake
      await grt.connect(governor).mint(attacker.address, toGRT('1000000'))

      await grt.connect(attacker).approve(staking.address, toGRT('1000000'))
      await staking.connect(attacker).stake(toGRT('100000'))
      const channelKey = deriveChannelKey()
      // Allocate to the same deployment ID
      await staking
        .connect(attacker)
        .allocateFrom(
          attacker.address,
          newSubgraph0.subgraphDeploymentID,
          toGRT('100000'),
          channelKey.address,
          randomHexBytes(32),
          await channelKey.generateProof(attacker.address),
        )
      // Spoof some query fees, 10% of which will go to the Curation pool
      await staking.connect(attacker).collect(collectTokens, channelKey.address)

      const callhookData = defaultAbiCoder.encode(
        ['uint8', 'uint256', 'address'],
        [toBN(1), l1SubgraphId, me.address],
      )
      const curatorTokensBefore = await grt.balanceOf(me.address)
      const gnsBalanceBefore = await grt.balanceOf(gns.address)
      const tx = gatewayFinalizeTransfer(
        l1GNSMock.address,
        gns.address,
        curatorTokens,
        callhookData,
      )
      await expect(tx)
        .emit(gns, 'CuratorBalanceReturnedToBeneficiary')
        .withArgs(l1SubgraphId, me.address, curatorTokens)
      const curatorTokensAfter = await grt.balanceOf(me.address)
      expect(curatorTokensAfter).eq(curatorTokensBefore.add(curatorTokens))
      const gnsBalanceAfter = await grt.balanceOf(gns.address)
      // gatewayFinalizeTransfer will mint the tokens that are sent to the curator,
      // so the GNS balance should be the same
      expect(gnsBalanceAfter).eq(gnsBalanceBefore)
    })

    it('if a subgraph was deprecated after transfer, it returns the tokens to the beneficiary', async function () {
      const l1GNSMockL2Alias = await helpers.getL2SignerFromL1(l1GNSMock.address)
      // Eth for gas:
      await helpers.setBalance(await l1GNSMockL2Alias.getAddress(), parseEther('1'))

      const { l1SubgraphId, curatedTokens, subgraphMetadata, versionMetadata }
        = await defaultL1SubgraphParams()
      await transferMockSubgraphFromL1(
        l1SubgraphId,
        curatedTokens,
        subgraphMetadata,
        versionMetadata,
      )
      const l2SubgraphId = await gns.getAliasedL2SubgraphID(l1SubgraphId)
      await gns.connect(me).deprecateSubgraph(l2SubgraphId)

      // SG was transferred, but is deprecated now!

      const callhookData = defaultAbiCoder.encode(
        ['uint8', 'uint256', 'address'],
        [toBN(1), l1SubgraphId, me.address],
      )
      const curatorTokensBefore = await grt.balanceOf(me.address)
      const gnsBalanceBefore = await grt.balanceOf(gns.address)
      const tx = gatewayFinalizeTransfer(l1GNSMock.address, gns.address, toGRT('1'), callhookData)
      await expect(tx)
        .emit(gns, 'CuratorBalanceReturnedToBeneficiary')
        .withArgs(l1SubgraphId, me.address, toGRT('1'))
      const curatorTokensAfter = await grt.balanceOf(me.address)
      expect(curatorTokensAfter).eq(curatorTokensBefore.add(toGRT('1')))
      const gnsBalanceAfter = await grt.balanceOf(gns.address)
      // gatewayFinalizeTransfer will mint the tokens that are sent to the curator,
      // so the GNS balance should be the same
      expect(gnsBalanceAfter).eq(gnsBalanceBefore)
    })
  })
  describe('onTokenTransfer with invalid codes', function () {
    it('reverts', async function () {
      // This should never really happen unless the Arbitrum bridge is compromised,
      // so we test it anyway to ensure it's a well-defined behavior.
      // code 2 does not exist:
      const callhookData = defaultAbiCoder.encode(
        ['uint8', 'uint256', 'address'],
        [toBN(2), toBN(1337), me.address],
      )
      const tx = gatewayFinalizeTransfer(l1GNSMock.address, gns.address, toGRT('1'), callhookData)
      await expect(tx).revertedWith('INVALID_CODE')
    })
  })
  describe('getAliasedL2SubgraphID', function () {
    it('returns the L2 subgraph ID that is the L1 subgraph ID with an offset', async function () {
      const l1SubgraphId = ethers.BigNumber.from(
        '68799548758199140224151701590582019137924969401915573086349306511960790045480',
      )
      const l2SubgraphId = await gns.getAliasedL2SubgraphID(l1SubgraphId)
      const offset = ethers.BigNumber.from(
        '0x1111000000000000000000000000000000000000000000000000000000001111',
      )
      const base = ethers.constants.MaxUint256.add(1)
      const expectedL2SubgraphId = l1SubgraphId.add(offset).mod(base)
      expect(l2SubgraphId).eq(expectedL2SubgraphId)
    })
    it('wraps around MAX_UINT256 in case of overflow', async function () {
      const l1SubgraphId = ethers.constants.MaxUint256
      const l2SubgraphId = await gns.getAliasedL2SubgraphID(l1SubgraphId)
      const offset = ethers.BigNumber.from(
        '0x1111000000000000000000000000000000000000000000000000000000001111',
      )
      const base = ethers.constants.MaxUint256.add(1)
      const expectedL2SubgraphId = l1SubgraphId.add(offset).mod(base)
      expect(l2SubgraphId).eq(expectedL2SubgraphId)
    })
  })
})
