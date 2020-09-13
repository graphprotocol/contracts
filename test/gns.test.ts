import { expect } from 'chai'
import { ethers, ContractTransaction, BigNumber, Event } from 'ethers'

import { Gns } from '../build/typechain/contracts/Gns'
import { getAccounts, randomHexBytes, Account, toGRT } from './lib/testHelpers'
import { NetworkFixture } from './lib/fixtures'
import { GraphToken } from '../build/typechain/contracts/GraphToken'
import { Curation } from '../build/typechain/contracts/Curation'

import { toBN, formatGRT } from './lib/testHelpers'

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

  let gns: Gns
  let grt: GraphToken
  let curation: Curation

  const tokens1000 = toGRT('1000')
  const tokens10000 = toGRT('10000')
  const tokens100000 = toGRT('100000')
  const withdrawalPercentage = 50000
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

  const getTokensAndVSig = async (subgraphID: string): Promise<Array<BigNumber>> => {
    const curationPool = await curation.pools(subgraphID)
    const grtTokens = curationPool[0]
    const vSig = await curation.getCurationPoolSignal(subgraphID)
    return [grtTokens, vSig]
  }

  async function calcGNSBondingCurve(
    gnsSupply: BigNumber, // nSignal
    gnsReserveBalance: BigNumber, // vSignal
    gnsReserveRatio: number, // default reserve ratio of GNS
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
    const expectedSignalBN = toGRT(String(expectedSignal))
    // Handle the initialization of the bonding curve
    if (gnsSupply.eq(0)) {
      const minDeposit = await gns.minimumVSignalStake()
      const minSupply = toGRT('1')
      return (
        (await calcGNSBondingCurve(
          minSupply,
          minDeposit,
          gnsReserveRatio,
          depositAmount,
          subgraphID,
        )) + toFloat(gnsSupply)
      )
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
    const tokensBeforeVSigOldCuration = await getTokensAndVSig(subgraph0.subgraphDeploymentID)
    const tokensBeforeOldCuration = tokensBeforeVSigOldCuration[0]
    const vSigBeforeOldCuration = tokensBeforeVSigOldCuration[1]

    // Before stats for the name curve
    const poolBefore = await gns.nameSignals(graphAccount, subgraphNumber)
    const nSigBefore = poolBefore[1]

    // Check what selling all nSignal, which == selling all vSignal, should return for tokens
    const nSignalToTokensResult = await gns.nSignalToTokens(
      graphAccount,
      subgraphNumber,
      nSigBefore,
    )
    const vSignalBurnEstimate = nSignalToTokensResult[0]
    const tokensReceivedEstimate = nSignalToTokensResult[1]

    // since in upgrade, owner must refund fees, we need to actually add this back in
    const feesToAddBackEstimate = nSignalToTokensResult[2]
    const upgradeTokenReturn = tokensReceivedEstimate.add(feesToAddBackEstimate)

    // Get the value for new vSignal that should be created on the new curve
    const newVSignalEstimate = await curation.tokensToSignal(
      subgraphToPublish.subgraphDeploymentID,
      upgradeTokenReturn,
    )

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
        upgradeTokenReturn,
        subgraphToPublish.subgraphDeploymentID,
      )

    // Check curation vSignal old was lowered and tokens too
    const tokensVSigOldCuration = await getTokensAndVSig(subgraph0.subgraphDeploymentID)
    const tokensAfterOldCuration = tokensVSigOldCuration[0]
    const vSigAfterOldCuration = tokensVSigOldCuration[1]
    expect(tokensAfterOldCuration).eq(tokensBeforeOldCuration.sub(upgradeTokenReturn))
    expect(vSigAfterOldCuration).eq(vSigBeforeOldCuration.sub(vSignalBurnEstimate))

    // Check the vSignal of the new curation curve, amd tokens
    const tokensVSigNewCuration = await getTokensAndVSig(subgraphToPublish.subgraphDeploymentID)
    const tokensAfterNewCurve = tokensVSigNewCuration[0]
    const vSigAfterNewCurve = tokensVSigNewCuration[1]
    expect(tokensAfterNewCurve).eq(upgradeTokenReturn)
    expect(vSigAfterNewCurve).eq(newVSignalEstimate)

    // Check the nSignal pool
    const pool = await gns.nameSignals(graphAccount, subgraphNumber)
    const vSigPool = pool[0]
    const nSigAfter = pool[1]
    const deploymentID = pool[2]
    expect(vSigAfterNewCurve).eq(vSigPool).eq(newVSignalEstimate)
    expect(nSigBefore).eq(nSigAfter) // should not change
    expect(deploymentID).eq(subgraphToPublish.subgraphDeploymentID)

    return tx
  }

  const deprecateSubgraph = async (
    account: Account,
    graphAccount: string,
    subgraphNumber0: number,
  ) => {
    const curationBefore = await getTokensAndVSig(subgraph0.subgraphDeploymentID)
    // We can use the whole amount, since in this test suite all vSignal is used to be staked on nSignal
    const tokensBefore = curationBefore[0]
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
    // Check that the owner balance decreased by the withdrawal fee
    const ownerBalanceAfter = await grt.balanceOf(account.address)
    expect(ownerBalanceBefore.sub(tokensBefore.div(toBN(1000000 / withdrawalPercentage)))).eq(
      ownerBalanceAfter,
    )
    // Should be equal since owner pays withdrawal fees
    expect(poolAfter.withdrawableGRT).eq(tokensBefore)
    // Check that deprecated is true
    expect(poolAfter.disabled).eq(true)
    // Check balance of gns increase by withdrawalFees from owner being added
    const gnsBalanceAfter = await grt.balanceOf(gns.address)
    expect(gnsBalanceAfter).eq(poolAfter.withdrawableGRT)
    return tx
  }

  const upgradeNameSignal = async (
    account: Account,
    graphAccount: string,
    subgraphNumber0: number,
    newSubgraphDeplyomentID: string,
  ): Promise<ContractTransaction> => {
    // Before stats for the old vSignal curve
    const tokensBeforeVSigOldCuration = await getTokensAndVSig(subgraph0.subgraphDeploymentID)
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
    const tokensVSigOldCuration = await getTokensAndVSig(subgraph0.subgraphDeploymentID)
    const tokensAfterOldCuration = tokensVSigOldCuration[0]
    const vSigAfterOldCuration = tokensVSigOldCuration[1]
    expect(tokensAfterOldCuration).eq(tokensBeforeOldCuration.sub(upgradeTokenReturn))
    expect(vSigAfterOldCuration).eq(vSigBeforeOldCuration.sub(vSignalBurnEstimate))

    // Check the vSignal of the new curation curve, amd tokens
    const tokensVSigNewCuration = await getTokensAndVSig(newSubgraphDeplyomentID)
    const tokensAfterNewCurve = tokensVSigNewCuration[0]
    const vSigAfterNewCurve = tokensVSigNewCuration[1]
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

  const mintNSignal = async (
    account: Account,
    graphAccount: string,
    subgraphNumber0: number,
    graphTokens: BigNumber,
  ): Promise<ContractTransaction> => {
    // Before checks
    const curationBefore = await getTokensAndVSig(subgraph0.subgraphDeploymentID)
    const tokensBefore = curationBefore[0]
    const vSigBefore = curationBefore[1]
    const poolBefore = await gns.nameSignals(graphAccount, subgraphNumber0)
    const nSigBefore = poolBefore[1]

    // Deposit
    const signals = await gns.tokensToNSignal(graphAccount, subgraphNumber0, graphTokens)
    const vSigEstimate = signals[0]
    const nSigEstimate = signals[1]
    const tx = gns.connect(account.signer).mintNSignal(graphAccount, subgraphNumber0, graphTokens)
    await expect(tx)
      .emit(gns, 'NSignalMinted')
      .withArgs(
        graphAccount,
        subgraphNumber0,
        account.address,
        nSigEstimate,
        vSigEstimate,
        graphTokens,
      )

    const tokensVSig = await getTokensAndVSig(subgraph0.subgraphDeploymentID)
    const tokensAfter = tokensVSig[0]
    const vSigCuration = tokensVSig[1]
    expect(graphTokens.add(tokensBefore)).eq(tokensAfter)

    const poolAfter = await gns.nameSignals(graphAccount, subgraphNumber0)
    const nSig = poolAfter[1]
    expect(vSigCuration).eq(vSigEstimate.add(vSigBefore))
    expect(nSigEstimate.add(nSigBefore)).eq(nSig)

    return tx
  }

  const burnNSignal = async (
    account: Account,
    graphAccount: string,
    subgraphNumber0: number,
  ): Promise<ContractTransaction> => {
    // Before checks
    const curationBefore = await getTokensAndVSig(subgraph0.subgraphDeploymentID)
    const tokensBefore = curationBefore[0]
    const vSigBefore = curationBefore[1]
    const poolBefore = await gns.nameSignals(graphAccount, subgraphNumber0)
    const nSigBefore = poolBefore[1]

    const usersNSigBefore = await gns.getCuratorNSignal(
      graphAccount,
      subgraphNumber0,
      account.address,
    )

    // Withdraw
    const vSigAndTokensEstimate = await gns.nSignalToTokens(
      graphAccount,
      subgraphNumber0,
      usersNSigBefore,
    )
    const vSigEstimate = vSigAndTokensEstimate[0]
    const tokensEstimate = vSigAndTokensEstimate[1]
    const feeEstimate = vSigAndTokensEstimate[2]

    // Do withdraw tx
    const tx = gns
      .connect(account.signer)
      .burnNSignal(graphAccount, subgraphNumber0, usersNSigBefore)
    await expect(tx)
      .emit(gns, 'NSignalBurned')
      .withArgs(
        graphAccount,
        subgraphNumber0,
        account.address,
        usersNSigBefore,
        vSigEstimate,
        tokensEstimate,
      )

    // After checks
    const tokensVSig = await getTokensAndVSig(subgraph0.subgraphDeploymentID)
    const tokensAfter = tokensVSig[0]

    const vSigCurationAfter = tokensVSig[1]
    expect(tokensBefore).eq(tokensAfter.add(tokensEstimate).add(feeEstimate))

    const poolAfter = await gns.nameSignals(graphAccount, subgraphNumber0)
    const nSig = poolAfter[1]
    expect(vSigCurationAfter).eq(vSigBefore.sub(vSigEstimate))
    expect(nSigBefore.sub(usersNSigBefore)).eq(nSig)

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
    // Update withdrawal fee to test the functionality of it in disableNameSignal()
    await curation.connect(governor.signer).setWithdrawalFeePercentage(withdrawalPercentage)
  })

  beforeEach(async function () {
    await fixture.setUp()
  })

  afterEach(async function () {
    await fixture.tearDown()
  })

  describe('Publishing names and versions', function () {
    describe('setDefaultName', function () {
      it('setDefaultName emits the event', async function () {
        const tx = gns
          .connect(me.signer)
          .setDefaultName(me.address, 0, defaultName.nameIdentifier, defaultName.name)
        await expect(tx)
          .emit(gns, 'SetDefaultName')
          .withArgs(subgraph0.graphAccount.address, 0, defaultName.nameIdentifier, defaultName.name)
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
        await curation.connect(me.signer).mint(subgraph1.subgraphDeploymentID, tokens1000)
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
        await mintNSignal(other, me.address, subgraphNumber0, tokens10000)
      })
      it('should fail when name signal is disabled', async function () {
        await publishNewSubgraph(me, me.address, subgraphNumber0)
        await deprecateSubgraph(me, me.address, 0)
        const tx = gns.connect(me.signer).mintNSignal(me.address, subgraphNumber0, tokens1000)
        await expect(tx).revertedWith('GNS: Cannot be disabled')
      })
      it('should fail if you try to deposit on a non existing name', async function () {
        const tx = gns.connect(me.signer).mintNSignal(me.address, subgraphNumber0, tokens1000)
        await expect(tx).revertedWith('GNS: Must deposit on a name signal that exists')
      })
    })
    describe('burnNSignal()', async function () {
      beforeEach(async () => {
        await publishNewSubgraph(me, me.address, subgraphNumber0)
        await mintNSignal(other, me.address, subgraphNumber0, tokens10000)
      })
      it('should withdraw from the name signal curve', async function () {
        await burnNSignal(other, me.address, subgraphNumber0)
      })
      it('should fail when name signal is disabled', async function () {
        await deprecateSubgraph(me, me.address, 0)
        // just test 1 since it will fail
        const tx = gns.connect(me.signer).burnNSignal(me.address, subgraphNumber0, 1)
        await expect(tx).revertedWith('GNS: Cannot be disabled')
      })
      it('should fail when the curator tries to withdraw more nSignal than they have', async function () {
        const tx = gns.connect(me.signer).burnNSignal(
          me.address,
          subgraphNumber0,
          // 1000000 * 10^18 nSignal is a lot, and will cause fail
          toBN('1000000000000000000000000'),
        )
        await expect(tx).revertedWith('GNS: Curator cannot withdraw more nSignal than they have')
      })
    })
    describe('withdraw()', async function () {
      beforeEach(async () => {
        await publishNewSubgraph(me, me.address, subgraphNumber0)
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
    describe('setMinimumVsignal', function () {
      const newValue = toGRT('100')
      it('should set `minimumVSignalStake`', async function () {
        // Can set if allowed
        await gns.connect(governor.signer).setMinimumVsignal(newValue)
        expect(await gns.minimumVSignalStake()).eq(newValue)
      })

      it('reject set `minimumVSignalStake` if out of bounds', async function () {
        const tx = gns.connect(governor.signer).setMinimumVsignal(0)
        await expect(tx).revertedWith('Minimum vSignal cannot be 0')
      })

      it('reject set `minimumVSignalStake` if not allowed', async function () {
        const tx = gns.connect(me.signer).setMinimumVsignal(newValue)
        await expect(tx).revertedWith('Caller must be Controller governor')
      })
    })
    describe('multiple minting', async function () {
      it('should mint less signal every time due to the bonding curve', async function () {
        const tokensToDepositMany = [
          toGRT('1000'), // should mint if we start with number above minimum deposit
          toGRT('1000'), // every time it should mint less GST due to bonding curve...
          toGRT('1'), // should mint below minimum deposit
          toGRT('1000'),
          toGRT('1000'),
          toGRT('2000'),
          toGRT('2000'),
          toGRT('123'),
        ]
        await publishNewSubgraph(me, me.address, 0)
        // Check the nSignal pool

        // State updated
        for (const tokensToDeposit of tokensToDepositMany) {
          const poolOld = await gns.nameSignals(me.address, 0)
          const vSig = poolOld[0]
          const nSig = poolOld[1]
          const deploymentID = poolOld[2]
          const reserveRatio = poolOld[3]
          expect(subgraph0.subgraphDeploymentID).eq(deploymentID)
          const expectedNSignal = await calcGNSBondingCurve(
            nSig,
            vSig,
            reserveRatio,
            tokensToDeposit,
            deploymentID,
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
        await gns.setMinimumVsignal(toGRT('1'))
        // note - reserve ratio is already set to 1000000 in GNS

        const tokensToDepositMany = [
          toGRT('1000'), // should mint if we start with number above minimum deposit
          toGRT('1000'), // every time it should mint less GST due to bonding curve...
          toGRT('1000'),
          toGRT('1000'),
          toGRT('2000'),
          toGRT('2000'),
          toGRT('123'),
          toGRT('1'), // should mint below minimum deposit
        ]

        await publishNewSubgraph(me, me.address, 0)

        // State updated
        for (const tokensToDeposit of tokensToDepositMany) {
          const tx = await mintNSignal(me, me.address, 0, tokensToDeposit)
          const receipt = await tx.wait()
          const event: Event = receipt.events.pop()
          const nSignalCreated = event.args['nSignalCreated']
          // we compare 1:1 ratio. Its implied that vSignal is 1 as well (1:1:1)
          expect(tokensToDeposit).eq(nSignalCreated)
        }
    describe('setDeprecateFeePercentage', function () {
      const newValue = 10
      it('should set `minimumVSignalStake`', async function () {
        // Can set if allowed
        await gns.connect(governor.signer).setDeprecateFeePercentage(newValue)
        expect(await gns.deprecateFeePercentage()).eq(newValue)
      })

      it('reject set `minimumVSignalStake` if out of bounds', async function () {
        const tx = gns.connect(governor.signer).setDeprecateFeePercentage(101)
        await expect(tx).revertedWith('Deprecate fee must be 100 or less')
      })

      it('reject set `minimumVSignalStake` if not allowed', async function () {
        const tx = gns.connect(me.signer).setDeprecateFeePercentage(newValue)
        await expect(tx).revertedWith('Caller must be Controller governor')
      })
    })
  })
})
