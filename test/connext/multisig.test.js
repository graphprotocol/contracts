const { expect } = require('chai')
const { constants, expectRevert } = require('@openzeppelin/test-helpers')
const { ZERO_ADDRESS } = constants

// helpers
const deployment = require('../lib/deployment')

contract('MinimumViableMultisig.sol', ([node, indexer, governor]) => {
  beforeEach(async function() {
    // Deploy graph token
    this.token = await deployment.deployGRT(governor, { from: indexer })

    // Deploy epoch contract
    this.epochManager = await deployment.deployEpochManagerContract(governor, { from: indexer })

    // Deploy staking contract
    this.staking = await deployment.deployStakingContract(
      governor,
      this.token.address,
      this.epochManager.address,
      ZERO_ADDRESS,
      { from: indexer },
    )

    // Deploy indexer multisig + interpreters
    const channelContracts = await deployment.deployIndexerMultisigWithContext(node, indexer)
    this.multisig = channelContracts.multisig
    this.indexerCtdt = channelContracts.ctdt
    this.interpreters = {
      singleAsset: channelContracts.singleAssetInterpreter,
      multiAsset: channelContracts.multiAssetInterpreter,
      withdraw: channelContracts.withdrawInterpreter,
    }
  })

  describe('constructor', function() {
    it('correct node address', async function() {
      expect(await this.multisig.NODE_ADDRESS()).to.be.eq(node)
    })

    it('correct indexer staking address', async function() {
      expect(await this.multisig.INDEXER_STAKING_ADDRESS()).to.be.eq(this.staking.address)
    })

    it('correct indexer conditional transaction delegate target (ctdt) address', async function() {
      expect(await this.multisig.INDEXER_CTDT_ADDRESS()).to.be.eq(this.indexerCtdt.address)
    })

    it('correct indexer single asset interpreter', async function() {
      expect(await this.multisig.INDEXER_SINGLE_ASSET_INTERPRETER_ADDRESS()).to.be.eq(
        this.interpreters.singleAsset.address,
      )
    })

    it('correct indexer multi asset interpreter', async function() {
      expect(await this.multisig.INDEXER_MULTI_ASSET_INTERPRETER_ADDRESS()).to.be.eq(
        this.interpreters.multiAsset.address,
      )
    })

    it('correct indexer withdrawal interpreter', async function() {
      expect(await this.multisig.INDEXER_WITHDRAW_INTERPRETER_ADDRESS()).to.be.eq(
        this.interpreters.withdraw.address,
      )
    })
  })

  describe('setup', function() {
    it('should be able to setup', async function() {
      const owners = [node, indexer]
      await this.multisig.setup(owners)
      const retrieved = await this.multisig.getOwners()
      expect(retrieved).to.be.deep.eq(owners)
    })

    it('should fail if already setup', async function() {
      const owners = [node, indexer]
      await this.multisig.setup(owners)
      await expectRevert(this.multisig.setup(owners), 'Contract has been set up before')
    })
  })

  describe('lock', function() {
    beforeEach(async function() {
      // Set the multisig owners
      await this.multisig.setup([node, indexer])
    })

    it('should lock', async function() {
      await this.multisig.lock({ from: indexer })
      expect(await this.multisig.locked()).to.be.eq(true)
    })

    it('should fail if not called by staking address', async function() {
      await expectRevert(this.multisig.lock({ from: node }), 'Caller must be the staking contract')
    })

    it('should fail if already locked', async function() {
      await this.multisig.lock({ from: indexer })
      await expectRevert(this.multisig.lock({ from: indexer }), 'Multisig must be unlocked to lock')
    })
  })

  describe('unlock', function() {
    beforeEach(async function() {
      // Set the multisig owners
      await this.multisig.setup([node, indexer])

      // Lock the multisig
      await this.multisig.lock({ from: indexer })
    })

    it('should unlock', async function() {
      await this.multisig.unlock({ from: indexer })
      expect(await this.multisig.locked()).to.be.eq(false)
    })

    it('should fail if not called by staking address', async function() {
      await expectRevert(this.multisig.lock({ from: node }), 'Caller must be the staking contract')
    })

    it('should fail if already unlocked', async function() {
      await this.multisig.unlock({ from: indexer })
      await expectRevert(
        this.multisig.unlock({ from: indexer }),
        'Multisig must be locked to unlock',
      )
    })
  })
})
