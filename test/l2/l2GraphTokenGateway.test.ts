import { expect, use } from 'chai'
import { constants, ContractTransaction, Signer, utils } from 'ethers'

import { L2GraphToken } from '../../build/types/L2GraphToken'
import { L2GraphTokenGateway } from '../../build/types/L2GraphTokenGateway'
import { CallhookReceiverMock } from '../../build/types/CallhookReceiverMock'

import { L2FixtureContracts, NetworkFixture } from '../lib/fixtures'

import { FakeContract, smock } from '@defi-wonderland/smock'

use(smock.matchers)

import { getAccounts, toGRT, Account, toBN, getL2SignerFromL1 } from '../lib/testHelpers'
import { Interface } from 'ethers/lib/utils'
import { deployContract } from '../lib/deployment'
import { RewardsManager } from '../../build/types/RewardsManager'

const { AddressZero } = constants

describe('L2GraphTokenGateway', () => {
  let me: Account
  let governor: Account
  let tokenSender: Account
  let l1Receiver: Account
  let l2Receiver: Account
  let mockRouter: Account
  let mockL1GRT: Account
  let mockL1Gateway: Account
  let pauseGuardian: Account
  let fixture: NetworkFixture
  let arbSysMock: FakeContract

  let fixtureContracts: L2FixtureContracts
  let grt: L2GraphToken
  let l2GraphTokenGateway: L2GraphTokenGateway
  let callhookReceiverMock: CallhookReceiverMock
  let rewardsManager: RewardsManager

  const senderTokens = toGRT('1000')
  const defaultData = '0x'
  const defaultDataWithNotEmptyCallHookData = utils.defaultAbiCoder.encode(
    ['uint256', 'uint256'],
    [toBN('1337'), toBN('42')],
  )

  before(async function () {
    ;[
      me,
      governor,
      tokenSender,
      l1Receiver,
      mockRouter,
      mockL1GRT,
      mockL1Gateway,
      l2Receiver,
      pauseGuardian,
    ] = await getAccounts()

    fixture = new NetworkFixture()
    fixtureContracts = await fixture.loadL2(governor.signer)
    ;({ grt, l2GraphTokenGateway, rewardsManager } = fixtureContracts)

    callhookReceiverMock = (await deployContract(
      'CallhookReceiverMock',
      governor.signer,
    )) as unknown as CallhookReceiverMock

    // Give some funds to the token sender
    await grt.connect(governor.signer).mint(tokenSender.address, senderTokens)
  })

  beforeEach(async function () {
    await fixture.setUp()
    // Thanks to Livepeer: https://github.com/livepeer/arbitrum-lpt-bridge/blob/main/test/unit/L2/l2LPTGateway.test.ts#L86
    arbSysMock = await smock.fake('ArbSys', {
      address: '0x0000000000000000000000000000000000000064',
    })
    arbSysMock.sendTxToL1.returns(1)
  })

  afterEach(async function () {
    await fixture.tearDown()
  })

  context('> immediately after deploy', function () {
    describe('calculateL2TokenAddress', function () {
      it('should return the zero address', async function () {
        expect(await l2GraphTokenGateway.calculateL2TokenAddress(grt.address)).eq(AddressZero)
      })
    })

    describe('outboundTransfer', function () {
      it('reverts because it is paused', async function () {
        const tx = l2GraphTokenGateway
          .connect(tokenSender.signer)
          ['outboundTransfer(address,address,uint256,bytes)'](
            grt.address,
            l1Receiver.address,
            toGRT('10'),
            defaultData,
          )
        await expect(tx).revertedWith('Paused (contract)')
      })
    })

    describe('finalizeInboundTransfer', function () {
      it('revert because it is paused', async function () {
        const tx = l2GraphTokenGateway
          .connect(tokenSender.signer)
          .finalizeInboundTransfer(
            grt.address,
            tokenSender.address,
            l1Receiver.address,
            toGRT('10'),
            defaultData,
          )
        await expect(tx).revertedWith('Paused (contract)')
      })
    })

    describe('setL2Router', function () {
      it('is not callable by addreses that are not the governor', async function () {
        const tx = l2GraphTokenGateway.connect(tokenSender.signer).setL2Router(mockRouter.address)
        await expect(tx).revertedWith('Only Controller governor')
      })
      it('sets router address', async function () {
        const tx = l2GraphTokenGateway.connect(governor.signer).setL2Router(mockRouter.address)
        await expect(tx).emit(l2GraphTokenGateway, 'L2RouterSet').withArgs(mockRouter.address)
        expect(await l2GraphTokenGateway.l2Router()).eq(mockRouter.address)
      })
    })

    describe('setL1TokenAddress', function () {
      it('is not callable by addreses that are not the governor', async function () {
        const tx = l2GraphTokenGateway
          .connect(tokenSender.signer)
          .setL1TokenAddress(mockL1GRT.address)
        await expect(tx).revertedWith('Only Controller governor')
      })
      it('sets l2GRT', async function () {
        const tx = l2GraphTokenGateway.connect(governor.signer).setL1TokenAddress(mockL1GRT.address)
        await expect(tx).emit(l2GraphTokenGateway, 'L1TokenAddressSet').withArgs(mockL1GRT.address)
        expect(await l2GraphTokenGateway.l1GRT()).eq(mockL1GRT.address)
      })
    })

    describe('setL1CounterpartAddress', function () {
      it('is not callable by addreses that are not the governor', async function () {
        const tx = l2GraphTokenGateway
          .connect(tokenSender.signer)
          .setL1CounterpartAddress(mockL1Gateway.address)
        await expect(tx).revertedWith('Only Controller governor')
      })
      it('sets L1Counterpart', async function () {
        const tx = l2GraphTokenGateway
          .connect(governor.signer)
          .setL1CounterpartAddress(mockL1Gateway.address)
        await expect(tx)
          .emit(l2GraphTokenGateway, 'L1CounterpartAddressSet')
          .withArgs(mockL1Gateway.address)
        expect(await l2GraphTokenGateway.l1Counterpart()).eq(mockL1Gateway.address)
      })
    })
    describe('Pausable behavior', () => {
      it('cannot be paused or unpaused by someone other than governor or pauseGuardian', async () => {
        let tx = l2GraphTokenGateway.connect(tokenSender.signer).setPaused(false)
        await expect(tx).revertedWith('Only Governor or Guardian')
        tx = l2GraphTokenGateway.connect(tokenSender.signer).setPaused(true)
        await expect(tx).revertedWith('Only Governor or Guardian')
      })
      it('cannot be paused if some state variables are not set', async function () {
        let tx = l2GraphTokenGateway.connect(governor.signer).setPaused(false)
        await expect(tx).revertedWith('L2_ROUTER_NOT_SET')
        await l2GraphTokenGateway.connect(governor.signer).setL2Router(mockRouter.address)
        tx = l2GraphTokenGateway.connect(governor.signer).setPaused(false)
        await expect(tx).revertedWith('L1_COUNTERPART_NOT_SET')
        await l2GraphTokenGateway
          .connect(governor.signer)
          .setL1CounterpartAddress(mockL1Gateway.address)
        tx = l2GraphTokenGateway.connect(governor.signer).setPaused(false)
        await expect(tx).revertedWith('L1_GRT_NOT_SET')
      })
      it('can be paused and unpaused by the governor', async function () {
        await fixture.configureL2Bridge(
          governor.signer,
          fixtureContracts,
          mockRouter.address,
          mockL1GRT.address,
          mockL1Gateway.address,
        )
        let tx = l2GraphTokenGateway.connect(governor.signer).setPaused(true)
        await expect(tx).emit(l2GraphTokenGateway, 'PauseChanged').withArgs(true)
        await expect(await l2GraphTokenGateway.paused()).eq(true)
        tx = l2GraphTokenGateway.connect(governor.signer).setPaused(false)
        await expect(tx).emit(l2GraphTokenGateway, 'PauseChanged').withArgs(false)
        await expect(await l2GraphTokenGateway.paused()).eq(false)
      })
      describe('setPauseGuardian', function () {
        it('cannot be called by someone other than governor', async function () {
          const tx = l2GraphTokenGateway
            .connect(tokenSender.signer)
            .setPauseGuardian(pauseGuardian.address)
          await expect(tx).revertedWith('Only Controller governor')
        })
        it('sets a new pause guardian', async function () {
          const tx = l2GraphTokenGateway
            .connect(governor.signer)
            .setPauseGuardian(pauseGuardian.address)
          await expect(tx)
            .emit(l2GraphTokenGateway, 'NewPauseGuardian')
            .withArgs(AddressZero, pauseGuardian.address)
        })
        it('allows a pause guardian to pause and unpause', async function () {
          await fixture.configureL2Bridge(
            governor.signer,
            fixtureContracts,
            mockRouter.address,
            mockL1GRT.address,
            mockL1Gateway.address,
          )
          await l2GraphTokenGateway.connect(governor.signer).setPauseGuardian(pauseGuardian.address)
          let tx = l2GraphTokenGateway.connect(pauseGuardian.signer).setPaused(true)
          await expect(tx).emit(l2GraphTokenGateway, 'PauseChanged').withArgs(true)
          await expect(await l2GraphTokenGateway.paused()).eq(true)
          tx = l2GraphTokenGateway.connect(pauseGuardian.signer).setPaused(false)
          await expect(tx).emit(l2GraphTokenGateway, 'PauseChanged').withArgs(false)
          await expect(await l2GraphTokenGateway.paused()).eq(false)
        })
      })
    })
  })

  context('> after configuring and unpausing', function () {
    const testValidOutboundTransfer = async function (signer: Signer, data: string) {
      const tx = l2GraphTokenGateway
        .connect(signer)
        ['outboundTransfer(address,address,uint256,bytes)'](
          mockL1GRT.address,
          l1Receiver.address,
          toGRT('10'),
          data,
        )
      const expectedId = 1
      await expect(tx)
        .emit(l2GraphTokenGateway, 'WithdrawalInitiated')
        .withArgs(
          mockL1GRT.address,
          tokenSender.address,
          l1Receiver.address,
          expectedId,
          0,
          toGRT('10'),
        )

      // Should use the L1 Gateway's interface, but both come from ITokenGateway
      const calldata = l2GraphTokenGateway.interface.encodeFunctionData('finalizeInboundTransfer', [
        mockL1GRT.address,
        tokenSender.address,
        l1Receiver.address,
        toGRT('10'),
        utils.defaultAbiCoder.encode(['uint256', 'bytes'], [0, []]),
      ])
      await expect(tx)
        .emit(l2GraphTokenGateway, 'TxToL1')
        .withArgs(tokenSender.address, mockL1Gateway.address, 1, calldata)

      // For some reason the call count doesn't work properly,
      // and each function call is counted 12 times.
      // Possibly related to https://github.com/defi-wonderland/smock/issues/85 ?
      //expect(arbSysMock.sendTxToL1).to.have.been.calledOnce
      expect(arbSysMock.sendTxToL1).to.have.been.calledWith(mockL1Gateway.address, calldata)
      const senderBalance = await grt.balanceOf(tokenSender.address)
      await expect(senderBalance).eq(toGRT('990'))
    }
    before(async function () {
      await fixture.configureL2Bridge(
        governor.signer,
        fixtureContracts,
        mockRouter.address,
        mockL1GRT.address,
        mockL1Gateway.address,
      )
    })

    describe('calculateL2TokenAddress', function () {
      it('returns the L2 token address', async function () {
        expect(await l2GraphTokenGateway.calculateL2TokenAddress(mockL1GRT.address)).eq(grt.address)
      })
      it('returns the zero address if the input is any other address', async function () {
        expect(await l2GraphTokenGateway.calculateL2TokenAddress(tokenSender.address)).eq(
          AddressZero,
        )
      })
    })

    describe('outboundTransfer', function () {
      it('reverts when called with the wrong token address', async function () {
        const tx = l2GraphTokenGateway
          .connect(tokenSender.signer)
          ['outboundTransfer(address,address,uint256,bytes)'](
            tokenSender.address,
            l1Receiver.address,
            toGRT('10'),
            defaultData,
          )
        await expect(tx).revertedWith('TOKEN_NOT_GRT')
      })
      it('burns tokens and triggers an L1 call', async function () {
        await grt.connect(tokenSender.signer).approve(l2GraphTokenGateway.address, toGRT('10'))
        await testValidOutboundTransfer(tokenSender.signer, defaultData)
      })
      it('decodes the sender address from messages sent by the router', async function () {
        await grt.connect(tokenSender.signer).approve(l2GraphTokenGateway.address, toGRT('10'))
        const routerEncodedData = utils.defaultAbiCoder.encode(
          ['address', 'bytes'],
          [tokenSender.address, defaultData],
        )
        await testValidOutboundTransfer(mockRouter.signer, routerEncodedData)
      })
      it('reverts when called with nonempty calldata', async function () {
        await grt.connect(tokenSender.signer).approve(l2GraphTokenGateway.address, toGRT('10'))
        const tx = l2GraphTokenGateway
          .connect(tokenSender.signer)
          ['outboundTransfer(address,address,uint256,bytes)'](
            mockL1GRT.address,
            l1Receiver.address,
            toGRT('10'),
            defaultDataWithNotEmptyCallHookData,
          )
        await expect(tx).revertedWith('CALL_HOOK_DATA_NOT_ALLOWED')
      })
      it('reverts when the sender does not have enough GRT', async function () {
        await grt.connect(tokenSender.signer).approve(l2GraphTokenGateway.address, toGRT('1001'))
        const tx = l2GraphTokenGateway
          .connect(tokenSender.signer)
          ['outboundTransfer(address,address,uint256,bytes)'](
            mockL1GRT.address,
            l1Receiver.address,
            toGRT('1001'),
            defaultData,
          )
        await expect(tx).revertedWith('ERC20: burn amount exceeds balance')
      })
    })

    describe('finalizeInboundTransfer', function () {
      const testValidFinalizeTransfer = async function (
        data: string,
        to?: string,
      ): Promise<ContractTransaction> {
        to = to ?? l2Receiver.address
        const mockL1GatewayL2Alias = await getL2SignerFromL1(mockL1Gateway.address)
        await me.signer.sendTransaction({
          to: await mockL1GatewayL2Alias.getAddress(),
          value: utils.parseUnits('1', 'ether'),
        })
        const tx = l2GraphTokenGateway
          .connect(mockL1GatewayL2Alias)
          .finalizeInboundTransfer(mockL1GRT.address, tokenSender.address, to, toGRT('10'), data)
        await expect(tx)
          .emit(l2GraphTokenGateway, 'DepositFinalized')
          .withArgs(mockL1GRT.address, tokenSender.address, to, toGRT('10'))

        await expect(tx).emit(grt, 'BridgeMinted').withArgs(to, toGRT('10'))

        // Unchanged
        const senderBalance = await grt.balanceOf(tokenSender.address)
        await expect(senderBalance).eq(toGRT('1000'))
        // 10 newly minted GRT
        const receiverBalance = await grt.balanceOf(to)
        await expect(receiverBalance).eq(toGRT('10'))
        return tx
      }
      it('reverts when called by an account that is not the gateway', async function () {
        const tx = l2GraphTokenGateway
          .connect(tokenSender.signer)
          .finalizeInboundTransfer(
            mockL1GRT.address,
            tokenSender.address,
            l2Receiver.address,
            toGRT('10'),
            defaultData,
          )
        await expect(tx).revertedWith('ONLY_COUNTERPART_GATEWAY')
      })
      it('reverts when called by an account that is the gateway but without the L2 alias', async function () {
        const tx = l2GraphTokenGateway
          .connect(mockL1Gateway.signer)
          .finalizeInboundTransfer(
            mockL1GRT.address,
            tokenSender.address,
            l2Receiver.address,
            toGRT('10'),
            defaultData,
          )
        await expect(tx).revertedWith('ONLY_COUNTERPART_GATEWAY')
      })
      it('mints and sends tokens when called by the aliased gateway', async function () {
        await testValidFinalizeTransfer(defaultData)
      })
      it('calls a callhook if the transfer includes calldata', async function () {
        const tx = await testValidFinalizeTransfer(
          defaultDataWithNotEmptyCallHookData,
          callhookReceiverMock.address,
        )
        // Emitted by the callhook:
        await expect(tx)
          .emit(callhookReceiverMock, 'TransferReceived')
          .withArgs(tokenSender.address, toGRT('10'), toBN('1337'), toBN('42'))
      })
      it('reverts if a callhook reverts', async function () {
        // The 0 will make the callhook revert (see CallhookReceiverMock.sol)
        const callHookData = utils.defaultAbiCoder.encode(
          ['uint256', 'uint256'],
          [toBN('0'), toBN('42')],
        )
        const mockL1GatewayL2Alias = await getL2SignerFromL1(mockL1Gateway.address)
        await me.signer.sendTransaction({
          to: await mockL1GatewayL2Alias.getAddress(),
          value: utils.parseUnits('1', 'ether'),
        })
        const tx = l2GraphTokenGateway
          .connect(mockL1GatewayL2Alias)
          .finalizeInboundTransfer(
            mockL1GRT.address,
            tokenSender.address,
            callhookReceiverMock.address,
            toGRT('10'),
            callHookData,
          )
        await expect(tx).revertedWith('FOO_IS_ZERO')
      })
      it('reverts if trying to call a callhook in a contract that does not implement onTokenTransfer', async function () {
        const callHookData = utils.defaultAbiCoder.encode(['uint256'], [toBN('0')])
        const mockL1GatewayL2Alias = await getL2SignerFromL1(mockL1Gateway.address)
        await me.signer.sendTransaction({
          to: await mockL1GatewayL2Alias.getAddress(),
          value: utils.parseUnits('1', 'ether'),
        })
        // RewardsManager does not implement onTokenTransfer, so this will fail
        const tx = l2GraphTokenGateway
          .connect(mockL1GatewayL2Alias)
          .finalizeInboundTransfer(
            mockL1GRT.address,
            tokenSender.address,
            rewardsManager.address,
            toGRT('10'),
            callHookData,
          )
        await expect(tx).revertedWith(
          "function selector was not recognized and there's no fallback function",
        )
      })
    })
  })
})
