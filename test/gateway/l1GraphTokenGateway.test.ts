import { expect } from 'chai'
import { constants, Signer, utils } from 'ethers'

import { GraphToken } from '../../build/types/GraphToken'
import { BridgeMock } from '../../build/types/BridgeMock'
import { InboxMock } from '../../build/types/InboxMock'
import { OutboxMock } from '../../build/types/OutboxMock'
import { L1GraphTokenGateway } from '../../build/types/L1GraphTokenGateway'

import { NetworkFixture, ArbitrumL1Mocks, L1FixtureContracts } from '../lib/fixtures'

import {
  getAccounts,
  latestBlock,
  toBN,
  toGRT,
  Account,
  applyL1ToL2Alias,
  provider,
} from '../lib/testHelpers'
import { BridgeEscrow } from '../../build/types/BridgeEscrow'

const { AddressZero } = constants

describe('L1GraphTokenGateway', () => {
  let governor: Account
  let tokenSender: Account
  let l2Receiver: Account
  let mockRouter: Account
  let mockL2GRT: Account
  let mockL2Gateway: Account
  let pauseGuardian: Account
  let fixture: NetworkFixture

  let grt: GraphToken
  let l1GraphTokenGateway: L1GraphTokenGateway
  let bridgeEscrow: BridgeEscrow
  let bridgeMock: BridgeMock
  let inboxMock: InboxMock
  let outboxMock: OutboxMock

  let arbitrumMocks: ArbitrumL1Mocks
  let fixtureContracts: L1FixtureContracts

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
    ;[governor, tokenSender, l2Receiver, mockRouter, mockL2GRT, mockL2Gateway, pauseGuardian] =
      await getAccounts()

    // Dummy code on the mock router so that it appears as a contract
    await provider().send('hardhat_setCode', [mockRouter.address, '0x1234'])
    fixture = new NetworkFixture()
    fixtureContracts = await fixture.load(governor.signer)
    ;({ grt, l1GraphTokenGateway, bridgeEscrow } = fixtureContracts)

    // Give some funds to the token sender
    await grt.connect(governor.signer).mint(tokenSender.address, senderTokens)
    // Deploy contracts that mock Arbitrum's bridge contracts
    arbitrumMocks = await fixture.loadArbitrumL1Mocks(governor.signer)
    ;({ bridgeMock, inboxMock, outboxMock } = arbitrumMocks)
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
          .connect(tokenSender.signer)
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
          .connect(tokenSender.signer)
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
          .connect(tokenSender.signer)
          .setArbitrumAddresses(inboxMock.address, mockRouter.address)
        await expect(tx).revertedWith('Only Controller governor')
      })
      it('rejects setting an EOA as router or inbox', async function () {
        let tx = l1GraphTokenGateway
          .connect(governor.signer)
          .setArbitrumAddresses(tokenSender.address, mockRouter.address)
        await expect(tx).revertedWith('INBOX_MUST_BE_CONTRACT')
        tx = l1GraphTokenGateway
          .connect(governor.signer)
          .setArbitrumAddresses(inboxMock.address, tokenSender.address)
        await expect(tx).revertedWith('ROUTER_MUST_BE_CONTRACT')
      })
      it('sets inbox and router address', async function () {
        const tx = l1GraphTokenGateway
          .connect(governor.signer)
          .setArbitrumAddresses(inboxMock.address, mockRouter.address)
        await expect(tx)
          .emit(l1GraphTokenGateway, 'ArbitrumAddressesSet')
          .withArgs(inboxMock.address, mockRouter.address)
        expect(await l1GraphTokenGateway.l1Router()).eq(mockRouter.address)
        expect(await l1GraphTokenGateway.inbox()).eq(inboxMock.address)
      })
    })

    describe('setL2TokenAddress', function () {
      it('is not callable by addreses that are not the governor', async function () {
        const tx = l1GraphTokenGateway
          .connect(tokenSender.signer)
          .setL2TokenAddress(mockL2GRT.address)
        await expect(tx).revertedWith('Only Controller governor')
      })
      it('sets l2GRT', async function () {
        const tx = l1GraphTokenGateway.connect(governor.signer).setL2TokenAddress(mockL2GRT.address)
        await expect(tx).emit(l1GraphTokenGateway, 'L2TokenAddressSet').withArgs(mockL2GRT.address)
        expect(await l1GraphTokenGateway.l2GRT()).eq(mockL2GRT.address)
      })
    })

    describe('setL2CounterpartAddress', function () {
      it('is not callable by addreses that are not the governor', async function () {
        const tx = l1GraphTokenGateway
          .connect(tokenSender.signer)
          .setL2CounterpartAddress(mockL2Gateway.address)
        await expect(tx).revertedWith('Only Controller governor')
      })
      it('sets l2Counterpart which can be queried with counterpartGateway()', async function () {
        const tx = l1GraphTokenGateway
          .connect(governor.signer)
          .setL2CounterpartAddress(mockL2Gateway.address)
        await expect(tx)
          .emit(l1GraphTokenGateway, 'L2CounterpartAddressSet')
          .withArgs(mockL2Gateway.address)
        expect(await l1GraphTokenGateway.l2Counterpart()).eq(mockL2Gateway.address)
        expect(await l1GraphTokenGateway.counterpartGateway()).eq(mockL2Gateway.address)
      })
    })
    describe('setEscrowAddress', function () {
      it('is not callable by addreses that are not the governor', async function () {
        const tx = l1GraphTokenGateway
          .connect(tokenSender.signer)
          .setEscrowAddress(bridgeEscrow.address)
        await expect(tx).revertedWith('Only Controller governor')
      })
      it('sets escrow', async function () {
        const tx = l1GraphTokenGateway
          .connect(governor.signer)
          .setEscrowAddress(bridgeEscrow.address)
        await expect(tx)
          .emit(l1GraphTokenGateway, 'EscrowAddressSet')
          .withArgs(bridgeEscrow.address)
        expect(await l1GraphTokenGateway.escrow()).eq(bridgeEscrow.address)
      })
    })
    describe('addToCallhookAllowlist', function () {
      it('is not callable by addreses that are not the governor', async function () {
        const tx = l1GraphTokenGateway
          .connect(tokenSender.signer)
          .addToCallhookAllowlist(fixtureContracts.rewardsManager.address)
        await expect(tx).revertedWith('Only Controller governor')
        expect(
          await l1GraphTokenGateway.callhookAllowlist(fixtureContracts.rewardsManager.address),
        ).eq(false)
      })
      it('rejects adding an EOA to the callhook allowlist', async function () {
        const tx = l1GraphTokenGateway
          .connect(governor.signer)
          .addToCallhookAllowlist(tokenSender.address)
        await expect(tx).revertedWith('MUST_BE_CONTRACT')
      })
      it('adds an address to the callhook allowlist', async function () {
        const tx = l1GraphTokenGateway
          .connect(governor.signer)
          .addToCallhookAllowlist(fixtureContracts.rewardsManager.address)
        await expect(tx)
          .emit(l1GraphTokenGateway, 'AddedToCallhookAllowlist')
          .withArgs(fixtureContracts.rewardsManager.address)
        expect(
          await l1GraphTokenGateway.callhookAllowlist(fixtureContracts.rewardsManager.address),
        ).eq(true)
      })
    })
    describe('removeFromCallhookAllowlist', function () {
      it('is not callable by addreses that are not the governor', async function () {
        await l1GraphTokenGateway
          .connect(governor.signer)
          .addToCallhookAllowlist(fixtureContracts.rewardsManager.address)
        const tx = l1GraphTokenGateway
          .connect(tokenSender.signer)
          .removeFromCallhookAllowlist(fixtureContracts.rewardsManager.address)
        await expect(tx).revertedWith('Only Controller governor')
        expect(
          await l1GraphTokenGateway.callhookAllowlist(fixtureContracts.rewardsManager.address),
        ).eq(true)
      })
      it('removes an address from the callhook allowlist', async function () {
        await l1GraphTokenGateway
          .connect(governor.signer)
          .addToCallhookAllowlist(fixtureContracts.rewardsManager.address)
        const tx = l1GraphTokenGateway
          .connect(governor.signer)
          .removeFromCallhookAllowlist(fixtureContracts.rewardsManager.address)
        await expect(tx)
          .emit(l1GraphTokenGateway, 'RemovedFromCallhookAllowlist')
          .withArgs(fixtureContracts.rewardsManager.address)
        expect(
          await l1GraphTokenGateway.callhookAllowlist(fixtureContracts.rewardsManager.address),
        ).eq(false)
      })
    })
    describe('Pausable behavior', () => {
      it('cannot be paused or unpaused by someone other than governor or pauseGuardian', async () => {
        let tx = l1GraphTokenGateway.connect(tokenSender.signer).setPaused(false)
        await expect(tx).revertedWith('Only Governor or Guardian')
        tx = l1GraphTokenGateway.connect(tokenSender.signer).setPaused(true)
        await expect(tx).revertedWith('Only Governor or Guardian')
      })
      it('cannot be unpaused if some state variables are not set', async function () {
        let tx = l1GraphTokenGateway.connect(governor.signer).setPaused(false)
        await expect(tx).revertedWith('INBOX_NOT_SET')
        await l1GraphTokenGateway
          .connect(governor.signer)
          .setArbitrumAddresses(arbitrumMocks.inboxMock.address, mockRouter.address)
        tx = l1GraphTokenGateway.connect(governor.signer).setPaused(false)
        await expect(tx).revertedWith('L2_COUNTERPART_NOT_SET')
        await l1GraphTokenGateway
          .connect(governor.signer)
          .setL2CounterpartAddress(mockL2Gateway.address)
        tx = l1GraphTokenGateway.connect(governor.signer).setPaused(false)
        await expect(tx).revertedWith('ESCROW_NOT_SET')
      })
      it('can be paused and unpaused by the governor', async function () {
        await fixture.configureL1Bridge(
          governor.signer,
          arbitrumMocks,
          fixtureContracts,
          mockRouter.address,
          mockL2GRT.address,
          mockL2Gateway.address,
        )
        let tx = l1GraphTokenGateway.connect(governor.signer).setPaused(true)
        await expect(tx).emit(l1GraphTokenGateway, 'PauseChanged').withArgs(true)
        await expect(await l1GraphTokenGateway.paused()).eq(true)
        tx = l1GraphTokenGateway.connect(governor.signer).setPaused(false)
        await expect(tx).emit(l1GraphTokenGateway, 'PauseChanged').withArgs(false)
        await expect(await l1GraphTokenGateway.paused()).eq(false)
      })
      describe('setPauseGuardian', function () {
        it('cannot be called by someone other than governor', async function () {
          const tx = l1GraphTokenGateway
            .connect(tokenSender.signer)
            .setPauseGuardian(pauseGuardian.address)
          await expect(tx).revertedWith('Only Controller governor')
        })
        it('sets a new pause guardian', async function () {
          const tx = l1GraphTokenGateway
            .connect(governor.signer)
            .setPauseGuardian(pauseGuardian.address)
          await expect(tx)
            .emit(l1GraphTokenGateway, 'NewPauseGuardian')
            .withArgs(AddressZero, pauseGuardian.address)
        })
        it('allows a pause guardian to pause and unpause', async function () {
          await fixture.configureL1Bridge(
            governor.signer,
            arbitrumMocks,
            fixtureContracts,
            mockRouter.address,
            mockL2GRT.address,
            mockL2Gateway.address,
          )
          await l1GraphTokenGateway.connect(governor.signer).setPauseGuardian(pauseGuardian.address)
          let tx = l1GraphTokenGateway.connect(pauseGuardian.signer).setPaused(true)
          await expect(tx).emit(l1GraphTokenGateway, 'PauseChanged').withArgs(true)
          await expect(await l1GraphTokenGateway.paused()).eq(true)
          tx = l1GraphTokenGateway.connect(pauseGuardian.signer).setPaused(false)
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
          toBN(mockL2Gateway.address),
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
      await expect(escrowBalance).eq(toGRT('10'))
      await expect(senderBalance).eq(toGRT('990'))
    }
    before(async function () {
      await fixture.configureL1Bridge(
        governor.signer,
        arbitrumMocks,
        fixtureContracts,
        mockRouter.address,
        mockL2GRT.address,
        mockL2Gateway.address,
      )
    })

    describe('calculateL2TokenAddress', function () {
      it('returns the L2 token address', async function () {
        expect(await l1GraphTokenGateway.calculateL2TokenAddress(grt.address)).eq(mockL2GRT.address)
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
          .connect(tokenSender.signer)
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
        await grt.connect(tokenSender.signer).approve(l1GraphTokenGateway.address, toGRT('10'))
        await testValidOutboundTransfer(tokenSender.signer, defaultData, emptyCallHookData)
      })
      it('decodes the sender address from messages sent by the router', async function () {
        await grt.connect(tokenSender.signer).approve(l1GraphTokenGateway.address, toGRT('10'))
        const routerEncodedData = utils.defaultAbiCoder.encode(
          ['address', 'bytes'],
          [tokenSender.address, defaultData],
        )
        await testValidOutboundTransfer(mockRouter.signer, routerEncodedData, emptyCallHookData)
      })
      it('reverts when called with no submission cost', async function () {
        await grt.connect(tokenSender.signer).approve(l1GraphTokenGateway.address, toGRT('10'))
        const tx = l1GraphTokenGateway
          .connect(tokenSender.signer)
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
        await grt.connect(tokenSender.signer).approve(l1GraphTokenGateway.address, toGRT('10'))
        const tx = l1GraphTokenGateway
          .connect(tokenSender.signer)
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
        await provider().send('hardhat_setCode', [tokenSender.address, '0x1234'])
        await l1GraphTokenGateway
          .connect(governor.signer)
          .addToCallhookAllowlist(tokenSender.address)
        await grt.connect(tokenSender.signer).approve(l1GraphTokenGateway.address, toGRT('10'))
        await testValidOutboundTransfer(
          tokenSender.signer,
          defaultDataWithNotEmptyCallHookData,
          notEmptyCallHookData,
        )
      })
      it('reverts when the sender does not have enough GRT', async function () {
        await grt.connect(tokenSender.signer).approve(l1GraphTokenGateway.address, toGRT('1001'))
        const tx = l1GraphTokenGateway
          .connect(tokenSender.signer)
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
          .connect(tokenSender.signer)
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
        const tx = outboxMock.connect(tokenSender.signer).executeTransaction(
          toBN('0'),
          [],
          toBN('0'),
          l2Receiver.address, // Note this is not mockL2Gateway
          l1GraphTokenGateway.address,
          toBN('1337'),
          await latestBlock(),
          toBN('133701337'),
          toBN('0'),
          encodedCalldata,
        )
        await expect(tx).revertedWith('ONLY_COUNTERPART_GATEWAY')
      })
      it('reverts if the gateway does not have tokens', async function () {
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
          .connect(tokenSender.signer)
          .executeTransaction(
            toBN('0'),
            [],
            toBN('0'),
            mockL2Gateway.address,
            l1GraphTokenGateway.address,
            toBN('1337'),
            await latestBlock(),
            toBN('133701337'),
            toBN('0'),
            encodedCalldata,
          )
        await expect(tx).revertedWith('BRIDGE_OUT_OF_FUNDS')
      })
      it('reverts if the gateway is revoked from escrow', async function () {
        await grt.connect(tokenSender.signer).approve(l1GraphTokenGateway.address, toGRT('10'))
        await testValidOutboundTransfer(tokenSender.signer, defaultData, emptyCallHookData)
        // At this point, the gateway holds 10 GRT in escrow
        // But we revoke the gateway's permission to move the funds:
        await bridgeEscrow.connect(governor.signer).revokeAll(l1GraphTokenGateway.address)
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
          .connect(tokenSender.signer)
          .executeTransaction(
            toBN('0'),
            [],
            toBN('0'),
            mockL2Gateway.address,
            l1GraphTokenGateway.address,
            toBN('1337'),
            await latestBlock(),
            toBN('133701337'),
            toBN('0'),
            encodedCalldata,
          )
        await expect(tx).revertedWith('ERC20: transfer amount exceeds allowance')
      })
      it('sends tokens out of escrow', async function () {
        await grt.connect(tokenSender.signer).approve(l1GraphTokenGateway.address, toGRT('10'))
        await testValidOutboundTransfer(tokenSender.signer, defaultData, emptyCallHookData)
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
          .connect(tokenSender.signer)
          .executeTransaction(
            toBN('0'),
            [],
            toBN('0'),
            mockL2Gateway.address,
            l1GraphTokenGateway.address,
            toBN('1337'),
            await latestBlock(),
            toBN('133701337'),
            toBN('0'),
            encodedCalldata,
          )
        await expect(tx)
          .emit(l1GraphTokenGateway, 'WithdrawalFinalized')
          .withArgs(grt.address, l2Receiver.address, tokenSender.address, toBN('0'), toGRT('8'))
        const escrowBalance = await grt.balanceOf(bridgeEscrow.address)
        const senderBalance = await grt.balanceOf(tokenSender.address)
        await expect(escrowBalance).eq(toGRT('2'))
        await expect(senderBalance).eq(toGRT('998'))
      })
    })
  })
})
