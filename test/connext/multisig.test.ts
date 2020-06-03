import { expect } from 'chai'
import { ethers } from '@nomiclabs/buidler'
import { ChannelSigner } from '@connext/utils'

import { GraphToken } from '../../build/typechain/contracts/GraphToken'
import { deployIndexerMultisigWithContext, deployGRTWithFactory } from '../lib/deployment'
import { getRandomFundedChannelSigners } from '../lib/channel'
import { MinimumViableMultisig } from '../../build/typechain/contracts/MinimumViableMultisig'
import { IndexerCtdt } from '../../build/typechain/contracts/IndexerCTDT'
import { IndexerSingleAssetInterpreter } from '../../build/typechain/contracts/IndexerSingleAssetInterpreter'
import { IndexerMultiAssetInterpreter } from '../../build/typechain/contracts/IndexerMultiAssetInterpreter'
import { IndexerWithdrawInterpreter } from '../../build/typechain/contracts/IndexerWithdrawInterpreter'
import { Signer } from 'ethers'
import { MockStaking } from '../../build/typechain/contracts/MockStaking'

describe('MinimumViableMultisig.sol', () => {
  let masterCopy: MinimumViableMultisig
  let indexerCTDT: IndexerCtdt
  let singleAssetInterpreter: IndexerSingleAssetInterpreter
  let multiAssetInterpreter: IndexerMultiAssetInterpreter
  let withdrawInterpreter: IndexerWithdrawInterpreter
  let node: ChannelSigner
  let indexer: ChannelSigner
  let token: GraphToken
  let governor: Signer
  let staking: MockStaking

  beforeEach(async function() {
    const accounts = await ethers.getSigners()
    governor = accounts[0]

    // Deploy graph token
    token = await deployGRTWithFactory(await governor.getAddress())

    // Get channel signers
    const [_node, _indexer] = await getRandomFundedChannelSigners(2, governor, token)
    node = _node
    indexer = _indexer

    // Deploy indexer multisig + CTDT + interpreters
    const channelContracts = await deployIndexerMultisigWithContext(node.address, token.address, [
      node,
      indexer,
    ])
    indexerCTDT = channelContracts.ctdt
    singleAssetInterpreter = channelContracts.singleAssetInterpreter
    multiAssetInterpreter = channelContracts.multiAssetInterpreter
    withdrawInterpreter = channelContracts.withdrawInterpreter
    masterCopy = channelContracts.masterCopy
    staking = channelContracts.mockStaking
  })

  describe('constructor', function() {
    it('correct node address', async function() {
      expect(await masterCopy.NODE_ADDRESS()).to.be.eq(node.address)
    })

    it('correct indexer staking address', async function() {
      expect(await masterCopy.INDEXER_STAKING_ADDRESS()).to.be.eq(staking.address)
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

  // TODO: how to call from staking contract properly?
  describe.skip('lock', function() {
    beforeEach(async function() {
      // Set the multisig owners
      await masterCopy.setup([node.address, indexer.address])
    })

    it('should lock', async function() {
      const tx = await staking.functions.lockMultisig(masterCopy.address)
      await tx.wait()
      expect(await masterCopy.locked()).to.be.eq(true)
    })

    it('should fail if not called by staking address', async function() {
      await expect(
        masterCopy.connect(governor).lockMultisig(masterCopy.address),
      ).to.be.revertedWith('Caller must be the staking contract')
    })

    it('should fail if already locked', async function() {
      const tx = await staking.functions.lockMultisig(masterCopy.address)
      await tx.wait()
      await expect(staking.functions.lockMultisig(masterCopy.address)).to.be.revertedWith(
        'Multisig must be unlocked to lock',
      )
    })
  })

  // TODO: how to call from staking contract properly?
  describe.skip('unlock', function() {
    beforeEach(async function() {
      // Set the multisig owners
      await masterCopy.setup([node.address, indexer.address])

      // Lock the multisig
      const tx = await staking.functions.lockMultisig(masterCopy.address)
      await tx.wait()
    })

    it('should unlock', async function() {
      const tx = await staking.functions.unlockMultisig(masterCopy.address)
      await tx.wait()
      expect(await masterCopy.locked()).to.be.eq(false)
    })

    it('should fail if not called by staking address', async function() {
      await expect(
        masterCopy.connect(governor).unlockMultisig(masterCopy.address),
      ).to.be.revertedWith('Caller must be the staking contract')
    })

    it('should fail if already unlocked', async function() {
      const tx = await staking.functions.unlockMultisig(masterCopy.address)
      await tx.wait()
      await expect(staking.functions.unlockMultisig(masterCopy.address)).to.be.revertedWith(
        'Multisig must be locked to unlock',
      )
    })
  })
})
