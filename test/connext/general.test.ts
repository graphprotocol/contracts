import { expect } from 'chai'

import { defaults, provider, randomHexBytes, toBN, toGRT } from '../lib/testHelpers'
import { deployGRT, deployIndexerMultisigWithContext } from '../lib/deployment'
import { getRandomFundedChannelSigners, fundMultisig, MiniCommitment } from '../lib/channel'
import { Proxy } from '../../build/typechain/contracts/Proxy'
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

  const [me, other, governor, curator, staking] = provider().getWallets()
  beforeEach(async function() {
    // Deploy graph token
    token = await deployGRT(governor.address, me)

    // Get channel signers
    const [_node, _indexer] = await getRandomFundedChannelSigners(
      2,
      'http://localhost:8545',
      governor,
      token,
    )
    node = _node
    indexer = _indexer

    // Deploy indexer multisig + CTDT + interpreters
    const channelContracts = await deployIndexerMultisigWithContext(node.address, me)
    multisig = channelContracts.multisig.connect(me)
    masterCopy = channelContracts.masterCopy.connect(me)
    indexerCTDT = channelContracts.ctdt
    singleAssetInterpreter = channelContracts.singleAssetInterpreter
    multiAssetInterpreter = channelContracts.multiAssetInterpreter
    withdrawInterpreter = channelContracts.withdrawInterpreter
    mockStaking = channelContracts.mockStaking

    // Setup the multisig
    await masterCopy.setup([node.address, indexer.address])

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
      const preDepositEth = await me.getBalance(multisig.address)
      expect(preDepositEth).to.be.eq('0')
      const preDepositToken = await token.balanceOf(multisig.address)
      expect(preDepositToken.toString()).to.be.eq('0')

      // Fund multisig with eth and tokens
      await fundMultisig(ETH_DEPOSIT, multisig.address, governor)
      await fundMultisig(TOKEN_DEPOSIT, multisig.address, governor, token)

      // Verify post-deposit balances
      const postDepositEth = await me.getBalance(multisig.address)
      expect(postDepositEth).to.be.eq(ETH_DEPOSIT.toString())
      const postDepositToken = await token.balanceOf(multisig.address)
      expect(postDepositToken.toString()).to.be.eq(TOKEN_DEPOSIT.toString())
    })

    it('node should be able to withdraw eth', async function() {})

    it.only('node should be able to withdraw tokens', async function() {
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

      const { to, value, data, operation } = commitment.getTransactionDetails(
        commitmentType,
        params,
      )
      const hash = await masterCopy.getTransactionHash(to, value, data, operation)
      console.log('contract generated hash', hash)

      // TODO: remove  trying to send directly to ctdt to debug where tx is failing
      const recipt = await me.sendTransaction({
        to: params.ctdt.address,
        value: 0,
        data,
        from: node.address,
      })
      console.log('recipt: ', recipt)

      // Send transaction
      await me.sendTransaction({ ...tx, from: node.address })

      // Verify post withdrawal balances
      const postWithdrawalEth = await me.getBalance(multisig.address)
      expect(postWithdrawalEth).to.be.eq(ETH_DEPOSIT)
      const postWithdrawalToken = await token.balanceOf(multisig.address)
      expect(postWithdrawalToken.toString()).to.be.eq(TOKEN_DEPOSIT.sub(params.amount).toString())
    })

    it.skip('node should be able to withdraw eth', async function() {})

    it.skip('indexer should be able to withdraw tokens', async function() {})
  })
})
