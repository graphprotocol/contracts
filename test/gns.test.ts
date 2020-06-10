import { ethers, Wallet } from 'ethers'
import { expect } from 'chai'
import { AddressZero } from 'ethers/constants'

import { Gns } from '../build/typechain/contracts/Gns'
import { EthereumDidRegistry } from '../build/typechain/contracts/EthereumDidRegistry'

import * as deployment from './lib/deployment'
import { randomHexBytes, provider } from './lib/testHelpers'

describe('GNS', () => {
  const [me, other, governor] = provider().getWallets()

  let gns: Gns
  let didRegistry: EthereumDidRegistry
  let name = 'graph'

  const newSubgraph = {
    graphAccount: me,
    subgraphDeploymentID: randomHexBytes(),
    name: name,
    nameIdentifier: ethers.utils.namehash(name),
    metadataHash: '0xeb50d096ba95573ae31640e38e4ef64fd02eec174f586624a37ea04e7bd8c751',
  }

  beforeEach(async function() {
    // No need to call the didRegistry and update owner, since an account is the owner of itself
    // by default. Thus, we don't even bother, but the contract still is needed in testing
    didRegistry = await deployment.deployEthereumDIDRegistry(me)
    gns = await deployment.deployGNS(governor.address, didRegistry.address, me)

    this.publishNewSubgraph = (signer: Wallet, graphAccount: string) =>
      gns
        .connect(signer)
        .publishNewSubgraph(
          graphAccount,
          newSubgraph.subgraphDeploymentID,
          newSubgraph.nameIdentifier,
          newSubgraph.name,
          newSubgraph.metadataHash,
        )

    this.publishNewVersion = (signer: Wallet, graphAccount: string, subgraphNumber: number) =>
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

    this.deprecate = (signer: Wallet, graphAccount: string, subgraphNumber: number) =>
      gns.connect(signer).deprecate(graphAccount, subgraphNumber)
  })

  describe('isPublished()', function() {
    it('should return if the subgraph is published', async function() {
      expect(await gns.isPublished(newSubgraph.graphAccount.address, 0)).to.be.eq(false)
      await this.publishNewSubgraph(me, me.address)
      expect(await gns.isPublished(newSubgraph.graphAccount.address, 0)).to.be.eq(true)
    })
  })

  describe('publishNewSubgraph()', async function() {
    it('should publish a new subgraph and first version with it', async function() {
      const tx = this.publishNewSubgraph(me, me.address)
      await expect(tx)
        .to.emit(gns, 'SubgraphPublished')
        .withArgs(
          newSubgraph.graphAccount.address,
          0,
          newSubgraph.subgraphDeploymentID,
          newSubgraph.nameIdentifier,
          newSubgraph.name,
          newSubgraph.metadataHash,
        )

      // State updated
      const deploymentID = await gns.subgraphs(newSubgraph.graphAccount.address, 0)
      expect(newSubgraph.subgraphDeploymentID).to.be.eq(deploymentID)
    })

    it('should publish a new subgraph with an incremented value', async function() {
      // We publish the exact same subgraph here, with same name, This is okay
      // in the contract, but the subgraph would make decisions on how to resolve this
      await this.publishNewSubgraph(me, me.address)
      await this.publishNewSubgraph(me, me.address)
      const deploymentID = await gns.subgraphs(newSubgraph.graphAccount.address, 1)
      expect(newSubgraph.subgraphDeploymentID).to.be.eq(deploymentID)
    })

    it('should reject publish if not sent from owner', async function() {
      const tx = this.publishNewSubgraph(other, me.address)
      await expect(tx).to.revertedWith('GNS: Only graph account owner can call')
    })

    it('should prevent subgraphDeploymentID of 0 to be used', async function() {
      const tx = gns
        .connect(me)
        .publishNewSubgraph(
          newSubgraph.graphAccount.address,
          ethers.constants.HashZero,
          newSubgraph.nameIdentifier,
          newSubgraph.name,
          newSubgraph.metadataHash,
        )
      await expect(tx).to.revertedWith('GNS: Cannot set to 0 in publish')
    })
  })

  describe('publishNewVersion()', async function() {
    it('should publish a new version on an existing subgraph', async function() {
      await this.publishNewSubgraph(me, me.address)
      const tx = this.publishNewVersion(me, me.address, 0)

      // Event being emitted indicates version has been updated
      await expect(tx)
        .to.emit(gns, 'SubgraphPublished')
        .withArgs(
          newSubgraph.graphAccount.address,
          0,
          newSubgraph.subgraphDeploymentID,
          newSubgraph.nameIdentifier,
          newSubgraph.name,
          newSubgraph.metadataHash,
        )
    })

    it('should reject publishing a version to a numbered subgraph that does not exist', async function() {
      const tx = this.publishNewVersion(me, me.address, 0)
      await expect(tx).to.revertedWith('GNS: Cant publish a version directly for a subgraph that wasnt created yet')
    })

    it('reject if not the owner', async function() {
      await this.publishNewSubgraph(me, me.address)
      const tx = this.publishNewVersion(other, me.address, 0)
      await expect(tx).to.revertedWith('GNS: Only graph account owner can call')
    })
  })

  describe('deprecate()', async function() {
    it('should deprecate a subgraph', async function() {
      await this.publishNewSubgraph(me, me.address)
      const tx = this.deprecate(me, me.address, 0)
      await expect(tx)
        .to.emit(gns, 'SubgraphDeprecated')
        .withArgs(newSubgraph.graphAccount.address, 0)

      // State updated
      const deploymentID = await gns.subgraphs(newSubgraph.graphAccount.address, 0)
      expect(ethers.constants.HashZero).to.be.eq(deploymentID)
    })

    it('should allow a deprecated subgraph to be republished', async function() {
      await this.publishNewSubgraph(me, me.address)
      await this.deprecate(me, me.address, 0)
      const tx = this.publishNewVersion(me, me.address, 0)

      // Event being emitted indicates version has been updated
      await expect(tx)
      .to.emit(gns, 'SubgraphPublished')
      .withArgs(
        newSubgraph.graphAccount.address,
        0,
        newSubgraph.subgraphDeploymentID,
        newSubgraph.nameIdentifier,
        newSubgraph.name,
        newSubgraph.metadataHash,
      )
    })

    it('reject if the subgraph does not exist', async function() {
      const tx = this.deprecate(me, me.address, 0)
      await expect(tx).to.revertedWith('GNS: Cannot deprecate a subgraph which does not exist')
      const tx2 = this.deprecate(me, me.address, 2340)
      await expect(tx2).to.revertedWith('GNS: Cannot deprecate a subgraph which does not exist')
    })

    it('reject if not the owner', async function() {
      await this.publishNewSubgraph(me, me.address)
      const tx = this.deprecate(other, me.address, 0)
      await expect(tx).to.revertedWith('GNS: Only graph account owner can call')
    })
  })
})
