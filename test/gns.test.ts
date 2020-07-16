import { expect } from 'chai'
import { ethers, Signer } from 'ethers'

import { Gns } from '../build/typechain/contracts/Gns'
import { getAccounts, randomHexBytes, Account } from './lib/testHelpers'
import { NetworkFixture } from './lib/fixtures'

describe('GNS', () => {
  let me: Account
  let other: Account
  let governor: Account

  let fixture: NetworkFixture

  let gns: Gns

  const name = 'graph'

  const newSubgraph = {
    graphAccount: me,
    subgraphDeploymentID: randomHexBytes(),
    name: name,
    nameIdentifier: ethers.utils.namehash(name),
    metadataHash: '0xeb50d096ba95573ae31640e38e4ef64fd02eec174f586624a37ea04e7bd8c751', // TODO - make this randomHexBytes
  }

  const publishNewSubgraph = (signer: Signer, graphAccount: string) =>
    gns
      .connect(signer)
      .publishNewSubgraph(
        graphAccount,
        newSubgraph.subgraphDeploymentID,
        newSubgraph.nameIdentifier,
        newSubgraph.name,
        newSubgraph.metadataHash,
      )

  const publishNewVersion = (signer: Signer, graphAccount: string, subgraphNumber: number) =>
    gns
      .connect(signer)
      .publishNewVersion(
        graphAccount,
        subgraphNumber,
        newSubgraph.subgraphDeploymentID,
        newSubgraph.nameIdentifier,
        newSubgraph.name,
        newSubgraph.metadataHash,
      )

  const deprecateSubgraph = (signer: Signer, graphAccount: string, subgraphNumber: number) =>
    gns.connect(signer).deprecateSubgraph(graphAccount, subgraphNumber)

  before(async function () {
    ;[me, other, governor] = await getAccounts()
    fixture = new NetworkFixture()
    ;({ gns } = await fixture.load(governor.signer))
    newSubgraph.graphAccount = me
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
        expect(await gns.isPublished(newSubgraph.graphAccount.address, 0)).eq(false)
        await publishNewSubgraph(me.signer, me.address)
        expect(await gns.isPublished(newSubgraph.graphAccount.address, 0)).eq(true)
      })
    })

    describe('publishNewSubgraph', async function () {
      it('should publish a new subgraph and first version with it', async function () {
        const tx = publishNewSubgraph(me.signer, me.address)
        await expect(tx)
          .emit(gns, 'SubgraphPublished')
          .withArgs(
            newSubgraph.graphAccount.address,
            0,
            newSubgraph.subgraphDeploymentID,
            0,
            newSubgraph.nameIdentifier,
            newSubgraph.name,
            newSubgraph.metadataHash,
          )

        // State updated
        const deploymentID = await gns.subgraphs(newSubgraph.graphAccount.address, 0)
        expect(newSubgraph.subgraphDeploymentID).eq(deploymentID)
      })

      it('should publish a new subgraph with an incremented value', async function () {
        // We publish the exact same subgraph here, with same name, This is okay
        // in the contract, but the subgraph would make decisions on how to resolve this
        await publishNewSubgraph(me.signer, me.address)
        await publishNewSubgraph(me.signer, me.address)
        const deploymentID = await gns.subgraphs(newSubgraph.graphAccount.address, 1)
        expect(newSubgraph.subgraphDeploymentID).eq(deploymentID)
      })

      it('should reject publish if not sent from owner', async function () {
        const tx = publishNewSubgraph(other.signer, me.address)
        await expect(tx).revertedWith('GNS: Only graph account owner can call')
      })

      it('should prevent subgraphDeploymentID of 0 to be used', async function () {
        const tx = gns
          .connect(me.signer)
          .publishNewSubgraph(
            newSubgraph.graphAccount.address,
            ethers.constants.HashZero,
            newSubgraph.nameIdentifier,
            newSubgraph.name,
            newSubgraph.metadataHash,
          )
        await expect(tx).revertedWith('GNS: Cannot set to 0 in publish')
      })
    })

    describe('publishNewVersion', async function () {
      it('should publish a new version on an existing subgraph', async function () {
        await publishNewSubgraph(me.signer, me.address)
        const tx = publishNewVersion(me.signer, me.address, 0)

        // Event being emitted indicates version has been updated
        await expect(tx)
          .emit(gns, 'SubgraphPublished')
          .withArgs(
            newSubgraph.graphAccount.address,
            0,
            newSubgraph.subgraphDeploymentID,
            0,
            newSubgraph.nameIdentifier,
            newSubgraph.name,
            newSubgraph.metadataHash,
          )
      })

      it('should reject publishing a version to a numbered subgraph that does not exist', async function () {
        const tx = publishNewVersion(me.signer, me.address, 0)
        await expect(tx).revertedWith(
          'GNS: Cant publish a version directly for a subgraph that wasnt created yet',
        )
      })

      it('reject if not the owner', async function () {
        await publishNewSubgraph(me.signer, me.address)
        const tx = publishNewVersion(other.signer, me.address, 0)
        await expect(tx).revertedWith('GNS: Only graph account owner can call')
      })
    })

    describe('deprecateSubgraph', async function () {
      it('should deprecate a subgraph', async function () {
        await publishNewSubgraph(me.signer, me.address)
        const tx = deprecateSubgraph(me.signer, me.address, 0)
        await expect(tx)
          .emit(gns, 'SubgraphDeprecated')
          .withArgs(newSubgraph.graphAccount.address, 0)

        // State updated
        const deploymentID = await gns.subgraphs(newSubgraph.graphAccount.address, 0)
        expect(ethers.constants.HashZero).eq(deploymentID)
      })

      it('should allow a deprecated subgraph to be republished', async function () {
        await publishNewSubgraph(me.signer, me.address)
        await deprecateSubgraph(me.signer, me.address, 0)
        const tx = publishNewVersion(me.signer, me.address, 0)

        // Event being emitted indicates version has been updated
        await expect(tx)
          .emit(gns, 'SubgraphPublished')
          .withArgs(
            newSubgraph.graphAccount.address,
            0,
            newSubgraph.subgraphDeploymentID,
            0,
            newSubgraph.nameIdentifier,
            newSubgraph.name,
            newSubgraph.metadataHash,
          )
      })

      it('reject if the subgraph does not exist', async function () {
        const tx = deprecateSubgraph(me.signer, me.address, 0)
        await expect(tx).revertedWith('GNS: Cannot deprecate a subgraph which does not exist')
        const tx2 = deprecateSubgraph(me.signer, me.address, 2340)
        await expect(tx2).revertedWith('GNS: Cannot deprecate a subgraph which does not exist')
      })

      it('reject if not the owner', async function () {
        await publishNewSubgraph(me.signer, me.address)
        const tx = deprecateSubgraph(other.signer, me.address, 0)
        await expect(tx).revertedWith('GNS: Only graph account owner can call')
      })
    })
  })
  describe('Curating on names', async function () {
    describe('createNameSignal()', async function () {
      it('should create a name signal', async function () {
        // todo
        // check event
      })
      it('should fail to create a name signal on the same subgraph number', async function () {
        // todo
      })
      it('should fail when the subgraph was previously deprecated, and all nSignal withdrawn', async function () {
        // todo
      })
      it('should fail when the subgraph has no nSignal left, but was created and not deprecated', async function () {
        // todo
      })
      it('should fail if the subgraphDeploymentID was not set by the owner', async function () {
        // todo
      })
    })
    describe('upgradeNameSignal()', async function () {
      it('should upgrade the name signal and migrate old vSignal to new vSignal', async function () {
        // todo
        // check event
      })
      it('should fail when subgraph deployment ids do not match', async function () {
        // todo
      })
      it('should fail when upgrade tries to point to a pre-curated', async function () {
        // todo
      })
      it('should fail when trying to upgrade when there is no nSignal', async function () {
        // todo
      })
      it('should fail when name signal is deprecated', async function () {
        // todo
      })
    })
    describe('depositIntoNameSignal()', async function () {
      it('should deposit into the name signal curve', async function () {
        // todo
        // check event
      })
      it('should fail when name signal is deprecated', async function () {
        // todo
      })
      it('should fail if the owner updated the subgraph number deployment ID, but not the name signal', async function () {
        // todo
      })
    })
    describe('withdrawFromNameSignal()', async function () {
      it('should withdraw from the name signal curve', async function () {
        // todo
        // check event
      })
      it('should fail when name signal is deprecated', async function () {
        // todo
      })
      it('should fail when the curator tries to withdraw more nSignal than they have', async function () {
        // todo
      })
      it('should', async function () {
        // todo
      })
      it('should', async function () {
        // todo
      })
    })
    describe('deprecateNameSignal()', async function () {
      it('should deprecate the name signal', async function () {
        // todo
        // check event
      })
      it('should fail upon trying to deprecate twice', async function () {
        // todo
      })
    })
    describe('withdrawGRT()', async function () {
      it('should withdraw GRT from a deprecated name signal', async function () {
        // todo
        // check event
      })
      it('should fail when there is no more GRT to withdraw', async function () {
        // todo
      })
      it('should fail if the curator has no nSignal', async function () {
        // todo
      })
      it('should', async function () {
        // todo
      })
      it('should', async function () {
        // todo
      })
    })
    describe('tokensToNSignal()', async function () {
      it('should work as a getter function', async function () {
        // todo
        // check event
      })
    })
    describe('nSignalToTokens()', async function () {
      it('should work as a getter function', async function () {
        // todo
        // check event
      })
    })
  })
})
