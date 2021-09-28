import { expect } from 'chai'
import { ethers, ContractTransaction, BigNumber, Event } from 'ethers'

import { GNS } from '../build/types/GNS'
import {
  getAccounts,
  randomHexBytes,
  Account,
  toGRT,
  calcBondingCurve,
  advanceBlockTo,
} from './lib/testHelpers'
import { NetworkFixture } from './lib/fixtures'
import { GraphToken } from '../build/types/GraphToken'
import { Curation } from '../build/types/Curation'

import { toBN, formatGRT, BIG_NUMBER_ZERO } from './lib/testHelpers'

interface Subgraph {
  graphAccount: Account
  subgraphDeploymentID: string
  subgraphNumber: BigNumber
  versionMetadata: string
  subgraphMetadata: string
}

interface AccountDefaultName {
  name: string
  nameIdentifier: string
}

const toFloat = (n: BigNumber) => parseFloat(formatGRT(n))
const toRound = (n: number) => n.toFixed(12)

describe('GNS', () => {
  let me: Account
  let other: Account
  let governor: Account

  let fixture: NetworkFixture

  let gns: GNS
  let grt: GraphToken
  let curation: Curation

  const tokens1000 = toGRT('1000')
  const tokens10000 = toGRT('10000')
  const tokens100000 = toGRT('100000')
  const curationTaxPercentage = 50000
  let subgraph0: Subgraph
  let subgraph1: Subgraph
  let defaultName: AccountDefaultName

  const createSubgraph = (account: Account, subgraphNumber: string): Subgraph => {
    return {
      graphAccount: account,
      subgraphDeploymentID: randomHexBytes(),
      subgraphNumber: BigNumber.from(subgraphNumber),

      versionMetadata: randomHexBytes(),
      subgraphMetadata: randomHexBytes(),
    }
  }

  const createDefaultName = (name: string): AccountDefaultName => {
    return {
      name: name,
      nameIdentifier: ethers.utils.namehash(name),
    }
  }

  const getTokensAndVSignal = async (subgraphID: string): Promise<Array<BigNumber>> => {
    const curationPool = await curation.pools(subgraphID)
    const vSignal = await curation.getCurationPoolSignal(subgraphID)
    return [curationPool.tokens, vSignal]
  }

  async function calcGNSBondingCurve(
    gnsSupply: BigNumber, // nSignal
    gnsReserveBalance: BigNumber, // vSignal
    depositAmount: BigNumber, // GRT deposited
    subgraphID: string,
  ): Promise<number> {
    const signal = await curation.getCurationPoolSignal(subgraphID)
    const curationTokens = await curation.getCurationPoolTokens(subgraphID)
    const expectedSignal = await calcBondingCurve(
      signal,
      curationTokens,
      depositAmount,
      BIG_NUMBER_ZERO,
      BigNumber.from(100),
      await curation.initializationPeriod(),
      await curation.initializationExitPeriod(),
      await curation.defaultReserveRatio(),
      await curation.minimumCurationDeposit(),
    )
    const expectedSignalBN = toGRT(String(expectedSignal.toFixed(18)))

    // Handle the initialization of the bonding curve
    if (gnsSupply.eq(0)) {
      return expectedSignal
    }
    // Since we known CW = 1, we can do the simplified formula of:
    return (toFloat(gnsSupply) * toFloat(expectedSignalBN)) / toFloat(gnsReserveBalance)
  }

  const publishNewSubgraph = async (
    account: Account,
    graphAccount: string,
    subgraphNumber: number,
    subgraphToPublish = subgraph0, // Defaults to subgraph created in before()
  ): Promise<ContractTransaction> => {
    const tx = gns
      .connect(account.signer)
      .publishNewSubgraph(
        graphAccount,
        subgraphToPublish.subgraphDeploymentID,
        subgraphToPublish.versionMetadata,
        subgraphToPublish.subgraphMetadata,
      )
    await expect(tx)
      .emit(gns, 'SubgraphPublished')
      .withArgs(
        subgraphToPublish.graphAccount.address,
        subgraphNumber,
        subgraphToPublish.subgraphDeploymentID,
        subgraphToPublish.versionMetadata,
      )
      .emit(gns, 'NameSignalEnabled')
      .withArgs(graphAccount, subgraphNumber, subgraphToPublish.subgraphDeploymentID, 1000000)
      .emit(gns, 'SubgraphMetadataUpdated')
      .withArgs(
        subgraphToPublish.graphAccount.address,
        subgraphNumber,
        subgraphToPublish.subgraphMetadata,
      )

    const pool = await gns.nameSignals(graphAccount, subgraphNumber)
    const reserveRatio = pool[3]
    expect(reserveRatio).eq(1000000)
    return tx
  }

  const publishNewVersion = async (
    account: Account,
    graphAccount: string,
    subgraphNumber: number,
    subgraphToPublish = subgraph0, // Defaults to subgraph created in before()
  ) => {
    // Before stats for the old vSignal curve
    const ownerTaxPercentage = await gns.ownerTaxPercentage()
    const curationTaxPercentage = await curation.curationTaxPercentage()
    // Before stats for the name curve
    const namePoolBefore = await gns.nameSignals(graphAccount, subgraphNumber)

    // Check what selling all nSignal, which == selling all vSignal, should return for tokens
    // NOTE - no tax on burning on nSignal
    const { 1: tokensReceivedEstimate } = await gns.nSignalToTokens(
      graphAccount,
      subgraphNumber,
      namePoolBefore.nSignal,
    )
    // Example:
    // Deposit 100, 5 is taxed, 95 GRT in curve
    // Upgrade - calculate 5% tax on 95 --> 4.75 GRT
    // Multiple by ownerPercentage --> 50% * 4.75 = 2.375 GRT
    // Owner adds 2.375 to 90.25, we deposit 92.625 GRT into the curve
    // Divide this by 0.95 to get exactly 97.5 total tokens to be deposited

    // nSignalToTokens returns the amount of tokens with tax removed
    // already. So we must add in the tokens removed
    const MAX_PPM = 1000000
    const taxOnOriginal = tokensReceivedEstimate.mul(curationTaxPercentage).div(MAX_PPM)
    const totalWithoutOwnerTax = tokensReceivedEstimate.sub(taxOnOriginal)
    const ownerTax = taxOnOriginal.mul(ownerTaxPercentage).div(MAX_PPM)

    const totalWithOwnerTax = totalWithoutOwnerTax.add(ownerTax)

    const totalAdjustedUp = totalWithOwnerTax.mul(MAX_PPM).div(MAX_PPM - curationTaxPercentage)

    // Re-estimate amount of signal to get considering the owner tax paid by the owner
    const { 0: newVSignalEstimate, 1: newCurationTaxEstimate } = await curation.tokensToSignal(
      subgraphToPublish.subgraphDeploymentID,
      totalAdjustedUp,
    )

    // Send transaction
    const tx = gns
      .connect(account.signer)
      .publishNewVersion(
        graphAccount,
        subgraphNumber,
        subgraphToPublish.subgraphDeploymentID,
        subgraphToPublish.versionMetadata,
      )
    await expect(tx)
      .emit(gns, 'SubgraphPublished')
      .withArgs(
        subgraphToPublish.graphAccount.address,
        subgraphNumber,
        subgraphToPublish.subgraphDeploymentID,
        subgraphToPublish.versionMetadata,
      )
      .emit(gns, 'NameSignalUpgrade')
      .withArgs(
        graphAccount,
        subgraphNumber,
        newVSignalEstimate,
        totalAdjustedUp,
        subgraphToPublish.subgraphDeploymentID,
      )

    // Check curation vSignal old are set to zero
    const [tokensAfterOldCuration, vSignalAfterOldCuration] = await getTokensAndVSignal(
      subgraph0.subgraphDeploymentID,
    )
    expect(tokensAfterOldCuration).eq(0)
    expect(vSignalAfterOldCuration).eq(0)

    // Check the vSignal of the new curation curve, amd tokens
    const [tokensAfterNewCurve, vSignalAfterNewCurve] = await getTokensAndVSignal(
      subgraphToPublish.subgraphDeploymentID,
    )
    expect(tokensAfterNewCurve).eq(totalAdjustedUp.sub(newCurationTaxEstimate))
    expect(vSignalAfterNewCurve).eq(newVSignalEstimate)

    // Check the nSignal pool
    const namePoolAfter = await gns.nameSignals(graphAccount, subgraphNumber)
    expect(namePoolAfter.vSignal).eq(vSignalAfterNewCurve).eq(newVSignalEstimate)
    expect(namePoolAfter.nSignal).eq(namePoolBefore.nSignal) // should not change
    expect(namePoolAfter.subgraphDeploymentID).eq(subgraphToPublish.subgraphDeploymentID)

    return tx
  }

  const deprecateSubgraph = async (
    account: Account,
    graphAccount: string,
    subgraphNumber0: number,
  ) => {
    const [tokensBefore] = await getTokensAndVSignal(subgraph0.subgraphDeploymentID)
    // We can use the whole amount, since in this test suite all vSignal is used to be staked on nSignal
    const ownerBalanceBefore = await grt.balanceOf(account.address)

    const tx = gns.connect(account.signer).deprecateSubgraph(graphAccount, subgraphNumber0)
    await expect(tx).emit(gns, 'SubgraphDeprecated').withArgs(subgraph0.graphAccount.address, 0)
    await expect(tx)
      .emit(gns, 'NameSignalDisabled')
      .withArgs(graphAccount, subgraphNumber0, tokensBefore)

    const deploymentID = await gns.subgraphs(subgraph0.graphAccount.address, 0)
    expect(ethers.constants.HashZero).eq(deploymentID)

    // Check that vSignal is set to 0
    const poolAfter = await gns.nameSignals(graphAccount, subgraphNumber0)
    const poolVSignalAfter = poolAfter.vSignal
    expect(poolVSignalAfter.eq(toBN('0')))
    // Check that the owner balance decreased by the curation tax
    const ownerBalanceAfter = await grt.balanceOf(account.address)
    expect(ownerBalanceBefore.eq(ownerBalanceAfter))
    // Should be equal since owner pays curation tax
    expect(poolAfter.withdrawableGRT).eq(tokensBefore)
    // Check that deprecated is true
    expect(poolAfter.disabled).eq(true)
    // Check balance of gns increase by curation tax from owner being added
    const gnsBalanceAfter = await grt.balanceOf(gns.address)
    expect(gnsBalanceAfter).eq(poolAfter.withdrawableGRT)
    return tx
  }

  /*
  const upgradeNameSignal = async (
    account: Account,
    graphAccount: string,
    subgraphNumber0: number,
    newSubgraphDeplyomentID: string,
  ): Promise<ContractTransaction> => {
    // Before stats for the old vSignal curve
    const tokensBeforeVSigOldCuration = await getTokensAndVSignal(subgraph0.subgraphDeploymentID)
    const tokensBeforeOldCuration = tokensBeforeVSigOldCuration[0]
    const vSigBeforeOldCuration = tokensBeforeVSigOldCuration[1]

    // Before stats for the name curve
    const poolBefore = await gns.nameSignals(graphAccount, subgraphNumber0)
    const nSigBefore = poolBefore[1]

    // Check what selling all nSignal, which == selling all vSignal, should return for tokens
    const nSignalToTokensResult = await gns.nSignalToTokens(
      graphAccount,
      subgraphNumber0,
      nSigBefore,
    )
    const vSignalBurnEstimate = nSignalToTokensResult[0]
    const tokensReceivedEstimate = nSignalToTokensResult[1]

    // since in upgrade, owner must refund fees, we need to actually add this back in
    const feesToAddBackEstimate = nSignalToTokensResult[2]
    const upgradeTokenReturn = tokensReceivedEstimate.add(feesToAddBackEstimate)

    // Get the value for new vSignal that should be created on the new curve
    const newVSignalEstimate = await curation.tokensToSignal(
      newSubgraphDeplyomentID,
      upgradeTokenReturn,
    )

    // Do the upgrade
    const tx = gns
      .connect(account.signer)
      .upgradeNameSignal(graphAccount, subgraphNumber0, newSubgraphDeplyomentID)
    await expect(tx)
      .emit(gns, 'NameSignalUpgrade')
      .withArgs(
        graphAccount,
        subgraphNumber0,
        newVSignalEstimate,
        upgradeTokenReturn,
        newSubgraphDeplyomentID,
      )

    // Check curation vSignal old was lowered and tokens too
    const [tokensAfterOldCuration, vSigAfterOldCuration] = await getTokensAndVSignal(
      subgraph0.subgraphDeploymentID,
    )
    expect(tokensAfterOldCuration).eq(tokensBeforeOldCuration.sub(upgradeTokenReturn))
    expect(vSigAfterOldCuration).eq(vSigBeforeOldCuration.sub(vSignalBurnEstimate))

    // Check the vSignal of the new curation curve, amd tokens
    const [tokensAfterNewCurve, vSigAfterNewCurve] = await getTokensAndVSignal(
      newSubgraphDeplyomentID,
    )
    expect(tokensAfterNewCurve).eq(upgradeTokenReturn)
    expect(vSigAfterNewCurve).eq(newVSignalEstimate)

    // Check the nSignal pool
    const pool = await gns.nameSignals(graphAccount, subgraphNumber0)
    const vSigPool = pool[0]
    const nSigAfter = pool[1]
    const deploymentID = pool[2]
    expect(vSigAfterNewCurve).eq(vSigPool).eq(newVSignalEstimate)
    expect(nSigBefore).eq(nSigAfter) // should not change
    expect(deploymentID).eq(newSubgraphDeplyomentID)

    return tx
  }
  */

  const mintNSignal = async (
    account: Account,
    graphAccount: string,
    subgraphNumber0: number,
    graphTokens: BigNumber,
  ): Promise<ContractTransaction> => {
    // Before state
    const [tokensBefore, vSignalBefore] = await getTokensAndVSignal(subgraph0.subgraphDeploymentID)
    const namePoolBefore = await gns.nameSignals(graphAccount, subgraphNumber0)

    // Deposit
    const {
      0: vSignalExpected,
      1: nSignalExpected,
      2: curationTax,
    } = await gns.tokensToNSignal(graphAccount, subgraphNumber0, graphTokens)
    const tx = gns
      .connect(account.signer)
      .mintNSignal(graphAccount, subgraphNumber0, graphTokens, 0)
    await expect(tx)
      .emit(gns, 'NSignalMinted')
      .withArgs(
        graphAccount,
        subgraphNumber0,
        account.address,
        nSignalExpected,
        vSignalExpected,
        graphTokens,
      )

    // After state
    const [tokensAfter, vSignalAfter] = await getTokensAndVSignal(subgraph0.subgraphDeploymentID)
    const namePoolAfter = await gns.nameSignals(graphAccount, subgraphNumber0)

    expect(tokensAfter).eq(tokensBefore.add(graphTokens.sub(curationTax)))
    expect(vSignalAfter).eq(vSignalBefore.add(vSignalExpected))
    expect(namePoolAfter.nSignal).eq(namePoolBefore.nSignal.add(nSignalExpected))
    expect(namePoolAfter.vSignal).eq(vSignalBefore.add(vSignalExpected))

    return tx
  }

  const burnNSignal = async (
    account: Account,
    graphAccount: string,
    subgraphNumber0: number,
  ): Promise<ContractTransaction> => {
    // Before checks
    const [tokensBefore, vSigBefore] = await getTokensAndVSignal(subgraph0.subgraphDeploymentID)
    const namePoolBefore = await gns.nameSignals(graphAccount, subgraphNumber0)
    const usersNSignalBefore = await gns.getCuratorNSignal(
      graphAccount,
      subgraphNumber0,
      account.address,
    )

    // Withdraw
    const { 0: vSignalExpected, 1: tokensExpected } = await gns.nSignalToTokens(
      graphAccount,
      subgraphNumber0,
      usersNSignalBefore,
    )

    // Do withdraw tx
    const tx = gns
      .connect(account.signer)
      .burnNSignal(graphAccount, subgraphNumber0, usersNSignalBefore, 0)
    await expect(tx)
      .emit(gns, 'NSignalBurned')
      .withArgs(
        graphAccount,
        subgraphNumber0,
        account.address,
        usersNSignalBefore,
        vSignalExpected,
        tokensExpected,
      )

    // After checks
    const [tokensAfter, vSignalCurationAfter] = await getTokensAndVSignal(
      subgraph0.subgraphDeploymentID,
    )
    const namePoolAfter = await gns.nameSignals(graphAccount, subgraphNumber0)

    expect(tokensAfter).eq(tokensBefore.sub(tokensExpected))
    expect(vSignalCurationAfter).eq(vSigBefore.sub(vSignalExpected))
    expect(namePoolAfter.nSignal).eq(namePoolBefore.nSignal.sub(usersNSignalBefore))

    return tx
  }

  const withdraw = async (
    account: Account,
    graphAccount: string,
    subgraphNumber0: number,
  ): Promise<ContractTransaction> => {
    const curatorNSignalBefore = await gns.getCuratorNSignal(
      graphAccount,
      subgraphNumber0,
      account.address,
    )
    const poolBefore = await gns.nameSignals(graphAccount, subgraphNumber0)
    const gnsBalanceBefore = await grt.balanceOf(gns.address)
    const tokensEstimate = poolBefore.withdrawableGRT
      .mul(curatorNSignalBefore)
      .div(poolBefore.nSignal)

    // Run tx
    const tx = gns.connect(account.signer).withdraw(graphAccount, subgraphNumber0)
    await expect(tx)
      .emit(gns, 'GRTWithdrawn')
      .withArgs(
        graphAccount,
        subgraphNumber0,
        account.address,
        curatorNSignalBefore,
        tokensEstimate,
      )

    // curator nSignal should be updated
    const curatorNSignalAfter = await gns.getCuratorNSignal(
      graphAccount,
      subgraphNumber0,
      account.address,
    )

    expect(curatorNSignalAfter).eq(toBN(0))

    // overall n signal should be updated
    const poolAfter = await gns.nameSignals(graphAccount, subgraphNumber0)
    expect(poolAfter.nSignal).eq(poolBefore.nSignal.sub(curatorNSignalBefore))
    // withdrawableGRT should be updated

    // Token balance should be updated
    const gnsBalanceAfter = await grt.balanceOf(gns.address)
    expect(gnsBalanceAfter).eq(gnsBalanceBefore.sub(tokensEstimate))

    return tx
  }

  before(async function () {
    ;[me, other, governor] = await getAccounts()
    fixture = new NetworkFixture()
    ;({ grt, curation, gns } = await fixture.load(governor.signer))
    subgraph0 = createSubgraph(me, '0')
    subgraph1 = createSubgraph(me, '1')
    defaultName = createDefaultName('graph')
    // Give some funds to the signers and approve gns contract to use funds on signers behalf
    await grt.connect(governor.signer).mint(me.address, tokens100000)
    await grt.connect(governor.signer).mint(other.address, tokens100000)
    await grt.connect(me.signer).approve(gns.address, tokens100000)
    await grt.connect(me.signer).approve(curation.address, tokens100000)
    await grt.connect(other.signer).approve(gns.address, tokens100000)
    await grt.connect(other.signer).approve(curation.address, tokens100000)
    // Update curation tax to test the functionality of it in disableNameSignal()
    await curation.connect(governor.signer).setCurationTaxPercentage(curationTaxPercentage)
  })

  beforeEach(async function () {
    await fixture.setUp()
  })

  afterEach(async function () {
    await fixture.tearDown()
  })

  describe('when initialization phases exited', function () {
    describe('Publishing names and versions', function () {
      describe('setDefaultName', function () {
        it('setDefaultName emits the event', async function () {
          const tx = gns
            .connect(me.signer)
            .setDefaultName(me.address, 0, defaultName.nameIdentifier, defaultName.name)
          await expect(tx)
            .emit(gns, 'SetDefaultName')
            .withArgs(
              subgraph0.graphAccount.address,
              0,
              defaultName.nameIdentifier,
              defaultName.name,
            )
        })

        it('setDefaultName fails if not owner', async function () {
          const tx = gns
            .connect(other.signer)
            .setDefaultName(me.address, 0, defaultName.nameIdentifier, defaultName.name)
          await expect(tx).revertedWith('GNS: Only graph account owner can call')
        })
      })

      describe('updateSubgraphMetadata', function () {
        it('updateSubgraphMetadata emits the event', async function () {
          const tx = gns
            .connect(me.signer)
            .updateSubgraphMetadata(me.address, 0, subgraph0.subgraphMetadata)
          await expect(tx)
            .emit(gns, 'SubgraphMetadataUpdated')
            .withArgs(subgraph0.graphAccount.address, 0, subgraph0.subgraphMetadata)
        })

        it('updateSubgraphMetadata fails if not owner', async function () {
          const tx = gns
            .connect(other.signer)
            .updateSubgraphMetadata(me.address, 0, subgraph0.subgraphMetadata)
          await expect(tx).revertedWith('GNS: Only graph account owner can call')
        })
      })

      describe('isPublished', function () {
        it('should return if the subgraph is published', async function () {
          expect(await gns.isPublished(subgraph0.graphAccount.address, 0)).eq(false)
          await publishNewSubgraph(me, me.address, 0)
          expect(await gns.isPublished(subgraph0.graphAccount.address, 0)).eq(true)
        })
      })

      describe('publishNewSubgraph', async function () {
        it('should publish a new subgraph and first version with it', async function () {
          await publishNewSubgraph(me, me.address, 0)
          // State updated
          const deploymentID = await gns.subgraphs(subgraph0.graphAccount.address, 0)
          expect(subgraph0.subgraphDeploymentID).eq(deploymentID)
        })

        it('should publish a new subgraph with an incremented value', async function () {
          await publishNewSubgraph(me, me.address, 0)
          await publishNewSubgraph(me, me.address, 1, subgraph1)
          const deploymentID = await gns.subgraphs(subgraph1.graphAccount.address, 1)
          expect(subgraph1.subgraphDeploymentID).eq(deploymentID)
        })

        it('should reject publish if not sent from owner', async function () {
          const tx = gns
            .connect(other.signer)
            .publishNewSubgraph(
              subgraph0.graphAccount.address,
              ethers.constants.HashZero,
              subgraph0.versionMetadata,
              subgraph0.subgraphMetadata,
            )
          await expect(tx).revertedWith('GNS: Only graph account owner can call')
        })

        it('should prevent subgraphDeploymentID of 0 to be used', async function () {
          const tx = gns
            .connect(me.signer)
            .publishNewSubgraph(
              subgraph0.graphAccount.address,
              ethers.constants.HashZero,
              subgraph0.versionMetadata,
              subgraph0.subgraphMetadata,
            )
          await expect(tx).revertedWith('GNS: Cannot set deploymentID to 0 in publish')
        })
      })

      describe('publishNewVersion', async function () {
        beforeEach(async () => {
          await publishNewSubgraph(me, me.address, 0)
          await advanceBlockTo(100)
          await mintNSignal(me, me.address, 0, tokens10000)
        })

        it('should publish a new version on an existing subgraph', async function () {
          await publishNewVersion(me, me.address, 0, subgraph1)
        })

        it('should reject a new version with the same subgraph deployment ID', async function () {
          const tx = gns
            .connect(me.signer)
            .publishNewVersion(
              subgraph0.graphAccount.address,
              0,
              subgraph0.subgraphDeploymentID,
              subgraph0.versionMetadata,
            )
          await expect(tx).revertedWith(
            'GNS: Cannot publish a new version with the same subgraph deployment ID',
          )
        })

        it('should reject publishing a version to a numbered subgraph that does not exist', async function () {
          const wrongNumberedSubgraph = 9999
          const tx = gns
            .connect(me.signer)
            .publishNewVersion(
              subgraph1.graphAccount.address,
              wrongNumberedSubgraph,
              subgraph1.subgraphDeploymentID,
              subgraph1.versionMetadata,
            )
          await expect(tx).revertedWith(
            'GNS: Cannot update version if not published, or has been deprecated',
          )
        })

        it('reject if not the owner', async function () {
          const tx = gns
            .connect(other.signer)
            .publishNewVersion(
              subgraph1.graphAccount.address,
              0,
              subgraph1.subgraphDeploymentID,
              subgraph1.versionMetadata,
            )
          await expect(tx).revertedWith('GNS: Only graph account owner can call')
        })

        it('should fail when upgrade tries to point to a pre-curated', async function () {
          await curation.connect(me.signer).mint(subgraph1.subgraphDeploymentID, tokens1000, 0)
          const tx = gns
            .connect(me.signer)
            .publishNewVersion(
              me.address,
              0,
              subgraph1.subgraphDeploymentID,
              subgraph1.versionMetadata,
            )
          await expect(tx).revertedWith(
            'GNS: Owner cannot point to a subgraphID that has been pre-curated',
          )
        })

        it('should fail when trying to upgrade when there is no nSignal', async function () {
          await burnNSignal(me, me.address, 0)
          const tx = gns
            .connect(me.signer)
            .publishNewVersion(
              me.address,
              0,
              subgraph1.subgraphDeploymentID,
              subgraph1.versionMetadata,
            )
          await expect(tx).revertedWith(
            'GNS: There must be nSignal on this subgraph for curve math to work',
          )
        })

        it('should fail when subgraph is deprecated', async function () {
          await deprecateSubgraph(me, me.address, 0)
          const tx = gns
            .connect(me.signer)
            .publishNewVersion(
              me.address,
              0,
              subgraph1.subgraphDeploymentID,
              subgraph1.versionMetadata,
            )
          await expect(tx).revertedWith(
            'GNS: Cannot update version if not published, or has been deprecated',
          )
        })
      })

      describe('deprecateSubgraph', async function () {
        beforeEach(async () => {
          await publishNewSubgraph(me, me.address, 0)
          await advanceBlockTo(100)
          await mintNSignal(me, me.address, 0, tokens10000)
        })

        it('should deprecate a subgraph', async function () {
          await deprecateSubgraph(me, me.address, 0)
        })

        it('should prevent a deprecated subgraph from being republished', async function () {
          await deprecateSubgraph(me, me.address, 0)
          const tx = gns
            .connect(me.signer)
            .publishNewVersion(
              subgraph1.graphAccount.address,
              1,
              subgraph1.subgraphDeploymentID,
              subgraph1.versionMetadata,
            )
          await expect(tx).revertedWith(
            'Cannot update version if not published, or has been deprecated',
          )
        })

        it('reject if the subgraph does not exist', async function () {
          const wrongNumberedSubgraph = 2340
          const tx = gns
            .connect(me.signer)
            .deprecateSubgraph(subgraph1.graphAccount.address, wrongNumberedSubgraph)
          await expect(tx).revertedWith('GNS: Cannot deprecate a subgraph which does not exist')
        })

        it('reject deprecate if not the owner', async function () {
          const tx = gns
            .connect(other.signer)
            .deprecateSubgraph(subgraph0.graphAccount.address, subgraph0.subgraphNumber)
          await expect(tx).revertedWith('GNS: Only graph account owner can call')
        })
      })
    })

    describe('Curating on names', async function () {
      const subgraphNumber0 = 0

      describe('mintNSignal()', async function () {
        it('should deposit into the name signal curve', async function () {
          await publishNewSubgraph(me, me.address, subgraphNumber0)
          await advanceBlockTo(100)
          await mintNSignal(other, me.address, subgraphNumber0, tokens10000)
        })

        it('should fail when name signal is disabled', async function () {
          await publishNewSubgraph(me, me.address, subgraphNumber0)
          await advanceBlockTo(100)
          await deprecateSubgraph(me, me.address, 0)
          const tx = gns.connect(me.signer).mintNSignal(me.address, subgraphNumber0, tokens1000, 0)
          await expect(tx).revertedWith('GNS: Cannot be disabled')
        })

        it('should fail if you try to deposit on a non existing name', async function () {
          const tx = gns.connect(me.signer).mintNSignal(me.address, subgraphNumber0, tokens1000, 0)
          await expect(tx).revertedWith('GNS: Must deposit on a name signal that exists')
        })

        it('reject minting if under slippage', async function () {
          // First publish the subgraph
          await publishNewSubgraph(me, me.address, subgraphNumber0)
          await advanceBlockTo(100)

          // Set slippage to be 1 less than expected result to force reverting
          const { 1: expectedNSignal } = await gns.tokensToNSignal(
            me.address,
            subgraphNumber0,
            tokens1000,
          )
          const tx = gns
            .connect(me.signer)
            .mintNSignal(me.address, subgraphNumber0, tokens1000, expectedNSignal.add(1))
          await expect(tx).revertedWith('Slippage protection')
        })
      })

      describe('burnNSignal()', async function () {
        beforeEach(async () => {
          await publishNewSubgraph(me, me.address, subgraphNumber0)
          await advanceBlockTo(100)
          await mintNSignal(other, me.address, subgraphNumber0, tokens10000)
        })

        it('should withdraw from the name signal curve', async function () {
          await burnNSignal(other, me.address, subgraphNumber0)
        })

        it('should fail when name signal is disabled', async function () {
          await deprecateSubgraph(me, me.address, 0)
          // just test 1 since it will fail
          const tx = gns.connect(me.signer).burnNSignal(me.address, subgraphNumber0, 1, 0)
          await expect(tx).revertedWith('GNS: Cannot be disabled')
        })

        it('should fail when the curator tries to withdraw more nSignal than they have', async function () {
          const tx = gns.connect(me.signer).burnNSignal(
            me.address,
            subgraphNumber0,
            // 1000000 * 10^18 nSignal is a lot, and will cause fail
            toBN('1000000000000000000000000'),
            0,
          )
          await expect(tx).revertedWith('GNS: Curator cannot withdraw more nSignal than they have')
        })

        it('reject burning if under slippage', async function () {
          // Get current curator name signal
          const curatorNSignal = await gns.getCuratorNSignal(
            me.address,
            subgraphNumber0,
            other.address,
          )

          // Withdraw
          const { 1: expectedTokens } = await gns.nSignalToTokens(
            me.address,
            subgraphNumber0,
            curatorNSignal,
          )

          // Force a revert by asking 1 more token than the function will return
          const tx = gns
            .connect(other.signer)
            .burnNSignal(me.address, subgraphNumber0, curatorNSignal, expectedTokens.add(1))
          await expect(tx).revertedWith('Slippage protection')
        })
      })

      describe('withdraw()', async function () {
        beforeEach(async () => {
          await publishNewSubgraph(me, me.address, subgraphNumber0)
          await advanceBlockTo(100)
          await mintNSignal(other, me.address, subgraphNumber0, tokens10000)
        })

        it('should withdraw GRT from a disabled name signal', async function () {
          await deprecateSubgraph(me, me.address, 0)
          await withdraw(other, me.address, subgraphNumber0)
        })

        it('should fail if not disabled', async function () {
          const tx = gns.connect(other.signer).withdraw(me.address, subgraphNumber0)
          await expect(tx).revertedWith('GNS: Name bonding curve must be disabled first')
        })

        it('should fail when there is no more GRT to withdraw', async function () {
          await deprecateSubgraph(me, me.address, 0)
          await withdraw(other, me.address, subgraphNumber0)
          const tx = gns.connect(other.signer).withdraw(me.address, subgraphNumber0)
          await expect(tx).revertedWith('GNS: No more GRT to withdraw')
        })

        it('should fail if the curator has no nSignal', async function () {
          await deprecateSubgraph(me, me.address, 0)
          const tx = gns.connect(me.signer).withdraw(me.address, subgraphNumber0)
          await expect(tx).revertedWith('GNS: Curator must have some nSignal to withdraw GRT')
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
          await publishNewSubgraph(me, me.address, 0)
          await advanceBlockTo(100)

          // State updated
          const curationTaxPercentage = await curation.curationTaxPercentage()

          for (const tokensToDeposit of tokensToDepositMany) {
            const poolOld = await gns.nameSignals(me.address, 0)
            expect(subgraph0.subgraphDeploymentID).eq(poolOld.subgraphDeploymentID)

            const curationTax = toBN(curationTaxPercentage).mul(tokensToDeposit).div(toBN(1000000))
            const expectedNSignal = await calcGNSBondingCurve(
              poolOld.nSignal,
              poolOld.vSignal,
              tokensToDeposit.sub(curationTax),
              poolOld.subgraphDeploymentID,
            )
            const tx = await mintNSignal(me, me.address, 0, tokensToDeposit)
            const receipt = await tx.wait()
            const event: Event = receipt.events.pop()
            const nSignalCreated = event.args['nSignalCreated']
            expect(toRound(expectedNSignal)).eq(toRound(toFloat(nSignalCreated)))
          }
        })

        it('should mint when using the edge case of linear function', async function () {
          // Setup edge case like linear function: 1 vSignal = 1 nSignal = 1 token
          await curation.setMinimumCurationDeposit(toGRT('1'))
          await curation.setDefaultReserveRatio(1000000)
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

          await publishNewSubgraph(me, me.address, 0)
          await advanceBlockTo(100)

          // State updated
          for (const tokensToDeposit of tokensToDepositMany) {
            await mintNSignal(me, me.address, 0, tokensToDeposit)
          }
        })

        describe('setOwnerTaxPercentage', function () {
          const newValue = 10

          it('should set `ownerTaxPercentage`', async function () {
            // Can set if allowed
            await gns.connect(governor.signer).setOwnerTaxPercentage(newValue)
            expect(await gns.ownerTaxPercentage()).eq(newValue)
          })

          it('reject set `ownerTaxPercentage` if out of bounds', async function () {
            const tx = gns.connect(governor.signer).setOwnerTaxPercentage(1000001)
            await expect(tx).revertedWith('Owner tax must be MAX_PPM or less')
          })

          it('reject set `ownerTaxPercentage` if not allowed', async function () {
            const tx = gns.connect(me.signer).setOwnerTaxPercentage(newValue)
            await expect(tx).revertedWith('Caller must be Controller governor')
          })
        })
      })
    })

    describe('Two named subgraphs point to the same subgraph deployment ID', function () {
      it('handle initialization under minimum signal values', async function () {
        await curation.setMinimumCurationDeposit(toGRT('1'))

        // Publish a named subgraph-0 -> subgraphDeployment0
        await gns
          .connect(me.signer)
          .publishNewSubgraph(
            me.address,
            subgraph0.subgraphDeploymentID,
            subgraph0.versionMetadata,
            subgraph0.subgraphMetadata,
          )
        await advanceBlockTo(100)
        // Curate on the first subgraph
        await gns.connect(me.signer).mintNSignal(me.address, 0, toGRT('90000'), 0)

        // Publish a named subgraph-1 -> subgraphDeployment0
        await gns
          .connect(me.signer)
          .publishNewSubgraph(
            me.address,
            subgraph0.subgraphDeploymentID,
            subgraph0.versionMetadata,
            subgraph0.subgraphMetadata,
          )
        await advanceBlockTo(150)
        // Curate on the second subgraph should work
        await gns.connect(me.signer).mintNSignal(me.address, 1, toGRT('10'), 0)
      })
    })
  })

  describe('batch calls', function () {
    it('should publish new subgraph and mint signal in single transaction', async function () {
      // Create a subgraph
      const tx1 = await gns.populateTransaction.publishNewSubgraph(
        me.address,
        subgraph0.subgraphDeploymentID,
        subgraph0.versionMetadata,
        subgraph0.subgraphMetadata,
      )
      // Curate on the subgraph
      const subgraphNumber = await gns.graphAccountSubgraphNumbers(me.address)
      const tx2 = await gns.populateTransaction.mintNSignal(
        me.address,
        subgraphNumber,
        toGRT('90000'),
        0,
      )

      // Batch send transaction
      await gns.connect(me.signer).multicall([tx1.data, tx2.data])
    })

    it('should revert if batching a call to non-authorized function', async function () {
      // Call a forbidden function
      const tx1 = await gns.populateTransaction.setOwnerTaxPercentage(100)

      // Create a subgraph
      const tx2 = await gns.populateTransaction.publishNewSubgraph(
        me.address,
        subgraph0.subgraphDeploymentID,
        subgraph0.versionMetadata,
        subgraph0.subgraphMetadata,
      )

      // Batch send transaction
      const tx = gns.connect(me.signer).multicall([tx1.data, tx2.data])
      await expect(tx).revertedWith('Caller must be Controller governor')
    })

    it('should revert if batching a call to initialize', async function () {
      // Call a forbidden function
      const tx1 = await gns.populateTransaction.initialize(me.address, me.address, me.address)

      // Create a subgraph
      const tx2 = await gns.populateTransaction.publishNewSubgraph(
        me.address,
        subgraph0.subgraphDeploymentID,
        subgraph0.versionMetadata,
        subgraph0.subgraphMetadata,
      )

      // Batch send transaction
      const tx = gns.connect(me.signer).multicall([tx1.data, tx2.data])
      await expect(tx).revertedWith('Caller must be the implementation')
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
        me.address,
        subgraph0.subgraphDeploymentID,
        subgraph0.versionMetadata,
        subgraph0.subgraphMetadata,
      )

      // Batch send transaction
      const tx = gns.connect(me.signer).multicall([bogusPayload, tx2.data])
      await expect(tx).revertedWith('')
    })
  })
})
