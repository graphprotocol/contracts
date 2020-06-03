import { expect } from 'chai'
import { ethers } from '@nomiclabs/buidler'
import { Signer } from 'ethers'
import { bigNumberify, parseEther, BigNumberish, BigNumber } from 'ethers/utils'
import { ChallengeStatus, MinimalTransaction } from '@connext/types'
import { ChannelSigner, toBN } from '@connext/utils'

import { deployGRTWithFactory, deployIndexerMultisigWithContext } from '../lib/deployment'
import {
  getRandomFundedChannelSigners,
  fundMultisig,
  MiniCommitment,
  CommitmentTypes,
  getAppInitialState,
  getFreeBalanceState,
  appWithCounterStateEncoding,
  createAppDispute,
} from '../lib/channel'
import { MinimumViableMultisig } from '../../build/typechain/contracts/MinimumViableMultisig'
import { IndexerCtdt } from '../../build/typechain/contracts/IndexerCTDT'
import { IndexerSingleAssetInterpreter } from '../../build/typechain/contracts/IndexerSingleAssetInterpreter'
import { IndexerMultiAssetInterpreter } from '../../build/typechain/contracts/IndexerMultiAssetInterpreter'
import { IndexerWithdrawInterpreter } from '../../build/typechain/contracts/IndexerWithdrawInterpreter'
import { MockStaking } from '../../build/typechain/contracts/MockStaking'
import { GraphToken } from '../../build/typechain/contracts/GraphToken'
import { AddressZero, Zero } from 'ethers/constants'
import { MockDispute } from '../../build/typechain/contracts/MockDispute'
import { AppWithAction } from '../../build/typechain/contracts/AppWithAction'
import { IdentityApp } from '../../build/typechain/contracts/IdentityApp'

describe('Indexer Channel Operations', () => {
  let multisig: MinimumViableMultisig
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
  let sendTransactionWithSettle: (
    tx: MinimalTransaction,
    sender?: ChannelSigner,
  ) => Promise<{ amount: BigNumber; sender: string }>

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
    const channelContracts = await deployIndexerMultisigWithContext(node.address, token.address, [
      node,
      indexer,
    ])
    indexerCTDT = channelContracts.ctdt
    singleAssetInterpreter = channelContracts.singleAssetInterpreter
    multiAssetInterpreter = channelContracts.multiAssetInterpreter
    withdrawInterpreter = channelContracts.withdrawInterpreter
    mockStaking = channelContracts.mockStaking
    mockDispute = channelContracts.mockDispute
    multisig = channelContracts.multisig
    app = channelContracts.app
    identity = channelContracts.identity

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

    sendTransactionWithSettle = async (
      tx: MinimalTransaction,
      txSender: ChannelSigner = indexer,
    ): Promise<{ amount: BigNumber; sender: string }> => {
      const settleEvent = await new Promise(async (resolve, reject) => {
        mockStaking.once('SettleCalled', (amount, sender) => {
          resolve({ amount, sender })
        })
        try {
          const response = await txSender.sendTransaction(tx)
          await response.wait()
        } catch (e) {
          return reject(e)
        }
      })
      return settleEvent as any
    }
  })

  describe('funding + withdrawal', function() {
    // Establish test constants
    const ETH_DEPOSIT = bigNumberify(180)
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
        const commitmentType = CommitmentTypes.withdraw

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
    const ETH_DEPOSIT = bigNumberify(180)
    const TOKEN_DEPOSIT = parseEther('4')
    const APP_DEPOSIT = toBN(15)

    // Helpers
    let createOnchainDisputes: (
      appBeneficiary?: ChannelSigner,
    ) => Promise<{ freeBalanceIdentityHash: string; appIdentityHash: string }>
    let getOnchainBalances: () => Promise<any>
    let verifyPostAppDisputeBalances: (
      preDisputeBalances: any,
      disputer: ChannelSigner,
      appBeneficiary?: ChannelSigner,
      isToken?: boolean,
    ) => Promise<void>
    let verifyPostFreeBalanceDisputeBalances: (
      preDisputeBalances: any,
      disputer: ChannelSigner,
      nodeSettlement?: BigNumber,
    ) => Promise<void>
    let sendAndVerifySetup: (
      params: any,
      commitment: MiniCommitment,
      disputer?: ChannelSigner,
      indexerSettlement?: BigNumber,
      nodeSettlement?: BigNumber,
    ) => Promise<void>
    let sendAndVerifyConditional: (
      params: any,
      commitment: MiniCommitment,
      disputer?: ChannelSigner,
      beneficiary?: ChannelSigner,
    ) => Promise<void>

    beforeEach(async function() {
      const multisigOwners = [node.address, indexer.address]

      // Fund multisig and staking contract
      const tx = await token.transfer(mockStaking.address, TOKEN_DEPOSIT)
      await tx.wait()
      await fundMultisigAndAssert(ETH_DEPOSIT)
      await fundMultisigAndAssert(TOKEN_DEPOSIT, token)

      // Helpers
      createOnchainDisputes = async (appBeneficiary: ChannelSigner = node) => {
        // Get state with deposit going to beneficiary (participants[0])
        const participants = [
          appBeneficiary.address,
          multisigOwners.find(owner => owner !== appBeneficiary.address),
        ]
        const appInitialState = getAppInitialState(APP_DEPOSIT, participants)

        // Create initial app dispute and set outcome
        const appIdentityHash = await createAppDispute(
          mockDispute,
          app.address,
          multisig.address,
          multisigOwners,
          appInitialState,
          appWithCounterStateEncoding,
          participants,
        )
        const appChallenge = await mockDispute.functions.appChallenges(appIdentityHash)
        expect(appChallenge.status).to.be.eq(ChallengeStatus.OUTCOME_SET)

        // Create free balance state
        const freeBalanceState = getFreeBalanceState(
          multisigOwners,
          ETH_DEPOSIT,
          TOKEN_DEPOSIT,
          appBeneficiary,
          [{ identityHash: appIdentityHash, assetId: token.address, deposit: APP_DEPOSIT }],
        )

        // Create initial fb dispute and set outcome
        const freeBalanceIdentityHash = await createAppDispute(
          mockDispute,
          identity.address,
          multisig.address,
          multisigOwners,
          freeBalanceState,
        )
        const freeBalanceChallenge = await mockDispute.functions.appChallenges(
          freeBalanceIdentityHash,
        )
        expect(freeBalanceChallenge.status).to.be.eq(ChallengeStatus.OUTCOME_SET)
        return { freeBalanceIdentityHash, appIdentityHash }
      }

      getOnchainBalances = async () => {
        const provider = governer.provider
        return {
          [AddressZero]: {
            [multisig.address]: await provider.getBalance(multisig.address),
            [indexer.address]: await provider.getBalance(indexer.address),
            [node.address]: await provider.getBalance(node.address),
          },
          [token.address]: {
            [multisig.address]: await token.balanceOf(multisig.address),
            [indexer.address]: await token.balanceOf(indexer.address),
            [node.address]: await token.balanceOf(node.address),
          },
        }
      }

      verifyPostAppDisputeBalances = async (
        preDisputeBalances: any,
        disputer: ChannelSigner,
        appBeneficiary: ChannelSigner = node,
        isToken: boolean = true,
      ) => {
        const postDisputeBalances = await getOnchainBalances()
        const nodeIsBeneficiary = appBeneficiary.address === node.address

        const expected = {
          ...preDisputeBalances,
          [token.address]: {
            ...preDisputeBalances[token.address],

            [multisig.address]: preDisputeBalances[token.address][multisig.address].sub(
              isToken ? APP_DEPOSIT : Zero,
            ),

            [node.address]: preDisputeBalances[token.address][node.address].add(
              isToken && nodeIsBeneficiary ? APP_DEPOSIT : Zero,
            ),
          },
        }

        // Verify all balances
        Object.keys(postDisputeBalances).forEach(assetId => {
          Object.keys(postDisputeBalances[assetId]).forEach(address => {
            // if its the disputer, and its eth, account for gas
            if (address === disputer.address && assetId === AddressZero) {
              expect(postDisputeBalances[assetId][address]).to.be.at.most(
                expected[assetId][address],
              )
              return
            }
            expect(postDisputeBalances[assetId][address]).to.be.eq(expected[assetId][address])
          })
        })
      }

      verifyPostFreeBalanceDisputeBalances = async (
        preDisputeBalances: any,
        disputer: ChannelSigner,
        nodeSettlement: BigNumber = TOKEN_DEPOSIT.div(2),
      ) => {
        const postDisputeBalances = await getOnchainBalances()
        const expected = {
          ...preDisputeBalances,
          [token.address]: {
            ...preDisputeBalances[token.address],
            [multisig.address]: Zero,
            [node.address]: preDisputeBalances[token.address][node.address].add(nodeSettlement),
          },
        }

        // Verify all balances
        Object.keys(postDisputeBalances).forEach(assetId => {
          Object.keys(postDisputeBalances[assetId]).forEach(address => {
            // if its the disputer, and its eth, account for gas
            if (address === disputer.address && assetId === AddressZero) {
              expect(postDisputeBalances[assetId][address]).to.be.at.most(
                expected[assetId][address],
              )
              return
            }
            expect(postDisputeBalances[assetId][address]).to.be.eq(expected[assetId][address])
          })
        })
      }

      sendAndVerifyConditional = async (
        params: any,
        commitment: MiniCommitment,
        disputer: ChannelSigner = indexer,
        beneficiary: ChannelSigner = indexer,
      ) => {
        // Execute effect of app dispute
        const preAppDisputeBalances = await getOnchainBalances()
        const conditionalTx = await commitment.getSignedTransaction(
          CommitmentTypes.conditional,
          params,
        )
        const appSettleEvent = await sendTransactionWithSettle(conditionalTx, disputer)
        expect(appSettleEvent.amount).to.be.eq(
          beneficiary.address === indexer.address ? params.amount : Zero,
        )
        expect(appSettleEvent.sender).to.be.eq(multisig.address)

        // Verify balances post app dispute execution
        await verifyPostAppDisputeBalances(
          preAppDisputeBalances,
          disputer,
          beneficiary,
          params.assetId !== AddressZero,
        )
      }

      sendAndVerifySetup = async (
        params: any,
        commitment: MiniCommitment,
        disputer: ChannelSigner = indexer,
        indexerSettlement: BigNumber = TOKEN_DEPOSIT.div(2).sub(APP_DEPOSIT),
        nodeSettlement: BigNumber = TOKEN_DEPOSIT.div(2),
      ) => {
        const preFreeBalanceDisputeBalances = await getOnchainBalances()
        const fbTx = await commitment.getSignedTransaction(CommitmentTypes.setup, {
          ...params,
          interpreterAddr: multiAssetInterpreter.address,
        })
        const freeBalanceSettleEvent = await sendTransactionWithSettle(fbTx, disputer)
        expect(freeBalanceSettleEvent.amount).to.be.eq(indexerSettlement)
        expect(freeBalanceSettleEvent.sender).to.be.eq(multisig.address)

        // Verify balances post fb dispute execution
        await verifyPostFreeBalanceDisputeBalances(
          preFreeBalanceDisputeBalances,
          disputer,
          nodeSettlement,
        )
      }
    })

    it('indexer can execute a channel dispute (1 app where they are owed tokens, free balance)', async function() {
      // Have indexer initiate both free balance and app dispute
      const { freeBalanceIdentityHash, appIdentityHash } = await createOnchainDisputes(indexer)

      // Generate parameters
      const params = {
        ctdt: indexerCTDT,
        freeBalanceIdentityHash,
        appIdentityHash,
        interpreterAddr: singleAssetInterpreter.address,
        amount: APP_DEPOSIT,
        assetId: token.address,
        mockDispute,
      }

      // Create the commitment
      const commitment = new MiniCommitment(multisig.address, [node, indexer])

      // Execute conditional tx (app dispute)
      await sendAndVerifyConditional(params, commitment, indexer, indexer)

      // Execute fb tx (empty multisig)
      await sendAndVerifySetup(params, commitment, indexer)
    })

    it('node can execute a channel dispute (1 app where they are owed tokens, free balance)', async function() {
      // Have indexer initiate both free balance and app dispute
      const { freeBalanceIdentityHash, appIdentityHash } = await createOnchainDisputes(node)

      // Generate parameters
      const params = {
        ctdt: indexerCTDT,
        freeBalanceIdentityHash,
        appIdentityHash,
        interpreterAddr: singleAssetInterpreter.address,
        amount: APP_DEPOSIT,
        assetId: token.address,
        mockDispute,
      }

      // Create the commitment
      const commitment = new MiniCommitment(multisig.address, [node, indexer])

      // Execute conditional tx (app dispute)
      await sendAndVerifyConditional(params, commitment, node, node)

      // Execute fb tx (empty multisig)
      await sendAndVerifySetup(
        params,
        commitment,
        node,
        TOKEN_DEPOSIT.div(2),
        TOKEN_DEPOSIT.div(2).sub(APP_DEPOSIT),
      )
    })
  })
})
