import { expect } from 'chai'
import { ethers } from '@nomiclabs/buidler'
import { ChannelSigner } from '@connext/utils'
import { Signer } from 'ethers'

import { GraphToken } from '../../build/typechain/contracts/GraphToken'
import { deployMultisigWithProxy, deployGRT } from '../lib/deployment'
import { getRandomFundedChannelSigners } from '../lib/channel'
import { MinimumViableMultisig } from '../../build/typechain/contracts/MinimumViableMultisig'
import { IndexerCtdt } from '../../build/typechain/contracts/IndexerCtdt'
import { IndexerSingleAssetInterpreter } from '../../build/typechain/contracts/IndexerSingleAssetInterpreter'
import { IndexerMultiAssetInterpreter } from '../../build/typechain/contracts/IndexerMultiAssetInterpreter'
import { IndexerWithdrawInterpreter } from '../../build/typechain/contracts/IndexerWithdrawInterpreter'
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
  let multisig: MinimumViableMultisig

  beforeEach(async function () {
    const accounts = await ethers.getSigners()
    governor = accounts[0]

    // Deploy graph token
    token = await deployGRT(governor)

    // Get channel signers
    const [_node, _indexer] = await getRandomFundedChannelSigners(2, governor, token)
    node = _node
    indexer = _indexer

    // Deploy indexer multisig + CTDT + interpreters
    const channelContracts = await deployMultisigWithProxy(node.address, token.address, [
      node,
      indexer,
    ])
    indexerCTDT = channelContracts.ctdt
    singleAssetInterpreter = channelContracts.singleAssetInterpreter
    multiAssetInterpreter = channelContracts.multiAssetInterpreter
    withdrawInterpreter = channelContracts.withdrawInterpreter
    masterCopy = channelContracts.masterCopy
    staking = channelContracts.mockStaking
    multisig = channelContracts.multisig
  })

  describe('constructor', function () {
    it('correct node address', async function () {
      expect(await masterCopy.NODE_ADDRESS()).to.be.eq(node.address)
    })

    it('correct indexer staking address', async function () {
      expect(await masterCopy.INDEXER_STAKING_ADDRESS()).to.be.eq(staking.address)
    })

    it('correct indexer conditional transaction delegate target (ctdt) address', async function () {
      expect(await masterCopy.INDEXER_CTDT_ADDRESS()).to.be.eq(indexerCTDT.address)
    })

    it('correct indexer single asset interpreter', async function () {
      expect(await masterCopy.INDEXER_SINGLE_ASSET_INTERPRETER_ADDRESS()).to.be.eq(
        singleAssetInterpreter.address,
      )
    })

    it('correct indexer multi asset interpreter', async function () {
      expect(await masterCopy.INDEXER_MULTI_ASSET_INTERPRETER_ADDRESS()).to.be.eq(
        multiAssetInterpreter.address,
      )
    })

    it('correct indexer withdrawal interpreter', async function () {
      expect(await masterCopy.INDEXER_WITHDRAW_INTERPRETER_ADDRESS()).to.be.eq(
        withdrawInterpreter.address,
      )
    })
  })

  describe('setup', function () {
    it('should be able to setup', async function () {
      const owners = [node.address, indexer.address]
      const retrieved = await multisig.getOwners()
      expect(retrieved).to.be.deep.eq(owners)
    })
    it('should fail if already setup', async function () {
      const owners = [node.address, indexer.address]
      await expect(multisig.connect(node).setup(owners)).to.be.revertedWith(
        'Contract has been set up before',
      )
    })
  })

  describe('lock', function () {
    beforeEach(async function () {
      // Set the multisig owners
      await masterCopy.setup([node.address, indexer.address])
    })

    it('should lock', async function () {
      const tx = await staking.functions.lockMultisig(multisig.address)
      await tx.wait()
      expect(await multisig.locked()).to.be.eq(true)
    })

    it('should fail if not called by staking address', async function () {
      await expect(multisig.connect(governor).lock()).to.be.revertedWith(
        'Caller must be the staking contract',
      )
    })

    it('should fail if already locked', async function () {
      const tx = await staking.functions.lockMultisig(multisig.address)
      await tx.wait()
      await expect(staking.functions.lockMultisig(multisig.address)).to.be.revertedWith(
        'Multisig must be unlocked to lock',
      )
    })
  })
})
