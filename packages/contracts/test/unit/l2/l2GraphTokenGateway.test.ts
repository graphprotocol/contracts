import hre from 'hardhat'
import { expect, use } from 'chai'
import { constants, ContractTransaction, Signer, utils, Wallet } from 'ethers'

import { L2GraphToken } from '../../../build/types/L2GraphToken'
import { L2GraphTokenGateway } from '../../../build/types/L2GraphTokenGateway'
import { CallhookReceiverMock } from '../../../build/types/CallhookReceiverMock'

import { NetworkFixture } from '../lib/fixtures'

import { FakeContract, smock } from '@defi-wonderland/smock'

use(smock.matchers)

import { RewardsManager } from '../../../build/types/RewardsManager'
import { deploy, DeployType, GraphNetworkContracts, helpers, toBN, toGRT } from '@graphprotocol/sdk'
import { SignerWithAddress } from '@nomiclabs/hardhat-ethers/signers'
import { GraphToken, L1GraphTokenGateway } from '../../../build/types'

const { AddressZero } = constants

describe('L2GraphTokenGateway', () => {
  const graph = hre.graph()
  let me: SignerWithAddress
  let governor: SignerWithAddress
  let tokenSender: SignerWithAddress
  let l1Receiver: SignerWithAddress
  let l2Receiver: SignerWithAddress
  let pauseGuardian: SignerWithAddress
  let fixture: NetworkFixture
  let arbSysMock: FakeContract

  let fixtureContracts: GraphNetworkContracts
  let l1MockContracts: GraphNetworkContracts
  let l1GRTMock: GraphToken
  let l1GRTGatewayMock: L1GraphTokenGateway
  let routerMock: Wallet

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
    [me, governor, tokenSender, l1Receiver, l2Receiver, pauseGuardian]
      = await graph.getTestAccounts()

    fixture = new NetworkFixture(graph.provider)

    // Deploy L2
    fixtureContracts = await fixture.load(governor, true)
    grt = fixtureContracts.GraphToken as L2GraphToken
    l2GraphTokenGateway = fixtureContracts.L2GraphTokenGateway
    rewardsManager = fixtureContracts.RewardsManager

    // Deploy L2 arbitrum bridge
    ;({ routerMock } = await fixture.loadL2ArbitrumBridge(governor))

    // Deploy L1 mock
    l1MockContracts = await fixture.loadMock(false)
    l1GRTMock = l1MockContracts.GraphToken as GraphToken
    l1GRTGatewayMock = l1MockContracts.L1GraphTokenGateway

    callhookReceiverMock = (
      await deploy(DeployType.Deploy, governor, {
        name: 'CallhookReceiverMock',
      })
    ).contract as CallhookReceiverMock

    // Give some funds to the token sender and router mock
    await grt.connect(governor).mint(tokenSender.address, senderTokens)
    await helpers.setBalance(routerMock.address, utils.parseEther('1'))
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
          .connect(tokenSender)['outboundTransfer(address,address,uint256,bytes)'](
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
          .connect(tokenSender)
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
        const tx = l2GraphTokenGateway.connect(tokenSender).setL2Router(routerMock.address)
        await expect(tx).revertedWith('Only Controller governor')
      })
      it('sets router address', async function () {
        const tx = l2GraphTokenGateway.connect(governor).setL2Router(routerMock.address)
        await expect(tx).emit(l2GraphTokenGateway, 'L2RouterSet').withArgs(routerMock.address)
        expect(await l2GraphTokenGateway.l2Router()).eq(routerMock.address)
      })
    })

    describe('setL1TokenAddress', function () {
      it('is not callable by addreses that are not the governor', async function () {
        const tx = l2GraphTokenGateway.connect(tokenSender).setL1TokenAddress(l1GRTMock.address)
        await expect(tx).revertedWith('Only Controller governor')
      })
      it('sets l2GRT', async function () {
        const tx = l2GraphTokenGateway.connect(governor).setL1TokenAddress(l1GRTMock.address)
        await expect(tx).emit(l2GraphTokenGateway, 'L1TokenAddressSet').withArgs(l1GRTMock.address)
        expect(await l2GraphTokenGateway.l1GRT()).eq(l1GRTMock.address)
      })
    })

    describe('setL1CounterpartAddress', function () {
      it('is not callable by addreses that are not the governor', async function () {
        const tx = l2GraphTokenGateway
          .connect(tokenSender)
          .setL1CounterpartAddress(l1GRTGatewayMock.address)
        await expect(tx).revertedWith('Only Controller governor')
      })
      it('sets L1Counterpart', async function () {
        const tx = l2GraphTokenGateway
          .connect(governor)
          .setL1CounterpartAddress(l1GRTGatewayMock.address)
        await expect(tx)
          .emit(l2GraphTokenGateway, 'L1CounterpartAddressSet')
          .withArgs(l1GRTGatewayMock.address)
        expect(await l2GraphTokenGateway.l1Counterpart()).eq(l1GRTGatewayMock.address)
      })
    })
    describe('Pausable behavior', () => {
      it('cannot be paused or unpaused by someone other than governor or pauseGuardian', async () => {
        let tx = l2GraphTokenGateway.connect(tokenSender).setPaused(false)
        await expect(tx).revertedWith('Only Governor or Guardian')
        tx = l2GraphTokenGateway.connect(tokenSender).setPaused(true)
        await expect(tx).revertedWith('Only Governor or Guardian')
      })
      it('cannot be paused if some state variables are not set', async function () {
        let tx = l2GraphTokenGateway.connect(governor).setPaused(false)
        await expect(tx).revertedWith('L2_ROUTER_NOT_SET')
        await l2GraphTokenGateway.connect(governor).setL2Router(routerMock.address)
        tx = l2GraphTokenGateway.connect(governor).setPaused(false)
        await expect(tx).revertedWith('L1_COUNTERPART_NOT_SET')
        await l2GraphTokenGateway
          .connect(governor)
          .setL1CounterpartAddress(l1GRTGatewayMock.address)
        tx = l2GraphTokenGateway.connect(governor).setPaused(false)
        await expect(tx).revertedWith('L1_GRT_NOT_SET')
      })
      it('can be paused and unpaused by the governor', async function () {
        await fixture.configureL2Bridge(governor, fixtureContracts, l1MockContracts)
        let tx = l2GraphTokenGateway.connect(governor).setPaused(true)
        await expect(tx).emit(l2GraphTokenGateway, 'PauseChanged').withArgs(true)
        expect(await l2GraphTokenGateway.paused()).eq(true)
        tx = l2GraphTokenGateway.connect(governor).setPaused(false)
        await expect(tx).emit(l2GraphTokenGateway, 'PauseChanged').withArgs(false)
        expect(await l2GraphTokenGateway.paused()).eq(false)
      })
      describe('setPauseGuardian', function () {
        it('cannot be called by someone other than governor', async function () {
          const tx = l2GraphTokenGateway
            .connect(tokenSender)
            .setPauseGuardian(pauseGuardian.address)
          await expect(tx).revertedWith('Only Controller governor')
        })
        it('sets a new pause guardian', async function () {
          const currentPauseGuardian = await l2GraphTokenGateway.pauseGuardian()
          const tx = l2GraphTokenGateway.connect(governor).setPauseGuardian(pauseGuardian.address)
          await expect(tx)
            .emit(l2GraphTokenGateway, 'NewPauseGuardian')
            .withArgs(currentPauseGuardian, pauseGuardian.address)
        })
        it('allows a pause guardian to pause and unpause', async function () {
          await fixture.configureL2Bridge(governor, fixtureContracts, l1MockContracts)
          await l2GraphTokenGateway.connect(governor).setPauseGuardian(pauseGuardian.address)
          let tx = l2GraphTokenGateway.connect(pauseGuardian).setPaused(true)
          await expect(tx).emit(l2GraphTokenGateway, 'PauseChanged').withArgs(true)
          expect(await l2GraphTokenGateway.paused()).eq(true)
          tx = l2GraphTokenGateway.connect(pauseGuardian).setPaused(false)
          await expect(tx).emit(l2GraphTokenGateway, 'PauseChanged').withArgs(false)
          expect(await l2GraphTokenGateway.paused()).eq(false)
        })
      })
    })
  })

  context('> after configuring and unpausing', function () {
    const testValidOutboundTransfer = async function (signer: Signer, data: string) {
      const tx = l2GraphTokenGateway
        .connect(signer)['outboundTransfer(address,address,uint256,bytes)'](
          l1GRTMock.address,
          l1Receiver.address,
          toGRT('10'),
          data,
        )
      const expectedId = 1
      await expect(tx)
        .emit(l2GraphTokenGateway, 'WithdrawalInitiated')
        .withArgs(
          l1GRTMock.address,
          tokenSender.address,
          l1Receiver.address,
          expectedId,
          0,
          toGRT('10'),
        )

      // Should use the L1 Gateway's interface, but both come from ITokenGateway
      const calldata = l2GraphTokenGateway.interface.encodeFunctionData('finalizeInboundTransfer', [
        l1GRTMock.address,
        tokenSender.address,
        l1Receiver.address,
        toGRT('10'),
        utils.defaultAbiCoder.encode(['uint256', 'bytes'], [0, []]),
      ])
      await expect(tx)
        .emit(l2GraphTokenGateway, 'TxToL1')
        .withArgs(tokenSender.address, l1GRTGatewayMock.address, 1, calldata)

      // For some reason the call count doesn't work properly,
      // and each function call is counted 12 times.
      // Possibly related to https://github.com/defi-wonderland/smock/issues/85 ?
      // expect(arbSysMock.sendTxToL1).to.have.been.calledOnce
      expect(arbSysMock.sendTxToL1).to.have.been.calledWith(l1GRTGatewayMock.address, calldata)
      const senderBalance = await grt.balanceOf(tokenSender.address)
      expect(senderBalance).eq(toGRT('990'))
    }
    before(async function () {
      await fixture.configureL2Bridge(governor, fixtureContracts, l1MockContracts)
    })

    describe('calculateL2TokenAddress', function () {
      it('returns the L2 token address', async function () {
        expect(await l2GraphTokenGateway.calculateL2TokenAddress(l1GRTMock.address)).eq(grt.address)
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
          .connect(tokenSender)['outboundTransfer(address,address,uint256,bytes)'](
            tokenSender.address,
            l1Receiver.address,
            toGRT('10'),
            defaultData,
          )
        await expect(tx).revertedWith('TOKEN_NOT_GRT')
      })
      it('burns tokens and triggers an L1 call', async function () {
        await grt.connect(tokenSender).approve(l2GraphTokenGateway.address, toGRT('10'))
        await testValidOutboundTransfer(tokenSender, defaultData)
      })
      it('decodes the sender address from messages sent by the router', async function () {
        await grt.connect(tokenSender).approve(l2GraphTokenGateway.address, toGRT('10'))
        const routerEncodedData = utils.defaultAbiCoder.encode(
          ['address', 'bytes'],
          [tokenSender.address, defaultData],
        )
        await testValidOutboundTransfer(routerMock, routerEncodedData)
      })
      it('reverts when called with nonempty calldata', async function () {
        await grt.connect(tokenSender).approve(l2GraphTokenGateway.address, toGRT('10'))
        const tx = l2GraphTokenGateway
          .connect(tokenSender)['outboundTransfer(address,address,uint256,bytes)'](
            l1GRTMock.address,
            l1Receiver.address,
            toGRT('10'),
            defaultDataWithNotEmptyCallHookData,
          )
        await expect(tx).revertedWith('CALL_HOOK_DATA_NOT_ALLOWED')
      })
      it('reverts when the sender does not have enough GRT', async function () {
        await grt.connect(tokenSender).approve(l2GraphTokenGateway.address, toGRT('1001'))
        const tx = l2GraphTokenGateway
          .connect(tokenSender)['outboundTransfer(address,address,uint256,bytes)'](
            l1GRTMock.address,
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
        const l1GRTGatewayMockL2Alias = await helpers.getL2SignerFromL1(l1GRTGatewayMock.address)
        await me.sendTransaction({
          to: await l1GRTGatewayMockL2Alias.getAddress(),
          value: utils.parseUnits('1', 'ether'),
        })
        const tx = l2GraphTokenGateway
          .connect(l1GRTGatewayMockL2Alias)
          .finalizeInboundTransfer(l1GRTMock.address, tokenSender.address, to, toGRT('10'), data)
        await expect(tx)
          .emit(l2GraphTokenGateway, 'DepositFinalized')
          .withArgs(l1GRTMock.address, tokenSender.address, to, toGRT('10'))

        await expect(tx).emit(grt, 'BridgeMinted').withArgs(to, toGRT('10'))

        // Unchanged
        const senderBalance = await grt.balanceOf(tokenSender.address)
        expect(senderBalance).eq(toGRT('1000'))
        // 10 newly minted GRT
        const receiverBalance = await grt.balanceOf(to)
        expect(receiverBalance).eq(toGRT('10'))
        return tx
      }
      it('reverts when called by an account that is not the gateway', async function () {
        const tx = l2GraphTokenGateway
          .connect(tokenSender)
          .finalizeInboundTransfer(
            l1GRTMock.address,
            tokenSender.address,
            l2Receiver.address,
            toGRT('10'),
            defaultData,
          )
        await expect(tx).revertedWith('ONLY_COUNTERPART_GATEWAY')
      })
      it('reverts when called by an account that is the gateway but without the L2 alias', async function () {
        const impersonatedGateway = await helpers.impersonateAccount(l1GRTGatewayMock.address)
        const tx = l2GraphTokenGateway
          .connect(impersonatedGateway)
          .finalizeInboundTransfer(
            l1GRTMock.address,
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
        const l1GRTGatewayMockL2Alias = await helpers.getL2SignerFromL1(l1GRTGatewayMock.address)
        await me.sendTransaction({
          to: await l1GRTGatewayMockL2Alias.getAddress(),
          value: utils.parseUnits('1', 'ether'),
        })
        const tx = l2GraphTokenGateway
          .connect(l1GRTGatewayMockL2Alias)
          .finalizeInboundTransfer(
            l1GRTMock.address,
            tokenSender.address,
            callhookReceiverMock.address,
            toGRT('10'),
            callHookData,
          )
        await expect(tx).revertedWith('FOO_IS_ZERO')
      })
      it('reverts if trying to call a callhook in a contract that does not implement onTokenTransfer', async function () {
        const callHookData = utils.defaultAbiCoder.encode(['uint256'], [toBN('0')])
        const l1GRTGatewayMockL2Alias = await helpers.getL2SignerFromL1(l1GRTGatewayMock.address)
        await me.sendTransaction({
          to: await l1GRTGatewayMockL2Alias.getAddress(),
          value: utils.parseUnits('1', 'ether'),
        })
        // RewardsManager does not implement onTokenTransfer, so this will fail
        const tx = l2GraphTokenGateway
          .connect(l1GRTGatewayMockL2Alias)
          .finalizeInboundTransfer(
            l1GRTMock.address,
            tokenSender.address,
            rewardsManager.address,
            toGRT('10'),
            callHookData,
          )
        await expect(tx).revertedWith(
          'function selector was not recognized and there\'s no fallback function',
        )
      })
    })
  })
})
