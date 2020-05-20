const { utils } = require('ethers')
const { expectEvent, expectRevert } = require('@openzeppelin/test-helpers')

const deployment = require('./lib/deployment')
const helpers = require('./lib/testHelpers')

contract('GNS', ([me, other, governor]) => {
  beforeEach(async function() {
    this.gns = await deployment.deployGNS(governor, { from: me })
    this.record = {
      name: 'graph',
      nameHash: utils.id('graph'),
      subgraphID: helpers.randomSubgraphId(),
      metadataHash: '0xeb50d096ba95573ae31640e38e4ef64fd02eec174f586624a37ea04e7bd8c751',
    }

    this.publish = params =>
      this.gns.publish(this.record.name, this.record.subgraphID, this.record.metadataHash, params)
    this.unpublish = params => this.gns.unpublish(this.record.nameHash, params)
  })

  describe('isReserved()', function() {
    it('should return if the name is reserved', async function() {
      expect(await this.gns.isReserved(this.record.nameHash)).to.be.eq(false)
      await this.publish({ from: me })
      expect(await this.gns.isReserved(this.record.nameHash)).to.be.eq(true)
    })
  })

  describe('publish()', async function() {
    it('should publish a version', async function() {
      const { logs } = await this.publish({ from: me })

      // State updated
      const record = await this.gns.records(this.record.nameHash)
      expect(record.owner).to.be.eq(me)
      expect(record.subgraphID).to.be.eq(this.record.subgraphID)

      // Event emitted
      expectEvent.inLogs(logs, 'SubgraphPublished', {
        name: this.record.name,
        owner: me,
        subgraphID: this.record.subgraphID,
        metadataHash: this.record.metadataHash,
      })
    })

    it('should allow re-publish', async function() {
      await this.publish({ from: me })
      await this.publish({ from: me })
    })

    it('reject publish if overwritting with different account', async function() {
      await this.publish({ from: me })
      await expectRevert(
        this.publish({ from: other }),
        'GNS: Record reserved, only record owner can publish',
      )
    })
  })

  describe('unpublish()', async function() {
    it('should unpublish a name', async function() {
      await this.publish({ from: me })
      const { logs } = await this.unpublish({ from: me })

      // State updated
      const record = await this.gns.records(this.record.nameHash)
      expect(record.owner).to.be.eq(helpers.zeroAddress())

      // Event emitted
      expectEvent.inLogs(logs, 'SubgraphUnpublished', {
        nameHash: this.record.nameHash,
      })
    })

    it('reject unpublish if not the owner', async function() {
      await expectRevert(this.unpublish({ from: other }), 'GNS: Only record owner can call')
    })
  })

  describe('transfer()', function() {
    beforeEach(async function() {
      await this.publish({ from: me })
    })

    it('should transfer to new owner', async function() {
      const { logs } = await this.gns.transfer(this.record.nameHash, other, { from: me })

      // State updated
      const record = await this.gns.records(this.record.nameHash)
      expect(record.owner).to.be.eq(other)

      // Event emitted
      expectEvent.inLogs(logs, 'SubgraphTransferred', {
        nameHash: this.record.nameHash,
        from: me,
        to: other,
      })
    })

    it('reject transfer if not owner', async function() {
      await expectRevert(
        this.gns.transfer(this.record.nameHash, other, { from: other }),
        'GNS: Only record owner can call',
      )
    })

    it('reject transfer to empty address', async function() {
      await expectRevert(
        this.gns.transfer(this.record.nameHash, helpers.zeroAddress(), { from: me }),
        'GNS: Cannot transfer to empty address',
      )
    })

    it('reject transfer to itself', async function() {
      await expectRevert(
        this.gns.transfer(this.record.nameHash, me, { from: me }),
        'GNS: Cannot transfer to itself',
      )
    })
  })
})
