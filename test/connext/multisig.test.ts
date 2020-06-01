import { expect } from 'chai'
import { ethers } from '@nomiclabs/buidler'
import { ChannelSigner } from '@connext/utils'

import { GraphToken } from '../../build/typechain/contracts/GraphToken'
import {
  deployIndexerMultisigWithContext,
  deployGRTWithFactory,
  deployEpochManagerWithFactory,
} from '../lib/deployment'
import { getRandomFundedChannelSigners } from '../lib/channel'
import { MinimumViableMultisig } from '../../build/typechain/contracts/MinimumViableMultisig'
import { IndexerCtdt } from '../../build/typechain/contracts/IndexerCTDT'
import { IndexerSingleAssetInterpreter } from '../../build/typechain/contracts/IndexerSingleAssetInterpreter'
import { IndexerMultiAssetInterpreter } from '../../build/typechain/contracts/IndexerMultiAssetInterpreter'
import { IndexerWithdrawInterpreter } from '../../build/typechain/contracts/IndexerWithdrawInterpreter'
import { MockStaking } from '../../build/typechain/contracts/MockStaking'
import { Proxy } from '../../build/typechain/contracts/Proxy'
import { EpochManager } from '../../build/typechain/contracts/EpochManager'
import { Signer } from 'ethers'

describe('MinimumViableMultisig.sol', () => {
  let multisig: MinimumViableMultisig
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
  let governor: Signer
  let staking: Signer

  beforeEach(async function() {
    const accounts = await ethers.getSigners()
    governor = accounts[0]
    staking = accounts[1]
    // Deploy graph token
    token = await deployGRTWithFactory(await governor.getAddress())

    // Get channel signers
    const [_node, _indexer] = await getRandomFundedChannelSigners(2, governor, token)
    node = _node
    indexer = _indexer

    // Deploy epoch contract
    epochManager = await deployEpochManagerWithFactory(await governor.getAddress())

    // Deploy indexer multisig + CTDT + interpreters
    const channelContracts = await deployIndexerMultisigWithContext(node.address, token.address)
    indexerCTDT = channelContracts.ctdt
    singleAssetInterpreter = channelContracts.singleAssetInterpreter
    multiAssetInterpreter = channelContracts.multiAssetInterpreter
    withdrawInterpreter = channelContracts.withdrawInterpreter
    mockStaking = channelContracts.mockStaking
    masterCopy = channelContracts.masterCopy
    multisig = channelContracts.multisig
  })

  describe('constructor', function() {
    it('correct node address', async function() {
      expect(await masterCopy.NODE_ADDRESS()).to.be.eq(node.address)
    })

    it('correct indexer staking address', async function() {
      expect(await masterCopy.INDEXER_STAKING_ADDRESS()).to.be.eq(await staking.getAddress())
    })

    it('correct indexer conditional transaction delegate target (ctdt) address', async function() {
      expect(await masterCopy.INDEXER_CTDT_ADDRESS()).to.be.eq(indexerCTDT.address)
    })

    it('correct indexer single asset interpreter', async function() {
      expect(await masterCopy.INDEXER_SINGLE_ASSET_INTERPRETER_ADDRESS()).to.be.eq(
        singleAssetInterpreter.address,
      )
    })

    it('correct indexer multi asset interpreter', async function() {
      expect(await masterCopy.INDEXER_MULTI_ASSET_INTERPRETER_ADDRESS()).to.be.eq(
        multiAssetInterpreter.address,
      )
    })

    it('correct indexer withdrawal interpreter', async function() {
      expect(await masterCopy.INDEXER_WITHDRAW_INTERPRETER_ADDRESS()).to.be.eq(
        withdrawInterpreter.address,
      )
    })
  })

  describe('setup', function() {
    it('should be able to setup', async function() {
      const owners = [node.address, indexer.address]
      await masterCopy.setup(owners)
      const retrieved = await masterCopy.getOwners()
      expect(retrieved).to.be.deep.eq(owners)
    })

    it('should fail if already setup', async function() {
      const owners = [node.address, indexer.address]
      await masterCopy.setup(owners)
      await expect(masterCopy.setup(owners)).to.be.revertedWith('Contract has been set up before')
    })
  })

  describe('lock', function() {
    beforeEach(async function() {
      // Set the multisig owners
      await masterCopy.setup([node.address, indexer.address])
    })

    it('should lock', async function() {
      masterCopy.connect(staking)
      await masterCopy.lock()
      expect(masterCopy.locked()).to.be.eq(true)
    })

    it('should fail if not called by staking address', async function() {
      await expect(masterCopy.lock()).to.be.revertedWith('Caller must be the staking contract')
    })

    it('should fail if already locked', async function() {
      masterCopy.connect(staking)
      await masterCopy.lock()
      await expect(masterCopy.lock()).to.be.revertedWith('Multisig must be unlocked to lock')
    })
  })

  describe('unlock', function() {
    beforeEach(async function() {
      // Set the multisig owners
      await masterCopy.setup([node.address, indexer.address])

      // Lock the multisig
      masterCopy.connect(staking)
      await masterCopy.lock()
    })

    it('should unlock', async function() {
      await masterCopy.unlock()
      expect(await masterCopy.locked()).to.be.eq(false)
    })

    it('should fail if not called by staking address', async function() {
      await expect(masterCopy.lock()).to.be.revertedWith('Caller must be the staking contract')
    })

    it('should fail if already unlocked', async function() {
      await masterCopy.unlock()
      await expect(masterCopy.unlock()).to.be.revertedWith('Multisig must be locked to unlock')
    })
  })
})
