import { expect } from 'chai'
import { ethers } from '@nomiclabs/buidler'
import { Signer, Wallet } from 'ethers'
import { bigNumberify, parseEther, BigNumberish, BigNumber } from 'ethers/utils'
import { ChallengeStatus } from '@connext/types'
import { ChannelSigner } from '@connext/utils'

import { deployGRTWithFactory, deployIndexerMultisigWithContext } from '../lib/deployment'
import {
  getRandomFundedChannelSigners,
  fundMultisig,
  MiniCommitment,
  CommitmentType,
  getInitialDisputeTx,
  freeBalanceStateEncoding,
} from '../lib/channel'
import { MinimumViableMultisig } from '../../build/typechain/contracts/MinimumViableMultisig'
import { IndexerCtdt } from '../../build/typechain/contracts/IndexerCTDT'
import { IndexerSingleAssetInterpreter } from '../../build/typechain/contracts/IndexerSingleAssetInterpreter'
import { IndexerMultiAssetInterpreter } from '../../build/typechain/contracts/IndexerMultiAssetInterpreter'
import { IndexerWithdrawInterpreter } from '../../build/typechain/contracts/IndexerWithdrawInterpreter'
import { MockStaking } from '../../build/typechain/contracts/MockStaking'
import { GraphToken } from '../../build/typechain/contracts/GraphToken'
import { AddressZero } from 'ethers/constants'
import { MockDispute } from '../../build/typechain/contracts/MockDispute'
import { AppWithAction } from '../../build/typechain/contracts/AppWithAction'
import { IdentityApp } from '../../build/typechain/contracts/IdentityApp'

describe('Indexer Channel Operations', () => {
  let multisig: MinimumViableMultisig
  let masterCopy: MinimumViableMultisig
  let indexerCTDT: IndexerCtdt
  let singleAssetInterpreter: IndexerSingleAssetInterpreter
  let multiAssetInterpreter: IndexerMultiAssetInterpreter
  let withdrawInterpreter: IndexerWithdrawInterpreter
  let mockStaking: MockStaking
  let mockDispute: MockDispute
  let identity: IdentityApp
  let app: AppWithAction
  let node: ChannelSigner
  let indexer: ChannelSigner
  let token: GraphToken
  let governer: Signer

  // helpers
  let fundMultisigAndAssert: (amount: BigNumberish, token?: GraphToken) => Promise<void>

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
    mockDispute = channelContracts.mockDispute
    masterCopy = channelContracts.masterCopy
    multisig = channelContracts.multisig
    app = channelContracts.app
    identity = channelContracts.identity

    // Setup the multisig
    // await masterCopy.setup([node.address, indexer.address])

    // Add channel to mock staking contract
    await mockStaking.setChannel(indexer.address)

    // Helpers
    fundMultisigAndAssert = async (amount: BigNumberish, tokenContract?: GraphToken) => {
      // Get + verify pre deposit balance
      const preDeposit = tokenContract
        ? await tokenContract.balanceOf(multisig.address)
        : await governer.provider.getBalance(multisig.address)
      expect(preDeposit.toString()).to.be.eq('0')

      // Fund multisig from governor
      await fundMultisig(new BigNumber(amount), multisig.address, governer, tokenContract)

      // Get + verify post deposit balance
      const postDeposit = tokenContract
        ? await tokenContract.balanceOf(multisig.address)
        : await governer.provider.getBalance(multisig.address)
      expect(postDeposit.toString()).to.be.eq(preDeposit.add(amount).toString())
    }
  })

  describe('funding + withdrawal', function() {
    // Establish test constants
    const ETH_DEPOSIT = bigNumberify(175)
    const TOKEN_DEPOSIT = parseEther('4')

    let sendWithdrawalCommitment: (commitment: MiniCommitment, params: any) => Promise<void>

    beforeEach(async function() {
      // make sure staking contract is funded
      const tx = await token.transfer(mockStaking.address, TOKEN_DEPOSIT)
      await tx.wait()
      await fundMultisigAndAssert(ETH_DEPOSIT)
      await fundMultisigAndAssert(TOKEN_DEPOSIT, token)

      // Helper
      sendWithdrawalCommitment = async (commitment: MiniCommitment, params: any) => {
        const commitmentType = CommitmentType.Withdraw

        // Get recipient address pre withdraw balance
        const isEth = params.assetId === AddressZero
        const preWithdraw = isEth
          ? await governer.provider.getBalance(params.recipient)
          : await token.balanceOf(params.recipient)

        // Send transaction
        const tx = await commitment.getSignedTransaction(commitmentType, params)
        await governer.sendTransaction(tx)

        // Verify post withdrawal multisig balances
        const postWithdrawalEth = await governer.provider.getBalance(multisig.address)
        expect(postWithdrawalEth.toString()).to.be.eq(ETH_DEPOSIT.toString())

        const postWithdrawalToken = await token.balanceOf(multisig.address)
        expect(postWithdrawalToken.toString()).to.be.eq(
          isEth ? TOKEN_DEPOSIT.toString() : TOKEN_DEPOSIT.sub(params.amount).toString(),
        )

        // Verify post withdrawal recipient balance
        const postWithdrawalRecipient = isEth
          ? await governer.provider.getBalance(params.recipient)
          : await token.balanceOf(params.recipient)

        // TODO: settle function is called correctly by multisig,
        // but transfer seems to fail
        expect(postWithdrawalRecipient.toString()).to.be.eq(
          !isEth && params.recipient === node.address
            ? preWithdraw.add(params.amount).toString()
            : preWithdraw.toString(),
        )
      }
    })

    it('node should be able to withdraw eth (no balance increase, transaction does not revert)', async function() {
      // Generate withdrawal commitment for node
      const commitment = new MiniCommitment(multisig.address, [node, indexer])

      // Generate test params
      const params = {
        assetId: AddressZero,
        amount: 5,
        recipient: node.address,
        withdrawInterpreterAddress: withdrawInterpreter.address,
        ctdt: indexerCTDT,
      }

      await sendWithdrawalCommitment(commitment, params)
    })

    it('node should be able to withdraw tokens', async function() {
      // Generate withdrawal commitment for node
      const commitment = new MiniCommitment(multisig.address, [node, indexer])

      // Generate test params
      const params = {
        assetId: token.address,
        amount: 5,
        recipient: node.address,
        withdrawInterpreterAddress: withdrawInterpreter.address,
        ctdt: indexerCTDT,
      }

      await sendWithdrawalCommitment(commitment, params)
    })

    it('indexer should be able to withdraw eth (settle is not called)', async function() {
      // Generate withdrawal commitment for node
      const commitment = new MiniCommitment(multisig.address, [node, indexer])

      // Generate test params
      const params = {
        assetId: AddressZero,
        amount: 5,
        recipient: indexer.address,
        withdrawInterpreterAddress: withdrawInterpreter.address,
        ctdt: indexerCTDT,
      }

      await sendWithdrawalCommitment(commitment, params)
    })

    it('indexer should be able to withdraw tokens (settle is called with correct amount by multisig)', async function() {
      // Generate withdrawal commitment for node
      const commitment = new MiniCommitment(multisig.address, [node, indexer])

      // Generate test params
      const params = {
        assetId: token.address,
        amount: 5,
        recipient: indexer.address,
        withdrawInterpreterAddress: withdrawInterpreter.address,
        ctdt: indexerCTDT,
      }

      const settleEvent = await new Promise((resolve, reject) => {
        mockStaking.once('SettleCalled', (amount, sender) => {
          resolve({ amount, sender })
        })
        sendWithdrawalCommitment(commitment, params).catch(e => reject(e.stack || e.message))
      })
      const { amount, sender } = (settleEvent as unknown) as any
      expect(amount).to.be.eq(params.amount)
      expect(sender).to.be.eq(multisig.address)
    })
  })

  describe('disputes', function() {
    // Establish test constants
    const ETH_DEPOSIT = bigNumberify(175)
    const TOKEN_DEPOSIT = parseEther('4')

    let appInitialDisputeTx: any
    let freeBalanceDisputeTx: any

    // Helpers
    let initiateAndVerifyDispute: (disputer: ChannelSigner, isApp?: boolean) => Promise<void>

    beforeEach(async function() {
      // fund multisig and staking contract
      const tx = await token.transfer(mockStaking.address, TOKEN_DEPOSIT)
      await tx.wait()
      await fundMultisigAndAssert(ETH_DEPOSIT)
      await fundMultisigAndAssert(TOKEN_DEPOSIT, token)

      // Get the app initial dispute tx + identity hash
      const { identityHash, transaction } = await getInitialDisputeTx(
        mockDispute.address,
        app.address,
        multisig.address,
        [node.address, indexer.address],
      )
      appInitialDisputeTx = transaction

      // Create free balance state to dispute
      const fbState = {
        activeApps: [identityHash],
        tokenAddresses: [AddressZero, token.address],
        balances: [
          [
            { to: node.address, amount: ETH_DEPOSIT.div(2) },
            { to: indexer.address, amount: ETH_DEPOSIT.div(2) },
          ],
          [
            { to: node.address, amount: TOKEN_DEPOSIT.div(2) },
            { to: indexer.address, amount: TOKEN_DEPOSIT.div(2) },
          ],
        ],
      }

      // Get the db initial dispute tx + identity hash
      const fbInfo = await getInitialDisputeTx(
        mockDispute.address,
        identity.address,
        multisig.address,
        [node.address, indexer.address],
        fbState,
        freeBalanceStateEncoding,
      )
      freeBalanceDisputeTx = fbInfo.transaction

      // Helpers
      initiateAndVerifyDispute = async (disputer: ChannelSigner, isApp: boolean = true) => {
        // Initiate dispute onchain/
        const tx = await disputer.sendTransaction(
          isApp ? appInitialDisputeTx : freeBalanceDisputeTx,
        )
        await tx.wait()
        const disputeId = isApp ? identityHash : fbInfo.identityHash
        const challenge = await mockDispute.functions.appChallenges(disputeId)
        expect(challenge.status).to.be.eq(ChallengeStatus.OUTCOME_SET)
      }
    })

    it('indexer can execute a channel dispute (1 app, free balance)', async function() {
      // Have indexer initiate both free balance and app dispute

      // FIXME: see TODO in channel.ts#getRandomFundedChannelSigners
      await initiateAndVerifyDispute(indexer)
      await initiateAndVerifyDispute(indexer, false)
    })

    it.skip('node can execute a channel dispute (1 app, free balance)', async function() {})
  })
})
