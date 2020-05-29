import { expect } from 'chai'
import { ChannelSigner } from '@connext/utils'

import { GraphToken } from '../../build/typechain/contracts/GraphToken'
import { provider } from '../lib/testHelpers'
import { deployGRT, deployEpochManager, deployIndexerMultisigWithContext } from '../lib/deployment'
import { getRandomFundedChannelSigners } from '../lib/channel'
import { MinimumViableMultisig } from '../../build/typechain/contracts/MinimumViableMultisig'
import { IndexerCtdt } from '../../build/typechain/contracts/IndexerCTDT'
import { IndexerSingleAssetInterpreter } from '../../build/typechain/contracts/IndexerSingleAssetInterpreter'
import { IndexerMultiAssetInterpreter } from '../../build/typechain/contracts/IndexerMultiAssetInterpreter'
import { IndexerWithdrawInterpreter } from '../../build/typechain/contracts/IndexerWithdrawInterpreter'
import { MockStaking } from '../../build/typechain/contracts/MockStaking'
import { Proxy } from '../../build/typechain/contracts/Proxy'
import { EpochManager } from '../../build/typechain/contracts/EpochManager'

describe('MinimumViableMultisig.sol', () => {
  let multisig: Proxy
  let masterCopy: MinimumViableMultisig
  let indexerCTDT: IndexerCtdt
  let singleAssetInterpreter: IndexerSingleAssetInterpreter
  let multiAssetInterpreter: IndexerMultiAssetInterpreter
  let withdrawInterpreter: IndexerWithdrawInterpreter
  let mockStaking: MockStaking
  let node: ChannelSigner
  let indexer: ChannelSigner
  let token: GraphToken
  let epochManager: EpochManager

  const [me, other, governor, curator, staking] = provider().getWallets()
  beforeEach(async function() {
    // Deploy graph token
    token = await deployGRT(governor.address, me)

    // Get channel signers
    const [_node, _indexer] = await getRandomFundedChannelSigners(2, governor, token)
    node = _node
    indexer = _indexer

    // Deploy epoch contract
    epochManager = await deployEpochManager(governor.address, me)

    // Deploy indexer multisig + CTDT + interpreters
    const channelContracts = await deployIndexerMultisigWithContext(node.address)
    multisig = channelContracts.multisig.connect(me)
    masterCopy = channelContracts.masterCopy.connect(me)
    indexerCTDT = channelContracts.ctdt
    singleAssetInterpreter = channelContracts.singleAssetInterpreter
    multiAssetInterpreter = channelContracts.multiAssetInterpreter
    withdrawInterpreter = channelContracts.withdrawInterpreter
    mockStaking = channelContracts.mockStaking
  })

  describe('constructor', function() {
    it('correct node address', async function() {
      expect(await multisig.NODE_ADDRESS()).to.be.eq(node)
    })

    it('correct indexer staking address', async function() {
      expect(await multisig.INDEXER_STAKING_ADDRESS()).to.be.eq(staking.address)
    })

    it('correct indexer conditional transaction delegate target (ctdt) address', async function() {
      expect(await multisig.INDEXER_CTDT_ADDRESS()).to.be.eq(indexerCTDT.address)
    })

    it('correct indexer single asset interpreter', async function() {
      expect(await multisig.INDEXER_SINGLE_ASSET_INTERPRETER_ADDRESS()).to.be.eq(
        singleAssetInterpreter.address,
      )
    })

    it('correct indexer multi asset interpreter', async function() {
      expect(await multisig.INDEXER_MULTI_ASSET_INTERPRETER_ADDRESS()).to.be.eq(
        multiAssetInterpreter.address,
      )
    })

    it('correct indexer withdrawal interpreter', async function() {
      expect(await multisig.INDEXER_WITHDRAW_INTERPRETER_ADDRESS()).to.be.eq(
        withdrawInterpreter.address,
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
      await expect(this.multisig.setup(owners)).to.be.revertedWith(
        'Contract has been set up before',
      )
    })
  })

  describe('lock', function() {
    beforeEach(async function() {
      // Set the multisig owners
      await this.multisig.setup([node, indexer])
    })

    it('should lock', async function() {
      await this.multisig.lock({ from: indexer })
      expect(this.multisig.locked()).to.be.eq(true)
    })

    it('should fail if not called by staking address', async function() {
      await expect(this.multisig.lock({ from: node })).to.be.revertedWith(
        'Contract has been set up before',
      )
    })

    it('should fail if already locked', async function() {
      await this.multisig.lock({ from: indexer })
      await expect(this.multisig.lock({ from: indexer })).to.be.revertedWith(
        'Multisig must be unlocked to lock',
      )
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
      await expect(this.multisig.lock({ from: node })).to.be.revertedWith(
        'Caller must be the staking contract',
      )
    })

    it('should fail if already unlocked', async function() {
      await this.multisig.unlock({ from: indexer })
      await expect(this.multisig.unlock({ from: indexer })).to.be.revertedWith(
        'Multisig must be locked to unlock',
      )
    })
  })
})
