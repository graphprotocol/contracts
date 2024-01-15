import hre from 'hardhat'
import { expect } from 'chai'
import { constants, BigNumber } from 'ethers'
import { defaultAbiCoder, parseEther } from 'ethers/lib/utils'

import { GraphToken } from '../../../build/types/GraphToken'
import { IL1Staking } from '../../../build/types/IL1Staking'
import { IController } from '../../../build/types/IController'
import { L1GraphTokenGateway } from '../../../build/types/L1GraphTokenGateway'
import { L1GraphTokenLockTransferToolMock } from '../../../build/types/L1GraphTokenLockTransferToolMock'
import { L1GraphTokenLockTransferToolBadMock } from '../../../build/types/L1GraphTokenLockTransferToolBadMock'

import { NetworkFixture } from '../lib/fixtures'

import {
  DeployType,
  GraphNetworkContracts,
  deploy,
  deriveChannelKey,
  helpers,
  randomHexBytes,
  toBN,
  toGRT,
} from '@graphprotocol/sdk'
import { SignerWithAddress } from '@nomiclabs/hardhat-ethers/signers'
import { L2GraphTokenGateway, L2Staking } from '../../../build/types'

const { AddressZero } = constants

describe('L1Staking:L2Transfer', () => {
  const graph = hre.graph()
  let governor: SignerWithAddress
  let indexer: SignerWithAddress
  let l2Indexer: SignerWithAddress
  let delegator: SignerWithAddress
  let l2Delegator: SignerWithAddress

  let fixture: NetworkFixture
  let fixtureContracts: GraphNetworkContracts
  let l2MockContracts: GraphNetworkContracts

  let l2StakingMock: L2Staking
  let l2GRTGatewayMock: L2GraphTokenGateway

  let grt: GraphToken
  let staking: IL1Staking
  let controller: IController
  let l1GraphTokenGateway: L1GraphTokenGateway
  let l1GraphTokenLockTransferTool: L1GraphTokenLockTransferToolMock
  let l1GraphTokenLockTransferToolBad: L1GraphTokenLockTransferToolBadMock

  // Test values
  const indexerTokens = toGRT('10000000')
  const delegatorTokens = toGRT('1000000')
  const tokensToStake = toGRT('200000')
  const subgraphDeploymentID = randomHexBytes()
  const channelKey = deriveChannelKey()
  const allocationID = channelKey.address
  const metadata = randomHexBytes(32)
  const minimumIndexerStake = toGRT('100000')
  const delegationTaxPPM = 10000 // 1%
  // Dummy L2 gas values
  const maxGas = toBN('1000000')
  const gasPriceBid = toBN('1000000000')
  const maxSubmissionCost = toBN('1000000000')

  // Allocate with test values
  const allocate = async (tokens: BigNumber) => {
    return staking
      .connect(indexer)
      .allocateFrom(
        indexer.address,
        subgraphDeploymentID,
        tokens,
        allocationID,
        metadata,
        await channelKey.generateProof(indexer.address),
      )
  }

  before(async function () {
    ;[indexer, delegator, l2Indexer, l2Delegator] = await graph.getTestAccounts()
    ;({ governor } = await graph.getNamedAccounts())

    fixture = new NetworkFixture(graph.provider)

    // Deploy L1
    fixtureContracts = await fixture.load(governor)
    grt = fixtureContracts.GraphToken as GraphToken
    staking = fixtureContracts.L1Staking as unknown as IL1Staking
    l1GraphTokenGateway = fixtureContracts.L1GraphTokenGateway as L1GraphTokenGateway
    controller = fixtureContracts.Controller as IController

    // Deploy L1 arbitrum bridge
    await fixture.loadL1ArbitrumBridge(governor)

    // Deploy L2 mock
    l2MockContracts = await fixture.loadMock(true)
    l2StakingMock = l2MockContracts.L2Staking as L2Staking
    l2GRTGatewayMock = l2MockContracts.L2GraphTokenGateway as L2GraphTokenGateway

    // Configure graph bridge
    await fixture.configureL1Bridge(governor, fixtureContracts, l2MockContracts)

    l1GraphTokenLockTransferTool = (
      await deploy(DeployType.Deploy, governor, {
        name: 'L1GraphTokenLockTransferToolMock',
      })
    ).contract as L1GraphTokenLockTransferToolMock

    l1GraphTokenLockTransferToolBad = (
      await deploy(DeployType.Deploy, governor, { name: 'L1GraphTokenLockTransferToolBadMock' })
    ).contract as L1GraphTokenLockTransferToolBadMock

    await helpers.setBalances([
      { address: l1GraphTokenLockTransferTool.address, balance: parseEther('1') },
      { address: l1GraphTokenLockTransferToolBad.address, balance: parseEther('1') },
    ])

    await staking
      .connect(governor)
      .setL1GraphTokenLockTransferTool(l1GraphTokenLockTransferTool.address)

    // Give some funds to the indexer and approve staking contract to use funds on indexer behalf
    await grt.connect(governor).mint(indexer.address, indexerTokens)
    await grt.connect(indexer).approve(staking.address, indexerTokens)

    await grt.connect(governor).mint(delegator.address, delegatorTokens)
    await grt.connect(delegator).approve(staking.address, delegatorTokens)

    await staking.connect(governor).setMinimumIndexerStake(minimumIndexerStake)
    await staking.connect(governor).setDelegationTaxPercentage(delegationTaxPPM) // 1%
  })

  beforeEach(async function () {
    await fixture.setUp()
  })

  afterEach(async function () {
    await fixture.tearDown()
  })

  context('> when not staked', function () {
    describe('transferStakeToL2', function () {
      it('should not allow transferring for someone who has not staked', async function () {
        const tx = staking
          .connect(indexer)
          .transferStakeToL2(
            l2Indexer.address,
            tokensToStake,
            maxGas,
            gasPriceBid,
            maxSubmissionCost,
            {
              value: maxSubmissionCost.add(gasPriceBid.mul(maxGas)),
            },
          )
        await expect(tx).revertedWith('tokensStaked == 0')
      })
    })
  })

  context('> when staked', function () {
    const shouldTransferIndexerStake = async (
      amountToSend: BigNumber,
      options: {
        expectedSeqNum?: number
        l2Beneficiary?: string
      } = {},
    ) => {
      const l2Beneficiary = options.l2Beneficiary ?? l2Indexer.address
      const expectedSeqNum = options.expectedSeqNum ?? 1
      const tx = staking
        .connect(indexer)
        .transferStakeToL2(l2Beneficiary, amountToSend, maxGas, gasPriceBid, maxSubmissionCost, {
          value: maxSubmissionCost.add(gasPriceBid.mul(maxGas)),
        })
      const expectedFunctionData = defaultAbiCoder.encode(['tuple(address)'], [[l2Indexer.address]])

      const expectedCallhookData = defaultAbiCoder.encode(
        ['uint8', 'bytes'],
        [toBN(0), expectedFunctionData], // code = 1 means RECEIVE_INDEXER_CODE
      )
      const expectedL2Data = await l1GraphTokenGateway.getOutboundCalldata(
        grt.address,
        staking.address,
        l2StakingMock.address,
        amountToSend,
        expectedCallhookData,
      )

      await expect(tx)
        .emit(l1GraphTokenGateway, 'TxToL2')
        .withArgs(staking.address, l2GRTGatewayMock.address, toBN(expectedSeqNum), expectedL2Data)
    }

    beforeEach(async function () {
      await staking.connect(indexer).stake(tokensToStake)
    })

    describe('receive()', function () {
      it('should not allow receiving funds from a random address', async function () {
        const tx = indexer.sendTransaction({
          to: staking.address,
          value: parseEther('1'),
        })
        await expect(tx).revertedWith('Only transfer tool can send ETH')
      })
      it('should allow receiving funds from the transfer tool', async function () {
        const impersonatedTransferTool = await helpers.impersonateAccount(
          l1GraphTokenLockTransferTool.address,
        )

        const tx = impersonatedTransferTool.sendTransaction({
          to: staking.address,
          value: parseEther('1'),
        })
        await expect(tx).to.not.be.reverted
      })
    })
    describe('transferStakeToL2', function () {
      it('should not allow transferring if the protocol is partially paused', async function () {
        await controller.connect(governor).setPartialPaused(true)

        const tx = staking
          .connect(indexer)
          .transferStakeToL2(
            l2Indexer.address,
            tokensToStake.sub(minimumIndexerStake),
            maxGas,
            gasPriceBid,
            maxSubmissionCost,
            {
              value: maxSubmissionCost.add(gasPriceBid.mul(maxGas)),
            },
          )
        await expect(tx).revertedWith('Partial-paused')
      })
      it('should not allow transferring but leaving less than the minimum indexer stake', async function () {
        const tx = staking
          .connect(indexer)
          .transferStakeToL2(
            l2Indexer.address,
            tokensToStake.sub(minimumIndexerStake).add(1),
            maxGas,
            gasPriceBid,
            maxSubmissionCost,
            {
              value: maxSubmissionCost.add(gasPriceBid.mul(maxGas)),
            },
          )
        await expect(tx).revertedWith('!minimumIndexerStake remaining')
      })
      it('should not allow transferring less than the minimum indexer stake the first time', async function () {
        const tx = staking
          .connect(indexer)
          .transferStakeToL2(
            l2Indexer.address,
            minimumIndexerStake.sub(1),
            maxGas,
            gasPriceBid,
            maxSubmissionCost,
            {
              value: maxSubmissionCost.add(gasPriceBid.mul(maxGas)),
            },
          )
        await expect(tx).revertedWith('!minimumIndexerStake sent')
      })
      it('should not allow transferring if there are tokens locked for withdrawal', async function () {
        await staking.connect(indexer).unstake(tokensToStake)
        const tx = staking
          .connect(indexer)
          .transferStakeToL2(
            l2Indexer.address,
            tokensToStake,
            maxGas,
            gasPriceBid,
            maxSubmissionCost,
            {
              value: maxSubmissionCost.add(gasPriceBid.mul(maxGas)),
            },
          )
        await expect(tx).revertedWith('tokensLocked != 0')
      })
      it('should not allow transferring to a beneficiary that is address zero', async function () {
        const tx = staking
          .connect(indexer)
          .transferStakeToL2(AddressZero, tokensToStake, maxGas, gasPriceBid, maxSubmissionCost, {
            value: maxSubmissionCost.add(gasPriceBid.mul(maxGas)),
          })
        await expect(tx).revertedWith('l2Beneficiary == 0')
      })
      it('should not allow transferring the whole stake if there are open allocations', async function () {
        await allocate(toGRT('10'))
        const tx = staking
          .connect(indexer)
          .transferStakeToL2(
            l2Indexer.address,
            tokensToStake,
            maxGas,
            gasPriceBid,
            maxSubmissionCost,
            {
              value: maxSubmissionCost.add(gasPriceBid.mul(maxGas)),
            },
          )
        await expect(tx).revertedWith('allocated')
      })
      it('should not allow transferring partial stake if the remaining indexer capacity is insufficient for open allocations', async function () {
        // We set delegation ratio == 1 so an indexer can only use as much delegation as their own stake
        await staking.connect(governor).setDelegationRatio(1)
        const tokensToDelegate = toGRT('202100')
        await staking.connect(delegator).delegate(indexer.address, tokensToDelegate)

        // Now the indexer has 200k tokens staked and 200k tokens delegated
        await allocate(toGRT('400000'))

        // But if we try to transfer even 100k, we will not have enough indexer capacity to cover the open allocation
        const tx = staking
          .connect(indexer)
          .transferStakeToL2(
            l2Indexer.address,
            toGRT('100000'),
            maxGas,
            gasPriceBid,
            maxSubmissionCost,
            {
              value: maxSubmissionCost.add(gasPriceBid.mul(maxGas)),
            },
          )
        await expect(tx).revertedWith('! allocation capacity')
      })
      it('should not allow transferring if the ETH sent is more than required', async function () {
        const tx = staking
          .connect(indexer)
          .transferStakeToL2(
            indexer.address,
            tokensToStake,
            maxGas,
            gasPriceBid,
            maxSubmissionCost,
            {
              value: maxSubmissionCost.add(gasPriceBid.mul(maxGas)).add(1),
            },
          )
        await expect(tx).revertedWith('INVALID_ETH_AMOUNT')
      })
      it('sends the tokens and a message through the L1GraphTokenGateway', async function () {
        const amountToSend = minimumIndexerStake
        await shouldTransferIndexerStake(amountToSend)
        // Check that the indexer stake was reduced by the sent amount
        expect((await staking.stakes(indexer.address)).tokensStaked).to.equal(
          tokensToStake.sub(amountToSend),
        )
      })
      it('should allow transferring the whole stake if there are no open allocations', async function () {
        await shouldTransferIndexerStake(tokensToStake)
        // Check that the indexer stake was reduced by the sent amount
        expect((await staking.stakes(indexer.address)).tokensStaked).to.equal(0)
      })
      it('should allow transferring partial stake if the remaining capacity can cover the allocations', async function () {
        // We set delegation ratio == 1 so an indexer can only use as much delegation as their own stake
        await staking.connect(governor).setDelegationRatio(1)
        const tokensToDelegate = toGRT('200000')
        await staking.connect(delegator).delegate(indexer.address, tokensToDelegate)

        // Now the indexer has 200k tokens staked and 200k tokens delegated,
        // but they allocate 200k
        await allocate(toGRT('200000'))

        // If we transfer 100k, we will still have enough indexer capacity to cover the open allocation
        const amountToSend = toGRT('100000')
        await shouldTransferIndexerStake(amountToSend)
        // Check that the indexer stake was reduced by the sent amount
        expect((await staking.stakes(indexer.address)).tokensStaked).to.equal(
          tokensToStake.sub(amountToSend),
        )
      })
      it('allows transferring several times to the same beneficiary', async function () {
        // Stake a bit more so we're still over the minimum stake after transferring twice
        await staking.connect(indexer).stake(tokensToStake)
        await shouldTransferIndexerStake(minimumIndexerStake)
        await shouldTransferIndexerStake(toGRT('1000'), { expectedSeqNum: 2 })
        expect((await staking.stakes(indexer.address)).tokensStaked).to.equal(
          tokensToStake.mul(2).sub(minimumIndexerStake).sub(toGRT('1000')),
        )
      })
      it('should not allow transferring to a different beneficiary the second time', async function () {
        await shouldTransferIndexerStake(minimumIndexerStake)
        const tx = staking.connect(indexer).transferStakeToL2(
          indexer.address, // Note this is different from l2Indexer used before
          minimumIndexerStake,
          maxGas,
          gasPriceBid,
          maxSubmissionCost,
          {
            value: maxSubmissionCost.add(gasPriceBid.mul(maxGas)),
          },
        )
        await expect(tx).revertedWith('l2Beneficiary != previous')
      })
    })

    describe('transferLockedStakeToL2', function () {
      it('should not allow transferring if the protocol is partially paused', async function () {
        await controller.connect(governor).setPartialPaused(true)

        const tx = staking
          .connect(indexer)
          .transferLockedStakeToL2(minimumIndexerStake, maxGas, gasPriceBid, maxSubmissionCost)
        await expect(tx).revertedWith('Partial-paused')
      })
      it('sends a message through L1GraphTokenGateway like transferStakeToL2, but gets the beneficiary and ETH from a transfer tool contract', async function () {
        const amountToSend = minimumIndexerStake

        await l1GraphTokenLockTransferTool.setL2WalletAddress(indexer.address, l2Indexer.address)
        const oldTransferToolEthBalance = await graph.provider.getBalance(
          l1GraphTokenLockTransferTool.address,
        )
        const tx = staking
          .connect(indexer)
          .transferLockedStakeToL2(minimumIndexerStake, maxGas, gasPriceBid, maxSubmissionCost)
        const expectedFunctionData = defaultAbiCoder.encode(
          ['tuple(address)'],
          [[l2Indexer.address]],
        )

        const expectedCallhookData = defaultAbiCoder.encode(
          ['uint8', 'bytes'],
          [toBN(0), expectedFunctionData], // code = 0 means RECEIVE_INDEXER_CODE
        )
        const expectedL2Data = await l1GraphTokenGateway.getOutboundCalldata(
          grt.address,
          staking.address,
          l2StakingMock.address,
          amountToSend,
          expectedCallhookData,
        )

        await expect(tx)
          .emit(l1GraphTokenGateway, 'TxToL2')
          .withArgs(staking.address, l2GRTGatewayMock.address, toBN(1), expectedL2Data)
        expect(await graph.provider.getBalance(l1GraphTokenLockTransferTool.address)).to.equal(
          oldTransferToolEthBalance.sub(maxSubmissionCost).sub(gasPriceBid.mul(maxGas)),
        )
      })
      it('should not allow transferring if the transfer tool contract returns a zero address beneficiary', async function () {
        const tx = staking
          .connect(indexer)
          .transferLockedStakeToL2(minimumIndexerStake, maxGas, gasPriceBid, maxSubmissionCost)
        await expect(tx).revertedWith('LOCK NOT TRANSFERRED')
      })
      it('should not allow transferring if the transfer tool contract does not provide enough ETH', async function () {
        await staking
          .connect(governor)
          .setL1GraphTokenLockTransferTool(l1GraphTokenLockTransferToolBad.address)
        await l1GraphTokenLockTransferToolBad.setL2WalletAddress(indexer.address, l2Indexer.address)
        const tx = staking
          .connect(indexer)
          .transferLockedStakeToL2(minimumIndexerStake, maxGas, gasPriceBid, maxSubmissionCost)
        await expect(tx).revertedWith('ETH TRANSFER FAILED')
      })
    })
    describe('unlockDelegationToTransferredIndexer', function () {
      beforeEach(async function () {
        await staking.connect(governor).setDelegationUnbondingPeriod(28) // epochs
      })
      it('allows a delegator to a transferred indexer to withdraw locked delegation before the unbonding period', async function () {
        const tokensToDelegate = toGRT('10000')
        await staking.connect(delegator).delegate(indexer.address, tokensToDelegate)
        const actualDelegation = tokensToDelegate.sub(
          tokensToDelegate.mul(delegationTaxPPM).div(1000000),
        )
        await staking
          .connect(indexer)
          .transferStakeToL2(
            l2Indexer.address,
            tokensToStake,
            maxGas,
            gasPriceBid,
            maxSubmissionCost,
            {
              value: maxSubmissionCost.add(gasPriceBid.mul(maxGas)),
            },
          )
        await staking.connect(delegator).undelegate(indexer.address, actualDelegation)
        const tx = await staking
          .connect(delegator)
          .unlockDelegationToTransferredIndexer(indexer.address)
        await expect(tx)
          .emit(staking, 'StakeDelegatedUnlockedDueToL2Transfer')
          .withArgs(indexer.address, delegator.address)
        const tx2 = await staking.connect(delegator).withdrawDelegated(indexer.address, AddressZero)
        await expect(tx2)
          .emit(staking, 'StakeDelegatedWithdrawn')
          .withArgs(indexer.address, delegator.address, actualDelegation)
      })
      it('rejects calls if the protocol is partially paused', async function () {
        await controller.connect(governor).setPartialPaused(true)

        const tx = staking.connect(delegator).unlockDelegationToTransferredIndexer(indexer.address)
        await expect(tx).revertedWith('Partial-paused')
      })
      it('rejects calls if the indexer has not transferred their stake to L2', async function () {
        const tokensToDelegate = toGRT('10000')
        await staking.connect(delegator).delegate(indexer.address, tokensToDelegate)
        const tx = staking.connect(delegator).unlockDelegationToTransferredIndexer(indexer.address)
        await expect(tx).revertedWith('indexer not transferred')
      })
      it('rejects calls if the indexer has only transferred part of their stake but not all', async function () {
        const tokensToDelegate = toGRT('10000')
        await staking.connect(delegator).delegate(indexer.address, tokensToDelegate)
        await staking
          .connect(indexer)
          .transferStakeToL2(
            l2Indexer.address,
            minimumIndexerStake,
            maxGas,
            gasPriceBid,
            maxSubmissionCost,
            {
              value: maxSubmissionCost.add(gasPriceBid.mul(maxGas)),
            },
          )
        const tx = staking.connect(delegator).unlockDelegationToTransferredIndexer(indexer.address)
        await expect(tx).revertedWith('indexer not transferred')
      })
      it('rejects calls if the delegator has not undelegated first', async function () {
        const tokensToDelegate = toGRT('10000')
        await staking.connect(delegator).delegate(indexer.address, tokensToDelegate)
        await staking
          .connect(indexer)
          .transferStakeToL2(
            l2Indexer.address,
            tokensToStake,
            maxGas,
            gasPriceBid,
            maxSubmissionCost,
            {
              value: maxSubmissionCost.add(gasPriceBid.mul(maxGas)),
            },
          )
        const tx = staking.connect(delegator).unlockDelegationToTransferredIndexer(indexer.address)
        await expect(tx).revertedWith('! locked')
      })
      it('rejects calls if the caller is not a delegator', async function () {
        await staking
          .connect(indexer)
          .transferStakeToL2(
            l2Indexer.address,
            tokensToStake,
            maxGas,
            gasPriceBid,
            maxSubmissionCost,
            {
              value: maxSubmissionCost.add(gasPriceBid.mul(maxGas)),
            },
          )
        const tx = staking.connect(delegator).unlockDelegationToTransferredIndexer(indexer.address)
        // The function checks for tokensLockedUntil so this is the error we should get:
        await expect(tx).revertedWith('! locked')
      })
    })
    describe('transferDelegationToL2', function () {
      it('rejects calls if the protocol is partially paused', async function () {
        await controller.connect(governor).setPartialPaused(true)

        const tx = staking
          .connect(delegator)
          .transferDelegationToL2(
            indexer.address,
            l2Delegator.address,
            maxGas,
            gasPriceBid,
            maxSubmissionCost,
            {
              value: maxSubmissionCost.add(gasPriceBid.mul(maxGas)),
            },
          )
        await expect(tx).revertedWith('Partial-paused')
      })
      it('rejects calls if the delegated indexer has not transferred stake to L2', async function () {
        const tokensToDelegate = toGRT('10000')
        await staking.connect(delegator).delegate(indexer.address, tokensToDelegate)

        const tx = staking
          .connect(delegator)
          .transferDelegationToL2(
            indexer.address,
            l2Delegator.address,
            maxGas,
            gasPriceBid,
            maxSubmissionCost,
            {
              value: maxSubmissionCost.add(gasPriceBid.mul(maxGas)),
            },
          )
        await expect(tx).revertedWith('indexer not transferred')
      })
      it('rejects calls if the beneficiary is zero', async function () {
        const tokensToDelegate = toGRT('10000')
        await staking.connect(delegator).delegate(indexer.address, tokensToDelegate)
        await staking
          .connect(indexer)
          .transferStakeToL2(
            l2Indexer.address,
            minimumIndexerStake,
            maxGas,
            gasPriceBid,
            maxSubmissionCost,
            {
              value: maxSubmissionCost.add(gasPriceBid.mul(maxGas)),
            },
          )

        const tx = staking
          .connect(delegator)
          .transferDelegationToL2(
            indexer.address,
            AddressZero,
            maxGas,
            gasPriceBid,
            maxSubmissionCost,
            {
              value: maxSubmissionCost.add(gasPriceBid.mul(maxGas)),
            },
          )
        await expect(tx).revertedWith('l2Beneficiary == 0')
      })
      it('rejects calls if the delegator has tokens locked for undelegation', async function () {
        const tokensToDelegate = toGRT('10000')
        await staking.connect(delegator).delegate(indexer.address, tokensToDelegate)
        await staking
          .connect(indexer)
          .transferStakeToL2(
            l2Indexer.address,
            minimumIndexerStake,
            maxGas,
            gasPriceBid,
            maxSubmissionCost,
            {
              value: maxSubmissionCost.add(gasPriceBid.mul(maxGas)),
            },
          )
        await staking.connect(delegator).undelegate(indexer.address, toGRT('1'))

        const tx = staking
          .connect(delegator)
          .transferDelegationToL2(
            indexer.address,
            l2Delegator.address,
            maxGas,
            gasPriceBid,
            maxSubmissionCost,
            {
              value: maxSubmissionCost.add(gasPriceBid.mul(maxGas)),
            },
          )
        await expect(tx).revertedWith('tokensLocked != 0')
      })
      it('rejects calls if the delegator has no tokens delegated to the indexer', async function () {
        await staking
          .connect(indexer)
          .transferStakeToL2(
            l2Indexer.address,
            minimumIndexerStake,
            maxGas,
            gasPriceBid,
            maxSubmissionCost,
            {
              value: maxSubmissionCost.add(gasPriceBid.mul(maxGas)),
            },
          )

        const tx = staking
          .connect(delegator)
          .transferDelegationToL2(
            indexer.address,
            l2Delegator.address,
            maxGas,
            gasPriceBid,
            maxSubmissionCost,
            {
              value: maxSubmissionCost.add(gasPriceBid.mul(maxGas)),
            },
          )
        await expect(tx).revertedWith('delegation == 0')
      })
      it('sends all the tokens delegated to the indexer to the beneficiary on L2, using the gateway', async function () {
        const tokensToDelegate = toGRT('10000')
        await staking.connect(delegator).delegate(indexer.address, tokensToDelegate)
        const actualDelegation = tokensToDelegate.sub(
          tokensToDelegate.mul(delegationTaxPPM).div(1000000),
        )
        await staking
          .connect(indexer)
          .transferStakeToL2(
            l2Indexer.address,
            minimumIndexerStake,
            maxGas,
            gasPriceBid,
            maxSubmissionCost,
            {
              value: maxSubmissionCost.add(gasPriceBid.mul(maxGas)),
            },
          )

        const expectedFunctionData = defaultAbiCoder.encode(
          ['tuple(address,address)'],
          [[l2Indexer.address, l2Delegator.address]],
        )

        const expectedCallhookData = defaultAbiCoder.encode(
          ['uint8', 'bytes'],
          [toBN(1), expectedFunctionData], // code = 1 means RECEIVE_DELEGATION_CODE
        )
        const expectedL2Data = await l1GraphTokenGateway.getOutboundCalldata(
          grt.address,
          staking.address,
          l2StakingMock.address,
          actualDelegation,
          expectedCallhookData,
        )

        const tx = staking
          .connect(delegator)
          .transferDelegationToL2(
            indexer.address,
            l2Delegator.address,
            maxGas,
            gasPriceBid,
            maxSubmissionCost,
            {
              value: maxSubmissionCost.add(gasPriceBid.mul(maxGas)),
            },
          )
        // seqNum is 2 because the first bridge call was in transferStakeToL2
        await expect(tx)
          .emit(l1GraphTokenGateway, 'TxToL2')
          .withArgs(staking.address, l2GRTGatewayMock.address, toBN(2), expectedL2Data)
        await expect(tx)
          .emit(staking, 'DelegationTransferredToL2')
          .withArgs(
            delegator.address,
            l2Delegator.address,
            indexer.address,
            l2Indexer.address,
            actualDelegation,
          )
      })
      it('sets the delegation shares to zero so cannot be called twice', async function () {
        const tokensToDelegate = toGRT('10000')
        await staking.connect(delegator).delegate(indexer.address, tokensToDelegate)
        await staking
          .connect(indexer)
          .transferStakeToL2(
            l2Indexer.address,
            minimumIndexerStake,
            maxGas,
            gasPriceBid,
            maxSubmissionCost,
            {
              value: maxSubmissionCost.add(gasPriceBid.mul(maxGas)),
            },
          )

        await staking
          .connect(delegator)
          .transferDelegationToL2(
            indexer.address,
            l2Delegator.address,
            maxGas,
            gasPriceBid,
            maxSubmissionCost,
            {
              value: maxSubmissionCost.add(gasPriceBid.mul(maxGas)),
            },
          )

        const tx = staking
          .connect(delegator)
          .transferDelegationToL2(
            indexer.address,
            l2Delegator.address,
            maxGas,
            gasPriceBid,
            maxSubmissionCost,
            {
              value: maxSubmissionCost.add(gasPriceBid.mul(maxGas)),
            },
          )
        await expect(tx).revertedWith('delegation == 0')
      })
      it('can be called again if the delegator added more delegation (edge case)', async function () {
        const tokensToDelegate = toGRT('10000')
        await staking.connect(delegator).delegate(indexer.address, tokensToDelegate)
        const actualDelegation = tokensToDelegate.sub(
          tokensToDelegate.mul(delegationTaxPPM).div(1000000),
        )
        await staking
          .connect(indexer)
          .transferStakeToL2(
            l2Indexer.address,
            minimumIndexerStake,
            maxGas,
            gasPriceBid,
            maxSubmissionCost,
            {
              value: maxSubmissionCost.add(gasPriceBid.mul(maxGas)),
            },
          )

        await staking
          .connect(delegator)
          .transferDelegationToL2(
            indexer.address,
            l2Delegator.address,
            maxGas,
            gasPriceBid,
            maxSubmissionCost,
            {
              value: maxSubmissionCost.add(gasPriceBid.mul(maxGas)),
            },
          )

        await staking.connect(delegator).delegate(indexer.address, tokensToDelegate)

        const tx = staking
          .connect(delegator)
          .transferDelegationToL2(
            indexer.address,
            l2Delegator.address,
            maxGas,
            gasPriceBid,
            maxSubmissionCost,
            {
              value: maxSubmissionCost.add(gasPriceBid.mul(maxGas)),
            },
          )
        await expect(tx)
          .emit(staking, 'DelegationTransferredToL2')
          .withArgs(
            delegator.address,
            l2Delegator.address,
            indexer.address,
            l2Indexer.address,
            actualDelegation,
          )
      })
      it('rejects calls if the ETH value is larger than expected', async function () {
        const tokensToDelegate = toGRT('10000')
        await staking.connect(delegator).delegate(indexer.address, tokensToDelegate)
        await staking
          .connect(indexer)
          .transferStakeToL2(
            l2Indexer.address,
            minimumIndexerStake,
            maxGas,
            gasPriceBid,
            maxSubmissionCost,
            {
              value: maxSubmissionCost.add(gasPriceBid.mul(maxGas)),
            },
          )

        const tx = staking
          .connect(delegator)
          .transferDelegationToL2(
            indexer.address,
            l2Delegator.address,
            maxGas,
            gasPriceBid,
            maxSubmissionCost,
            {
              value: maxSubmissionCost.add(gasPriceBid.mul(maxGas)).add(1),
            },
          )
        await expect(tx).revertedWith('INVALID_ETH_AMOUNT')
      })
    })
    describe('transferLockedDelegationToL2', function () {
      it('rejects calls if the protocol is partially paused', async function () {
        await controller.connect(governor).setPartialPaused(true)

        const tx = staking
          .connect(delegator)
          .transferLockedDelegationToL2(indexer.address, maxGas, gasPriceBid, maxSubmissionCost)
        await expect(tx).revertedWith('Partial-paused')
      })
      it('sends delegated tokens to L2 like transferDelegationToL2, but gets the beneficiary and ETH from the L1GraphTokenLockTransferTool', async function () {
        const tokensToDelegate = toGRT('10000')
        await staking.connect(delegator).delegate(indexer.address, tokensToDelegate)
        const actualDelegation = tokensToDelegate.sub(
          tokensToDelegate.mul(delegationTaxPPM).div(1000000),
        )

        await staking
          .connect(indexer)
          .transferStakeToL2(
            l2Indexer.address,
            minimumIndexerStake,
            maxGas,
            gasPriceBid,
            maxSubmissionCost,
            {
              value: maxSubmissionCost.add(gasPriceBid.mul(maxGas)),
            },
          )

        const expectedFunctionData = defaultAbiCoder.encode(
          ['tuple(address,address)'],
          [[l2Indexer.address, l2Delegator.address]],
        )

        const expectedCallhookData = defaultAbiCoder.encode(
          ['uint8', 'bytes'],
          [toBN(1), expectedFunctionData], // code = 1 means RECEIVE_DELEGATION_CODE
        )
        const expectedL2Data = await l1GraphTokenGateway.getOutboundCalldata(
          grt.address,
          staking.address,
          l2StakingMock.address,
          actualDelegation,
          expectedCallhookData,
        )

        await l1GraphTokenLockTransferTool.setL2WalletAddress(
          delegator.address,
          l2Delegator.address,
        )

        const oldTransferToolEthBalance = await graph.provider.getBalance(
          l1GraphTokenLockTransferTool.address,
        )
        const tx = staking
          .connect(delegator)
          .transferLockedDelegationToL2(indexer.address, maxGas, gasPriceBid, maxSubmissionCost)
        // seqNum is 2 because the first bridge call was in transferStakeToL2
        await expect(tx)
          .emit(l1GraphTokenGateway, 'TxToL2')
          .withArgs(staking.address, l2GRTGatewayMock.address, toBN(2), expectedL2Data)
        await expect(tx)
          .emit(staking, 'DelegationTransferredToL2')
          .withArgs(
            delegator.address,
            l2Delegator.address,
            indexer.address,
            l2Indexer.address,
            actualDelegation,
          )
        expect(await graph.provider.getBalance(l1GraphTokenLockTransferTool.address)).to.equal(
          oldTransferToolEthBalance.sub(maxSubmissionCost).sub(gasPriceBid.mul(maxGas)),
        )
      })
      it('rejects calls if the transfer tool contract returns a zero address beneficiary', async function () {
        const tokensToDelegate = toGRT('10000')
        await staking.connect(delegator).delegate(indexer.address, tokensToDelegate)

        await staking
          .connect(indexer)
          .transferStakeToL2(
            l2Indexer.address,
            minimumIndexerStake,
            maxGas,
            gasPriceBid,
            maxSubmissionCost,
            {
              value: maxSubmissionCost.add(gasPriceBid.mul(maxGas)),
            },
          )

        const tx = staking
          .connect(delegator)
          .transferLockedDelegationToL2(indexer.address, maxGas, gasPriceBid, maxSubmissionCost)
        await expect(tx).revertedWith('LOCK NOT TRANSFERRED')
      })
      it('rejects calls if the transfer tool contract does not provide enough ETH', async function () {
        const tokensToDelegate = toGRT('10000')
        await staking.connect(delegator).delegate(indexer.address, tokensToDelegate)

        await staking
          .connect(indexer)
          .transferStakeToL2(
            l2Indexer.address,
            minimumIndexerStake,
            maxGas,
            gasPriceBid,
            maxSubmissionCost,
            {
              value: maxSubmissionCost.add(gasPriceBid.mul(maxGas)),
            },
          )
        await staking
          .connect(governor)
          .setL1GraphTokenLockTransferTool(l1GraphTokenLockTransferToolBad.address)

        await l1GraphTokenLockTransferToolBad.setL2WalletAddress(
          delegator.address,
          l2Delegator.address,
        )
        const tx = staking
          .connect(delegator)
          .transferLockedDelegationToL2(indexer.address, maxGas, gasPriceBid, maxSubmissionCost)
        await expect(tx).revertedWith('ETH TRANSFER FAILED')
      })
    })
  })
})
