import hre from 'hardhat'
import { expect } from 'chai'
import { constants, Signer, utils, Wallet } from 'ethers'

import { GraphToken } from '../../../build/types/GraphToken'
import { BridgeMock } from '../../../build/types/BridgeMock'
import { InboxMock } from '../../../build/types/InboxMock'
import { OutboxMock } from '../../../build/types/OutboxMock'
import { L1GraphTokenGateway } from '../../../build/types/L1GraphTokenGateway'
import { L2GraphToken, L2GraphTokenGateway } from '../../../build/types'
import { BridgeEscrow } from '../../../build/types/BridgeEscrow'

import { NetworkFixture } from '../lib/fixtures'

import { helpers, applyL1ToL2Alias, toBN, toGRT, GraphNetworkContracts } from '@graphprotocol/sdk'
import { SignerWithAddress } from '@nomiclabs/hardhat-ethers/signers'

const { AddressZero } = constants

describe('L1GraphTokenGateway', () => {
  const graph = hre.graph()
  let governor: SignerWithAddress
  let tokenSender: SignerWithAddress
  let l2Receiver: SignerWithAddress
  let pauseGuardian: SignerWithAddress

  let fixture: NetworkFixture
  let grt: GraphToken
  let l1GraphTokenGateway: L1GraphTokenGateway
  let bridgeEscrow: BridgeEscrow

  let bridgeMock: BridgeMock
  let inboxMock: InboxMock
  let outboxMock: OutboxMock
  let routerMock: Wallet
  let l2GRTMock: L2GraphToken
  let l2GRTGatewayMock: L2GraphTokenGateway

  let fixtureContracts: GraphNetworkContracts
  let l2MockContracts: GraphNetworkContracts

  const senderTokens = toGRT('1000')
  const maxGas = toBN('1000000')
  const maxSubmissionCost = toBN('7')
  const gasPriceBid = toBN('2')
  const defaultEthValue = maxSubmissionCost.add(maxGas.mul(gasPriceBid))
  const emptyCallHookData = '0x'
  const defaultData = utils.defaultAbiCoder.encode(
    ['uint256', 'bytes'],
    [maxSubmissionCost, emptyCallHookData],
  )
  const defaultDataNoSubmissionCost = utils.defaultAbiCoder.encode(
    ['uint256', 'bytes'],
    [toBN(0), emptyCallHookData],
  )
  const notEmptyCallHookData = '0x12'
  const defaultDataWithNotEmptyCallHookData = utils.defaultAbiCoder.encode(
    ['uint256', 'bytes'],
    [maxSubmissionCost, notEmptyCallHookData],
  )

  before(async function () {
    ;[tokenSender, l2Receiver] = await graph.getTestAccounts()
    ;({ governor, pauseGuardian } = await graph.getNamedAccounts())

    fixture = new NetworkFixture(graph.provider)

    // Deploy L1
    fixtureContracts = await fixture.load(governor)
    grt = fixtureContracts.GraphToken as GraphToken
    l1GraphTokenGateway = fixtureContracts.L1GraphTokenGateway as L1GraphTokenGateway
    bridgeEscrow = fixtureContracts.BridgeEscrow as BridgeEscrow

    // Deploy L1 arbitrum bridge
    ;({ bridgeMock, inboxMock, outboxMock, routerMock } = await fixture.loadL1ArbitrumBridge(
      governor,
    ))

    // Deploy L2 mock
    l2MockContracts = await fixture.loadMock(true)
    l2GRTMock = l2MockContracts.L2GraphToken as L2GraphToken
    l2GRTGatewayMock = l2MockContracts.L2GraphTokenGateway as L2GraphTokenGateway

    // Give some funds to the token sender/router mock
    await grt.connect(governor).mint(tokenSender.address, senderTokens)
    await helpers.setBalance(routerMock.address, utils.parseEther('1'))
  })

  beforeEach(async function () {
    await fixture.setUp()
  })

  afterEach(async function () {
    await fixture.tearDown()
  })

  context('> immediately after deploy', function () {
    describe('calculateL2TokenAddress', function () {
      it('should return address zero as it was not set', async function () {
        expect(await l1GraphTokenGateway.calculateL2TokenAddress(grt.address)).eq(AddressZero)
      })
    })

    describe('outboundTransfer', function () {
      it('reverts because it is paused', async function () {
        const tx = l1GraphTokenGateway
          .connect(tokenSender)
          .outboundTransfer(
            grt.address,
            l2Receiver.address,
            toGRT('10'),
            maxGas,
            gasPriceBid,
            defaultData,
            {
              value: defaultEthValue,
            },
          )
        await expect(tx).revertedWith('Paused (contract)')
      })
    })

    describe('finalizeInboundTransfer', function () {
      it('revert because it is paused', async function () {
        const tx = l1GraphTokenGateway
          .connect(tokenSender)
          .finalizeInboundTransfer(
            grt.address,
            l2Receiver.address,
            tokenSender.address,
            toGRT('10'),
            defaultData,
          )
        await expect(tx).revertedWith('Paused (contract)')
      })
    })

    describe('setArbitrumAddresses', function () {
      it('is not callable by addreses that are not the governor', async function () {
        const tx = l1GraphTokenGateway
          .connect(tokenSender)
          .setArbitrumAddresses(inboxMock.address, routerMock.address)
        await expect(tx).revertedWith('Only Controller governor')
      })
      it('rejects setting an EOA as router or inbox', async function () {
        let tx = l1GraphTokenGateway
          .connect(governor)
          .setArbitrumAddresses(tokenSender.address, routerMock.address)
        await expect(tx).revertedWith('INBOX_MUST_BE_CONTRACT')
        tx = l1GraphTokenGateway
          .connect(governor)
          .setArbitrumAddresses(inboxMock.address, tokenSender.address)
        await expect(tx).revertedWith('ROUTER_MUST_BE_CONTRACT')
      })
      it('sets inbox and router address', async function () {
        const tx = l1GraphTokenGateway
          .connect(governor)
          .setArbitrumAddresses(inboxMock.address, routerMock.address)
        await expect(tx)
          .emit(l1GraphTokenGateway, 'ArbitrumAddressesSet')
          .withArgs(inboxMock.address, routerMock.address)
        expect(await l1GraphTokenGateway.l1Router()).eq(routerMock.address)
        expect(await l1GraphTokenGateway.inbox()).eq(inboxMock.address)
      })
    })

    describe('setL2TokenAddress', function () {
      it('is not callable by addreses that are not the governor', async function () {
        const tx = l1GraphTokenGateway.connect(tokenSender).setL2TokenAddress(l2GRTMock.address)
        await expect(tx).revertedWith('Only Controller governor')
      })
      it('sets l2GRT', async function () {
        const tx = l1GraphTokenGateway.connect(governor).setL2TokenAddress(l2GRTMock.address)
        await expect(tx).emit(l1GraphTokenGateway, 'L2TokenAddressSet').withArgs(l2GRTMock.address)
        expect(await l1GraphTokenGateway.l2GRT()).eq(l2GRTMock.address)
      })
    })

    describe('setL2CounterpartAddress', function () {
      it('is not callable by addreses that are not the governor', async function () {
        const tx = l1GraphTokenGateway
          .connect(tokenSender)
          .setL2CounterpartAddress(l2GRTGatewayMock.address)
        await expect(tx).revertedWith('Only Controller governor')
      })
      it('sets l2Counterpart which can be queried with counterpartGateway()', async function () {
        const tx = l1GraphTokenGateway
          .connect(governor)
          .setL2CounterpartAddress(l2GRTGatewayMock.address)
        await expect(tx)
          .emit(l1GraphTokenGateway, 'L2CounterpartAddressSet')
          .withArgs(l2GRTGatewayMock.address)
        expect(await l1GraphTokenGateway.l2Counterpart()).eq(l2GRTGatewayMock.address)
        expect(await l1GraphTokenGateway.counterpartGateway()).eq(l2GRTGatewayMock.address)
      })
    })
    describe('setEscrowAddress', function () {
      it('is not callable by addreses that are not the governor', async function () {
        const tx = l1GraphTokenGateway.connect(tokenSender).setEscrowAddress(bridgeEscrow.address)
        await expect(tx).revertedWith('Only Controller governor')
      })
      it('sets escrow', async function () {
        const tx = l1GraphTokenGateway.connect(governor).setEscrowAddress(bridgeEscrow.address)
        await expect(tx)
          .emit(l1GraphTokenGateway, 'EscrowAddressSet')
          .withArgs(bridgeEscrow.address)
        expect(await l1GraphTokenGateway.escrow()).eq(bridgeEscrow.address)
      })
    })
    describe('addToCallhookAllowlist', function () {
      it('is not callable by addreses that are not the governor', async function () {
        const tx = l1GraphTokenGateway
          .connect(tokenSender)
          .addToCallhookAllowlist(fixtureContracts.RewardsManager.address)
        await expect(tx).revertedWith('Only Controller governor')
        expect(
          await l1GraphTokenGateway.callhookAllowlist(fixtureContracts.RewardsManager.address),
        ).eq(false)
      })
      it('rejects adding an EOA to the callhook allowlist', async function () {
        const tx = l1GraphTokenGateway.connect(governor).addToCallhookAllowlist(tokenSender.address)
        await expect(tx).revertedWith('MUST_BE_CONTRACT')
      })
      it('adds an address to the callhook allowlist', async function () {
        const tx = l1GraphTokenGateway
          .connect(governor)
          .addToCallhookAllowlist(fixtureContracts.RewardsManager.address)
        await expect(tx)
          .emit(l1GraphTokenGateway, 'AddedToCallhookAllowlist')
          .withArgs(fixtureContracts.RewardsManager.address)
        expect(
          await l1GraphTokenGateway.callhookAllowlist(fixtureContracts.RewardsManager.address),
        ).eq(true)
      })
    })
    describe('removeFromCallhookAllowlist', function () {
      it('is not callable by addreses that are not the governor', async function () {
        await l1GraphTokenGateway
          .connect(governor)
          .addToCallhookAllowlist(fixtureContracts.RewardsManager.address)
        const tx = l1GraphTokenGateway
          .connect(tokenSender)
          .removeFromCallhookAllowlist(fixtureContracts.RewardsManager.address)
        await expect(tx).revertedWith('Only Controller governor')
        expect(
          await l1GraphTokenGateway.callhookAllowlist(fixtureContracts.RewardsManager.address),
        ).eq(true)
      })
      it('removes an address from the callhook allowlist', async function () {
        await l1GraphTokenGateway
          .connect(governor)
          .addToCallhookAllowlist(fixtureContracts.RewardsManager.address)
        const tx = l1GraphTokenGateway
          .connect(governor)
          .removeFromCallhookAllowlist(fixtureContracts.RewardsManager.address)
        await expect(tx)
          .emit(l1GraphTokenGateway, 'RemovedFromCallhookAllowlist')
          .withArgs(fixtureContracts.RewardsManager.address)
        expect(
          await l1GraphTokenGateway.callhookAllowlist(fixtureContracts.RewardsManager.address),
        ).eq(false)
      })
    })
    describe('Pausable behavior', () => {
      it('cannot be paused or unpaused by someone other than governor or pauseGuardian', async () => {
        let tx = l1GraphTokenGateway.connect(tokenSender).setPaused(false)
        await expect(tx).revertedWith('Only Governor or Guardian')
        tx = l1GraphTokenGateway.connect(tokenSender).setPaused(true)
        await expect(tx).revertedWith('Only Governor or Guardian')
      })
      it('cannot be unpaused if some state variables are not set', async function () {
        let tx = l1GraphTokenGateway.connect(governor).setPaused(false)
        await expect(tx).revertedWith('INBOX_NOT_SET')
        await l1GraphTokenGateway
          .connect(governor)
          .setArbitrumAddresses(inboxMock.address, routerMock.address)
        tx = l1GraphTokenGateway.connect(governor).setPaused(false)
        await expect(tx).revertedWith('L2_COUNTERPART_NOT_SET')
        await l1GraphTokenGateway
          .connect(governor)
          .setL2CounterpartAddress(l2GRTGatewayMock.address)
        tx = l1GraphTokenGateway.connect(governor).setPaused(false)
        await expect(tx).revertedWith('ESCROW_NOT_SET')
      })
      it('can be paused and unpaused by the governor', async function () {
        await fixture.configureL1Bridge(governor, fixtureContracts, l2MockContracts)
        let tx = l1GraphTokenGateway.connect(governor).setPaused(true)
        await expect(tx).emit(l1GraphTokenGateway, 'PauseChanged').withArgs(true)
        await expect(await l1GraphTokenGateway.paused()).eq(true)
        tx = l1GraphTokenGateway.connect(governor).setPaused(false)
        await expect(tx).emit(l1GraphTokenGateway, 'PauseChanged').withArgs(false)
        await expect(await l1GraphTokenGateway.paused()).eq(false)
      })
      describe('setPauseGuardian', function () {
        it('cannot be called by someone other than governor', async function () {
          const tx = l1GraphTokenGateway
            .connect(tokenSender)
            .setPauseGuardian(pauseGuardian.address)
          await expect(tx).revertedWith('Only Controller governor')
        })
        it('sets a new pause guardian', async function () {
          const currentPauseGuardian = await l1GraphTokenGateway.pauseGuardian()
          const tx = l1GraphTokenGateway.connect(governor).setPauseGuardian(pauseGuardian.address)
          await expect(tx)
            .emit(l1GraphTokenGateway, 'NewPauseGuardian')
            .withArgs(currentPauseGuardian, pauseGuardian.address)
        })
        it('allows a pause guardian to pause and unpause', async function () {
          await fixture.configureL1Bridge(governor, fixtureContracts, l2MockContracts)
          await l1GraphTokenGateway.connect(governor).setPauseGuardian(pauseGuardian.address)
          let tx = l1GraphTokenGateway.connect(pauseGuardian).setPaused(true)
          await expect(tx).emit(l1GraphTokenGateway, 'PauseChanged').withArgs(true)
          await expect(await l1GraphTokenGateway.paused()).eq(true)
          tx = l1GraphTokenGateway.connect(pauseGuardian).setPaused(false)
          await expect(tx).emit(l1GraphTokenGateway, 'PauseChanged').withArgs(false)
          await expect(await l1GraphTokenGateway.paused()).eq(false)
        })
      })
    })
  })

  context('> after configuring and unpausing', function () {
    const createMsgData = function (callHookData: string) {
      const selector = l1GraphTokenGateway.interface.getSighash('finalizeInboundTransfer')
      const params = utils.defaultAbiCoder.encode(
        ['address', 'address', 'address', 'uint256', 'bytes'],
        [grt.address, tokenSender.address, l2Receiver.address, toGRT('10'), callHookData],
      )
      const outboundData = utils.hexlify(utils.concat([selector, params]))

      const msgData = utils.solidityPack(
        [
          'uint256',
          'uint256',
          'uint256',
          'uint256',
          'uint256',
          'uint256',
          'uint256',
          'uint256',
          'uint256',
          'bytes',
        ],
        [
          toBN(l2GRTGatewayMock.address),
          toBN('0'),
          defaultEthValue,
          maxSubmissionCost,
          applyL1ToL2Alias(tokenSender.address),
          applyL1ToL2Alias(tokenSender.address),
          maxGas,
          gasPriceBid,
          utils.hexDataLength(outboundData),
          outboundData,
        ],
      )
      return msgData
    }
    const createInboxAccsEntry = function (msgDataHash: string) {
      // The real bridge would emit the InboxAccs entry that came before this one, but our mock
      // emits this, making it easier for us to validate here that all the parameters we sent are correct
      const expectedInboxAccsEntry = utils.keccak256(
        utils.solidityPack(
          ['address', 'uint8', 'address', 'bytes32'],
          [inboxMock.address, 9, l1GraphTokenGateway.address, msgDataHash],
        ),
      )
      return expectedInboxAccsEntry
    }
    const testValidOutboundTransfer = async function (
      signer: Signer,
      data: string,
      callHookData: string,
    ) {
      const tx = l1GraphTokenGateway
        .connect(signer)
        .outboundTransfer(grt.address, l2Receiver.address, toGRT('10'), maxGas, gasPriceBid, data, {
          value: defaultEthValue,
        })
      // Our bridge mock returns an incrementing seqNum starting at 1
      const expectedSeqNum = 1
      await expect(tx)
        .emit(l1GraphTokenGateway, 'DepositInitiated')
        .withArgs(grt.address, tokenSender.address, l2Receiver.address, expectedSeqNum, toGRT('10'))

      const msgData = createMsgData(callHookData)
      const msgDataHash = utils.keccak256(msgData)
      const expectedInboxAccsEntry = createInboxAccsEntry(msgDataHash)

      await expect(tx).emit(inboxMock, 'InboxMessageDelivered').withArgs(1, msgData)
      await expect(tx)
        .emit(bridgeMock, 'MessageDelivered')
        .withArgs(
          expectedSeqNum,
          expectedInboxAccsEntry,
          inboxMock.address,
          9,
          l1GraphTokenGateway.address,
          msgDataHash,
        )
      const escrowBalance = await grt.balanceOf(bridgeEscrow.address)
      const senderBalance = await grt.balanceOf(tokenSender.address)
      expect(escrowBalance).eq(toGRT('10'))
      expect(senderBalance).eq(toGRT('990'))
    }
    before(async function () {
      await fixture.configureL1Bridge(governor, fixtureContracts, l2MockContracts)
    })

    describe('updateL2MintAllowance', function () {
      it('rejects calls that are not from the governor', async function () {
        const tx = l1GraphTokenGateway
          .connect(pauseGuardian.address)
          .updateL2MintAllowance(toGRT('1'), await helpers.latestBlock())
        await expect(tx).revertedWith('Only Controller governor')
      })
      it('does not allow using a future or current block number', async function () {
        const issuancePerBlock = toGRT('120')
        let issuanceUpdatedAtBlock = (await helpers.latestBlock()) + 2
        const tx1 = l1GraphTokenGateway
          .connect(governor)
          .updateL2MintAllowance(issuancePerBlock, issuanceUpdatedAtBlock)
        await expect(tx1).revertedWith('BLOCK_MUST_BE_PAST')
        issuanceUpdatedAtBlock = (await helpers.latestBlock()) + 1 // This will be block.number in our next tx
        const tx2 = l1GraphTokenGateway
          .connect(governor)
          .updateL2MintAllowance(issuancePerBlock, issuanceUpdatedAtBlock)
        await expect(tx2).revertedWith('BLOCK_MUST_BE_PAST')
        issuanceUpdatedAtBlock = await helpers.latestBlock() // This will be block.number-1 in our next tx
        const tx3 = l1GraphTokenGateway
          .connect(governor)
          .updateL2MintAllowance(issuancePerBlock, issuanceUpdatedAtBlock)
        await expect(tx3)
          .emit(l1GraphTokenGateway, 'L2MintAllowanceUpdated')
          .withArgs(toGRT('0'), issuancePerBlock, issuanceUpdatedAtBlock)
      })
      it('does not allow using a block number lower than or equal to the previous one', async function () {
        const issuancePerBlock = toGRT('120')
        const issuanceUpdatedAtBlock = await helpers.latestBlock()
        const tx1 = l1GraphTokenGateway
          .connect(governor)
          .updateL2MintAllowance(issuancePerBlock, issuanceUpdatedAtBlock)
        await expect(tx1)
          .emit(l1GraphTokenGateway, 'L2MintAllowanceUpdated')
          .withArgs(toGRT('0'), issuancePerBlock, issuanceUpdatedAtBlock)
        const tx2 = l1GraphTokenGateway
          .connect(governor)
          .updateL2MintAllowance(issuancePerBlock, issuanceUpdatedAtBlock)
        await expect(tx2).revertedWith('BLOCK_MUST_BE_INCREMENTING')
        const tx3 = l1GraphTokenGateway
          .connect(governor)
          .updateL2MintAllowance(issuancePerBlock, issuanceUpdatedAtBlock - 1)
        await expect(tx3).revertedWith('BLOCK_MUST_BE_INCREMENTING')
        const tx4 = l1GraphTokenGateway
          .connect(governor)
          .updateL2MintAllowance(issuancePerBlock, issuanceUpdatedAtBlock + 1)
        await expect(tx4)
          .emit(l1GraphTokenGateway, 'L2MintAllowanceUpdated')
          .withArgs(issuancePerBlock, issuancePerBlock, issuanceUpdatedAtBlock + 1)
      })
      it('updates the snapshot and issuance to follow a new linear function, accumulating up to the specified block', async function () {
        const issuancePerBlock = toGRT('120')
        const issuanceUpdatedAtBlock = (await helpers.latestBlock()) - 2
        const tx1 = l1GraphTokenGateway
          .connect(governor)
          .updateL2MintAllowance(issuancePerBlock, issuanceUpdatedAtBlock)
        await expect(tx1)
          .emit(l1GraphTokenGateway, 'L2MintAllowanceUpdated')
          .withArgs(toGRT('0'), issuancePerBlock, issuanceUpdatedAtBlock)
        // Now the mint allowance should be issuancePerBlock * 3
        expect(
          await l1GraphTokenGateway.accumulatedL2MintAllowanceAtBlock(await helpers.latestBlock()),
        ).to.eq(issuancePerBlock.mul(3))
        expect(await l1GraphTokenGateway.accumulatedL2MintAllowanceSnapshot()).to.eq(0)
        expect(await l1GraphTokenGateway.l2MintAllowancePerBlock()).to.eq(issuancePerBlock)
        expect(await l1GraphTokenGateway.lastL2MintAllowanceUpdateBlock()).to.eq(
          issuanceUpdatedAtBlock,
        )

        await helpers.mine(10)

        const newIssuancePerBlock = toGRT('200')
        const newIssuanceUpdatedAtBlock = (await helpers.latestBlock()) - 1

        const expectedAccumulatedSnapshot = issuancePerBlock.mul(
          newIssuanceUpdatedAtBlock - issuanceUpdatedAtBlock,
        )
        const tx2 = l1GraphTokenGateway
          .connect(governor)
          .updateL2MintAllowance(newIssuancePerBlock, newIssuanceUpdatedAtBlock)
        await expect(tx2)
          .emit(l1GraphTokenGateway, 'L2MintAllowanceUpdated')
          .withArgs(expectedAccumulatedSnapshot, newIssuancePerBlock, newIssuanceUpdatedAtBlock)

        expect(
          await l1GraphTokenGateway.accumulatedL2MintAllowanceAtBlock(await helpers.latestBlock()),
        ).to.eq(expectedAccumulatedSnapshot.add(newIssuancePerBlock.mul(2)))
        expect(await l1GraphTokenGateway.accumulatedL2MintAllowanceSnapshot()).to.eq(
          expectedAccumulatedSnapshot,
        )
        expect(await l1GraphTokenGateway.l2MintAllowancePerBlock()).to.eq(newIssuancePerBlock)
        expect(await l1GraphTokenGateway.lastL2MintAllowanceUpdateBlock()).to.eq(
          newIssuanceUpdatedAtBlock,
        )
      })
    })
    describe('setL2MintAllowanceParametersManual', function () {
      it('rejects calls that are not from the governor', async function () {
        const tx = l1GraphTokenGateway
          .connect(pauseGuardian.address)
          .setL2MintAllowanceParametersManual(toGRT('0'), toGRT('1'), await helpers.latestBlock())
        await expect(tx).revertedWith('Only Controller governor')
      })
      it('does not allow using a future or current block number', async function () {
        const issuancePerBlock = toGRT('120')
        let issuanceUpdatedAtBlock = (await helpers.latestBlock()) + 2
        const tx1 = l1GraphTokenGateway
          .connect(governor)
          .setL2MintAllowanceParametersManual(toGRT('0'), issuancePerBlock, issuanceUpdatedAtBlock)
        await expect(tx1).revertedWith('BLOCK_MUST_BE_PAST')
        issuanceUpdatedAtBlock = (await helpers.latestBlock()) + 1 // This will be block.number in our next tx
        const tx2 = l1GraphTokenGateway
          .connect(governor)
          .setL2MintAllowanceParametersManual(toGRT('0'), issuancePerBlock, issuanceUpdatedAtBlock)
        await expect(tx2).revertedWith('BLOCK_MUST_BE_PAST')
        issuanceUpdatedAtBlock = await helpers.latestBlock() // This will be block.number-1 in our next tx
        const tx3 = l1GraphTokenGateway
          .connect(governor)
          .setL2MintAllowanceParametersManual(toGRT('0'), issuancePerBlock, issuanceUpdatedAtBlock)
        await expect(tx3)
          .emit(l1GraphTokenGateway, 'L2MintAllowanceUpdated')
          .withArgs(toGRT('0'), issuancePerBlock, issuanceUpdatedAtBlock)
      })
      it('updates the snapshot and issuance to follow a new linear function, manually setting the snapshot value', async function () {
        const issuancePerBlock = toGRT('120')
        const issuanceUpdatedAtBlock = (await helpers.latestBlock()) - 2
        const snapshotValue = toGRT('10')
        const tx1 = l1GraphTokenGateway
          .connect(governor)
          .setL2MintAllowanceParametersManual(
            snapshotValue,
            issuancePerBlock,
            issuanceUpdatedAtBlock,
          )
        await expect(tx1)
          .emit(l1GraphTokenGateway, 'L2MintAllowanceUpdated')
          .withArgs(snapshotValue, issuancePerBlock, issuanceUpdatedAtBlock)
        // Now the mint allowance should be 10 + issuancePerBlock * 3
        expect(
          await l1GraphTokenGateway.accumulatedL2MintAllowanceAtBlock(await helpers.latestBlock()),
        ).to.eq(snapshotValue.add(issuancePerBlock.mul(3)))
        expect(await l1GraphTokenGateway.accumulatedL2MintAllowanceSnapshot()).to.eq(snapshotValue)
        expect(await l1GraphTokenGateway.l2MintAllowancePerBlock()).to.eq(issuancePerBlock)
        expect(await l1GraphTokenGateway.lastL2MintAllowanceUpdateBlock()).to.eq(
          issuanceUpdatedAtBlock,
        )

        await helpers.mine(10)

        const newIssuancePerBlock = toGRT('200')
        const newIssuanceUpdatedAtBlock = (await helpers.latestBlock()) - 1
        const newSnapshotValue = toGRT('10')

        const tx2 = l1GraphTokenGateway
          .connect(governor)
          .setL2MintAllowanceParametersManual(
            newSnapshotValue,
            newIssuancePerBlock,
            newIssuanceUpdatedAtBlock,
          )
        await expect(tx2)
          .emit(l1GraphTokenGateway, 'L2MintAllowanceUpdated')
          .withArgs(newSnapshotValue, newIssuancePerBlock, newIssuanceUpdatedAtBlock)

        expect(
          await l1GraphTokenGateway.accumulatedL2MintAllowanceAtBlock(await helpers.latestBlock()),
        ).to.eq(newSnapshotValue.add(newIssuancePerBlock.mul(2)))
        expect(await l1GraphTokenGateway.accumulatedL2MintAllowanceSnapshot()).to.eq(
          newSnapshotValue,
        )
        expect(await l1GraphTokenGateway.l2MintAllowancePerBlock()).to.eq(newIssuancePerBlock)
        expect(await l1GraphTokenGateway.lastL2MintAllowanceUpdateBlock()).to.eq(
          newIssuanceUpdatedAtBlock,
        )
      })
    })
    describe('calculateL2TokenAddress', function () {
      it('returns the L2 token address', async function () {
        expect(await l1GraphTokenGateway.calculateL2TokenAddress(grt.address)).eq(l2GRTMock.address)
      })
      it('returns the zero address if the input is any other address', async function () {
        expect(await l1GraphTokenGateway.calculateL2TokenAddress(tokenSender.address)).eq(
          AddressZero,
        )
      })
    })

    describe('outboundTransfer', function () {
      it('reverts when called with the wrong token address', async function () {
        const tx = l1GraphTokenGateway
          .connect(tokenSender)
          .outboundTransfer(
            tokenSender.address,
            l2Receiver.address,
            toGRT('10'),
            maxGas,
            gasPriceBid,
            defaultData,
            {
              value: defaultEthValue,
            },
          )
        await expect(tx).revertedWith('TOKEN_NOT_GRT')
      })
      it('puts tokens in escrow and creates a retryable ticket', async function () {
        await grt.connect(tokenSender).approve(l1GraphTokenGateway.address, toGRT('10'))
        await testValidOutboundTransfer(tokenSender, defaultData, emptyCallHookData)
      })
      it('decodes the sender address from messages sent by the router', async function () {
        await grt.connect(tokenSender).approve(l1GraphTokenGateway.address, toGRT('10'))
        const routerEncodedData = utils.defaultAbiCoder.encode(
          ['address', 'bytes'],
          [tokenSender.address, defaultData],
        )
        await testValidOutboundTransfer(routerMock, routerEncodedData, emptyCallHookData)
      })
      it('reverts when called with no submission cost', async function () {
        await grt.connect(tokenSender).approve(l1GraphTokenGateway.address, toGRT('10'))
        const tx = l1GraphTokenGateway
          .connect(tokenSender)
          .outboundTransfer(
            grt.address,
            l2Receiver.address,
            toGRT('10'),
            maxGas,
            gasPriceBid,
            defaultDataNoSubmissionCost,
            {
              value: defaultEthValue,
            },
          )
        await expect(tx).revertedWith('NO_SUBMISSION_COST')
      })
      it('reverts when called with nonempty calldata, if the sender is not allowlisted', async function () {
        await grt.connect(tokenSender).approve(l1GraphTokenGateway.address, toGRT('10'))
        const tx = l1GraphTokenGateway
          .connect(tokenSender)
          .outboundTransfer(
            grt.address,
            l2Receiver.address,
            toGRT('10'),
            maxGas,
            gasPriceBid,
            defaultDataWithNotEmptyCallHookData,
            {
              value: defaultEthValue,
            },
          )
        await expect(tx).revertedWith('CALL_HOOK_DATA_NOT_ALLOWED')
      })
      it('allows sending nonempty calldata, if the sender is allowlisted', async function () {
        // Make the sender a contract so that it can be allowed to send callhooks
        await helpers.setCode(tokenSender.address, '0x1234')
        await l1GraphTokenGateway.connect(governor).addToCallhookAllowlist(tokenSender.address)
        await grt.connect(tokenSender).approve(l1GraphTokenGateway.address, toGRT('10'))
        await testValidOutboundTransfer(
          tokenSender,
          defaultDataWithNotEmptyCallHookData,
          notEmptyCallHookData,
        )
      })
      it('reverts when the sender does not have enough GRT', async function () {
        await grt.connect(tokenSender).approve(l1GraphTokenGateway.address, toGRT('1001'))
        const tx = l1GraphTokenGateway
          .connect(tokenSender)
          .outboundTransfer(
            grt.address,
            l2Receiver.address,
            toGRT('1001'),
            maxGas,
            gasPriceBid,
            defaultData,
            {
              value: defaultEthValue,
            },
          )
        await expect(tx).revertedWith('ERC20: transfer amount exceeds balance')
      })
    })

    describe('finalizeInboundTransfer', function () {
      it('reverts when called by an account that is not the bridge', async function () {
        const tx = l1GraphTokenGateway
          .connect(tokenSender)
          .finalizeInboundTransfer(
            grt.address,
            l2Receiver.address,
            tokenSender.address,
            toGRT('10'),
            defaultData,
          )
        await expect(tx).revertedWith('NOT_FROM_BRIDGE')
      })
      it('reverts when called by the bridge, but the tx was not started by the L2 gateway', async function () {
        const encodedCalldata = l1GraphTokenGateway.interface.encodeFunctionData(
          'finalizeInboundTransfer',
          [
            grt.address,
            l2Receiver.address,
            tokenSender.address,
            toGRT('10'),
            utils.defaultAbiCoder.encode(['uint256', 'bytes'], [0, []]),
          ],
        )
        // The real outbox would require a proof, which would
        // validate that the tx was initiated by the L2 gateway but our mock
        // just executes unconditionally
        const tx = outboxMock.connect(tokenSender).executeTransaction(
          toBN('0'),
          [],
          toBN('0'),
          l2Receiver.address, // Note this is not l2GRTGatewayMock
          l1GraphTokenGateway.address,
          toBN('1337'),
          await helpers.latestBlock(),
          toBN('133701337'),
          toBN('0'),
          encodedCalldata,
        )
        await expect(tx).revertedWith('ONLY_COUNTERPART_GATEWAY')
      })
      it('reverts if the gateway does not have tokens or allowance', async function () {
        // This scenario should never really happen, but we still
        // test that the gateway reverts in this case
        const encodedCalldata = l1GraphTokenGateway.interface.encodeFunctionData(
          'finalizeInboundTransfer',
          [
            grt.address,
            l2Receiver.address,
            tokenSender.address,
            toGRT('10'),
            utils.defaultAbiCoder.encode(['uint256', 'bytes'], [0, []]),
          ],
        )
        // The real outbox would require a proof, which would
        // validate that the tx was initiated by the L2 gateway but our mock
        // just executes unconditionally
        const tx = outboxMock
          .connect(tokenSender)
          .executeTransaction(
            toBN('0'),
            [],
            toBN('0'),
            l2GRTGatewayMock.address,
            l1GraphTokenGateway.address,
            toBN('1337'),
            await helpers.latestBlock(),
            toBN('133701337'),
            toBN('0'),
            encodedCalldata,
          )
        await expect(tx).revertedWith('INVALID_L2_MINT_AMOUNT')
      })
      it('reverts if the gateway is revoked from escrow', async function () {
        await grt.connect(tokenSender).approve(l1GraphTokenGateway.address, toGRT('10'))
        await testValidOutboundTransfer(tokenSender, defaultData, emptyCallHookData)
        // At this point, the gateway holds 10 GRT in escrow
        // But we revoke the gateway's permission to move the funds:
        await bridgeEscrow.connect(governor).revokeAll(l1GraphTokenGateway.address)
        const encodedCalldata = l1GraphTokenGateway.interface.encodeFunctionData(
          'finalizeInboundTransfer',
          [
            grt.address,
            l2Receiver.address,
            tokenSender.address,
            toGRT('8'),
            utils.defaultAbiCoder.encode(['uint256', 'bytes'], [0, []]),
          ],
        )
        // The real outbox would require a proof, which would
        // validate that the tx was initiated by the L2 gateway but our mock
        // just executes unconditionally
        const tx = outboxMock
          .connect(tokenSender)
          .executeTransaction(
            toBN('0'),
            [],
            toBN('0'),
            l2GRTGatewayMock.address,
            l1GraphTokenGateway.address,
            toBN('1337'),
            await helpers.latestBlock(),
            toBN('133701337'),
            toBN('0'),
            encodedCalldata,
          )
        await expect(tx).revertedWith('ERC20: transfer amount exceeds allowance')
      })
      it('sends tokens out of escrow', async function () {
        await grt.connect(tokenSender).approve(l1GraphTokenGateway.address, toGRT('10'))
        await testValidOutboundTransfer(tokenSender, defaultData, emptyCallHookData)
        // At this point, the gateway holds 10 GRT in escrow
        const encodedCalldata = l1GraphTokenGateway.interface.encodeFunctionData(
          'finalizeInboundTransfer',
          [
            grt.address,
            l2Receiver.address,
            tokenSender.address,
            toGRT('8'),
            utils.defaultAbiCoder.encode(['uint256', 'bytes'], [0, []]),
          ],
        )
        // The real outbox would require a proof, which would
        // validate that the tx was initiated by the L2 gateway but our mock
        // just executes unconditionally
        const tx = outboxMock
          .connect(tokenSender)
          .executeTransaction(
            toBN('0'),
            [],
            toBN('0'),
            l2GRTGatewayMock.address,
            l1GraphTokenGateway.address,
            toBN('1337'),
            await helpers.latestBlock(),
            toBN('133701337'),
            toBN('0'),
            encodedCalldata,
          )
        await expect(tx)
          .emit(l1GraphTokenGateway, 'WithdrawalFinalized')
          .withArgs(grt.address, l2Receiver.address, tokenSender.address, toBN('0'), toGRT('8'))
        const escrowBalance = await grt.balanceOf(bridgeEscrow.address)
        const senderBalance = await grt.balanceOf(tokenSender.address)
        expect(escrowBalance).eq(toGRT('2'))
        expect(senderBalance).eq(toGRT('998'))
      })
      it('mints tokens up to the L2 mint allowance', async function () {
        await grt.connect(tokenSender).approve(l1GraphTokenGateway.address, toGRT('10'))
        await testValidOutboundTransfer(tokenSender, defaultData, emptyCallHookData)

        // Start accruing L2 mint allowance at 2 GRT per block
        await l1GraphTokenGateway
          .connect(governor)
          .updateL2MintAllowance(toGRT('2'), await helpers.latestBlock())
        await helpers.mine(2)
        // Now it's been three blocks since the lastL2MintAllowanceUpdateBlock, so
        // there should be 8 GRT allowed to be minted from L2 in the next block.

        // At this point, the gateway holds 10 GRT in escrow
        const encodedCalldata = l1GraphTokenGateway.interface.encodeFunctionData(
          'finalizeInboundTransfer',
          [
            grt.address,
            l2Receiver.address,
            tokenSender.address,
            toGRT('18'),
            utils.defaultAbiCoder.encode(['uint256', 'bytes'], [0, []]),
          ],
        )
        // The real outbox would require a proof, which would
        // validate that the tx was initiated by the L2 gateway but our mock
        // just executes unconditionally
        const tx = outboxMock
          .connect(tokenSender)
          .executeTransaction(
            toBN('0'),
            [],
            toBN('0'),
            l2GRTGatewayMock.address,
            l1GraphTokenGateway.address,
            toBN('1337'),
            await helpers.latestBlock(),
            toBN('133701337'),
            toBN('0'),
            encodedCalldata,
          )
        await expect(tx)
          .emit(l1GraphTokenGateway, 'WithdrawalFinalized')
          .withArgs(grt.address, l2Receiver.address, tokenSender.address, toBN('0'), toGRT('18'))
          .emit(l1GraphTokenGateway, 'TokensMintedFromL2')
          .withArgs(toGRT('8'))
        expect(await l1GraphTokenGateway.totalMintedFromL2()).to.eq(toGRT('8'))
        expect(
          await l1GraphTokenGateway.accumulatedL2MintAllowanceAtBlock(await helpers.latestBlock()),
        ).to.eq(toGRT('8'))

        const escrowBalance = await grt.balanceOf(bridgeEscrow.address)
        const senderBalance = await grt.balanceOf(tokenSender.address)
        expect(escrowBalance).eq(toGRT('0'))
        expect(senderBalance).eq(toGRT('1008'))
      })
      it('reverts if the amount to mint is over the allowance', async function () {
        await grt.connect(tokenSender).approve(l1GraphTokenGateway.address, toGRT('10'))
        await testValidOutboundTransfer(tokenSender, defaultData, emptyCallHookData)

        // Start accruing L2 mint allowance at 2 GRT per block
        await l1GraphTokenGateway
          .connect(governor)
          .updateL2MintAllowance(toGRT('2'), await helpers.latestBlock())
        await helpers.mine(2)
        // Now it's been three blocks since the lastL2MintAllowanceUpdateBlock, so
        // there should be 8 GRT allowed to be minted from L2 in the next block.

        // At this point, the gateway holds 10 GRT in escrow
        const encodedCalldata = l1GraphTokenGateway.interface.encodeFunctionData(
          'finalizeInboundTransfer',
          [
            grt.address,
            l2Receiver.address,
            tokenSender.address,
            toGRT('18.001'),
            utils.defaultAbiCoder.encode(['uint256', 'bytes'], [0, []]),
          ],
        )
        // The real outbox would require a proof, which would
        // validate that the tx was initiated by the L2 gateway but our mock
        // just executes unconditionally
        const tx = outboxMock
          .connect(tokenSender)
          .executeTransaction(
            toBN('0'),
            [],
            toBN('0'),
            l2GRTGatewayMock.address,
            l1GraphTokenGateway.address,
            toBN('1337'),
            await helpers.latestBlock(),
            toBN('133701337'),
            toBN('0'),
            encodedCalldata,
          )
        await expect(tx).revertedWith('INVALID_L2_MINT_AMOUNT')
      })
    })
  })
})
