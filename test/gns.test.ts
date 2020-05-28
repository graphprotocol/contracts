import { ethers } from 'ethers'
import { expect } from 'chai'
import { AddressZero } from 'ethers/constants'

import { Gns } from '../build/typechain/contracts/GNS'

import * as deployment from './lib/deployment'
import { randomHexBytes, provider } from './lib/testHelpers'

describe('GNS', () => {
  const [me, other, governor] = provider().getWallets()

  let gns: Gns

  const record = {
    name: 'graph',
    nameHash: ethers.utils.id('graph'),
    subgraphID: randomHexBytes(),
    metadataHash: '0xeb50d096ba95573ae31640e38e4ef64fd02eec174f586624a37ea04e7bd8c751',
  }

  beforeEach(async function() {
    gns = await deployment.deployGNS(governor.address, me)

    this.publish = (signer: ethers.Wallet) =>
      gns.connect(signer).publish(record.name, record.subgraphID, record.metadataHash)
    this.unpublish = (signer: ethers.Wallet) => gns.connect(signer).unpublish(record.nameHash)
  })

  describe('isReserved()', function() {
    it('should return if the name is reserved', async function() {
      expect(await gns.isReserved(record.nameHash)).to.be.eq(false)
      await this.publish(me)
      expect(await gns.isReserved(record.nameHash)).to.be.eq(true)
    })
  })

  describe('publish()', async function() {
    it('should publish a version', async function() {
      const tx = this.publish(me)
      await expect(tx)
        .to.emit(gns, 'SubgraphPublished')
        .withArgs(record.name, me.address, record.subgraphID, record.metadataHash)

      // State updated
      const newRecord = await gns.records(record.nameHash)
      expect(newRecord.owner).to.be.eq(me.address)
      expect(newRecord.subgraphID).to.be.eq(record.subgraphID)
    })

    it('should allow re-publish', async function() {
      await this.publish(me)
      await this.publish(me)
    })

    it('reject publish if overwritting with different account', async function() {
      await this.publish(me)
      const tx = this.publish(other)
      await expect(tx).to.revertedWith('GNS: Record reserved, only record owner can publish')
    })
  })

  describe('unpublish()', async function() {
    it('should unpublish a name', async function() {
      await this.publish(me)
      const tx = this.unpublish(me)
      await expect(tx)
        .to.emit(gns, 'SubgraphUnpublished')
        .withArgs(record.nameHash)

      // State updated
      const newRecord = await gns.records(record.nameHash)
      expect(newRecord.owner).to.be.eq(AddressZero)
    })

    it('reject unpublish if not the owner', async function() {
      const tx = this.unpublish(other)
      await expect(tx).to.revertedWith('GNS: Only record owner can call')
    })
  })

  describe('transfer()', function() {
    beforeEach(async function() {
      await this.publish(me)
    })

    it('should transfer to new owner', async function() {
      const tx = gns.connect(me).transfer(record.nameHash, other.address)
      await expect(tx)
        .to.emit(gns, 'SubgraphTransferred')
        .withArgs(record.nameHash, me.address, other.address)

      // State updated
      const newRecord = await gns.records(record.nameHash)
      expect(newRecord.owner).to.be.eq(other.address)
    })

    it('reject transfer if not owner', async function() {
      const tx = gns.connect(other).transfer(record.nameHash, other.address)
      await expect(tx).to.be.revertedWith('GNS: Only record owner can call')
    })

    it('reject transfer to empty address', async function() {
      const tx = gns.connect(me).transfer(record.nameHash, AddressZero)
      await expect(tx).to.be.revertedWith('GNS: Cannot transfer to empty address')
    })

    it('reject transfer to itself', async function() {
      const tx = gns.connect(me).transfer(record.nameHash, me.address)
      await expect(tx).to.be.revertedWith('GNS: Cannot transfer to itself')
    })
  })
})
