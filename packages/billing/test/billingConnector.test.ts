import '@nomicfoundation/hardhat-chai-matchers'
import hre from 'hardhat'
import { expect } from 'chai'
import { BigNumber, constants, Signature } from 'ethers'
import * as deployment from '../utils/deploy'
import { getAccounts, Account, toGRT, toBN, applyL1ToL2Alias } from '../utils/helpers'

import { BillingConnector, L1TokenGatewayMock, Token, InboxMock, BridgeMock } from '../build/types'

const { AddressZero, MaxUint256 } = constants
import { eip712 } from '@graphprotocol/common-ts/dist/attestations'

import path from 'path'
import { Artifacts } from 'hardhat/internal/artifacts'
import {
  BytesLike,
  defaultAbiCoder,
  hexDataLength,
  Interface,
  keccak256,
  SigningKey,
  solidityPack,
} from 'ethers/lib/utils'

const ARTIFACTS_PATH = path.resolve('build/artifacts/contracts')
const artifacts = new Artifacts(ARTIFACTS_PATH)
const billingAbi = artifacts.readArtifactSync('Billing').abi
const billingInterface = new Interface(billingAbi)

// Permit tools adapted from https://github.com/graphprotocol/contracts/blob/0ac3f53b1898e8bbcfb909b7362fec2ffb498b65/test/lib/graphTokenTests.ts#L20-L87

const PERMIT_TYPE_HASH = eip712.typeHash(
  'Permit(address owner,address spender,uint256 value,uint256 nonce,uint256 deadline)',
)
const SALT = '0x372eb1ffe347bfa68969a6e8193fe5f811f0ac923bde07eb35d7e74347ba031a'

interface Permit {
  owner: string
  spender: string
  value: BigNumber
  nonce: BigNumber
  deadline: BigNumber
}

function hashEncodePermit(permit: Permit) {
  return eip712.hashStruct(
    PERMIT_TYPE_HASH,
    ['address', 'address', 'uint256', 'uint256', 'uint256'],
    [permit.owner, permit.spender, permit.value, permit.nonce, permit.deadline],
  )
}

function signPermit(
  privateKey: BytesLike,
  chainId: number,
  contractAddress: string,
  permit: Permit,
  salt: string,
): Signature {
  const domainSeparator = eip712.domainSeparator({
    name: 'Graph Token',
    version: '0',
    chainId,
    verifyingContract: contractAddress,
    salt: salt,
  })
  const hashEncodedPermit = hashEncodePermit(permit)
  const message = eip712.encode(domainSeparator, hashEncodedPermit)
  const messageHash = keccak256(message)
  const signingKey = new SigningKey(privateKey)
  return signingKey.signDigest(messageHash)
}

describe('BillingConnector', () => {
  let me: Account
  let user1: Account
  let user2: Account
  let user3: Account
  let governor: Account
  let l2BillingMock: Account

  let billingConnector: BillingConnector
  let token: Token
  let l1TokenGatewayMock: L1TokenGatewayMock
  let bridgeMock: BridgeMock
  let inboxMock: InboxMock

  const myPrivateKey = '0x4f3edf983ac636a65a842ce7c78d9aa706d3b113bce9c46f30d7d21715b23b1d'
  async function permitOK(value: BigNumber, from: string, to: string): Promise<Permit> {
    const nonce = await token.nonces(from)
    return {
      owner: from,
      spender: to,
      value: value,
      nonce: nonce,
      deadline: toBN('0'),
    }
  }

  async function permitMaxOK(from: string, to: string): Promise<Permit> {
    return permitOK(MaxUint256, from, to)
  }

  async function permitExpired(from: string, to: string): Promise<Permit> {
    const permit = await permitMaxOK(from, to)
    permit.deadline = toBN('1')
    return permit
  }

  function createSignedPermit(permit: Permit, privateKey: string, salt: string): Signature {
    const chainID = hre.network.config.chainId
    const signature: Signature = signPermit(privateKey, chainID, token.address, permit, salt)
    return signature
  }

  before(async function () {
    // eslint-disable-next-line @typescript-eslint/no-extra-semi
    ;[me, user1, user2, user3, governor, l2BillingMock] = await getAccounts()
  })

  const tenBillion = toGRT('10000000000')
  const oneHundred = toGRT('100')
  const oneMillion = toGRT('1000000')
  const defaultMaxGas = toBN('10')
  const defaultGasPriceBid = toBN('20')
  const defaultMaxSubmissionPrice = toBN('30')
  const defaultMsgValue = defaultMaxSubmissionPrice.add(defaultMaxGas.mul(defaultGasPriceBid))

  const deployArbitrumMocks = async function () {
    bridgeMock = (await deployment.deployBridgeMock([], me.signer, true)) as unknown as BridgeMock
    inboxMock = (await deployment.deployInboxMock([], me.signer, true)) as unknown as InboxMock
    await bridgeMock.connect(me.signer).setInbox(inboxMock.address, true)
    await inboxMock.connect(me.signer).setBridge(bridgeMock.address)
  }

  beforeEach(async function () {
    await deployArbitrumMocks()
    token = (await deployment.deployToken([tenBillion], me.signer, true)) as unknown as Token
    l1TokenGatewayMock = (await deployment.deployL1TokenGatewayMock(
      [],
      me.signer,
      true,
    )) as unknown as L1TokenGatewayMock
    billingConnector = (await deployment.deployBillingConnector(
      [l1TokenGatewayMock.address, l2BillingMock.address, token.address, governor.address, inboxMock.address],
      me.signer,
      true,
    )) as unknown as BillingConnector

    await token.connect(me.signer).transfer(user1.address, oneMillion)
    await token.connect(me.signer).transfer(user2.address, oneMillion)
    await token.connect(me.signer).transfer(user3.address, oneMillion)
  })

  describe('setL1TokenGateway', function () {
    it('sets the l1TokenGateway', async function () {
      expect(await billingConnector.l1TokenGateway()).eq(l1TokenGatewayMock.address)
      const tx = billingConnector.connect(governor.signer).setL1TokenGateway(user2.address)
      await expect(tx).emit(billingConnector, 'L1TokenGatewayUpdated').withArgs(user2.address)
      expect(await billingConnector.l1TokenGateway()).eq(user2.address)
    })
    it('rejects calls from someone other than the governor', async function () {
      const tx = billingConnector.connect(me.signer).setL1TokenGateway(user2.address)
      await expect(tx).revertedWith('Only Governor can call')
    })
    it('rejects calls to set token gateway to zero', async function () {
      const tx = billingConnector.connect(governor.signer).setL1TokenGateway(AddressZero)
      await expect(tx).revertedWith('L1 Token Gateway cannot be 0')
    })
  })
  describe('setL2Billing', function () {
    it('sets the l2Billing address', async function () {
      expect(await billingConnector.l2Billing()).eq(l2BillingMock.address)
      const tx = billingConnector.connect(governor.signer).setL2Billing(user3.address)
      await expect(tx).emit(billingConnector, 'L2BillingUpdated').withArgs(user3.address)
      expect(await billingConnector.l2Billing()).eq(user3.address)
    })
    it('rejects calls from someone other than the governor', async function () {
      const tx = billingConnector.connect(me.signer).setL2Billing(user3.address)
      await expect(tx).revertedWith('Only Governor can call')
    })
    it('rejects calls to set L2 billing to zero', async function () {
      const tx = billingConnector.connect(governor.signer).setL2Billing(AddressZero)
      await expect(tx).revertedWith('L2 Billing cannot be zero')
    })
  })
  describe('setArbitrumInbox', function () {
    it('sets the inbox address', async function () {
      expect(await billingConnector.inbox()).eq(inboxMock.address)
      const tx = billingConnector.connect(governor.signer).setArbitrumInbox(user3.address)
      await expect(tx).emit(billingConnector, 'ArbitrumInboxUpdated').withArgs(user3.address)
      expect(await billingConnector.inbox()).eq(user3.address)
    })
    it('rejects calls from someone other than the governor', async function () {
      const tx = billingConnector.connect(me.signer).setArbitrumInbox(user3.address)
      await expect(tx).revertedWith('Only Governor can call')
    })
    it('rejects calls to set Arbitrum Inbox to zero', async function () {
      const tx = billingConnector.connect(governor.signer).setArbitrumInbox(AddressZero)
      await expect(tx).revertedWith('Arbitrum Inbox cannot be zero')
    })
  })
  describe('addToL2', function () {
    it('pulls tokens and sends a message through the token gateway', async function () {
      const userBalanceBefore = await token.balanceOf(user1.address)
      const connectorBalanceBefore = await token.balanceOf(billingConnector.address)
      const bridgeBalanceBefore = await token.balanceOf(l1TokenGatewayMock.address)
      await token.connect(user1.signer).approve(billingConnector.address, oneHundred)
      const tx = billingConnector
        .connect(user1.signer)
        .addToL2(user2.address, oneHundred, defaultMaxGas, defaultGasPriceBid, defaultMaxSubmissionPrice, {
          value: defaultMsgValue,
        })
      const expectedCallhookData = defaultAbiCoder.encode(['address'], [user2.address])
      const expectedOutboundCalldata = l1TokenGatewayMock.interface.encodeFunctionData('finalizeInboundTransfer', [
        token.address,
        billingConnector.address,
        l2BillingMock.address,
        oneHundred,
        defaultAbiCoder.encode(['bytes', 'bytes'], ['0x', expectedCallhookData]),
      ])
      // Real event emitted by BillingConnector
      await expect(tx).emit(billingConnector, 'TokensSentToL2').withArgs(user1.address, user2.address, oneHundred)
      // Mock event from the gateway mock to validate what would be sent to L2
      await expect(tx)
        .emit(l1TokenGatewayMock, 'FakeTxToL2')
        .withArgs(
          billingConnector.address,
          defaultMsgValue,
          defaultMaxGas,
          defaultGasPriceBid,
          defaultMaxSubmissionPrice,
          expectedOutboundCalldata,
        )
      const userBalanceAfter = await token.balanceOf(user1.address)
      const connectorBalanceAfter = await token.balanceOf(billingConnector.address)
      const bridgeBalanceAfter = await token.balanceOf(l1TokenGatewayMock.address)
      expect(userBalanceAfter).eq(userBalanceBefore.sub(oneHundred))
      expect(connectorBalanceAfter).eq(connectorBalanceBefore)
      expect(bridgeBalanceAfter).eq(bridgeBalanceBefore.add(oneHundred))
    })
    it('rejects calls when the sender has not approved the contract', async function () {
      const tx = billingConnector
        .connect(user1.signer)
        .addToL2(user2.address, oneHundred, defaultMaxGas, defaultGasPriceBid, defaultMaxSubmissionPrice, {
          value: defaultMsgValue,
        })
      await expect(tx).revertedWith('ERC20: insufficient allowance')
    })
    it('rejects calls if the sender is out of funds', async function () {
      await token.connect(user1.signer).approve(billingConnector.address, tenBillion)
      const tx = billingConnector
        .connect(user1.signer)
        .addToL2(user2.address, tenBillion, defaultMaxGas, defaultGasPriceBid, defaultMaxSubmissionPrice, {
          value: defaultMsgValue,
        })
      await expect(tx).revertedWith('ERC20: transfer amount exceeds balance')
    })
    it('rejects sending to address zero', async function () {
      await token.connect(user1.signer).approve(billingConnector.address, oneHundred)
      const tx = billingConnector
        .connect(user1.signer)
        .addToL2(AddressZero, oneHundred, defaultMaxGas, defaultGasPriceBid, defaultMaxSubmissionPrice, {
          value: defaultMsgValue,
        })
      await expect(tx).revertedWith('destination != 0')
    })
    it('rejects sending a zero amount', async function () {
      await token.connect(user1.signer).approve(billingConnector.address, oneHundred)
      const tx = billingConnector
        .connect(user1.signer)
        .addToL2(user2.address, toBN(0), defaultMaxGas, defaultGasPriceBid, defaultMaxSubmissionPrice, {
          value: defaultMsgValue,
        })
      await expect(tx).revertedWith('Must add more than 0')
    })
    it("relies on the gateway's validation for the L2 gas params", async function () {
      await token.connect(user1.signer).approve(billingConnector.address, oneHundred)
      const tx = billingConnector
        .connect(user1.signer)
        .addToL2(user2.address, oneHundred, defaultMaxGas, defaultGasPriceBid, toBN(0), {
          value: defaultMsgValue,
        })
      await expect(tx).revertedWith('NO_SUBMISSION_COST')
    })
  })
  describe('addToL2WithPermit', function () {
    it('pulls tokens using a permit and sends a message through the token gateway', async function () {
      // Note the permit is from me to billingConnector, but the addToL2WithPermit tx is signed by user1
      const permit = await permitOK(oneHundred, me.address, billingConnector.address)
      const signedPermit = createSignedPermit(permit, myPrivateKey, SALT)

      const myBalanceBefore = await token.balanceOf(me.address)
      const userBalanceBefore = await token.balanceOf(user1.address)
      const connectorBalanceBefore = await token.balanceOf(billingConnector.address)
      const bridgeBalanceBefore = await token.balanceOf(l1TokenGatewayMock.address)

      const tx = billingConnector
        .connect(me.signer)
        .addToL2WithPermit(
          me.address,
          oneHundred,
          defaultMaxGas,
          defaultGasPriceBid,
          defaultMaxSubmissionPrice,
          permit.deadline,
          signedPermit.v,
          signedPermit.r,
          signedPermit.s,
          {
            value: defaultMsgValue,
          },
        )
      const expectedCallhookData = defaultAbiCoder.encode(['address'], [me.address])
      const expectedOutboundCalldata = l1TokenGatewayMock.interface.encodeFunctionData('finalizeInboundTransfer', [
        token.address,
        billingConnector.address,
        l2BillingMock.address,
        oneHundred,
        defaultAbiCoder.encode(['bytes', 'bytes'], ['0x', expectedCallhookData]),
      ])
      // Real event emitted by BillingConnector
      await expect(tx).emit(billingConnector, 'TokensSentToL2').withArgs(me.address, me.address, oneHundred)
      // Mock event from the gateway mock to validate what would be sent to L2
      await expect(tx)
        .emit(l1TokenGatewayMock, 'FakeTxToL2')
        .withArgs(
          billingConnector.address,
          defaultMsgValue,
          defaultMaxGas,
          defaultGasPriceBid,
          defaultMaxSubmissionPrice,
          expectedOutboundCalldata,
        )
      const myBalanceAfter = await token.balanceOf(me.address)
      const userBalanceAfter = await token.balanceOf(user1.address)
      const connectorBalanceAfter = await token.balanceOf(billingConnector.address)
      const bridgeBalanceAfter = await token.balanceOf(l1TokenGatewayMock.address)
      expect(myBalanceAfter).eq(myBalanceBefore.sub(oneHundred))
      expect(userBalanceAfter).eq(userBalanceBefore) // unchanged
      expect(connectorBalanceAfter).eq(connectorBalanceBefore)
      expect(bridgeBalanceAfter).eq(bridgeBalanceBefore.add(oneHundred))
    })
    it("doesn't revert after a frontrunning permit transaction", async function () {
      const permit = await permitOK(oneHundred, me.address, billingConnector.address)
      const signedPermit = createSignedPermit(permit, myPrivateKey, SALT)

      const myBalanceBefore = await token.balanceOf(me.address)
      const userBalanceBefore = await token.balanceOf(user1.address)
      const connectorBalanceBefore = await token.balanceOf(billingConnector.address)
      const bridgeBalanceBefore = await token.balanceOf(l1TokenGatewayMock.address)

      // user2 frontruns transaction
      const frontrunnerTx = await token
        .connect(user2.signer)
        .permit(
          me.address,
          billingConnector.address,
          permit.value,
          permit.deadline,
          signedPermit.v,
          signedPermit.r,
          signedPermit.s,
        )

      // my original transaction with permit
      const tx = await billingConnector
        .connect(me.signer)
        .addToL2WithPermit(
          me.address,
          permit.value,
          defaultMaxGas,
          defaultGasPriceBid,
          defaultMaxSubmissionPrice,
          permit.deadline,
          signedPermit.v,
          signedPermit.r,
          signedPermit.s,
          {
            value: defaultMsgValue,
          },
        )

      const expectedCallhookData = defaultAbiCoder.encode(['address'], [me.address])
      const expectedOutboundCalldata = l1TokenGatewayMock.interface.encodeFunctionData('finalizeInboundTransfer', [
        token.address,
        billingConnector.address,
        l2BillingMock.address,
        oneHundred,
        defaultAbiCoder.encode(['bytes', 'bytes'], ['0x', expectedCallhookData]),
      ])

      // frontrunnerTx approves funds
      await expect(frontrunnerTx)
        .to.emit(token, 'Approval')
        .withArgs(me.address, billingConnector.address, permit.value)

      // Transaction doesn't revert, instead it uses the allowance created by frontrunnerTx
      await expect(tx).not.to.be.reverted

      // Real event emitted by BillingConnector
      await expect(tx).emit(billingConnector, 'TokensSentToL2').withArgs(me.address, me.address, oneHundred)
      // Mock event from the gateway mock to validate what would be sent to L2
      await expect(tx)
        .emit(l1TokenGatewayMock, 'FakeTxToL2')
        .withArgs(
          billingConnector.address,
          defaultMsgValue,
          defaultMaxGas,
          defaultGasPriceBid,
          defaultMaxSubmissionPrice,
          expectedOutboundCalldata,
        )

      // Balances are fine since transaction was executed fine
      const myBalanceAfter = await token.balanceOf(me.address)
      const userBalanceAfter = await token.balanceOf(user1.address)
      const connectorBalanceAfter = await token.balanceOf(billingConnector.address)
      const bridgeBalanceAfter = await token.balanceOf(l1TokenGatewayMock.address)
      expect(myBalanceAfter).eq(myBalanceBefore.sub(oneHundred))
      expect(userBalanceAfter).eq(userBalanceBefore) // unchanged
      expect(connectorBalanceAfter).eq(connectorBalanceBefore)
      expect(bridgeBalanceAfter).eq(bridgeBalanceBefore.add(oneHundred))
    })
    it("relies on the token's validation when the sender has provided an expired permit", async function () {
      const permit = await permitExpired(me.address, billingConnector.address)
      const signedPermit = createSignedPermit(permit, myPrivateKey, SALT)

      const tx = billingConnector
        .connect(me.signer)
        .addToL2WithPermit(
          me.address,
          permit.value,
          defaultMaxGas,
          defaultGasPriceBid,
          defaultMaxSubmissionPrice,
          permit.deadline,
          signedPermit.v,
          signedPermit.r,
          signedPermit.s,
          {
            value: defaultMsgValue,
          },
        )
      await expect(tx).revertedWith('GRT: expired permit')
    })
    it("relies on the token's validation when the sender has provided an invalid permit", async function () {
      const permit = await permitOK(oneHundred, user1.address, billingConnector.address)
      const signedPermit = createSignedPermit(permit, myPrivateKey, SALT)

      const tx = billingConnector
        .connect(me.signer)
        .addToL2WithPermit(
          me.address,
          permit.value,
          defaultMaxGas,
          defaultGasPriceBid,
          defaultMaxSubmissionPrice,
          permit.deadline,
          signedPermit.v,
          signedPermit.r,
          signedPermit.s,
          {
            value: defaultMsgValue,
          },
        )
      await expect(tx).revertedWith('GRT: invalid permit')
    })
    it('rejects calls if the sender is out of funds', async function () {
      const permit = await permitOK(tenBillion, me.address, billingConnector.address)
      const signedPermit = createSignedPermit(permit, myPrivateKey, SALT)

      const tx = billingConnector
        .connect(me.signer)
        .addToL2WithPermit(
          me.address,
          permit.value,
          defaultMaxGas,
          defaultGasPriceBid,
          defaultMaxSubmissionPrice,
          permit.deadline,
          signedPermit.v,
          signedPermit.r,
          signedPermit.s,
          {
            value: defaultMsgValue,
          },
        )
      await expect(tx).revertedWith('ERC20: transfer amount exceeds balance')
    })
    it('rejects sending to address zero', async function () {
      const permit = await permitOK(oneHundred, me.address, billingConnector.address)
      const signedPermit = createSignedPermit(permit, myPrivateKey, SALT)

      const tx = billingConnector
        .connect(me.signer)
        .addToL2WithPermit(
          AddressZero,
          permit.value,
          defaultMaxGas,
          defaultGasPriceBid,
          defaultMaxSubmissionPrice,
          permit.deadline,
          signedPermit.v,
          signedPermit.r,
          signedPermit.s,
          {
            value: defaultMsgValue,
          },
        )
      await expect(tx).revertedWith('destination != 0')
    })
    it('rejects sending a zero amount', async function () {
      const permit = await permitOK(toBN(0), me.address, billingConnector.address)
      const signedPermit = createSignedPermit(permit, myPrivateKey, SALT)

      const tx = billingConnector
        .connect(me.signer)
        .addToL2WithPermit(
          me.address,
          permit.value,
          defaultMaxGas,
          defaultGasPriceBid,
          defaultMaxSubmissionPrice,
          permit.deadline,
          signedPermit.v,
          signedPermit.r,
          signedPermit.s,
          {
            value: defaultMsgValue,
          },
        )
      await expect(tx).revertedWith('Must add more than 0')
    })
    it("relies on the gateway's validation for the L2 gas params", async function () {
      const permit = await permitOK(oneHundred, me.address, billingConnector.address)
      const signedPermit = createSignedPermit(permit, myPrivateKey, SALT)

      const tx = billingConnector
        .connect(me.signer)
        .addToL2WithPermit(
          me.address,
          permit.value,
          defaultMaxGas,
          defaultGasPriceBid.add(1),
          defaultMaxSubmissionPrice,
          permit.deadline,
          signedPermit.v,
          signedPermit.r,
          signedPermit.s,
          {
            value: defaultMsgValue,
          },
        )
      await expect(tx).revertedWith('WRONG_ETH_VALUE')
    })
    it('rejects calls if not tokens owner', async function () {
      const permit = await permitOK(oneHundred, me.address, billingConnector.address)
      const signedPermit = createSignedPermit(permit, myPrivateKey, SALT)

      const tx = billingConnector
        .connect(user1.signer)
        .addToL2WithPermit(
          me.address,
          permit.value,
          defaultMaxGas,
          defaultGasPriceBid,
          defaultMaxSubmissionPrice,
          permit.deadline,
          signedPermit.v,
          signedPermit.r,
          signedPermit.s,
          {
            value: defaultMsgValue,
          },
        )
      await expect(tx).revertedWith('Only tokens owner can call')
    })
  })
  describe('rescueTokens', function () {
    it('should rescue tokens', async function () {
      // deploy token2 and accidentally send to the Billing contract
      const token2 = await deployment.deployToken([tenBillion], me.signer, true)
      await token2.connect(me.signer).transfer(user1.address, oneMillion)
      await token2.connect(user1.signer).transfer(billingConnector.address, oneMillion)

      // the bad transfer of GRT
      await token.connect(user1.signer).transfer(billingConnector.address, oneMillion)

      const tokenBeforeUser = await token.balanceOf(user1.address)
      const token2BeforeUser = await token2.balanceOf(user1.address)
      const tokenBeforeBilling = await token.balanceOf(billingConnector.address)
      const token2BeforeBilling = await token2.balanceOf(billingConnector.address)

      const tx = await billingConnector.connect(governor.signer).rescueTokens(user1.address, token.address, oneMillion)
      await expect(tx).emit(billingConnector, 'TokensRescued').withArgs(user1.address, token.address, oneMillion)
      await billingConnector.connect(governor.signer).rescueTokens(user1.address, token2.address, oneMillion)

      const tokenAfterUser = await token.balanceOf(user1.address)
      const token2AfterUser = await token2.balanceOf(user1.address)
      const tokenAfterBilling = await token.balanceOf(billingConnector.address)
      const token2AfterBilling = await token2.balanceOf(billingConnector.address)

      expect(tokenAfterUser).eq(tokenBeforeUser.add(oneMillion))
      expect(token2AfterUser).eq(token2BeforeUser.add(oneMillion))
      expect(tokenAfterBilling).eq(tokenBeforeBilling.sub(oneMillion))
      expect(token2AfterBilling).eq(token2BeforeBilling.sub(oneMillion))
    })

    it('should fail rescue tokens when not governor', async function () {
      // the bad transfer of GRT
      await token.connect(user1.signer).transfer(billingConnector.address, oneMillion)
      const tx = billingConnector.connect(user1.signer).rescueTokens(user1.address, token.address, oneMillion)
      await expect(tx).revertedWith('Only Governor can call')
    })

    it('should fail when trying to send to address zero', async function () {
      // the bad transfer of GRT
      await token.connect(user1.signer).transfer(billingConnector.address, oneMillion)
      const tx = billingConnector.connect(governor.signer).rescueTokens(AddressZero, token.address, oneMillion)
      await expect(tx).revertedWith('Cannot send to address(0)')
    })

    it('should fail when trying to send zero tokens', async function () {
      // the bad transfer of GRT
      await token.connect(user1.signer).transfer(billingConnector.address, oneMillion)
      const tx = billingConnector.connect(governor.signer).rescueTokens(user1.address, token.address, toBN(0))
      await expect(tx).revertedWith('Cannot rescue 0 tokens')
    })
  })
  describe('removeOnL2', function () {
    const submitRetryableTxCode = 9
    // createMsgData and createInboxAccsEntry copied/adapted from @graphprotocol/contracts
    const createMsgData = function (user: string, msgCalldata: string) {
      const msgData = solidityPack(
        ['uint256', 'uint256', 'uint256', 'uint256', 'uint256', 'uint256', 'uint256', 'uint256', 'uint256', 'bytes'],
        [
          toBN(l2BillingMock.address),
          toBN('0'),
          defaultMsgValue,
          defaultMaxSubmissionPrice,
          applyL1ToL2Alias(user),
          applyL1ToL2Alias(user),
          defaultMaxGas,
          defaultGasPriceBid,
          hexDataLength(msgCalldata),
          msgCalldata,
        ],
      )
      return msgData
    }
    const createInboxAccsEntry = function (msgDataHash: string) {
      // The real bridge would emit the InboxAccs entry that came before this one, but our mock
      // emits this, making it easier for us to validate here that all the parameters we sent are correct
      const expectedInboxAccsEntry = keccak256(
        solidityPack(
          ['address', 'uint8', 'address', 'bytes32'],
          [inboxMock.address, submitRetryableTxCode, billingConnector.address, msgDataHash],
        ),
      )
      return expectedInboxAccsEntry
    }

    it('sends a message through the Arbitrum inbox for the L2 Billing to remove tokens', async function () {
      // "me" sends the tokens from L2 Billing to user2.
      const tx = billingConnector
        .connect(me.signer)
        .removeOnL2(user2.address, oneHundred, defaultMaxGas, defaultGasPriceBid, defaultMaxSubmissionPrice, {
          value: defaultMsgValue,
        })
      const expectedCalldata = billingInterface.encodeFunctionData('removeFromL1', [
        me.address,
        user2.address,
        oneHundred,
      ])
      await expect(tx).emit(billingConnector, 'RemovalRequestSentToL2').withArgs(me.address, user2.address, oneHundred)
      // We set the refund address to the destination address, because it's assumed the source address might not exist in L2
      await expect(tx)
        .emit(billingConnector, 'TxToL2')
        .withArgs(user2.address, l2BillingMock.address, 1, expectedCalldata)

      const msgData = createMsgData(user2.address, expectedCalldata)
      const msgDataHash = keccak256(msgData)
      const expectedInboxAccsEntry = createInboxAccsEntry(msgDataHash)

      const expectedSeqNum = 1
      await expect(tx).emit(inboxMock, 'InboxMessageDelivered').withArgs(expectedSeqNum, msgData)
      await expect(tx)
        .emit(bridgeMock, 'MessageDelivered')
        .withArgs(
          expectedSeqNum,
          expectedInboxAccsEntry,
          inboxMock.address,
          submitRetryableTxCode,
          billingConnector.address,
          msgDataHash,
        )
    })
    it('rejects calls with a zero maxSubmissionCost', async function () {
      // "me" sends the tokens from L2 Billing to user2.
      const tx = billingConnector
        .connect(me.signer)
        .removeOnL2(user2.address, oneHundred, defaultMaxGas, defaultGasPriceBid, toBN(0), {
          value: defaultMsgValue,
        })
      await expect(tx).revertedWith('Submission cost must be > 0')
    })
    it('rejects calls to remove zero tokens', async function () {
      // "me" sends the tokens from L2 Billing to user2.
      const tx = billingConnector
        .connect(me.signer)
        .removeOnL2(user2.address, toBN(0), defaultMaxGas, defaultGasPriceBid, defaultMaxSubmissionPrice, {
          value: defaultMsgValue,
        })
      await expect(tx).revertedWith('Must remove more than 0')
    })
    it('rejects calls to remove tokens to the zero address', async function () {
      // "me" sends the tokens from L2 Billing to user2.
      const tx = billingConnector
        .connect(me.signer)
        .removeOnL2(AddressZero, oneHundred, defaultMaxGas, defaultGasPriceBid, defaultMaxSubmissionPrice, {
          value: defaultMsgValue,
        })
      await expect(tx).revertedWith('destination != 0')
    })
    it('rejects calls to remove tokens to the sender address', async function () {
      // "me" sends the tokens from L2 Billing to user2.
      const tx = billingConnector
        .connect(me.signer)
        .removeOnL2(me.address, oneHundred, defaultMaxGas, defaultGasPriceBid, defaultMaxSubmissionPrice, {
          value: defaultMsgValue,
        })
      await expect(tx).revertedWith('destination != sender')
    })
  })
})
