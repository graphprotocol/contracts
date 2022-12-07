import { expect } from 'chai'
import { ethers, ContractTransaction, BigNumber } from 'ethers'
import { defaultAbiCoder, parseEther } from 'ethers/lib/utils'

import {
  getAccounts,
  randomHexBytes,
  Account,
  toGRT,
  getL2SignerFromL1,
  setAccountBalance,
  latestBlock,
  advanceBlocks,
} from '../lib/testHelpers'
import { L2FixtureContracts, NetworkFixture } from '../lib/fixtures'
import { toBN } from '../lib/testHelpers'

import { L2GNS } from '../../build/types/L2GNS'
import { L2GraphTokenGateway } from '../../build/types/L2GraphTokenGateway'
import {
  buildSubgraph,
  buildSubgraphID,
  DEFAULT_RESERVE_RATIO,
  publishNewSubgraph,
  PublishSubgraph,
} from '../lib/gnsUtils'
import { L2Curation } from '../../build/types/L2Curation'
import { GraphToken } from '../../build/types/GraphToken'

const { HashZero } = ethers.constants

interface L1SubgraphParams {
  l1SubgraphId: string
  curatedTokens: BigNumber
  subgraphMetadata: string
  versionMetadata: string
  nSignal: BigNumber
}

describe('L2GNS', () => {
  let me: Account
  let other: Account
  let governor: Account
  let mockRouter: Account
  let mockL1GRT: Account
  let mockL1Gateway: Account
  let mockL1GNS: Account
  let fixture: NetworkFixture

  let fixtureContracts: L2FixtureContracts
  let l2GraphTokenGateway: L2GraphTokenGateway
  let gns: L2GNS
  let curation: L2Curation
  let grt: GraphToken

  let newSubgraph0: PublishSubgraph

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

  const defaultL1SubgraphParams = async function (): Promise<L1SubgraphParams> {
    return {
      l1SubgraphId: await buildSubgraphID(me.address, toBN('1'), 1),
      curatedTokens: toGRT('1337'),
      subgraphMetadata: randomHexBytes(),
      versionMetadata: randomHexBytes(),
      nSignal: toGRT('45670'),
    }
  }
  const migrateMockSubgraphFromL1 = async function (
    l1SubgraphId: string,
    curatedTokens: BigNumber,
    subgraphMetadata: string,
    versionMetadata: string,
    nSignal: BigNumber,
  ) {
    const callhookData = defaultAbiCoder.encode(
      ['uint256', 'address', 'uint256'],
      [l1SubgraphId, me.address, nSignal],
    )
    await gatewayFinalizeTransfer(mockL1GNS.address, gns.address, curatedTokens, callhookData)

    await gns
      .connect(me.signer)
      .finishSubgraphMigrationFromL1(
        l1SubgraphId,
        newSubgraph0.subgraphDeploymentID,
        subgraphMetadata,
        versionMetadata,
      )
  }

  before(async function () {
    newSubgraph0 = buildSubgraph()
    ;[me, other, governor, mockRouter, mockL1GRT, mockL1Gateway, mockL1GNS] = await getAccounts()

    fixture = new NetworkFixture()
    fixtureContracts = await fixture.loadL2(governor.signer)
    ;({ l2GraphTokenGateway, gns, curation, grt } = fixtureContracts)

    await grt.connect(governor.signer).mint(me.address, toGRT('10000'))
    await fixture.configureL2Bridge(
      governor.signer,
      fixtureContracts,
      mockRouter.address,
      mockL1GRT.address,
      mockL1Gateway.address,
      mockL1GNS.address,
    )
  })

  beforeEach(async function () {
    await fixture.setUp()
  })

  afterEach(async function () {
    await fixture.tearDown()
  })

  describe('receiving a subgraph from L1 (onTokenTransfer)', function () {
    it('cannot be called by someone other than the L2GraphTokenGateway', async function () {
      const { l1SubgraphId, curatedTokens, nSignal } = await defaultL1SubgraphParams()
      const callhookData = defaultAbiCoder.encode(
        ['uint256', 'address', 'uint256'],
        [l1SubgraphId, me.address, nSignal],
      )
      const tx = gns
        .connect(me.signer)
        .onTokenTransfer(mockL1GNS.address, curatedTokens, callhookData)
      await expect(tx).revertedWith('ONLY_GATEWAY')
    })
    it('rejects calls if the L1 sender is not the L1GNS', async function () {
      const { l1SubgraphId, curatedTokens, nSignal } = await defaultL1SubgraphParams()
      const callhookData = defaultAbiCoder.encode(
        ['uint256', 'address', 'uint256'],
        [l1SubgraphId, me.address, nSignal],
      )
      const tx = gatewayFinalizeTransfer(me.address, gns.address, curatedTokens, callhookData)

      await expect(tx).revertedWith('ONLY_L1_GNS_THROUGH_BRIDGE')
    })
    it('creates a subgraph in a disabled state', async function () {
      const l1SubgraphId = await buildSubgraphID(me.address, toBN('1'), 1)
      const curatedTokens = toGRT('1337')
      const nSignal = toBN('4567')
      const callhookData = defaultAbiCoder.encode(
        ['uint256', 'address', 'uint256'],
        [l1SubgraphId, me.address, nSignal],
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

      const migrationData = await gns.subgraphL2MigrationData(l1SubgraphId)
      const subgraphData = await gns.subgraphs(l1SubgraphId)

      expect(migrationData.tokens).eq(curatedTokens)
      expect(migrationData.l1Done).eq(false)
      expect(migrationData.l2Done).eq(false)
      expect(migrationData.subgraphReceivedOnL2BlockNumber).eq(await latestBlock())

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
      const nSignal = toBN('4567')
      const callhookData = defaultAbiCoder.encode(
        ['uint256', 'address', 'uint256'],
        [l1SubgraphId, me.address, nSignal],
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

      const migrationData = await gns.subgraphL2MigrationData(l1SubgraphId)
      const subgraphData = await gns.subgraphs(l1SubgraphId)

      expect(migrationData.tokens).eq(curatedTokens)
      expect(migrationData.l1Done).eq(false)
      expect(migrationData.l2Done).eq(false)
      expect(migrationData.subgraphReceivedOnL2BlockNumber).eq(await latestBlock())

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
    it('publishes the migrated subgraph and mints signal with no tax', async function () {
      const { l1SubgraphId, curatedTokens, subgraphMetadata, versionMetadata, nSignal } =
        await defaultL1SubgraphParams()
      const callhookData = defaultAbiCoder.encode(
        ['uint256', 'address', 'uint256'],
        [l1SubgraphId, me.address, nSignal],
      )
      await gatewayFinalizeTransfer(mockL1GNS.address, gns.address, curatedTokens, callhookData)
      // Calculate expected signal before minting
      const expectedSignal = await curation.tokensToSignalNoTax(
        newSubgraph0.subgraphDeploymentID,
        curatedTokens,
      )

      const tx = gns
        .connect(me.signer)
        .finishSubgraphMigrationFromL1(
          l1SubgraphId,
          newSubgraph0.subgraphDeploymentID,
          subgraphMetadata,
          versionMetadata,
        )
      await expect(tx)
        .emit(gns, 'SubgraphPublished')
        .withArgs(l1SubgraphId, newSubgraph0.subgraphDeploymentID, DEFAULT_RESERVE_RATIO)
      await expect(tx).emit(gns, 'SubgraphMetadataUpdated').withArgs(l1SubgraphId, subgraphMetadata)
      await expect(tx)
        .emit(gns, 'SubgraphUpgraded')
        .withArgs(l1SubgraphId, expectedSignal, curatedTokens, newSubgraph0.subgraphDeploymentID)
      await expect(tx)
        .emit(gns, 'SubgraphVersionUpdated')
        .withArgs(l1SubgraphId, newSubgraph0.subgraphDeploymentID, versionMetadata)
      await expect(tx).emit(gns, 'SubgraphMigrationFinalized').withArgs(l1SubgraphId)

      const subgraphAfter = await gns.subgraphs(l1SubgraphId)
      const migrationDataAfter = await gns.subgraphL2MigrationData(l1SubgraphId)
      expect(subgraphAfter.vSignal).eq(expectedSignal)
      expect(migrationDataAfter.l2Done).eq(true)
      expect(subgraphAfter.disabled).eq(false)
      expect(subgraphAfter.subgraphDeploymentID).eq(newSubgraph0.subgraphDeploymentID)
    })
    it('cannot be called by someone other than the subgraph owner', async function () {
      const { l1SubgraphId, curatedTokens, subgraphMetadata, versionMetadata, nSignal } =
        await defaultL1SubgraphParams()
      const callhookData = defaultAbiCoder.encode(
        ['uint256', 'address', 'uint256'],
        [l1SubgraphId, me.address, nSignal],
      )
      await gatewayFinalizeTransfer(mockL1GNS.address, gns.address, curatedTokens, callhookData)

      const tx = gns
        .connect(other.signer)
        .finishSubgraphMigrationFromL1(
          l1SubgraphId,
          newSubgraph0.subgraphDeploymentID,
          subgraphMetadata,
          versionMetadata,
        )
      await expect(tx).revertedWith('GNS: Must be authorized')
    })
    it('rejects calls for a subgraph that does not exist', async function () {
      const l1SubgraphId = await buildSubgraphID(me.address, toBN('1'), 1)
      const metadata = randomHexBytes()

      const tx = gns
        .connect(me.signer)
        .finishSubgraphMigrationFromL1(
          l1SubgraphId,
          newSubgraph0.subgraphDeploymentID,
          metadata,
          metadata,
        )
      await expect(tx).revertedWith('ERC721: owner query for nonexistent token')
    })
    it('rejects calls for a subgraph that was not migrated', async function () {
      const l2Subgraph = await publishNewSubgraph(me, newSubgraph0, gns)
      const metadata = randomHexBytes()

      const tx = gns
        .connect(me.signer)
        .finishSubgraphMigrationFromL1(
          l2Subgraph.id,
          newSubgraph0.subgraphDeploymentID,
          metadata,
          metadata,
        )
      await expect(tx).revertedWith('INVALID_SUBGRAPH')
    })
    it('accepts calls to a pre-curated subgraph deployment', async function () {
      const { l1SubgraphId, curatedTokens, subgraphMetadata, versionMetadata, nSignal } =
        await defaultL1SubgraphParams()
      const callhookData = defaultAbiCoder.encode(
        ['uint256', 'address', 'uint256'],
        [l1SubgraphId, me.address, nSignal],
      )
      await gatewayFinalizeTransfer(mockL1GNS.address, gns.address, curatedTokens, callhookData)

      // Calculate expected signal before minting
      const expectedSignal = await curation.tokensToSignalNoTax(
        newSubgraph0.subgraphDeploymentID,
        curatedTokens,
      )
      await grt.connect(me.signer).approve(curation.address, toGRT('100'))
      await curation
        .connect(me.signer)
        .mint(newSubgraph0.subgraphDeploymentID, toGRT('100'), toBN('0'))

      expect(await curation.getCurationPoolTokens(newSubgraph0.subgraphDeploymentID)).eq(
        toGRT('100'),
      )
      const tx = gns
        .connect(me.signer)
        .finishSubgraphMigrationFromL1(
          l1SubgraphId,
          newSubgraph0.subgraphDeploymentID,
          subgraphMetadata,
          versionMetadata,
        )
      await expect(tx)
        .emit(gns, 'SubgraphPublished')
        .withArgs(l1SubgraphId, newSubgraph0.subgraphDeploymentID, DEFAULT_RESERVE_RATIO)
      await expect(tx).emit(gns, 'SubgraphMetadataUpdated').withArgs(l1SubgraphId, subgraphMetadata)
      await expect(tx)
        .emit(gns, 'SubgraphUpgraded')
        .withArgs(l1SubgraphId, expectedSignal, curatedTokens, newSubgraph0.subgraphDeploymentID)
      await expect(tx)
        .emit(gns, 'SubgraphVersionUpdated')
        .withArgs(l1SubgraphId, newSubgraph0.subgraphDeploymentID, versionMetadata)
      await expect(tx).emit(gns, 'SubgraphMigrationFinalized').withArgs(l1SubgraphId)

      const subgraphAfter = await gns.subgraphs(l1SubgraphId)
      const migrationDataAfter = await gns.subgraphL2MigrationData(l1SubgraphId)
      expect(subgraphAfter.vSignal).eq(expectedSignal)
      expect(migrationDataAfter.l2Done).eq(true)
      expect(subgraphAfter.disabled).eq(false)
      expect(subgraphAfter.subgraphDeploymentID).eq(newSubgraph0.subgraphDeploymentID)
      expect(await curation.getCurationPoolTokens(newSubgraph0.subgraphDeploymentID)).eq(
        toGRT('100').add(curatedTokens),
      )
    })
    it('rejects calls if the subgraph deployment ID is zero', async function () {
      const l1SubgraphId = await buildSubgraphID(me.address, toBN('1'), 1)
      const curatedTokens = toGRT('1337')
      const metadata = randomHexBytes()
      const nSignal = toBN('4567')
      const callhookData = defaultAbiCoder.encode(
        ['uint256', 'address', 'uint256'],
        [l1SubgraphId, me.address, nSignal],
      )
      await gatewayFinalizeTransfer(mockL1GNS.address, gns.address, curatedTokens, callhookData)

      const tx = gns
        .connect(me.signer)
        .finishSubgraphMigrationFromL1(l1SubgraphId, HashZero, metadata, metadata)
      await expect(tx).revertedWith('GNS: deploymentID != 0')
    })
  })
  describe('deprecating a subgraph with an unfinished migration from L1', function () {
    it('deprecates the subgraph and sets the withdrawableGRT', async function () {
      const { l1SubgraphId, curatedTokens, nSignal } = await defaultL1SubgraphParams()
      const callhookData = defaultAbiCoder.encode(
        ['uint256', 'address', 'uint256'],
        [l1SubgraphId, me.address, nSignal],
      )
      await gatewayFinalizeTransfer(mockL1GNS.address, gns.address, curatedTokens, callhookData)

      await advanceBlocks(50400)

      const tx = gns
        .connect(other.signer) // Can be called by anyone
        .deprecateSubgraphMigratedFromL1(l1SubgraphId)
      await expect(tx).emit(gns, 'SubgraphDeprecated').withArgs(l1SubgraphId, curatedTokens)

      const subgraphAfter = await gns.subgraphs(l1SubgraphId)
      const migrationDataAfter = await gns.subgraphL2MigrationData(l1SubgraphId)
      expect(subgraphAfter.vSignal).eq(0)
      expect(migrationDataAfter.l2Done).eq(true)
      expect(subgraphAfter.disabled).eq(true)
      expect(subgraphAfter.subgraphDeploymentID).eq(HashZero)
      expect(subgraphAfter.withdrawableGRT).eq(curatedTokens)

      // Check that the curator can withdraw the GRT
      const mockL1GNSL2Alias = await getL2SignerFromL1(mockL1GNS.address)
      await setAccountBalance(await mockL1GNSL2Alias.getAddress(), parseEther('1'))
      // Note the signal is assigned to other.address as beneficiary
      await gns
        .connect(mockL1GNSL2Alias)
        .claimL1CuratorBalanceToBeneficiary(l1SubgraphId, me.address, toGRT('10'), other.address)
      const curatorBalanceBefore = await grt.balanceOf(other.address)
      const expectedTokensOut = curatedTokens.mul(toGRT('10')).div(nSignal)
      const withdrawTx = await gns.connect(other.signer).withdraw(l1SubgraphId)
      await expect(withdrawTx)
        .emit(gns, 'GRTWithdrawn')
        .withArgs(l1SubgraphId, other.address, toGRT('10'), expectedTokensOut)
      const curatorBalanceAfter = await grt.balanceOf(other.address)
      expect(curatorBalanceAfter.sub(curatorBalanceBefore)).eq(expectedTokensOut)
    })
    it('rejects calls if not enough time has passed', async function () {
      const { l1SubgraphId, curatedTokens, nSignal } = await defaultL1SubgraphParams()
      const callhookData = defaultAbiCoder.encode(
        ['uint256', 'address', 'uint256'],
        [l1SubgraphId, me.address, nSignal],
      )
      await gatewayFinalizeTransfer(mockL1GNS.address, gns.address, curatedTokens, callhookData)

      await advanceBlocks(50399)

      const tx = gns
        .connect(other.signer) // Can be called by anyone
        .deprecateSubgraphMigratedFromL1(l1SubgraphId)
      await expect(tx).revertedWith('TOO_EARLY')
    })
    it('rejects calls if the subgraph migration was finished', async function () {
      const { l1SubgraphId, curatedTokens, subgraphMetadata, versionMetadata, nSignal } =
        await defaultL1SubgraphParams()
      const callhookData = defaultAbiCoder.encode(
        ['uint256', 'address', 'uint256'],
        [l1SubgraphId, me.address, nSignal],
      )
      await gatewayFinalizeTransfer(mockL1GNS.address, gns.address, curatedTokens, callhookData)

      await advanceBlocks(50400)

      await gns
        .connect(me.signer)
        .finishSubgraphMigrationFromL1(
          l1SubgraphId,
          newSubgraph0.subgraphDeploymentID,
          subgraphMetadata,
          versionMetadata,
        )

      const tx = gns
        .connect(other.signer) // Can be called by anyone
        .deprecateSubgraphMigratedFromL1(l1SubgraphId)
      await expect(tx).revertedWith('ALREADY_FINISHED')
    })
    it('rejects calls for a subgraph that does not exist', async function () {
      const l1SubgraphId = await buildSubgraphID(me.address, toBN('1'), 1)

      const tx = gns.connect(me.signer).deprecateSubgraphMigratedFromL1(l1SubgraphId)
      await expect(tx).revertedWith('INVALID_SUBGRAPH')
    })
    it('rejects calls for a subgraph that was not migrated', async function () {
      const l2Subgraph = await publishNewSubgraph(me, newSubgraph0, gns)

      const tx = gns.connect(me.signer).deprecateSubgraphMigratedFromL1(l2Subgraph.id)
      await expect(tx).revertedWith('INVALID_SUBGRAPH')
    })
  })
  describe('claiming a curator balance with a message from L1', function () {
    it('assigns a curator balance to a beneficiary', async function () {
      const mockL1GNSL2Alias = await getL2SignerFromL1(mockL1GNS.address)
      // Eth for gas:
      await setAccountBalance(await mockL1GNSL2Alias.getAddress(), parseEther('1'))

      const { l1SubgraphId, curatedTokens, subgraphMetadata, versionMetadata, nSignal } =
        await defaultL1SubgraphParams()
      await migrateMockSubgraphFromL1(
        l1SubgraphId,
        curatedTokens,
        subgraphMetadata,
        versionMetadata,
        nSignal,
      )

      const tx = gns
        .connect(mockL1GNSL2Alias)
        .claimL1CuratorBalanceToBeneficiary(l1SubgraphId, me.address, toGRT('10'), other.address)
      await expect(tx)
        .emit(gns, 'CuratorBalanceClaimed')
        .withArgs(l1SubgraphId, me.address, other.address, toGRT('10'))
      const l1CuratorBalance = await gns.getCuratorSignal(l1SubgraphId, me.address)
      const l2CuratorBalance = await gns.getCuratorSignal(l1SubgraphId, other.address)
      expect(l1CuratorBalance).eq(0)
      expect(l2CuratorBalance).eq(toGRT('10'))
    })
    it('adds the balance to any existing balance for the beneficiary', async function () {
      const mockL1GNSL2Alias = await getL2SignerFromL1(mockL1GNS.address)
      // Eth for gas:
      await setAccountBalance(await mockL1GNSL2Alias.getAddress(), parseEther('1'))

      const { l1SubgraphId, curatedTokens, subgraphMetadata, versionMetadata, nSignal } =
        await defaultL1SubgraphParams()
      await migrateMockSubgraphFromL1(
        l1SubgraphId,
        curatedTokens,
        subgraphMetadata,
        versionMetadata,
        nSignal,
      )

      await grt.connect(governor.signer).mint(other.address, toGRT('10'))
      await grt.connect(other.signer).approve(gns.address, toGRT('10'))
      await gns.connect(other.signer).mintSignal(l1SubgraphId, toGRT('10'), toBN(0))
      const prevSignal = await gns.getCuratorSignal(l1SubgraphId, other.address)

      const tx = gns
        .connect(mockL1GNSL2Alias)
        .claimL1CuratorBalanceToBeneficiary(l1SubgraphId, me.address, toGRT('10'), other.address)
      await expect(tx)
        .emit(gns, 'CuratorBalanceClaimed')
        .withArgs(l1SubgraphId, me.address, other.address, toGRT('10'))
      const l1CuratorBalance = await gns.getCuratorSignal(l1SubgraphId, me.address)
      const l2CuratorBalance = await gns.getCuratorSignal(l1SubgraphId, other.address)
      expect(l1CuratorBalance).eq(0)
      expect(l2CuratorBalance).eq(prevSignal.add(toGRT('10')))
    })
    it('can only be called from the counterpart GNS L2 alias', async function () {
      const { l1SubgraphId, curatedTokens, subgraphMetadata, versionMetadata, nSignal } =
        await defaultL1SubgraphParams()
      await migrateMockSubgraphFromL1(
        l1SubgraphId,
        curatedTokens,
        subgraphMetadata,
        versionMetadata,
        nSignal,
      )

      const tx = gns
        .connect(governor.signer)
        .claimL1CuratorBalanceToBeneficiary(l1SubgraphId, me.address, toGRT('10'), other.address)
      await expect(tx).revertedWith('ONLY_COUNTERPART_GNS')

      const tx2 = gns
        .connect(me.signer)
        .claimL1CuratorBalanceToBeneficiary(l1SubgraphId, me.address, toGRT('10'), other.address)
      await expect(tx2).revertedWith('ONLY_COUNTERPART_GNS')

      const tx3 = gns
        .connect(mockL1GNS.signer)
        .claimL1CuratorBalanceToBeneficiary(l1SubgraphId, me.address, toGRT('10'), other.address)
      await expect(tx3).revertedWith('ONLY_COUNTERPART_GNS')
    })
    it('rejects calls for a subgraph that does not exist', async function () {
      const mockL1GNSL2Alias = await getL2SignerFromL1(mockL1GNS.address)
      // Eth for gas:
      await setAccountBalance(await mockL1GNSL2Alias.getAddress(), parseEther('1'))

      const { l1SubgraphId } = await defaultL1SubgraphParams()

      const tx = gns
        .connect(mockL1GNSL2Alias)
        .claimL1CuratorBalanceToBeneficiary(l1SubgraphId, me.address, toGRT('10'), other.address)
      await expect(tx).revertedWith('!MIGRATED')
    })
    it('rejects calls for an L2-native subgraph', async function () {
      const mockL1GNSL2Alias = await getL2SignerFromL1(mockL1GNS.address)
      // Eth for gas:
      await setAccountBalance(await mockL1GNSL2Alias.getAddress(), parseEther('1'))

      const l2Subgraph = await publishNewSubgraph(me, newSubgraph0, gns)

      const tx = gns
        .connect(mockL1GNSL2Alias)
        .claimL1CuratorBalanceToBeneficiary(l2Subgraph.id!, me.address, toGRT('10'), other.address)
      await expect(tx).revertedWith('!MIGRATED')
    })
    it('rejects calls if the balance was already claimed', async function () {
      const mockL1GNSL2Alias = await getL2SignerFromL1(mockL1GNS.address)
      // Eth for gas:
      await setAccountBalance(await mockL1GNSL2Alias.getAddress(), parseEther('1'))

      const { l1SubgraphId, curatedTokens, subgraphMetadata, versionMetadata, nSignal } =
        await defaultL1SubgraphParams()
      await migrateMockSubgraphFromL1(
        l1SubgraphId,
        curatedTokens,
        subgraphMetadata,
        versionMetadata,
        nSignal,
      )

      const tx = gns
        .connect(mockL1GNSL2Alias)
        .claimL1CuratorBalanceToBeneficiary(l1SubgraphId, me.address, toGRT('10'), other.address)
      await expect(tx)
        .emit(gns, 'CuratorBalanceClaimed')
        .withArgs(l1SubgraphId, me.address, other.address, toGRT('10'))
      const l1CuratorBalance = await gns.getCuratorSignal(l1SubgraphId, me.address)
      const l2CuratorBalance = await gns.getCuratorSignal(l1SubgraphId, other.address)
      expect(l1CuratorBalance).eq(0)
      expect(l2CuratorBalance).eq(toGRT('10'))

      // Now trying again should revert
      const tx2 = gns
        .connect(mockL1GNSL2Alias)
        .claimL1CuratorBalanceToBeneficiary(l1SubgraphId, me.address, toGRT('10'), other.address)
      await expect(tx2).revertedWith('ALREADY_CLAIMED')
    })
  })
})
