import { expect } from 'chai'
import { ethers, ContractTransaction, BigNumber } from 'ethers'

import { Gns } from '../build/typechain/contracts/Gns'
import { getAccounts, randomHexBytes, Account, toGRT } from './lib/testHelpers'
import { NetworkFixture } from './lib/fixtures'
import { GraphToken } from '../build/typechain/contracts/GraphToken'
import { Curation } from '../build/typechain/contracts/Curation'

import { toBN } from './lib/testHelpers'

interface Subgraph {
  graphAccount: Account
  subgraphDeploymentID: string
  name: string
  nameIdentifier: string
  metadataHash: string
}

describe('GNS', () => {
  let me: Account
  let other: Account
  let governor: Account

  let fixture: NetworkFixture

  let gns: Gns
  let grt: GraphToken
  let curation: Curation

  const name = 'graph'
  const tokens1000 = toGRT('1000')
  const tokens10000 = toGRT('10000')
  const withdrawalPercentage = 50000
  let subgraph1: Subgraph

  const createSubgraph = (account: Account): Subgraph => {
    return {
      graphAccount: account,
      subgraphDeploymentID: randomHexBytes(),
      name: name,
      nameIdentifier: ethers.utils.namehash(name),
      metadataHash: randomHexBytes(),
    }
  }

  const getTokensAndVSig = async (subgraphID: string): Promise<Array<BigNumber>> => {
    const curationPool = await curation.pools(subgraphID)
    const grtTokens = curationPool[0]
    const vSig = await curation.getCurationPoolSignal(subgraphID)
    return [grtTokens, vSig]
  }

  const publishNewSubgraph = async (
    account: Account,
    graphAccount: string,
    subgraphNumber0: number,
    subgraphToPublish = subgraph1, // Defaults to subgraph created in before()
  ): Promise<ContractTransaction> => {
    const tx = gns
      .connect(account.signer)
      .publishNewSubgraph(
        graphAccount,
        subgraphToPublish.subgraphDeploymentID,
        subgraphToPublish.nameIdentifier,
        subgraphToPublish.name,
        subgraphToPublish.metadataHash,
      )
    await expect(tx)
      .emit(gns, 'SubgraphPublished')
      .withArgs(
        subgraphToPublish.graphAccount.address,
        subgraphNumber0,
        subgraphToPublish.subgraphDeploymentID,
        0,
        subgraphToPublish.nameIdentifier,
        subgraphToPublish.name,
        subgraphToPublish.metadataHash,
      )
    return tx
  }
  const publishNewVersion = async (
    account: Account,
    graphAccount: string,
    subgraphNumber0: number,
    subgraphToPublish = subgraph1, // Defaults to subgraph created in before()
  ) =>
    gns
      .connect(account.signer)
      .publishNewVersion(
        graphAccount,
        subgraphNumber0,
        subgraphToPublish.subgraphDeploymentID,
        subgraphToPublish.nameIdentifier,
        subgraphToPublish.name,
        subgraphToPublish.metadataHash,
      )

  const deprecateSubgraph = async (
    account: Account,
    graphAccount: string,
    subgraphNumber0: number,
  ) => gns.connect(account.signer).deprecateSubgraph(graphAccount, subgraphNumber0)

  const enableNameSignal = async (
    account: Account,
    graphAccount: string,
    subgraphNumber0: number,
    graphTokens: BigNumber,
  ): Promise<ContractTransaction> => {
    await publishNewSubgraph(account, graphAccount, subgraphNumber0)
    const signals = await gns.tokensToNSignal(graphAccount, subgraphNumber0, graphTokens)
    const vSigEstimate = signals[0]
    const nSigEstimate = signals[1]

    const tx = gns
      .connect(account.signer)
      .enableNameSignal(graphAccount, subgraphNumber0, graphTokens)
    await expect(tx)
      .emit(gns, 'NameSignalEnabled')
      .withArgs(
        graphAccount,
        subgraphNumber0,
        vSigEstimate,
        nSigEstimate,
        subgraph1.subgraphDeploymentID,
        1000000,
      )

    const tokensVSig = await getTokensAndVSig(subgraph1.subgraphDeploymentID)
    const tokensAfter = tokensVSig[0]
    const vSigCuration = tokensVSig[1]
    expect(graphTokens).eq(tokensAfter)

    const pool = await gns.nameSignals(graphAccount, subgraphNumber0)
    const vSigPool = pool[0]
    const nSig = pool[1]
    expect(vSigCuration).eq(vSigPool).eq(vSigEstimate)
    expect(nSigEstimate).eq(nSig)
    const deploymentID = pool[2]
    const reserveRatio = pool[3]

    return tx
  }

  const upgradeNameSignal = async (
    account: Account,
    graphAccount: string,
    subgraphNumber0: number,
    newSubgraphDeplyomentID: string,
  ): Promise<ContractTransaction> => {
    // Before stats for the old vSignal curve
    const tokensBeforeVSigOldCuration = await getTokensAndVSig(subgraph1.subgraphDeploymentID)
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
    const tokensVSigOldCuration = await getTokensAndVSig(subgraph1.subgraphDeploymentID)
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
    const curationBefore = await getTokensAndVSig(subgraph1.subgraphDeploymentID)
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
      .withArgs(graphAccount, subgraphNumber0, other.address, nSigEstimate, vSigEstimate)

    const tokensVSig = await getTokensAndVSig(subgraph1.subgraphDeploymentID)
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
    const curationBefore = await getTokensAndVSig(subgraph1.subgraphDeploymentID)
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
    const tokensVSig = await getTokensAndVSig(subgraph1.subgraphDeploymentID)
    const tokensAfter = tokensVSig[0]

    const vSigCurationAfter = tokensVSig[1]
    expect(tokensBefore).eq(tokensAfter.add(tokensEstimate).add(feeEstimate))

    const poolAfter = await gns.nameSignals(graphAccount, subgraphNumber0)
    const nSig = poolAfter[1]
    expect(vSigCurationAfter).eq(vSigBefore.sub(vSigEstimate))
    expect(nSigBefore.sub(usersNSigBefore)).eq(nSig)

    return tx
  }

  const disableNameSignal = async (
    account: Account,
    graphAccount: string,
    subgraphNumber0: number,
  ): Promise<ContractTransaction> => {
    const curationBefore = await getTokensAndVSig(subgraph1.subgraphDeploymentID)
    // We can use the whole amount, since in this test suite all vSignal is used to be staked on nSignal
    const tokensBefore = curationBefore[0]
    const ownerBalanceBefore = await grt.balanceOf(account.address)

    // Do tx and check event
    const tx = gns.connect(account.signer).disableNameSignal(graphAccount, subgraphNumber0)
    await expect(tx)
      .emit(gns, 'NameSignalDisabled')
      .withArgs(graphAccount, subgraphNumber0, tokensBefore)

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
    subgraph1 = createSubgraph(me)
    // Give some funds to the signers and approve gns contract to use funds on signers behalf
    await grt.connect(governor.signer).mint(me.address, tokens10000)
    await grt.connect(governor.signer).mint(other.address, tokens10000)
    await grt.connect(me.signer).approve(gns.address, tokens10000)
    await grt.connect(me.signer).approve(curation.address, tokens10000)
    await grt.connect(other.signer).approve(gns.address, tokens10000)
    await grt.connect(other.signer).approve(curation.address, tokens10000)

    // Update withdrawal fee to test the functionality of it in disableNameSignal()
    await curation.connect(governor.signer).setWithdrawalFeePercentage(withdrawalPercentage)
  })

  beforeEach(async function () {
    await fixture.setUp()
  })

  afterEach(async function () {
    await fixture.tearDown()
  })

  describe('Publishing names', function () {
    describe('isPublished', function () {
      it('should return if the subgraph is published', async function () {
        expect(await gns.isPublished(subgraph1.graphAccount.address, 0)).eq(false)
        await publishNewSubgraph(me, me.address, 0)
        expect(await gns.isPublished(subgraph1.graphAccount.address, 0)).eq(true)
      })
    })

    describe('publishNewSubgraph', async function () {
      it('should publish a new subgraph and first version with it', async function () {
        await publishNewSubgraph(me, me.address, 0)
        // State updated
        const deploymentID = await gns.subgraphs(subgraph1.graphAccount.address, 0)
        expect(subgraph1.subgraphDeploymentID).eq(deploymentID)
      })

      it('should publish a new subgraph with an incremented value', async function () {
        await publishNewSubgraph(me, me.address, 0)
        const subgraph2 = createSubgraph(me)
        await publishNewSubgraph(me, me.address, 1, subgraph2)
        const deploymentID = await gns.subgraphs(subgraph2.graphAccount.address, 1)
        expect(subgraph2.subgraphDeploymentID).eq(deploymentID)
      })

      it('should reject publish if not sent from owner', async function () {
        const tx = publishNewSubgraph(other, me.address, 0)
        await expect(tx).revertedWith('GNS: Only graph account owner can call')
      })

      it('should prevent subgraphDeploymentID of 0 to be used', async function () {
        const tx = gns
          .connect(me.signer)
          .publishNewSubgraph(
            subgraph1.graphAccount.address,
            ethers.constants.HashZero,
            subgraph1.nameIdentifier,
            subgraph1.name,
            subgraph1.metadataHash,
          )
        await expect(tx).revertedWith('GNS: Cannot set to 0 in publish')
      })
    })

    describe('publishNewVersion', async function () {
      it('should publish a new version on an existing subgraph', async function () {
        await publishNewSubgraph(me, me.address, 0)
        const tx = publishNewVersion(me, me.address, 0)

        // Event being emitted indicates version has been updated
        await expect(tx)
          .emit(gns, 'SubgraphPublished')
          .withArgs(
            subgraph1.graphAccount.address,
            0,
            subgraph1.subgraphDeploymentID,
            0,
            subgraph1.nameIdentifier,
            subgraph1.name,
            subgraph1.metadataHash,
          )
      })

      it('should reject publishing a version to a numbered subgraph that does not exist', async function () {
        const tx = publishNewVersion(me, me.address, 0)
        await expect(tx).revertedWith(
          'GNS: Cant publish a version directly for a subgraph that wasnt created yet',
        )
      })

      it('reject if not the owner', async function () {
        await publishNewSubgraph(me, me.address, 0)
        const tx = publishNewVersion(other, me.address, 0)
        await expect(tx).revertedWith('GNS: Only graph account owner can call')
      })
    })

    describe('deprecateSubgraph', async function () {
      it('should deprecate a subgraph', async function () {
        await publishNewSubgraph(me, me.address, 0)
        const tx = deprecateSubgraph(me, me.address, 0)
        await expect(tx).emit(gns, 'SubgraphDeprecated').withArgs(subgraph1.graphAccount.address, 0)

        // State updated
        const deploymentID = await gns.subgraphs(subgraph1.graphAccount.address, 0)
        expect(ethers.constants.HashZero).eq(deploymentID)
      })

      it('should allow a deprecated subgraph to be republished', async function () {
        await publishNewSubgraph(me, me.address, 0)
        await deprecateSubgraph(me, me.address, 0)
        const tx = publishNewVersion(me, me.address, 0)

        // Event being emitted indicates version has been updated
        await expect(tx)
          .emit(gns, 'SubgraphPublished')
          .withArgs(
            subgraph1.graphAccount.address,
            0,
            subgraph1.subgraphDeploymentID,
            0,
            subgraph1.nameIdentifier,
            subgraph1.name,
            subgraph1.metadataHash,
          )
      })

      it('reject if the subgraph does not exist', async function () {
        const tx = deprecateSubgraph(me, me.address, 0)
        await expect(tx).revertedWith('GNS: Cannot deprecate a subgraph which does not exist')
        const tx2 = deprecateSubgraph(me, me.address, 2340)
        await expect(tx2).revertedWith('GNS: Cannot deprecate a subgraph which does not exist')
      })

      it('reject deprecate if not the owner', async function () {
        await publishNewSubgraph(me, me.address, 0)
        const tx = deprecateSubgraph(other, me.address, 0)
        await expect(tx).revertedWith('GNS: Only graph account owner can call')
      })
    })
  })
  describe('Curating on names', async function () {
    const subgraphNumber0 = 0
    describe('enableNameSignal()', async function () {
      it('should create a name signal', async function () {
        await enableNameSignal(me, me.address, subgraphNumber0, tokens1000)
        const vSignals = await getTokensAndVSig(subgraph1.subgraphDeploymentID)
        const pool = await gns.connect(me.signer).nameSignals(me.address, subgraphNumber0)
        expect(
          vSignals[1].eq(pool[0]),
          'stored vSignals should match upon brand new creation, where there was no vSignal there before',
        )
      })
      it('should fail to create a name signal on the same subgraph number', async function () {
        await enableNameSignal(me, me.address, subgraphNumber0, tokens1000)
        const tx = gns.connect(me.signer).enableNameSignal(me.address, subgraphNumber0, tokens1000)
        await expect(tx).revertedWith(
          'GNS: Enable name signal was already called for this subgraph number',
        )
      })
      it('should fail if the subgraphDeploymentID was not set by the owner', async function () {
        const tx = gns.connect(me.signer).enableNameSignal(me.address, subgraphNumber0, tokens1000)
        await expect(tx).revertedWith(
          'GNS: Cannot enable name signal on a subgraph without a deployment ID',
        )
      })
      it('should fail if not called by name owner', async function () {
        const tx = gns
          .connect(other.signer)
          .enableNameSignal(me.address, subgraphNumber0, tokens1000)
        await expect(tx).revertedWith('GNS: Only graph account owner can call')
      })
    })
    describe('mintNSignal()', async function () {
      it('should deposit into the name signal curve', async function () {
        await enableNameSignal(me, me.address, subgraphNumber0, tokens1000)
        await mintNSignal(other, me.address, subgraphNumber0, tokens10000)
      })
      it('should fail when name signal is deprecated', async function () {
        await enableNameSignal(me, me.address, subgraphNumber0, tokens1000)
        await disableNameSignal(me, me.address, subgraphNumber0)
        const tx = gns.connect(me.signer).mintNSignal(me.address, subgraphNumber0, tokens1000)
        await expect(tx).revertedWith('GNS: Cannot be disabled')
      })
      it('should fail if you try to deposit on a non existing name', async function () {
        const tx = gns.connect(me.signer).mintNSignal(me.address, subgraphNumber0, tokens1000)
        await expect(tx).revertedWith('GNS: Must deposit on a name signal that exists')
      })
      it('should fail if the owner updated the subgraph number deployment ID, but not the name signal', async function () {
        const subgraph2 = createSubgraph(me)
        await enableNameSignal(me, me.address, subgraphNumber0, tokens1000)
        await publishNewVersion(me, me.address, subgraphNumber0, subgraph2)
        const tx = gns.connect(me.signer).mintNSignal(me.address, subgraphNumber0, tokens1000)
        await expect(tx).revertedWith(
          'GNS: Name owner updated version without updating name signal',
        )
      })
    })
    describe('burnNSignal()', async function () {
      beforeEach(async () => {
        await enableNameSignal(me, me.address, subgraphNumber0, tokens1000)
        await mintNSignal(other, me.address, subgraphNumber0, tokens10000)
      })
      it('should withdraw from the name signal curve', async function () {
        await burnNSignal(other, me.address, subgraphNumber0)
      })
      it('should fail when name signal is disabled', async function () {
        await disableNameSignal(me, me.address, subgraphNumber0)
        // just test 1 since it will fail
        const tx = gns.connect(me.signer).burnNSignal(me.address, subgraphNumber0, 1)
        await expect(tx).revertedWith('GNS: Cannot be disabled')
      })
      it('should fail if the owner updated the subgraph number deployment ID, but not the name signal', async function () {
        const subgraph2 = createSubgraph(me)
        await publishNewVersion(me, me.address, subgraphNumber0, subgraph2)
        const tx = gns.connect(me.signer).burnNSignal(me.address, subgraphNumber0, tokens1000)
        await expect(tx).revertedWith(
          'GNS: Name owner updated version without updating name signal',
        )
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
    describe('upgradeNameSignal()', async function () {
      const subgraph2 = createSubgraph(me)

      beforeEach(async () => {
        await enableNameSignal(me, me.address, subgraphNumber0, tokens1000)
        await mintNSignal(other, me.address, subgraphNumber0, tokens10000)
      })

      it('should upgrade the name signal and migrate old vSignal to new vSignal', async function () {
        await publishNewVersion(me, me.address, subgraphNumber0, subgraph2)
        await upgradeNameSignal(me, me.address, subgraphNumber0, subgraph2.subgraphDeploymentID)
      })
      it('should fail when subgraph deployment ids do not match', async function () {
        const subgraph3 = createSubgraph(me)
        await publishNewVersion(me, me.address, subgraphNumber0, subgraph2)
        const tx = gns
          .connect(me.signer)
          .upgradeNameSignal(me.address, subgraphNumber0, subgraph3.subgraphDeploymentID)
        await expect(tx).revertedWith('GNS: Owner did not update subgraph deployment ID')
      })
      it('should fail when upgrade tries to point to a pre-curated', async function () {
        await publishNewVersion(me, me.address, subgraphNumber0, subgraph2)
        await curation.connect(me.signer).mint(subgraph2.subgraphDeploymentID, tokens1000)
        const tx = gns
          .connect(me.signer)
          .upgradeNameSignal(me.address, subgraphNumber0, subgraph2.subgraphDeploymentID)
        await expect(tx).revertedWith(
          'GNS: Owner cannot point to a subgraphID that has been pre-curated',
        )
      })
      it('should fail when trying to upgrade when there is no nSignal', async function () {
        await burnNSignal(me, me.address, subgraphNumber0)
        await burnNSignal(other, me.address, subgraphNumber0)
        await publishNewVersion(me, me.address, subgraphNumber0, subgraph2)
        const tx = gns
          .connect(me.signer)
          .upgradeNameSignal(me.address, subgraphNumber0, subgraph2.subgraphDeploymentID)
        await expect(tx).revertedWith(
          'GNS: There must be nSignal on this subgraph for curve math to work',
        )
      })
      it('should fail when name signal is disabled', async function () {
        await disableNameSignal(me, me.address, subgraphNumber0)
        await publishNewVersion(me, me.address, subgraphNumber0, subgraph2)
        const tx = gns
          .connect(me.signer)
          .upgradeNameSignal(me.address, subgraphNumber0, subgraph2.subgraphDeploymentID)
        await expect(tx).revertedWith('GNS: Cannot be disabled')
      })
      it('should fail if not called by name owner', async function () {
        await publishNewVersion(me, me.address, subgraphNumber0, subgraph2)
        const tx = gns
          .connect(other.signer)
          .upgradeNameSignal(me.address, subgraphNumber0, subgraph2.subgraphDeploymentID)
        await expect(tx).revertedWith('GNS: Only graph account owner can call')
      })
    })
    describe('disableNameSignal()', async function () {
      it('should deprecate the name signal', async function () {
        await enableNameSignal(me, me.address, subgraphNumber0, tokens1000)
        await disableNameSignal(me, me.address, subgraphNumber0)
      })
      it('should fail if the owner updated the subgraph number deployment ID, but not the name signal', async function () {
        await enableNameSignal(me, me.address, subgraphNumber0, tokens1000)
        const subgraph2 = createSubgraph(me)
        await publishNewVersion(me, me.address, subgraphNumber0, subgraph2)
        const tx = gns.connect(me.signer).disableNameSignal(me.address, subgraphNumber0)
        await expect(tx).revertedWith(
          'GNS: Name owner updated version without updating name signal',
        )
      })
      it('should fail upon trying to deprecate twice', async function () {
        await enableNameSignal(me, me.address, subgraphNumber0, tokens1000)
        await disableNameSignal(me, me.address, subgraphNumber0)
        const tx = gns.connect(me.signer).disableNameSignal(me.address, subgraphNumber0)
        await expect(tx).revertedWith('GNS: Cannot be disabled twice')
      })
      it('should fail if not called by name owner', async function () {
        await enableNameSignal(me, me.address, subgraphNumber0, tokens1000)
        const tx = gns.connect(other.signer).disableNameSignal(me.address, subgraphNumber0)
        await expect(tx).revertedWith('GNS: Only graph account owner can call')
      })
    })
    describe('withdraw()', async function () {
      beforeEach(async () => {
        await enableNameSignal(me, me.address, subgraphNumber0, tokens1000)
        await mintNSignal(other, me.address, subgraphNumber0, tokens10000)
        await disableNameSignal(me, me.address, subgraphNumber0)
      })
      it('should withdraw GRT from a disabled name signal', async function () {
        await withdraw(other, me.address, subgraphNumber0)
      })
      it('should fail when there is no more GRT to withdraw', async function () {
        await withdraw(other, me.address, subgraphNumber0)
        await withdraw(me, me.address, subgraphNumber0)
        const tx = gns.connect(other.signer).withdraw(me.address, subgraphNumber0)
        await expect(tx).revertedWith('GNS: No more GRT to withdraw')
      })
      it('should fail if the curator has no nSignal', async function () {
        await withdraw(me, me.address, subgraphNumber0)
        const tx = gns.connect(me.signer).withdraw(me.address, subgraphNumber0)
        await expect(tx).revertedWith('GNS: Curator must have some nSignal to withdraw GRT')
      })
    })
    describe('setMinimumVsignal', function () {
      const newValue = toGRT('100')
      it('should set `minimumVSignalStake`', async function () {
        // Can set if allowed
        const newValue = toGRT('100')
        await gns.connect(governor.signer).setMinimumVsignal(newValue)
        expect(await gns.minimumVSignalStake()).eq(newValue)
      })

      it('reject set `minimumVSignalStake` if out of bounds', async function () {
        const tx = gns.connect(governor.signer).setMinimumVsignal(0)
        await expect(tx).revertedWith('Minimum vSignal cannot be 0')
      })

      it('reject set `minimumVSignalStake` if not allowed', async function () {
        const tx = gns.connect(me.signer).setMinimumVsignal(newValue)
        await expect(tx).revertedWith('Only Governor can call')
      })
    })
  })
})
