import { expect } from 'chai'
import { ethers } from '@nomiclabs/buidler'
import { Signer } from 'ethers'

import { deployGRTWithFactory, deployIndexerMultisigWithContext } from '../lib/deployment'
import { getRandomFundedChannelSigners, fundMultisig, MiniCommitment } from '../lib/channel'
import { MinimumViableMultisig } from '../../build/typechain/contracts/MinimumViableMultisig'
import { IndexerCtdt } from '../../build/typechain/contracts/IndexerCTDT'
import { IndexerSingleAssetInterpreter } from '../../build/typechain/contracts/IndexerSingleAssetInterpreter'
import { IndexerMultiAssetInterpreter } from '../../build/typechain/contracts/IndexerMultiAssetInterpreter'
import { IndexerWithdrawInterpreter } from '../../build/typechain/contracts/IndexerWithdrawInterpreter'
import { MockStaking } from '../../build/typechain/contracts/MockStaking'
import { ChannelSigner } from '@connext/utils'
import { GraphToken } from '../../build/typechain/contracts/GraphToken'
import { bigNumberify, parseEther } from 'ethers/utils'

// helpers

// constants
const DEFAULT_GAS = 80000

describe('Indexer Channel Operations', () => {
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
  let governer: Signer

  beforeEach(async function() {
    const accounts = await ethers.getSigners()
    governer = accounts[0]
    // Deploy graph token
    token = await deployGRTWithFactory(await governer.getAddress())

    // Get channel signers
    const [_node, _indexer] = await getRandomFundedChannelSigners(2, governer, token)
    node = _node
    indexer = _indexer

    // Deploy indexer multisig + CTDT + interpreters
    const channelContracts = await deployIndexerMultisigWithContext(node.address, token.address)
    indexerCTDT = channelContracts.ctdt
    singleAssetInterpreter = channelContracts.singleAssetInterpreter
    multiAssetInterpreter = channelContracts.multiAssetInterpreter
    withdrawInterpreter = channelContracts.withdrawInterpreter
    mockStaking = channelContracts.mockStaking
    masterCopy = channelContracts.masterCopy
    multisig = channelContracts.multisig

    // Setup the multisig
    // await masterCopy.setup([node.address, indexer.address])

    // Add channel to mock staking contract
    await mockStaking.setChannel(indexer.address)

    // Helpers
  })

  describe('funding + withdrawal', function() {
    // Establish test constants
    const ETH_DEPOSIT = bigNumberify(175)
    const TOKEN_DEPOSIT = parseEther('4')

    beforeEach(async function() {
      // Verify pre-deposit balances
      const preDepositEth = await governer.provider.getBalance(multisig.address)
      expect(preDepositEth).to.be.eq('0')
      const preDepositToken = await token.balanceOf(multisig.address)
      expect(preDepositToken.toString()).to.be.eq('0')
      // Fund multisig with eth and tokens
      await fundMultisig(ETH_DEPOSIT, multisig.address, governer)
      await fundMultisig(TOKEN_DEPOSIT, multisig.address, governer, token)
      // Verify post-deposit balances
      const postDepositEth = await governer.provider.getBalance(multisig.address)
      expect(postDepositEth).to.be.eq(ETH_DEPOSIT.toString())
      const postDepositToken = await token.balanceOf(multisig.address)
      expect(postDepositToken.toString()).to.be.eq(TOKEN_DEPOSIT.toString())
    })

    it('node should be able to withdraw eth', async function() {})

    it('node should be able to withdraw tokens', async function() {
      // Generate withdrawal commitment for node
      const commitment = new MiniCommitment(multisig.address, [node, indexer])
      // Get signed multisig transaction to withdraw tokens
      const commitmentType = 'withdraw'
      const params = {
        assetId: token.address,
        amount: 5,
        recipient: node.address,
        withdrawInterpreterAddress: withdrawInterpreter.address,
        ctdt: indexerCTDT,
      }
      const tx = await commitment.getSignedTransaction(commitmentType, params)

      // Send transaction
      await governer.sendTransaction(tx)
      // Verify post withdrawal balances
      const postWithdrawalEth = await governer.provider.getBalance(multisig.address)
      expect(postWithdrawalEth).to.be.eq(ETH_DEPOSIT)
      const postWithdrawalToken = await token.balanceOf(multisig.address)
      expect(postWithdrawalToken.toString()).to.be.eq(TOKEN_DEPOSIT.sub(params.amount).toString())
      // TODO: CHECK NODE BALANCE
    })

    it.skip('node should be able to withdraw eth', async function() {})

    it.skip('indexer should be able to withdraw tokens', async function() {})
  })
})
