import { expect } from 'chai'
import { ethers } from '@nomiclabs/buidler'
import { constants, utils, BigNumberish, BigNumber, Signer } from 'ethers'

import { ChallengeStatus, MinimalTransaction } from '@connext/types'
import { ChannelSigner, toBN } from '@connext/utils'

import { deployGRT, deployMultisigWithProxy } from '../lib/deployment'
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
import { IndexerCtdt } from '../../build/typechain/contracts/IndexerCtdt'
import { IndexerSingleAssetInterpreter } from '../../build/typechain/contracts/IndexerSingleAssetInterpreter'
import { IndexerMultiAssetInterpreter } from '../../build/typechain/contracts/IndexerMultiAssetInterpreter'
import { IndexerWithdrawInterpreter } from '../../build/typechain/contracts/IndexerWithdrawInterpreter'
import { MockStaking } from '../../build/typechain/contracts/MockStaking'
import { GraphToken } from '../../build/typechain/contracts/GraphToken'
import { MockDispute } from '../../build/typechain/contracts/MockDispute'
import { AppWithAction } from '../../build/typechain/contracts/AppWithAction'
import { IdentityApp } from '../../build/typechain/contracts/IdentityApp'

const { AddressZero, Zero } = constants
const { parseEther } = utils

describe('Indexer Channel Operations', () => {
  let indexerMultisig: MinimumViableMultisig
  let nonIndexerMultisig: MinimumViableMultisig
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
  let thirdparty: ChannelSigner
  let token: GraphToken
  let governer: Signer

  // helpers
  let fundMultisigAndAssert: (
    multisig: MinimumViableMultisig,
    amount: BigNumberish,
    token?: GraphToken,
  ) => Promise<void>
  let sendTransactionWithSettle: (
    tx: MinimalTransaction,
    sender?: ChannelSigner,
  ) => Promise<{ amount: BigNumber; sender: string }>

  beforeEach(async function () {
    const accounts = await ethers.getSigners()
    governer = accounts[0]

    // Deploy graph token
    token = await deployGRT(await governer.getAddress())

    // Get channel signers
    const [_node, _indexer, _thirdparty] = await getRandomFundedChannelSigners(3, governer, token)
    node = _node
    indexer = _indexer
    thirdparty = _thirdparty

    // Deploy indexer multisig + CTDT + interpreters
    const channelContracts = await deployMultisigWithProxy(node.address, token.address, [
      node,
      indexer,
    ])
    indexerCTDT = channelContracts.ctdt
    singleAssetInterpreter = channelContracts.singleAssetInterpreter
    multiAssetInterpreter = channelContracts.multiAssetInterpreter
    withdrawInterpreter = channelContracts.withdrawInterpreter
    mockStaking = channelContracts.mockStaking
    mockDispute = channelContracts.mockDispute
    indexerMultisig = channelContracts.multisig
    app = channelContracts.app
    identity = channelContracts.identity

    // Deploy non-indexer multisig
    const { multisig: _nonIndexerMultisig } = await deployMultisigWithProxy(
      node.address,
      token.address,
      [node, thirdparty],
      { ...channelContracts },
    )
    nonIndexerMultisig = _nonIndexerMultisig

    // Add channel to mock staking contract for indexer only
    await mockStaking.setChannel(indexer.address)

    // Helpers
    fundMultisigAndAssert = async (
      multisig: MinimumViableMultisig,
      amount: BigNumberish,
      tokenContract?: GraphToken,
    ) => {
      // Get + verify pre deposit balance
      const preDeposit = tokenContract
        ? await tokenContract.balanceOf(multisig.address)
        : await governer.provider.getBalance(multisig.address)
      expect(preDeposit.toString()).to.be.eq('0')

      // Fund multisig from governor
      await fundMultisig(BigNumber.from(amount), multisig.address, governer, tokenContract)

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

  describe('funding + withdrawal', function () {
    // Establish test constants
    const ETH_DEPOSIT = BigNumber.from(180)
    const TOKEN_DEPOSIT = parseEther('4')

    let sendWithdrawalCommitment: (
      commitment: MiniCommitment,
      params: any,
      isIndexerNodeChannel: boolean,
    ) => Promise<void>

    beforeEach(async function () {
      // make sure staking contract is funded
      const tx = await token.transfer(mockStaking.address, TOKEN_DEPOSIT)
      await tx.wait()

      // Fund all multisigs with eth and tokens
      await fundMultisigAndAssert(indexerMultisig, ETH_DEPOSIT)
      await fundMultisigAndAssert(indexerMultisig, TOKEN_DEPOSIT, token)
      await fundMultisigAndAssert(nonIndexerMultisig, ETH_DEPOSIT)
      await fundMultisigAndAssert(nonIndexerMultisig, TOKEN_DEPOSIT, token)

      // Helper
      sendWithdrawalCommitment = async (
        commitment: MiniCommitment,
        params: any,
        isIndexerNodeChannel: boolean,
      ) => {
        const commitmentType = CommitmentTypes.withdraw

        // Get the right multisig
        const multisig = isIndexerNodeChannel ? indexerMultisig : nonIndexerMultisig

        // Get recipient address pre withdraw balance
        const isEth = params.assetId === AddressZero
        const preWithdraw = isEth
          ? await governer.provider.getBalance(params.recipient)
          : await token.balanceOf(params.recipient)

        // Send transaction
        const tx = await commitment.getSignedTransaction(commitmentType, params)
        await governer.sendTransaction(tx)

        // Generate expected values
        const expected: any = {
          [multisig.address]: {
            [AddressZero]:
              !isEth || isIndexerNodeChannel ? ETH_DEPOSIT : ETH_DEPOSIT.sub(params.amount),
            [token.address]: isEth ? TOKEN_DEPOSIT : TOKEN_DEPOSIT.sub(params.amount),
          },
          [params.recipient]: {
            [params.assetId]: !isIndexerNodeChannel
              ? preWithdraw.add(params.amount)
              : !isEth && params.recipient === node.address
              ? preWithdraw.add(params.amount)
              : preWithdraw,
          },
        }

        const postWithdrawalEth = await governer.provider.getBalance(multisig.address)
        const postWithdrawalToken = await token.balanceOf(multisig.address)
        const postWithdrawalRecipient = isEth
          ? await governer.provider.getBalance(params.recipient)
          : await token.balanceOf(params.recipient)

        // Verify post withdrawal multisig balances
        expect(postWithdrawalEth).to.be.eq(expected[multisig.address][AddressZero])
        expect(postWithdrawalToken).to.be.eq(expected[multisig.address][token.address])

        // Verify post withdrawal recipient balance
        expect(postWithdrawalRecipient).to.be.eq(expected[params.recipient][params.assetId])
      }
    })

    it('node should be able to withdraw eth (no balance increase, transaction does not revert) in indexer/node channels', async function () {
      // Generate withdrawal commitment for node
      const commitment = new MiniCommitment(indexerMultisig.address, [node, indexer])

      // Generate test params
      const params = {
        assetId: AddressZero,
        amount: 5,
        recipient: node.address,
        withdrawInterpreterAddress: withdrawInterpreter.address,
        ctdt: indexerCTDT,
      }

      await sendWithdrawalCommitment(commitment, params, true)
    })

    it('node should be able to withdraw eth (no balance increase, transaction does not revert) in non-indexer/node channels', async function () {
      // Generate withdrawal commitment for node
      const commitment = new MiniCommitment(nonIndexerMultisig.address, [node, thirdparty])

      // Generate test params
      const params = {
        assetId: AddressZero,
        amount: 5,
        recipient: node.address,
        withdrawInterpreterAddress: withdrawInterpreter.address,
        ctdt: indexerCTDT,
      }

      await sendWithdrawalCommitment(commitment, params, true)
    })

    it('node should be able to withdraw tokens in indexer/node channels', async function () {
      // Generate withdrawal commitment for node
      const commitment = new MiniCommitment(indexerMultisig.address, [node, indexer])

      // Generate test params
      const params = {
        assetId: token.address,
        amount: 5,
        recipient: node.address,
        withdrawInterpreterAddress: withdrawInterpreter.address,
        ctdt: indexerCTDT,
      }

      await sendWithdrawalCommitment(commitment, params, true)
    })

    it.skip('node should be able to withdraw tokens in non-indexer/node channels', async function () {
      // Generate withdrawal commitment for node
      const commitment = new MiniCommitment(nonIndexerMultisig.address, [node, thirdparty])

      // Generate test params
      const params = {
        assetId: token.address,
        amount: 5,
        recipient: node.address,
        withdrawInterpreterAddress: withdrawInterpreter.address,
        ctdt: indexerCTDT,
      }

      await sendWithdrawalCommitment(commitment, params, true)
    })

    it('indexer should be able to withdraw eth (settle is not called)', async function () {
      // Generate withdrawal commitment for node
      const commitment = new MiniCommitment(indexerMultisig.address, [node, indexer])

      // Generate test params
      const params = {
        assetId: AddressZero,
        amount: 5,
        recipient: indexer.address,
        withdrawInterpreterAddress: withdrawInterpreter.address,
        ctdt: indexerCTDT,
      }

      await sendWithdrawalCommitment(commitment, params, true)
    })

    it('indexer should be able to withdraw tokens (settle is called with correct amount by multisig)', async function () {
      // Generate withdrawal commitment for node
      const commitment = new MiniCommitment(indexerMultisig.address, [node, indexer])

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
        sendWithdrawalCommitment(commitment, params, true).catch((e) =>
          reject(e.stack || e.message),
        )
      })
      const { amount, sender } = (settleEvent as unknown) as any
      expect(amount).to.be.eq(params.amount)
      expect(sender).to.be.eq(indexerMultisig.address)
    })

    it('node should be able to withdraw tokens in non-indexer/node channels', async function () {})
  })

  describe('disputes', function () {
    // Establish test constants
    const ETH_DEPOSIT = BigNumber.from(180)
    const TOKEN_DEPOSIT = parseEther('4')
    const APP_DEPOSIT = toBN(15)

    // Helpers
    let createOnchainDisputes: (
      isIndexerNodeChannel: boolean,
      appBeneficiary?: ChannelSigner,
    ) => Promise<{ freeBalanceIdentityHash: string; appIdentityHash: string }>
    let getOnchainBalances: (isIndexerNodeChannel: boolean) => Promise<any>
    let verifyPostAppDisputeBalances: (
      isIndexerNodeChannel: boolean,
      preDisputeBalances: any,
      disputer: ChannelSigner,
      appBeneficiary?: ChannelSigner,
      isToken?: boolean,
    ) => Promise<void>
    let verifyPostFreeBalanceDisputeBalances: (
      isIndexerNodeChannel: boolean,
      preDisputeBalances: any,
      disputer: ChannelSigner,
      nodeSettlement?: BigNumber,
      counterpartySettlement?: BigNumber,
    ) => Promise<void>
    let sendAndVerifySetup: (
      isIndexerNodeChannel: boolean,
      params: any,
      commitment: MiniCommitment,
      disputer?: ChannelSigner,
      counterpartySettlement?: BigNumber,
      nodeSettlement?: BigNumber,
    ) => Promise<void>
    let sendAndVerifyConditional: (
      isIndexerNodeChannel: boolean,
      params: any,
      commitment: MiniCommitment,
      disputer?: ChannelSigner,
      beneficiary?: ChannelSigner,
    ) => Promise<void>

    beforeEach(async function () {
      // Fund multisig and staking contract
      const tx = await token.transfer(mockStaking.address, TOKEN_DEPOSIT)
      await tx.wait()
      await fundMultisigAndAssert(indexerMultisig, ETH_DEPOSIT)
      await fundMultisigAndAssert(indexerMultisig, TOKEN_DEPOSIT, token)

      // Helpers
      createOnchainDisputes = async (
        isIndexerNodeChannel: boolean,
        appBeneficiary: ChannelSigner = node,
      ) => {
        const multisig = isIndexerNodeChannel ? indexerMultisig : nonIndexerMultisig
        const multisigOwners = [
          node.address,
          isIndexerNodeChannel ? indexer.address : thirdparty.address,
        ]
        // Get state with deposit going to beneficiary (participants[0])
        const participants = [
          appBeneficiary.address,
          multisigOwners.find((owner) => owner !== appBeneficiary.address),
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

      getOnchainBalances = async (isIndexerNodeChannel: boolean) => {
        const multisig = isIndexerNodeChannel ? indexerMultisig : nonIndexerMultisig
        const counterpartyAddr = isIndexerNodeChannel ? indexer.address : node.address
        const provider = governer.provider
        return {
          [AddressZero]: {
            [multisig.address]: await provider.getBalance(multisig.address),
            [counterpartyAddr]: await provider.getBalance(counterpartyAddr),
            [node.address]: await provider.getBalance(node.address),
          },
          [token.address]: {
            [multisig.address]: await token.balanceOf(multisig.address),
            [counterpartyAddr]: await token.balanceOf(counterpartyAddr),
            [node.address]: await token.balanceOf(node.address),
          },
        }
      }

      verifyPostAppDisputeBalances = async (
        isIndexerNodeChannel: boolean,
        preDisputeBalances: any,
        disputer: ChannelSigner,
        appBeneficiary: ChannelSigner = node,
        isToken: boolean = true,
      ) => {
        const postDisputeBalances = await getOnchainBalances(isIndexerNodeChannel)
        const multisig = isIndexerNodeChannel ? indexerMultisig : nonIndexerMultisig
        const nodeIsBeneficiary = appBeneficiary.address === node.address
        const counterpartyAddr = isIndexerNodeChannel ? indexer.address : node.address

        // NOTE: assumes app will always have token balance
        const counterpartyPreToken = preDisputeBalances[token.address][counterpartyAddr]
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

            [counterpartyAddr]:
              !isToken || nodeIsBeneficiary
                ? counterpartyPreToken
                : counterpartyPreToken.add(isIndexerNodeChannel ? Zero : APP_DEPOSIT),
          },
        }

        // Verify all balances
        Object.keys(postDisputeBalances).forEach((assetId) => {
          Object.keys(postDisputeBalances[assetId]).forEach((address) => {
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
        isIndexerNodeChannel: boolean,
        preDisputeBalances: any,
        disputer: ChannelSigner,
        nodeSettlement: BigNumber = TOKEN_DEPOSIT.div(2),
        counterpartySettlement: BigNumber = Zero,
      ) => {
        const postDisputeBalances = await getOnchainBalances(isIndexerNodeChannel)
        const multisig = isIndexerNodeChannel ? indexerMultisig : nonIndexerMultisig
        const counterpartyAddr = isIndexerNodeChannel ? indexer.address : node.address
        const expected = {
          ...preDisputeBalances,
          [token.address]: {
            ...preDisputeBalances[token.address],
            [multisig.address]: Zero,
            [node.address]: preDisputeBalances[token.address][node.address].add(nodeSettlement),
            [counterpartyAddr]: preDisputeBalances[token.address][counterpartyAddr].add(
              counterpartySettlement,
            ),
          },
        }

        // Verify all balances
        Object.keys(postDisputeBalances).forEach((assetId) => {
          Object.keys(postDisputeBalances[assetId]).forEach((address) => {
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
        isIndexerNodeChannel: boolean,
        params: any,
        commitment: MiniCommitment,
        disputer: ChannelSigner = indexer,
        beneficiary: ChannelSigner = indexer,
      ) => {
        const multisig = isIndexerNodeChannel ? indexerMultisig : nonIndexerMultisig
        // Execute effect of app dispute
        const preAppDisputeBalances = await getOnchainBalances(isIndexerNodeChannel)
        const conditionalTx = await commitment.getSignedTransaction(
          CommitmentTypes.conditional,
          params,
        )
        if (isIndexerNodeChannel) {
          const appSettleEvent = await sendTransactionWithSettle(conditionalTx, disputer)
          expect(appSettleEvent.amount).to.be.eq(
            beneficiary.address === indexer.address ? params.amount : Zero,
          )
          expect(appSettleEvent.sender).to.be.eq(multisig.address)
        } else {
          const tx = await disputer.sendTransaction(conditionalTx)
          await tx.wait()
        }

        // Verify balances post app dispute execution
        await verifyPostAppDisputeBalances(
          isIndexerNodeChannel,
          preAppDisputeBalances,
          disputer,
          beneficiary,
          params.assetId !== AddressZero,
        )
      }

      sendAndVerifySetup = async (
        isIndexerNodeChannel: boolean,
        params: any,
        commitment: MiniCommitment,
        disputer: ChannelSigner = indexer,
        counterpartySettlement: BigNumber = TOKEN_DEPOSIT.div(2).sub(APP_DEPOSIT),
        nodeSettlement: BigNumber = TOKEN_DEPOSIT.div(2),
      ) => {
        const multisig = isIndexerNodeChannel ? indexerMultisig : nonIndexerMultisig
        const preFreeBalanceDisputeBalances = await getOnchainBalances(isIndexerNodeChannel)
        const fbTx = await commitment.getSignedTransaction(CommitmentTypes.setup, {
          ...params,
          interpreterAddr: multiAssetInterpreter.address,
        })
        if (isIndexerNodeChannel) {
          const freeBalanceSettleEvent = await sendTransactionWithSettle(fbTx, disputer)
          expect(freeBalanceSettleEvent.amount).to.be.eq(counterpartySettlement)
          expect(freeBalanceSettleEvent.sender).to.be.eq(multisig.address)
        } else {
          const tx = await disputer.sendTransaction(fbTx)
          await tx.wait()
        }

        // Verify balances post fb dispute execution
        await verifyPostFreeBalanceDisputeBalances(
          isIndexerNodeChannel,
          preFreeBalanceDisputeBalances,
          disputer,
          nodeSettlement,
        )
      }
    })

    it('indexer can execute a channel dispute (1 app where they are owed tokens, free balance)', async function () {
      // Have indexer initiate both free balance and app dispute
      const { freeBalanceIdentityHash, appIdentityHash } = await createOnchainDisputes(
        true,
        indexer,
      )

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
      const commitment = new MiniCommitment(indexerMultisig.address, [node, indexer])

      // Execute conditional tx (app dispute)
      await sendAndVerifyConditional(true, params, commitment)

      // Execute fb tx (empty multisig)
      await sendAndVerifySetup(true, params, commitment)
    })

    it('node can execute a channel dispute (1 app where they are owed tokens, free balance)', async function () {
      // Have indexer initiate both free balance and app dispute
      const { freeBalanceIdentityHash, appIdentityHash } = await createOnchainDisputes(true, node)

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
      const commitment = new MiniCommitment(indexerMultisig.address, [node, indexer])

      // Execute conditional tx (app dispute)
      await sendAndVerifyConditional(true, params, commitment, node, node)

      // Execute fb tx (empty multisig)
      await sendAndVerifySetup(
        true,
        params,
        commitment,
        node,
        TOKEN_DEPOSIT.div(2),
        TOKEN_DEPOSIT.div(2).sub(APP_DEPOSIT),
      )
    })
  })
})
