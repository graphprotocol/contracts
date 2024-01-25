import hre from 'hardhat'
import { expect } from 'chai'
import { ethers, ContractTransaction, BigNumber, Event } from 'ethers'
import { defaultAbiCoder } from 'ethers/lib/utils'
import { SubgraphDeploymentID, formatGRT } from '@graphprotocol/common-ts'

import { LegacyGNSMock } from '../../build/types/LegacyGNSMock'
import { GraphToken } from '../../build/types/GraphToken'
import { Curation } from '../../build/types/Curation'

import { NetworkFixture } from './lib/fixtures'
import { Controller } from '../../build/types/Controller'
import { L1GNS } from '../../build/types/L1GNS'
import { L1GraphTokenGateway } from '../../build/types/L1GraphTokenGateway'
import {
  AccountDefaultName,
  createDefaultName,
  publishNewSubgraph,
  publishNewVersion,
  mintSignal,
  deprecateSubgraph,
  burnSignal,
} from './lib/gnsUtils'
import {
  PublishSubgraph,
  Subgraph,
  buildLegacySubgraphId,
  buildSubgraph,
  buildSubgraphId,
  randomHexBytes,
  helpers,
  toGRT,
  toBN,
  deploy,
  DeployType,
  loadContractAt,
  GraphNetworkContracts,
} from '@graphprotocol/sdk'
import { SignerWithAddress } from '@nomiclabs/hardhat-ethers/signers'
import { L2GNS, L2GraphTokenGateway, SubgraphNFT } from '../../build/types'

const { AddressZero, HashZero } = ethers.constants

// Utils
const toFloat = (n: BigNumber) => parseFloat(formatGRT(n))
const toRound = (n: number) => n.toFixed(12)

describe('L1GNS', () => {
  const graph = hre.graph({ addressBook: 'addresses-local.json' })

  let me: SignerWithAddress
  let other: SignerWithAddress
  let another: SignerWithAddress
  let governor: SignerWithAddress

  let fixture: NetworkFixture
  let l2MockContracts: GraphNetworkContracts

  let l2GNSMock: L2GNS
  let l2GRTGatewayMock: L2GraphTokenGateway

  let gns: L1GNS
  let legacyGNSMock: LegacyGNSMock
  let grt: GraphToken
  let curation: Curation
  let controller: Controller
  let subgraphNFT: SubgraphNFT
  let l1GraphTokenGateway: L1GraphTokenGateway

  const tokens1000 = toGRT('1000')
  const tokens10000 = toGRT('10000')
  const tokens100000 = toGRT('100000')
  const curationTaxPercentage = 50000

  let newSubgraph0: PublishSubgraph
  let newSubgraph1: PublishSubgraph
  let defaultName: AccountDefaultName

  async function calcGNSBondingCurve(
    gnsSupply: BigNumber, // nSignal
    gnsReserveBalance: BigNumber, // vSignal
    depositAmount: BigNumber, // GRT deposited
    subgraphID: string,
  ): Promise<number> {
    const signal = await curation.getCurationPoolSignal(subgraphID)
    const curationTokens = await curation.getCurationPoolTokens(subgraphID)
    const curationReserveRatio = await curation.defaultReserveRatio()
    const expectedSignal = await calcCurationBondingCurve(
      signal,
      curationTokens,
      curationReserveRatio,
      depositAmount,
    )
    const expectedSignalBN = toGRT(String(expectedSignal.toFixed(18)))

    // Handle the initialization of the bonding curve
    if (gnsSupply.eq(0)) {
      return expectedSignal
    }
    // Since we known CW = 1, we can do the simplified formula of:
    return (toFloat(gnsSupply) * toFloat(expectedSignalBN)) / toFloat(gnsReserveBalance)
  }

  async function calcCurationBondingCurve(
    supply: BigNumber,
    reserveBalance: BigNumber,
    reserveRatio: number,
    depositAmount: BigNumber,
  ): Promise<number> {
    // Handle the initialization of the bonding curve
    const minSupply = toGRT('1')
    if (supply.eq(0)) {
      const minDeposit = await curation.minimumCurationDeposit()
      if (depositAmount.lt(minDeposit)) {
        throw new Error('deposit must be above minimum')
      }
      return (
        (await calcCurationBondingCurve(
          minSupply,
          minDeposit,
          reserveRatio,
          depositAmount.sub(minDeposit),
        )) + toFloat(minSupply)
      )
    }
    // Calculate bonding curve in the test
    return (
      toFloat(supply) *
      ((1 + toFloat(depositAmount) / toFloat(reserveBalance)) ** (reserveRatio / 1000000) - 1)
    )
  }

  const transferSignal = async (
    subgraphID: string,
    owner: SignerWithAddress,
    recipient: SignerWithAddress,
    amount: BigNumber,
  ): Promise<ContractTransaction> => {
    // Before state
    const beforeOwnerNSignal = await gns.getCuratorSignal(subgraphID, owner.address)
    const beforeRecipientNSignal = await gns.getCuratorSignal(subgraphID, recipient.address)

    // Transfer
    const tx = gns.connect(owner).transferSignal(subgraphID, recipient.address, amount)

    await expect(tx)
      .emit(gns, 'SignalTransferred')
      .withArgs(subgraphID, owner.address, recipient.address, amount)

    // After state
    const afterOwnerNSignal = await gns.getCuratorSignal(subgraphID, owner.address)
    const afterRecipientNSignal = await gns.getCuratorSignal(subgraphID, recipient.address)

    // Check state
    expect(afterOwnerNSignal).eq(beforeOwnerNSignal.sub(amount))
    expect(afterRecipientNSignal).eq(beforeRecipientNSignal.add(amount))

    return tx
  }

  const withdraw = async (
    account: SignerWithAddress,
    subgraphID: string,
  ): Promise<ContractTransaction> => {
    // Before state
    const beforeCuratorNSignal = await gns.getCuratorSignal(subgraphID, account.address)
    const beforeSubgraph = await gns.subgraphs(subgraphID)
    const beforeGNSBalance = await grt.balanceOf(gns.address)
    const tokensEstimate = beforeSubgraph.withdrawableGRT
      .mul(beforeCuratorNSignal)
      .div(beforeSubgraph.nSignal)

    // Send tx
    const tx = gns.connect(account).withdraw(subgraphID)
    await expect(tx)
      .emit(gns, 'GRTWithdrawn')
      .withArgs(subgraphID, account.address, beforeCuratorNSignal, tokensEstimate)

    // curator nSignal should be updated
    const afterCuratorNSignal = await gns.getCuratorSignal(subgraphID, account.address)
    expect(afterCuratorNSignal).eq(toBN(0))

    // overall n signal should be updated
    const afterSubgraph = await gns.subgraphs(subgraphID)
    expect(afterSubgraph.nSignal).eq(beforeSubgraph.nSignal.sub(beforeCuratorNSignal))

    // Token balance should be updated
    const afterGNSBalance = await grt.balanceOf(gns.address)
    expect(afterGNSBalance).eq(beforeGNSBalance.sub(tokensEstimate))

    return tx
  }

  const deployLegacyGNSMock = async (): Promise<any> => {
    const { contract: subgraphDescriptor } = await deploy(DeployType.Deploy, governor, {
      name: 'SubgraphNFTDescriptor',
    })
    const { contract: subgraphNFT } = await deploy(DeployType.Deploy, governor, {
      name: 'SubgraphNFT',
      args: [governor.address],
    })

    // Deploy
    const deployResult = await deploy(
      DeployType.DeployWithProxy,
      governor,
      { name: 'LegacyGNSMock', args: [controller.address, subgraphNFT.address] },
      graph.addressBook,
      {
        name: 'GraphProxy',
      },
    )
    legacyGNSMock = deployResult.contract as LegacyGNSMock

    // Post-config
    await subgraphNFT.connect(governor).setMinter(legacyGNSMock.address)
    await subgraphNFT.connect(governor).setTokenDescriptor(subgraphDescriptor.address)
    await legacyGNSMock.connect(governor).syncAllContracts()
    await legacyGNSMock.connect(governor).approveAll()
    await l1GraphTokenGateway.connect(governor).addToCallhookAllowlist(legacyGNSMock.address)
    await legacyGNSMock.connect(governor).setCounterpartGNSAddress(l2GNSMock.address)
  }

  before(async function () {
    ;[me, other, governor, another] = await graph.getTestAccounts()

    fixture = new NetworkFixture(graph.provider)

    // Deploy L1
    const fixtureContracts = await fixture.load(governor)
    grt = fixtureContracts.GraphToken as GraphToken
    curation = fixtureContracts.Curation as Curation
    gns = fixtureContracts.GNS as L1GNS
    controller = fixtureContracts.Controller as Controller
    l1GraphTokenGateway = fixtureContracts.L1GraphTokenGateway as L1GraphTokenGateway
    subgraphNFT = fixtureContracts.SubgraphNFT as SubgraphNFT

    // Deploy L1 arbitrum bridge
    await fixture.loadL1ArbitrumBridge(governor)

    // Deploy L2 mock
    l2MockContracts = await fixture.loadMock(true)
    l2GNSMock = l2MockContracts.L2GNS as L2GNS
    l2GRTGatewayMock = l2MockContracts.L2GraphTokenGateway as L2GraphTokenGateway

    // Configure graph bridge
    await fixture.configureL1Bridge(governor, fixtureContracts, l2MockContracts)

    newSubgraph0 = buildSubgraph()
    newSubgraph1 = buildSubgraph()
    defaultName = createDefaultName('graph')
    // Give some funds to the signers and approve gns contract to use funds on signers behalf
    await grt.connect(governor).mint(me.address, tokens100000)
    await grt.connect(governor).mint(other.address, tokens100000)
    await grt.connect(governor).mint(another.address, tokens100000)
    await grt.connect(me).approve(gns.address, tokens100000)
    await grt.connect(me).approve(curation.address, tokens100000)
    await grt.connect(other).approve(gns.address, tokens100000)
    await grt.connect(other).approve(curation.address, tokens100000)
    await grt.connect(another).approve(gns.address, tokens100000)
    await grt.connect(another).approve(curation.address, tokens100000)
    // Update curation tax to test the functionality of it in disableNameSignal()
    await curation.connect(governor).setCurationTaxPercentage(curationTaxPercentage)

    // Deploying a GNS mock with support for legacy subgraphs
    await deployLegacyGNSMock()
    await grt.connect(me).approve(legacyGNSMock.address, tokens100000)
  })

  beforeEach(async function () {
    await fixture.setUp()
  })

  afterEach(async function () {
    await fixture.tearDown()
  })

  describe('Configuration', async function () {
    describe('setOwnerTaxPercentage', function () {
      const newValue = 10

      it('should set `ownerTaxPercentage`', async function () {
        // Can set if allowed
        await gns.connect(governor).setOwnerTaxPercentage(newValue)
        expect(await gns.ownerTaxPercentage()).eq(newValue)
      })

      it('reject set `ownerTaxPercentage` if out of bounds', async function () {
        const tx = gns.connect(governor).setOwnerTaxPercentage(1000001)
        await expect(tx).revertedWith('Owner tax must be MAX_PPM or less')
      })

      it('reject set `ownerTaxPercentage` if not allowed', async function () {
        const tx = gns.connect(me).setOwnerTaxPercentage(newValue)
        await expect(tx).revertedWith('Only Controller governor')
      })
    })

    describe('setCounterpartGNSAddress', function () {
      it('should set `counterpartGNSAddress`', async function () {
        // Can set if allowed
        const newValue = other.address
        const tx = gns.connect(governor).setCounterpartGNSAddress(newValue)
        await expect(tx).emit(gns, 'CounterpartGNSAddressUpdated').withArgs(newValue)
        expect(await gns.counterpartGNSAddress()).eq(newValue)
      })

      it('reject set `counterpartGNSAddress` if not allowed', async function () {
        const newValue = other.address
        const tx = gns.connect(me).setCounterpartGNSAddress(newValue)
        await expect(tx).revertedWith('Only Controller governor')
      })
    })

    describe('setSubgraphNFT', function () {
      it('should set `setSubgraphNFT`', async function () {
        const newValue = gns.address // I just use any contract address
        const tx = gns.connect(governor).setSubgraphNFT(newValue)
        await expect(tx).emit(gns, 'SubgraphNFTUpdated').withArgs(newValue)
        expect(await gns.subgraphNFT()).eq(newValue)
      })

      it('revert set to empty address', async function () {
        const tx = gns.connect(governor).setSubgraphNFT(AddressZero)
        await expect(tx).revertedWith('NFT address cant be zero')
      })

      it('revert set to non-contract', async function () {
        const tx = gns.connect(governor).setSubgraphNFT(randomHexBytes(20))
        await expect(tx).revertedWith('NFT must be valid')
      })
    })
  })

  describe('Publishing names and versions', function () {
    describe('setDefaultName', function () {
      it('setDefaultName emits the event', async function () {
        const tx = gns
          .connect(me)
          .setDefaultName(me.address, 0, defaultName.nameIdentifier, defaultName.name)
        await expect(tx)
          .emit(gns, 'SetDefaultName')
          .withArgs(me.address, 0, defaultName.nameIdentifier, defaultName.name)
      })

      it('setDefaultName fails if not owner', async function () {
        const tx = gns
          .connect(other)
          .setDefaultName(me.address, 0, defaultName.nameIdentifier, defaultName.name)
        await expect(tx).revertedWith('GNS: Only you can set your name')
      })
    })

    describe('updateSubgraphMetadata', function () {
      let subgraph: Subgraph

      beforeEach(async function () {
        subgraph = await publishNewSubgraph(me, newSubgraph0, gns, graph.chainId)
      })

      it('updateSubgraphMetadata emits the event', async function () {
        const tx = gns
          .connect(me)
          .updateSubgraphMetadata(subgraph.id, newSubgraph0.subgraphMetadata)
        await expect(tx)
          .emit(gns, 'SubgraphMetadataUpdated')
          .withArgs(subgraph.id, newSubgraph0.subgraphMetadata)
      })

      it('updateSubgraphMetadata fails if not owner', async function () {
        const tx = gns
          .connect(other)
          .updateSubgraphMetadata(subgraph.id, newSubgraph0.subgraphMetadata)
        await expect(tx).revertedWith('GNS: Must be authorized')
      })
    })

    describe('isPublished', function () {
      it('should return if the subgraph is published', async function () {
        const subgraphID = await buildSubgraphId(me.address, toBN(0), graph.chainId)
        expect(await gns.isPublished(subgraphID)).eq(false)
        await publishNewSubgraph(me, newSubgraph0, gns, graph.chainId)
        expect(await gns.isPublished(subgraphID)).eq(true)
      })
    })

    describe('publishNewSubgraph', async function () {
      it('should publish a new subgraph and first version with it', async function () {
        await publishNewSubgraph(me, newSubgraph0, gns, graph.chainId)
      })

      it('should publish a new subgraph with an incremented value', async function () {
        const subgraph1 = await publishNewSubgraph(me, newSubgraph0, gns, graph.chainId)
        const subgraph2 = await publishNewSubgraph(me, newSubgraph1, gns, graph.chainId)
        expect(subgraph1.id).not.eq(subgraph2.id)
      })

      it('should prevent subgraphDeploymentID of 0 to be used', async function () {
        const tx = gns
          .connect(me)
          .publishNewSubgraph(HashZero, newSubgraph0.versionMetadata, newSubgraph0.subgraphMetadata)
        await expect(tx).revertedWith('GNS: Cannot set deploymentID to 0 in publish')
      })
    })

    describe('publishNewVersion', async function () {
      let subgraph: Subgraph

      beforeEach(async () => {
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

      it('should publish a new version on an existing subgraph when curation tax percentage is zero', async function () {
        await curation.connect(governor).setCurationTaxPercentage(0)
        await publishNewVersion(me, subgraph.id, newSubgraph1, gns, curation)
      })

      it('should publish a new version on an existing subgraph with no current signal', async function () {
        const emptySignalSubgraph = await publishNewSubgraph(
          me,
          buildSubgraph(),
          gns,
          graph.chainId,
        )
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

      it('should fail when upgrade tries to point to a pre-curated', async function () {
        // Curate directly to the deployment
        await curation.connect(me).mint(newSubgraph1.subgraphDeploymentID, tokens1000, 0)

        // Target a pre-curated subgraph deployment
        const tx = gns
          .connect(me)
          .publishNewVersion(
            subgraph.id,
            newSubgraph1.subgraphDeploymentID,
            newSubgraph1.versionMetadata,
          )
        await expect(tx).revertedWith(
          'GNS: Owner cannot point to a subgraphID that has been pre-curated',
        )
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
    describe('subgraphTokens', function () {
      it('should return the correct number of tokens for a subgraph', async function () {
        const subgraph = await publishNewSubgraph(me, newSubgraph0, gns, graph.chainId)
        const taxForMe = (
          await curation.tokensToSignal(subgraph.subgraphDeploymentID, tokens10000)
        )[1]
        await mintSignal(me, subgraph.id, tokens10000, gns, curation)
        const taxForOther = (
          await curation.tokensToSignal(subgraph.subgraphDeploymentID, tokens1000)
        )[1]
        await mintSignal(other, subgraph.id, tokens1000, gns, curation)
        expect(await gns.subgraphTokens(subgraph.id)).eq(
          tokens10000.add(tokens1000).sub(taxForMe).sub(taxForOther),
        )
      })
    })
    describe('subgraphSignal', function () {
      it('should return the correct amount of signal for a subgraph', async function () {
        const subgraph = await publishNewSubgraph(me, newSubgraph0, gns, graph.chainId)
        const vSignalForMe = (
          await curation.tokensToSignal(subgraph.subgraphDeploymentID, tokens10000)
        )[0]
        await mintSignal(me, subgraph.id, tokens10000, gns, curation)
        const vSignalForOther = (
          await curation.tokensToSignal(subgraph.subgraphDeploymentID, tokens1000)
        )[0]
        await mintSignal(other, subgraph.id, tokens1000, gns, curation)
        const expectedSignal = await gns.vSignalToNSignal(
          subgraph.id,
          vSignalForMe.add(vSignalForOther),
        )
        expect(await gns.subgraphSignal(subgraph.id)).eq(expectedSignal)
      })
    })
    describe('deprecateSubgraph', async function () {
      let subgraph: Subgraph

      beforeEach(async () => {
        subgraph = await publishNewSubgraph(me, newSubgraph0, gns, graph.chainId)
        await mintSignal(me, subgraph.id, tokens10000, gns, curation)
      })

      it('should deprecate a subgraph', async function () {
        await deprecateSubgraph(me, subgraph.id, gns, curation, grt)
      })

      it('should prevent a deprecated subgraph from being republished', async function () {
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

      it('reject if the subgraph does not exist', async function () {
        const subgraphID = randomHexBytes(32)
        const tx = gns.connect(me).deprecateSubgraph(subgraphID)
        await expect(tx).revertedWith('ERC721: owner query for nonexistent token')
      })

      it('reject deprecate if not the owner', async function () {
        const tx = gns.connect(other).deprecateSubgraph(subgraph.id)
        await expect(tx).revertedWith('GNS: Must be authorized')
      })
    })
  })

  describe('Curating on names', async function () {
    describe('mintSignal()', async function () {
      it('should deposit into the name signal curve', async function () {
        const subgraph = await publishNewSubgraph(me, newSubgraph0, gns, graph.chainId)
        await mintSignal(other, subgraph.id, tokens10000, gns, curation)
      })

      it('should fail when name signal is disabled', async function () {
        const subgraph = await publishNewSubgraph(me, newSubgraph0, gns, graph.chainId)
        await deprecateSubgraph(me, subgraph.id, gns, curation, grt)
        const tx = gns.connect(me).mintSignal(subgraph.id, tokens1000, 0)
        await expect(tx).revertedWith('GNS: Must be active')
      })

      it('should fail if you try to deposit on a non existing name', async function () {
        const subgraphID = randomHexBytes(32)
        const tx = gns.connect(me).mintSignal(subgraphID, tokens1000, 0)
        await expect(tx).revertedWith('GNS: Must be active')
      })

      it('reject minting if under slippage', async function () {
        // First publish the subgraph
        const subgraph = await publishNewSubgraph(me, newSubgraph0, gns, graph.chainId)

        // Set slippage to be 1 less than expected result to force reverting
        const { 1: expectedNSignal } = await gns.tokensToNSignal(subgraph.id, tokens1000)
        const tx = gns.connect(me).mintSignal(subgraph.id, tokens1000, expectedNSignal.add(1))
        await expect(tx).revertedWith('Slippage protection')
      })
    })

    describe('burnSignal()', async function () {
      let subgraph: Subgraph

      beforeEach(async () => {
        subgraph = await publishNewSubgraph(me, newSubgraph0, gns, graph.chainId)
        await mintSignal(other, subgraph.id, tokens10000, gns, curation)
      })

      it('should withdraw from the name signal curve', async function () {
        await burnSignal(other, subgraph.id, gns, curation)
      })

      it('should fail when name signal is disabled', async function () {
        await deprecateSubgraph(me, subgraph.id, gns, curation, grt)
        // just test 1 since it will fail
        const tx = gns.connect(me).burnSignal(subgraph.id, 1, 0)
        await expect(tx).revertedWith('GNS: Must be active')
      })

      it('should fail when the curator tries to withdraw more nSignal than they have', async function () {
        const tx = gns.connect(me).burnSignal(
          subgraph.id,
          // 1000000 * 10^18 nSignal is a lot, and will cause fail
          toBN('1000000000000000000000000'),
          0,
        )
        await expect(tx).revertedWith('GNS: Curator cannot withdraw more nSignal than they have')
      })

      it('reject burning if under slippage', async function () {
        // Get current curator name signal
        const curatorNSignal = await gns.getCuratorSignal(subgraph.id, other.address)

        // Withdraw
        const { 1: expectedTokens } = await gns.nSignalToTokens(subgraph.id, curatorNSignal)

        // Force a revert by asking 1 more token than the function will return
        const tx = gns.connect(other).burnSignal(subgraph.id, curatorNSignal, expectedTokens.add(1))
        await expect(tx).revertedWith('Slippage protection')
      })
    })

    describe('transferSignal()', async function () {
      let subgraph: Subgraph
      let otherNSignal: BigNumber

      beforeEach(async () => {
        subgraph = await publishNewSubgraph(me, newSubgraph0, gns, graph.chainId)
        await mintSignal(other, subgraph.id, tokens10000, gns, curation)
        otherNSignal = await gns.getCuratorSignal(subgraph.id, other.address)
      })

      it('should transfer signal from one curator to another', async function () {
        await transferSignal(subgraph.id, other, another, otherNSignal)
      })
      it('should fail when transferring to zero address', async function () {
        const tx = gns
          .connect(other)
          .transferSignal(subgraph.id, ethers.constants.AddressZero, otherNSignal)
        await expect(tx).revertedWith('GNS: Curator cannot transfer to the zero address')
      })
      it('should fail when name signal is disabled', async function () {
        await deprecateSubgraph(me, subgraph.id, gns, curation, grt)
        const tx = gns.connect(other).transferSignal(subgraph.id, another.address, otherNSignal)
        await expect(tx).revertedWith('GNS: Must be active')
      })
      it('should fail if you try to transfer on a non existing name', async function () {
        const subgraphID = randomHexBytes(32)
        const tx = gns.connect(other).transferSignal(subgraphID, another.address, otherNSignal)
        await expect(tx).revertedWith('GNS: Must be active')
      })
      it('should fail when the curator tries to transfer more signal than they have', async function () {
        const tx = gns
          .connect(other)
          .transferSignal(subgraph.id, another.address, otherNSignal.add(otherNSignal))
        await expect(tx).revertedWith('GNS: Curator transfer amount exceeds balance')
      })
    })
    describe('withdraw()', async function () {
      let subgraph: Subgraph

      beforeEach(async () => {
        subgraph = await publishNewSubgraph(me, newSubgraph0, gns, graph.chainId)
        await mintSignal(other, subgraph.id, tokens10000, gns, curation)
      })

      it('should withdraw GRT from a disabled name signal', async function () {
        await deprecateSubgraph(me, subgraph.id, gns, curation, grt)
        await withdraw(other, subgraph.id)
      })

      it('should fail if not disabled', async function () {
        const tx = gns.connect(other).withdraw(subgraph.id)
        await expect(tx).revertedWith('GNS: Must be disabled first')
      })

      it('should fail when there is no more GRT to withdraw', async function () {
        await deprecateSubgraph(me, subgraph.id, gns, curation, grt)
        await withdraw(other, subgraph.id)
        const tx = gns.connect(other).withdraw(subgraph.id)
        await expect(tx).revertedWith('GNS: No more GRT to withdraw')
      })

      it('should fail if the curator has no nSignal', async function () {
        await deprecateSubgraph(me, subgraph.id, gns, curation, grt)
        const tx = gns.connect(me).withdraw(subgraph.id)
        await expect(tx).revertedWith('GNS: No signal to withdraw GRT')
      })
    })

    describe('multiple minting', async function () {
      it('should mint less signal every time due to the bonding curve', async function () {
        const tokensToDepositMany = [
          toGRT('1000'), // should mint if we start with number above minimum deposit
          toGRT('1000'), // every time it should mint less GCS due to bonding curve...
          toGRT('1.06'), // should mint minimum deposit including tax
          toGRT('1000'),
          toGRT('1000'),
          toGRT('2000'),
          toGRT('2000'),
          toGRT('123'),
        ]
        const subgraph = await publishNewSubgraph(me, newSubgraph0, gns, graph.chainId)

        // State updated
        const curationTaxPercentage = await curation.curationTaxPercentage()

        for (const tokensToDeposit of tokensToDepositMany) {
          const beforeSubgraph = await gns.subgraphs(subgraph.id)
          expect(newSubgraph0.subgraphDeploymentID).eq(beforeSubgraph.subgraphDeploymentID)

          const curationTax = toBN(curationTaxPercentage).mul(tokensToDeposit).div(toBN(1000000))
          const expectedNSignal = await calcGNSBondingCurve(
            beforeSubgraph.nSignal,
            beforeSubgraph.vSignal,
            tokensToDeposit.sub(curationTax),
            beforeSubgraph.subgraphDeploymentID,
          )
          const tx = await mintSignal(me, subgraph.id, tokensToDeposit, gns, curation)
          const receipt = await tx.wait()
          const event: Event = receipt.events.pop()
          const nSignalCreated = event.args['nSignalCreated']
          expect(toRound(expectedNSignal)).eq(toRound(toFloat(nSignalCreated)))
        }
      })

      it('should mint when using the edge case of linear function', async function () {
        // Setup edge case like linear function: 1 vSignal = 1 nSignal = 1 token
        await curation.connect(governor).setMinimumCurationDeposit(toGRT('1'))
        await curation.connect(governor).setDefaultReserveRatio(1000000)
        // note - reserve ratio is already set to 1000000 in GNS

        const tokensToDepositMany = [
          toGRT('1000'), // should mint if we start with number above minimum deposit
          toGRT('1000'), // every time it should mint less GCS due to bonding curve...
          toGRT('1000'),
          toGRT('1000'),
          toGRT('2000'),
          toGRT('2000'),
          toGRT('123'),
          toGRT('1'), // should mint below minimum deposit
        ]

        const subgraph = await publishNewSubgraph(me, newSubgraph0, gns, graph.chainId)

        // State updated
        for (const tokensToDeposit of tokensToDepositMany) {
          await mintSignal(me, subgraph.id, tokensToDeposit, gns, curation)
        }
      })
    })
  })

  describe('Two named subgraphs point to the same subgraph deployment ID', function () {
    it('handle initialization under minimum signal values', async function () {
      await curation.connect(governor).setMinimumCurationDeposit(toGRT('1'))

      // Publish a named subgraph-0 -> subgraphDeployment0
      const subgraph0 = await publishNewSubgraph(me, newSubgraph0, gns, graph.chainId)
      // Curate on the first subgraph
      await gns.connect(me).mintSignal(subgraph0.id, toGRT('90000'), 0)

      // Publish a named subgraph-1 -> subgraphDeployment0
      const subgraph1 = await publishNewSubgraph(me, newSubgraph0, gns, graph.chainId)
      // Curate on the second subgraph should work
      await gns.connect(me).mintSignal(subgraph1.id, toGRT('10'), 0)
    })
  })

  describe('batch calls', function () {
    it('should publish new subgraph and mint signal in single transaction', async function () {
      // Create a subgraph
      const tx1 = await gns.populateTransaction.publishNewSubgraph(
        newSubgraph0.subgraphDeploymentID,
        newSubgraph0.versionMetadata,
        newSubgraph0.subgraphMetadata,
      )
      // Curate on the subgraph
      const subgraphID = await buildSubgraphId(
        me.address,
        await gns.nextAccountSeqID(me.address),
        graph.chainId,
      )
      const tx2 = await gns.populateTransaction.mintSignal(subgraphID, toGRT('90000'), 0)

      // Batch send transaction
      await gns.connect(me).multicall([tx1.data, tx2.data])
    })

    it('should revert if batching a call to non-authorized function', async function () {
      // Call a forbidden function
      const tx1 = await gns.populateTransaction.setOwnerTaxPercentage(100)

      // Create a subgraph
      const tx2 = await gns.populateTransaction.publishNewSubgraph(
        newSubgraph0.subgraphDeploymentID,
        newSubgraph0.versionMetadata,
        newSubgraph0.subgraphMetadata,
      )

      // Batch send transaction
      const tx = gns.connect(me).multicall([tx1.data, tx2.data])
      await expect(tx).revertedWith('Only Controller governor')
    })

    it('should revert if batching a call to initialize', async function () {
      // Call a forbidden function
      const tx1 = await gns.populateTransaction.initialize(me.address, me.address)

      // Create a subgraph
      const tx2 = await gns.populateTransaction.publishNewSubgraph(
        newSubgraph0.subgraphDeploymentID,
        newSubgraph0.versionMetadata,
        newSubgraph0.subgraphMetadata,
      )

      // Batch send transaction
      const tx = gns.connect(me).multicall([tx1.data, tx2.data])
      await expect(tx).revertedWith('Only implementation')
    })

    it('should revert if trying to call a private function', async function () {
      // Craft call a private function
      const hash = ethers.utils.id('_setOwnerTaxPercentage(uint32)')
      const functionHash = hash.slice(0, 10)
      const calldata = ethers.utils.arrayify(
        ethers.utils.defaultAbiCoder.encode(['uint32'], ['100']),
      )
      const bogusPayload = ethers.utils.concat([functionHash, calldata])

      // Create a subgraph
      const tx2 = await gns.populateTransaction.publishNewSubgraph(
        newSubgraph0.subgraphDeploymentID,
        newSubgraph0.versionMetadata,
        newSubgraph0.subgraphMetadata,
      )

      // Batch send transaction
      const tx = gns.connect(me).multicall([bogusPayload, tx2.data])
      await expect(tx).revertedWith('')
    })
  })

  describe('NFT descriptor', function () {
    it('cannot be minted by an account that is not the minter (i.e. GNS)', async function () {
      const tx = subgraphNFT.connect(me).mint(me.address, 1)
      await expect(tx).revertedWith('Must be a minter')
    })
    it('cannot be burned by an account that is not the minter (i.e. GNS)', async function () {
      const tx = subgraphNFT.connect(me).burn(1)
      await expect(tx).revertedWith('Must be a minter')
    })
    it('with token descriptor', async function () {
      const subgraph0 = await publishNewSubgraph(me, newSubgraph0, gns, graph.chainId)

      const tokenURI = await subgraphNFT.connect(me).tokenURI(subgraph0.id)

      const sub = new SubgraphDeploymentID(newSubgraph0.subgraphMetadata)
      expect(sub.ipfsHash).eq(tokenURI)
    })

    it('with token descriptor and baseURI', async function () {
      const subgraph0 = await publishNewSubgraph(me, newSubgraph0, gns, graph.chainId)

      await subgraphNFT.connect(governor).setBaseURI('ipfs://')
      const tokenURI = await subgraphNFT.connect(me).tokenURI(subgraph0.id)

      const sub = new SubgraphDeploymentID(newSubgraph0.subgraphMetadata)
      expect('ipfs://' + sub.ipfsHash).eq(tokenURI)
    })

    it('without token descriptor', async function () {
      const subgraph0 = await publishNewSubgraph(me, newSubgraph0, gns, graph.chainId)

      await subgraphNFT.connect(governor).setTokenDescriptor(AddressZero)
      const tokenURI = await subgraphNFT.connect(me).tokenURI(subgraph0.id)

      const sub = new SubgraphDeploymentID(newSubgraph0.subgraphMetadata)
      expect(sub.bytes32).eq(tokenURI)
    })

    it('without token descriptor and baseURI', async function () {
      const subgraph0 = await publishNewSubgraph(me, newSubgraph0, gns, graph.chainId)

      await subgraphNFT.connect(governor).setTokenDescriptor(AddressZero)
      await subgraphNFT.connect(governor).setBaseURI('ipfs://')
      const tokenURI = await subgraphNFT.connect(me).tokenURI(subgraph0.id)

      const sub = new SubgraphDeploymentID(newSubgraph0.subgraphMetadata)
      expect('ipfs://' + sub.bytes32).eq(tokenURI)
    })

    it('without token descriptor and 0x0 metadata', async function () {
      const newSubgraphNoMetadata = buildSubgraph()
      newSubgraphNoMetadata.subgraphMetadata = HashZero
      const subgraph0 = await publishNewSubgraph(me, newSubgraphNoMetadata, gns, graph.chainId)

      await subgraphNFT.connect(governor).setTokenDescriptor(AddressZero)
      await subgraphNFT.connect(governor).setBaseURI('ipfs://')
      const tokenURI = await subgraphNFT.connect(me).tokenURI(subgraph0.id)
      expect('ipfs://' + subgraph0.id).eq(tokenURI)
    })
  })
  describe('Legacy subgraph migration', function () {
    it('migrates a legacy subgraph', async function () {
      const seqID = toBN('2')
      await legacyGNSMock.connect(me).createLegacySubgraph(seqID, newSubgraph0.subgraphDeploymentID)
      const tx = legacyGNSMock
        .connect(me)
        .migrateLegacySubgraph(me.address, seqID, newSubgraph0.subgraphMetadata)
      await expect(tx).emit(legacyGNSMock, ' LegacySubgraphClaimed').withArgs(me.address, seqID)
      const expectedSubgraphID = buildLegacySubgraphId(me.address, seqID)
      const migratedSubgraphDeploymentID = await legacyGNSMock.getSubgraphDeploymentID(
        expectedSubgraphID,
      )
      const migratedNSignal = await legacyGNSMock.getSubgraphNSignal(expectedSubgraphID)
      expect(migratedSubgraphDeploymentID).eq(newSubgraph0.subgraphDeploymentID)
      expect(migratedNSignal).eq(toBN('1000'))

      const subgraphNFTAddress = await legacyGNSMock.subgraphNFT()
      const subgraphNFT = loadContractAt('SubgraphNFT', subgraphNFTAddress)
      const tokenURI = await subgraphNFT.connect(me).tokenURI(expectedSubgraphID)

      const sub = new SubgraphDeploymentID(newSubgraph0.subgraphMetadata)
      expect(sub.ipfsHash).eq(tokenURI)
    })
    it('refuses to migrate an already migrated subgraph', async function () {
      const seqID = toBN('2')
      await legacyGNSMock.connect(me).createLegacySubgraph(seqID, newSubgraph0.subgraphDeploymentID)
      let tx = legacyGNSMock
        .connect(me)
        .migrateLegacySubgraph(me.address, seqID, newSubgraph0.subgraphMetadata)
      await expect(tx).emit(legacyGNSMock, ' LegacySubgraphClaimed').withArgs(me.address, seqID)
      tx = legacyGNSMock
        .connect(me)
        .migrateLegacySubgraph(me.address, seqID, newSubgraph0.subgraphMetadata)
      await expect(tx).revertedWith('GNS: Subgraph was already claimed')
    })
  })
  describe('Legacy subgraph view functions', function () {
    it('isLegacySubgraph returns whether a subgraph is legacy or not', async function () {
      const seqID = toBN('2')
      const subgraphId = buildLegacySubgraphId(me.address, seqID)
      await legacyGNSMock.connect(me).createLegacySubgraph(seqID, newSubgraph0.subgraphDeploymentID)
      await legacyGNSMock
        .connect(me)
        .migrateLegacySubgraph(me.address, seqID, newSubgraph0.subgraphMetadata)

      expect(await legacyGNSMock.isLegacySubgraph(subgraphId)).eq(true)

      const subgraph0 = await publishNewSubgraph(me, newSubgraph0, legacyGNSMock, graph.chainId)
      expect(await legacyGNSMock.isLegacySubgraph(subgraph0.id)).eq(false)
    })
    it('getLegacySubgraphKey returns the account and seqID for a legacy subgraph', async function () {
      const seqID = toBN('2')
      const subgraphId = buildLegacySubgraphId(me.address, seqID)
      await legacyGNSMock.connect(me).createLegacySubgraph(seqID, newSubgraph0.subgraphDeploymentID)
      await legacyGNSMock
        .connect(me)
        .migrateLegacySubgraph(me.address, seqID, newSubgraph0.subgraphMetadata)
      const [account, id] = await legacyGNSMock.getLegacySubgraphKey(subgraphId)
      expect(account).eq(me.address)
      expect(id).eq(seqID)
    })
    it('getLegacySubgraphKey returns zero values for a non-legacy subgraph', async function () {
      const subgraph0 = await publishNewSubgraph(me, newSubgraph0, legacyGNSMock, graph.chainId)
      const [account, id] = await legacyGNSMock.getLegacySubgraphKey(subgraph0.id)
      expect(account).eq(AddressZero)
      expect(id).eq(toBN('0'))
    })
  })
  describe('Subgraph transfer to L2', function () {
    const publishAndCurateOnSubgraph = async function (): Promise<Subgraph> {
      // Publish a named subgraph-0 -> subgraphDeployment0
      const subgraph0 = await publishNewSubgraph(me, newSubgraph0, gns, graph.chainId)
      // Curate on the subgraph
      await gns.connect(me).mintSignal(subgraph0.id, toGRT('90000'), 0)
      // Add an additional curator that is not the owner
      await gns.connect(other).mintSignal(subgraph0.id, toGRT('10000'), 0)
      return subgraph0
    }

    const publishCurateAndSendSubgraph = async function (
      beforeTransferCallback?: (subgraphID: string) => Promise<void>,
    ): Promise<Subgraph> {
      const subgraph0 = await publishAndCurateOnSubgraph()

      if (beforeTransferCallback != null) {
        await beforeTransferCallback(subgraph0.id)
      }

      const maxSubmissionCost = toBN('100')
      const maxGas = toBN('10')
      const gasPriceBid = toBN('20')

      const subgraphBefore = await gns.subgraphs(subgraph0.id)
      const curatedTokens = await gns.subgraphTokens(subgraph0.id)
      const beforeOwnerSignal = await gns.getCuratorSignal(subgraph0.id, me.address)
      const expectedSentToL2 = beforeOwnerSignal.mul(curatedTokens).div(subgraphBefore.nSignal)

      const tx = gns
        .connect(me)
        .sendSubgraphToL2(subgraph0.id, me.address, maxGas, gasPriceBid, maxSubmissionCost, {
          value: maxSubmissionCost.add(maxGas.mul(gasPriceBid)),
        })

      await expect(tx)
        .emit(gns, 'SubgraphSentToL2')
        .withArgs(subgraph0.id, me.address, me.address, expectedSentToL2)
      return subgraph0
    }
    const publishAndCurateOnLegacySubgraph = async function (seqID: BigNumber): Promise<string> {
      await legacyGNSMock.connect(me).createLegacySubgraph(seqID, newSubgraph0.subgraphDeploymentID)
      // The legacy subgraph must be claimed
      const migrateTx = legacyGNSMock
        .connect(me)
        .migrateLegacySubgraph(me.address, seqID, newSubgraph0.subgraphMetadata)
      await expect(migrateTx)
        .emit(legacyGNSMock, ' LegacySubgraphClaimed')
        .withArgs(me.address, seqID)
      const subgraphID = buildLegacySubgraphId(me.address, seqID)

      // Curate on the subgraph
      await legacyGNSMock.connect(me).mintSignal(subgraphID, toGRT('10000'), 0)

      return subgraphID
    }

    describe('sendSubgraphToL2', function () {
      it('sends tokens and calldata to L2 through the GRT bridge, for a desired L2 owner', async function () {
        const subgraph0 = await publishAndCurateOnSubgraph()

        const curatedTokens = await grt.balanceOf(curation.address)
        const subgraphBefore = await gns.subgraphs(subgraph0.id)

        const beforeOwnerSignal = await gns.getCuratorSignal(subgraph0.id, me.address)

        const maxSubmissionCost = toBN('100')
        const maxGas = toBN('10')
        const gasPriceBid = toBN('20')
        const tx = gns
          .connect(me)
          .sendSubgraphToL2(subgraph0.id, other.address, maxGas, gasPriceBid, maxSubmissionCost, {
            value: maxSubmissionCost.add(maxGas.mul(gasPriceBid)),
          })
        const expectedSentToL2 = beforeOwnerSignal.mul(curatedTokens).div(subgraphBefore.nSignal)
        await expect(tx)
          .emit(gns, 'SubgraphSentToL2')
          .withArgs(subgraph0.id, me.address, other.address, expectedSentToL2)

        const expectedRemainingTokens = curatedTokens.sub(expectedSentToL2)
        const subgraphAfter = await gns.subgraphs(subgraph0.id)
        expect(subgraphAfter.vSignal).eq(0)
        expect(await grt.balanceOf(gns.address)).eq(expectedRemainingTokens)
        expect(subgraphAfter.disabled).eq(true)
        expect(subgraphAfter.withdrawableGRT).eq(expectedRemainingTokens)

        const transferred = await gns.subgraphTransferredToL2(subgraph0.id)
        expect(transferred).eq(true)

        const expectedCallhookData = defaultAbiCoder.encode(
          ['uint8', 'uint256', 'address'],
          [toBN(0), subgraph0.id, other.address], // code = 0 means RECEIVE_SUBGRAPH_CODE
        )
        const expectedL2Data = await l1GraphTokenGateway.getOutboundCalldata(
          grt.address,
          gns.address,
          l2GNSMock.address,
          expectedSentToL2,
          expectedCallhookData,
        )
        await expect(tx)
          .emit(l1GraphTokenGateway, 'TxToL2')
          .withArgs(gns.address, l2GRTGatewayMock.address, toBN(1), expectedL2Data)
      })
      it('sends tokens and calldata for a legacy subgraph to L2 through the GRT bridge', async function () {
        const seqID = toBN('2')
        const subgraphID = await publishAndCurateOnLegacySubgraph(seqID)

        const subgraphBefore = await legacyGNSMock.legacySubgraphData(me.address, seqID)
        const curatedTokens = await legacyGNSMock.subgraphTokens(subgraphID)
        const beforeOwnerSignal = await legacyGNSMock.getCuratorSignal(subgraphID, me.address)
        const expectedSentToL2 = beforeOwnerSignal.mul(curatedTokens).div(subgraphBefore.nSignal)

        const maxSubmissionCost = toBN('100')
        const maxGas = toBN('10')
        const gasPriceBid = toBN('20')
        const tx = legacyGNSMock
          .connect(me)
          .sendSubgraphToL2(subgraphID, other.address, maxGas, gasPriceBid, maxSubmissionCost, {
            value: maxSubmissionCost.add(maxGas.mul(gasPriceBid)),
          })
        await expect(tx)
          .emit(legacyGNSMock, 'SubgraphSentToL2')
          .withArgs(subgraphID, me.address, other.address, expectedSentToL2)

        const expectedRemainingTokens = curatedTokens.sub(expectedSentToL2)
        const subgraphAfter = await legacyGNSMock.legacySubgraphData(me.address, seqID)
        expect(subgraphAfter.vSignal).eq(0)
        expect(await grt.balanceOf(legacyGNSMock.address)).eq(expectedRemainingTokens)
        expect(subgraphAfter.disabled).eq(true)
        expect(subgraphAfter.withdrawableGRT).eq(expectedRemainingTokens)

        const transferred = await legacyGNSMock.subgraphTransferredToL2(subgraphID)
        expect(transferred).eq(true)

        const expectedCallhookData = defaultAbiCoder.encode(
          ['uint8', 'uint256', 'address'],
          [toBN(0), subgraphID, other.address], // code = 0 means RECEIVE_SUBGRAPH_CODE
        )

        const expectedL2Data = await l1GraphTokenGateway.getOutboundCalldata(
          grt.address,
          legacyGNSMock.address,
          l2GNSMock.address,
          expectedSentToL2,
          expectedCallhookData,
        )
        await expect(tx)
          .emit(l1GraphTokenGateway, 'TxToL2')
          .withArgs(legacyGNSMock.address, l2GRTGatewayMock.address, toBN(1), expectedL2Data)
      })
      it('rejects calls from someone who is not the subgraph owner', async function () {
        const subgraph0 = await publishAndCurateOnSubgraph()

        const maxSubmissionCost = toBN('100')
        const maxGas = toBN('10')
        const gasPriceBid = toBN('20')
        const tx = gns
          .connect(other)
          .sendSubgraphToL2(subgraph0.id, other.address, maxGas, gasPriceBid, maxSubmissionCost, {
            value: maxSubmissionCost.add(maxGas.mul(gasPriceBid)),
          })
        await expect(tx).revertedWith('GNS: Must be authorized')
      })
      it('rejects calls for a subgraph that was already sent', async function () {
        const subgraph0 = await publishAndCurateOnSubgraph()

        const subgraphBefore = await gns.subgraphs(subgraph0.id)
        const curatedTokens = await gns.subgraphTokens(subgraph0.id)
        const beforeOwnerSignal = await gns.getCuratorSignal(subgraph0.id, me.address)
        const expectedSentToL2 = beforeOwnerSignal.mul(curatedTokens).div(subgraphBefore.nSignal)

        const maxSubmissionCost = toBN('100')
        const maxGas = toBN('10')
        const gasPriceBid = toBN('20')
        const tx = gns
          .connect(me)
          .sendSubgraphToL2(subgraph0.id, me.address, maxGas, gasPriceBid, maxSubmissionCost, {
            value: maxSubmissionCost.add(maxGas.mul(gasPriceBid)),
          })
        await expect(tx)
          .emit(gns, 'SubgraphSentToL2')
          .withArgs(subgraph0.id, me.address, me.address, expectedSentToL2)

        const tx2 = gns
          .connect(me)
          .sendSubgraphToL2(subgraph0.id, me.address, maxGas, gasPriceBid, maxSubmissionCost, {
            value: maxSubmissionCost.add(maxGas.mul(gasPriceBid)),
          })
        await expect(tx2).revertedWith('ALREADY_DONE')
      })
      it('rejects a call for a subgraph that is deprecated', async function () {
        const subgraph0 = await publishAndCurateOnSubgraph()

        await gns.connect(me).deprecateSubgraph(subgraph0.id)

        const maxSubmissionCost = toBN('100')
        const maxGas = toBN('10')
        const gasPriceBid = toBN('20')
        const tx = gns
          .connect(me)
          .sendSubgraphToL2(subgraph0.id, me.address, maxGas, gasPriceBid, maxSubmissionCost, {
            value: maxSubmissionCost.add(maxGas.mul(gasPriceBid)),
          })

        await expect(tx).revertedWith('GNS: Must be active')
      })
      it('rejects a call for a subgraph that does not exist', async function () {
        const subgraphId = await buildSubgraphId(me.address, toBN(100), graph.chainId)

        const maxSubmissionCost = toBN('100')
        const maxGas = toBN('10')
        const gasPriceBid = toBN('20')
        const tx = gns
          .connect(me)
          .sendSubgraphToL2(subgraphId, me.address, maxGas, gasPriceBid, maxSubmissionCost, {
            value: maxSubmissionCost.add(maxGas.mul(gasPriceBid)),
          })

        await expect(tx).revertedWith('GNS: Must be active')
      })
      it('rejects calls with more ETH than maxSubmissionCost + maxGas * gasPriceBid', async function () {
        const subgraph0 = await publishAndCurateOnSubgraph()

        const maxSubmissionCost = toBN('100')
        const maxGas = toBN('10')
        const gasPriceBid = toBN('20')
        const tx = gns
          .connect(me)
          .sendSubgraphToL2(subgraph0.id, me.address, maxGas, gasPriceBid, maxSubmissionCost, {
            value: maxSubmissionCost.add(maxGas.mul(gasPriceBid)).add(toBN('1')),
          })
        await expect(tx).revertedWith('INVALID_ETH_VALUE')
      })
      it('does not allow curators to burn signal after sending', async function () {
        const subgraph0 = await publishAndCurateOnSubgraph()

        const subgraphBefore = await gns.subgraphs(subgraph0.id)
        const curatedTokens = await gns.subgraphTokens(subgraph0.id)
        const beforeOwnerSignal = await gns.getCuratorSignal(subgraph0.id, me.address)
        const expectedSentToL2 = beforeOwnerSignal.mul(curatedTokens).div(subgraphBefore.nSignal)

        const maxSubmissionCost = toBN('100')
        const maxGas = toBN('10')
        const gasPriceBid = toBN('20')
        const tx = gns
          .connect(me)
          .sendSubgraphToL2(subgraph0.id, me.address, maxGas, gasPriceBid, maxSubmissionCost, {
            value: maxSubmissionCost.add(maxGas.mul(gasPriceBid)),
          })
        await expect(tx)
          .emit(gns, 'SubgraphSentToL2')
          .withArgs(subgraph0.id, me.address, me.address, expectedSentToL2)

        const tx2 = gns.connect(me).burnSignal(subgraph0.id, toBN(1), toGRT('0'))
        await expect(tx2).revertedWith('GNS: Must be active')
        const tx3 = gns.connect(other).burnSignal(subgraph0.id, toBN(1), toGRT('0'))
        await expect(tx3).revertedWith('GNS: Must be active')
      })
      it('does not allow curators to transfer signal after sending', async function () {
        const subgraph0 = await publishAndCurateOnSubgraph()

        const subgraphBefore = await gns.subgraphs(subgraph0.id)
        const curatedTokens = await gns.subgraphTokens(subgraph0.id)
        const beforeOwnerSignal = await gns.getCuratorSignal(subgraph0.id, me.address)
        const expectedSentToL2 = beforeOwnerSignal.mul(curatedTokens).div(subgraphBefore.nSignal)

        const maxSubmissionCost = toBN('100')
        const maxGas = toBN('10')
        const gasPriceBid = toBN('20')
        const tx = gns
          .connect(me)
          .sendSubgraphToL2(subgraph0.id, me.address, maxGas, gasPriceBid, maxSubmissionCost, {
            value: maxSubmissionCost.add(maxGas.mul(gasPriceBid)),
          })
        await expect(tx)
          .emit(gns, 'SubgraphSentToL2')
          .withArgs(subgraph0.id, me.address, me.address, expectedSentToL2)

        const tx2 = gns.connect(me).transferSignal(subgraph0.id, other.address, toBN(1))
        await expect(tx2).revertedWith('GNS: Must be active')
        const tx3 = gns.connect(other).transferSignal(subgraph0.id, me.address, toBN(1))
        await expect(tx3).revertedWith('GNS: Must be active')
      })
      it('does not allow the owner to withdraw GRT after sending', async function () {
        const subgraph0 = await publishAndCurateOnSubgraph()

        const subgraphBefore = await gns.subgraphs(subgraph0.id)
        const curatedTokens = await gns.subgraphTokens(subgraph0.id)
        const beforeOwnerSignal = await gns.getCuratorSignal(subgraph0.id, me.address)
        const expectedSentToL2 = beforeOwnerSignal.mul(curatedTokens).div(subgraphBefore.nSignal)

        const maxSubmissionCost = toBN('100')
        const maxGas = toBN('10')
        const gasPriceBid = toBN('20')
        const tx = gns
          .connect(me)
          .sendSubgraphToL2(subgraph0.id, me.address, maxGas, gasPriceBid, maxSubmissionCost, {
            value: maxSubmissionCost.add(maxGas.mul(gasPriceBid)),
          })
        await expect(tx)
          .emit(gns, 'SubgraphSentToL2')
          .withArgs(subgraph0.id, me.address, me.address, expectedSentToL2)

        const tx2 = gns.connect(me).withdraw(subgraph0.id)
        await expect(tx2).revertedWith('GNS: No signal to withdraw GRT')
      })
      it('allows a curator that is not the owner to withdraw GRT after sending', async function () {
        const subgraph0 = await publishAndCurateOnSubgraph()

        const subgraphBefore = await gns.subgraphs(subgraph0.id)
        const curatedTokens = await gns.subgraphTokens(subgraph0.id)
        const beforeOwnerSignal = await gns.getCuratorSignal(subgraph0.id, me.address)
        const expectedSentToL2 = beforeOwnerSignal.mul(curatedTokens).div(subgraphBefore.nSignal)
        const beforeOtherSignal = await gns.getCuratorSignal(subgraph0.id, other.address)

        const maxSubmissionCost = toBN('100')
        const maxGas = toBN('10')
        const gasPriceBid = toBN('20')
        const tx = gns
          .connect(me)
          .sendSubgraphToL2(subgraph0.id, me.address, maxGas, gasPriceBid, maxSubmissionCost, {
            value: maxSubmissionCost.add(maxGas.mul(gasPriceBid)),
          })
        await expect(tx)
          .emit(gns, 'SubgraphSentToL2')
          .withArgs(subgraph0.id, me.address, me.address, expectedSentToL2)

        const remainingTokens = (await gns.subgraphs(subgraph0.id)).withdrawableGRT
        const tx2 = gns.connect(other).withdraw(subgraph0.id)
        await expect(tx2)
          .emit(gns, 'GRTWithdrawn')
          .withArgs(subgraph0.id, other.address, beforeOtherSignal, remainingTokens)
      })
    })
    describe('sendCuratorBalanceToBeneficiaryOnL2', function () {
      it('sends a transaction with a curator balance to the L2GNS using the L1 gateway', async function () {
        const subgraph0 = await publishCurateAndSendSubgraph()
        const afterSubgraph = await gns.subgraphs(subgraph0.id)
        const curatorTokens = afterSubgraph.withdrawableGRT

        const expectedCallhookData = defaultAbiCoder.encode(
          ['uint8', 'uint256', 'address'],
          [toBN(1), subgraph0.id, another.address], // code = 1 means RECEIVE_CURATOR_BALANCE_CODE
        )
        const expectedL2Data = await l1GraphTokenGateway.getOutboundCalldata(
          grt.address,
          gns.address,
          l2GNSMock.address,
          curatorTokens,
          expectedCallhookData,
        )

        const maxSubmissionCost = toBN('100')
        const maxGas = toBN('10')
        const gasPriceBid = toBN('20')

        const tx = gns
          .connect(other)
          .sendCuratorBalanceToBeneficiaryOnL2(
            subgraph0.id,
            another.address,
            maxGas,
            gasPriceBid,
            maxSubmissionCost,
            {
              value: maxSubmissionCost.add(maxGas.mul(gasPriceBid)),
            },
          )

        // seqNum (third argument in the event) is 2, because number 1 was when the subgraph was sent to L2
        await expect(tx)
          .emit(l1GraphTokenGateway, 'TxToL2')
          .withArgs(gns.address, l2GRTGatewayMock.address, toBN('2'), expectedL2Data)
        await expect(tx)
          .emit(gns, 'CuratorBalanceSentToL2')
          .withArgs(subgraph0.id, other.address, another.address, curatorTokens)
      })
      it('sets the curator signal to zero so it cannot be called twice', async function () {
        const subgraph0 = await publishCurateAndSendSubgraph()
        const afterSubgraph = await gns.subgraphs(subgraph0.id)
        const curatorTokens = afterSubgraph.withdrawableGRT

        const expectedCallhookData = defaultAbiCoder.encode(
          ['uint8', 'uint256', 'address'],
          [toBN(1), subgraph0.id, other.address], // code = 1 means RECEIVE_CURATOR_BALANCE_CODE
        )
        const expectedL2Data = await l1GraphTokenGateway.getOutboundCalldata(
          grt.address,
          gns.address,
          l2GNSMock.address,
          curatorTokens,
          expectedCallhookData,
        )

        const maxSubmissionCost = toBN('100')
        const maxGas = toBN('10')
        const gasPriceBid = toBN('20')

        const tx = gns
          .connect(other)
          .sendCuratorBalanceToBeneficiaryOnL2(
            subgraph0.id,
            other.address,
            maxGas,
            gasPriceBid,
            maxSubmissionCost,
            {
              value: maxSubmissionCost.add(maxGas.mul(gasPriceBid)),
            },
          )

        // seqNum (third argument in the event) is 2, because number 1 was when the subgraph was sent to L2
        await expect(tx)
          .emit(l1GraphTokenGateway, 'TxToL2')
          .withArgs(gns.address, l2GRTGatewayMock.address, toBN('2'), expectedL2Data)

        const tx2 = gns
          .connect(other)
          .sendCuratorBalanceToBeneficiaryOnL2(
            subgraph0.id,
            other.address,
            maxGas,
            gasPriceBid,
            maxSubmissionCost,
            {
              value: maxSubmissionCost.add(maxGas.mul(gasPriceBid)),
            },
          )
        await expect(tx2).revertedWith('NO_SIGNAL')
      })
      it('sets the curator signal to zero so they cannot withdraw', async function () {
        const subgraph0 = await publishCurateAndSendSubgraph(async (_subgraphId) => {
          // We add another curator before transferring, so the the subgraph doesn't
          // run out of withdrawable GRT and we can test that it denies the specific curator
          // because they have sent their signal to L2, not because the subgraph is out of GRT.
          await gns.connect(another).mintSignal(_subgraphId, toGRT('1000'), toBN(0))
        })

        const maxSubmissionCost = toBN('100')
        const maxGas = toBN('10')
        const gasPriceBid = toBN('20')

        await gns
          .connect(other)
          .sendCuratorBalanceToBeneficiaryOnL2(
            subgraph0.id,
            other.address,
            maxGas,
            gasPriceBid,
            maxSubmissionCost,
            {
              value: maxSubmissionCost.add(maxGas.mul(gasPriceBid)),
            },
          )

        const tx = gns.connect(other).withdraw(subgraph0.id)
        await expect(tx).revertedWith('GNS: No signal to withdraw GRT')
      })
      it('gives each curator an amount of tokens proportional to their nSignal', async function () {
        let beforeOtherNSignal: BigNumber
        let beforeAnotherNSignal: BigNumber
        const subgraph0 = await publishCurateAndSendSubgraph(async (subgraphID) => {
          beforeOtherNSignal = await gns.getCuratorSignal(subgraphID, other.address)
          await gns.connect(another).mintSignal(subgraphID, toGRT('10000'), 0)
          beforeAnotherNSignal = await gns.getCuratorSignal(subgraphID, another.address)
        })
        const afterSubgraph = await gns.subgraphs(subgraph0.id)

        // Compute how much is owed to each curator
        const curator1Tokens = beforeOtherNSignal
          .mul(afterSubgraph.withdrawableGRT)
          .div(afterSubgraph.nSignal)
        const curator2Tokens = beforeAnotherNSignal
          .mul(afterSubgraph.withdrawableGRT)
          .div(afterSubgraph.nSignal)

        const expectedCallhookData1 = defaultAbiCoder.encode(
          ['uint8', 'uint256', 'address'],
          [toBN(1), subgraph0.id, other.address], // code = 1 means RECEIVE_CURATOR_BALANCE_CODE
        )
        const expectedCallhookData2 = defaultAbiCoder.encode(
          ['uint8', 'uint256', 'address'],
          [toBN(1), subgraph0.id, another.address], // code = 1 means RECEIVE_CURATOR_BALANCE_CODE
        )
        const expectedL2Data1 = await l1GraphTokenGateway.getOutboundCalldata(
          grt.address,
          gns.address,
          l2GNSMock.address,
          curator1Tokens,
          expectedCallhookData1,
        )

        const maxSubmissionCost = toBN('100')
        const maxGas = toBN('10')
        const gasPriceBid = toBN('20')

        const tx = gns
          .connect(other)
          .sendCuratorBalanceToBeneficiaryOnL2(
            subgraph0.id,
            other.address,
            maxGas,
            gasPriceBid,
            maxSubmissionCost,
            {
              value: maxSubmissionCost.add(maxGas.mul(gasPriceBid)),
            },
          )

        // seqNum (third argument in the event) is 2, because number 1 was when the subgraph was sent to L2
        await expect(tx)
          .emit(l1GraphTokenGateway, 'TxToL2')
          .withArgs(gns.address, l2GRTGatewayMock.address, toBN('2'), expectedL2Data1)

        // Accept slight numerical errors given how we compute the amount of tokens to send
        const curator2TokensUpdated = (await gns.subgraphs(subgraph0.id)).withdrawableGRT
        expect(toRound(toFloat(curator2TokensUpdated))).to.equal(toRound(toFloat(curator2Tokens)))
        const expectedL2Data2 = await l1GraphTokenGateway.getOutboundCalldata(
          grt.address,
          gns.address,
          l2GNSMock.address,
          curator2TokensUpdated,
          expectedCallhookData2,
        )
        const tx2 = gns
          .connect(another)
          .sendCuratorBalanceToBeneficiaryOnL2(
            subgraph0.id,
            another.address,
            maxGas,
            gasPriceBid,
            maxSubmissionCost,
            {
              value: maxSubmissionCost.add(maxGas.mul(gasPriceBid)),
            },
          )
        // seqNum (third argument in the event) is 3 now
        await expect(tx2)
          .emit(l1GraphTokenGateway, 'TxToL2')
          .withArgs(gns.address, l2GRTGatewayMock.address, toBN('3'), expectedL2Data2)
      })
      it('rejects calls for a subgraph that was not sent to L2', async function () {
        const subgraph0 = await publishAndCurateOnSubgraph()

        const maxSubmissionCost = toBN('100')
        const maxGas = toBN('10')
        const gasPriceBid = toBN('20')

        const tx = gns
          .connect(me)
          .sendCuratorBalanceToBeneficiaryOnL2(
            subgraph0.id,
            other.address,
            maxGas,
            gasPriceBid,
            maxSubmissionCost,
            {
              value: maxSubmissionCost.add(maxGas.mul(gasPriceBid)),
            },
          )

        await expect(tx).revertedWith('!TRANSFERRED')
      })

      it('rejects calls for a subgraph that was deprecated', async function () {
        const subgraph0 = await publishAndCurateOnSubgraph()

        await helpers.mine(256)
        await gns.connect(me).deprecateSubgraph(subgraph0.id)

        const maxSubmissionCost = toBN('100')
        const maxGas = toBN('10')
        const gasPriceBid = toBN('20')

        const tx = gns
          .connect(me)
          .sendCuratorBalanceToBeneficiaryOnL2(
            subgraph0.id,
            other.address,
            maxGas,
            gasPriceBid,
            maxSubmissionCost,
            {
              value: maxSubmissionCost.add(maxGas.mul(gasPriceBid)),
            },
          )

        await expect(tx).revertedWith('!TRANSFERRED')
      })
      it('rejects calls with zero maxSubmissionCost', async function () {
        const subgraph0 = await publishCurateAndSendSubgraph()

        const maxSubmissionCost = toBN('0')
        const maxGas = toBN('10')
        const gasPriceBid = toBN('20')

        const tx = gns
          .connect(me)
          .sendCuratorBalanceToBeneficiaryOnL2(
            subgraph0.id,
            other.address,
            maxGas,
            gasPriceBid,
            maxSubmissionCost,
            {
              value: maxSubmissionCost.add(maxGas.mul(gasPriceBid)),
            },
          )

        await expect(tx).revertedWith('NO_SUBMISSION_COST')
      })
      it('rejects calls with more ETH than maxSubmissionCost + maxGas * gasPriceBid', async function () {
        const subgraph0 = await publishCurateAndSendSubgraph()

        const maxSubmissionCost = toBN('100')
        const maxGas = toBN('10')
        const gasPriceBid = toBN('20')

        const tx = gns
          .connect(me)
          .sendCuratorBalanceToBeneficiaryOnL2(
            subgraph0.id,
            other.address,
            maxGas,
            gasPriceBid,
            maxSubmissionCost,
            {
              value: maxSubmissionCost.add(maxGas.mul(gasPriceBid)).add(toBN('1')),
            },
          )

        await expect(tx).revertedWith('INVALID_ETH_VALUE')
      })
      it('rejects calls if the curator has withdrawn the GRT', async function () {
        const subgraph0 = await publishCurateAndSendSubgraph()

        await gns.connect(other).withdraw(subgraph0.id)

        const maxSubmissionCost = toBN('100')
        const maxGas = toBN('10')
        const gasPriceBid = toBN('20')

        const tx = gns
          .connect(other)
          .sendCuratorBalanceToBeneficiaryOnL2(
            subgraph0.id,
            another.address,
            maxGas,
            gasPriceBid,
            maxSubmissionCost,
            {
              value: maxSubmissionCost.add(maxGas.mul(gasPriceBid)),
            },
          )

        // seqNum (third argument in the event) is 2, because number 1 was when the subgraph was sent to L2
        await expect(tx).revertedWith('NO_SIGNAL')
      })
    })
  })
})
