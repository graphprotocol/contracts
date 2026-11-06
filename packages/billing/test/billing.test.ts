import '@nomicfoundation/hardhat-chai-matchers'

import { expect } from 'chai'
import { PANIC_CODES } from '@nomicfoundation/hardhat-chai-matchers/panic'
import { BigNumber, constants, Contract, Signer } from 'ethers'
import * as deployment from '../utils/deploy'
import { getAccounts, Account, toGRT, toBN, getL2SignerFromL1 } from '../utils/helpers'

import { Billing } from '../build/types/contracts/Billing'
import { defaultAbiCoder, parseUnits } from 'ethers/lib/utils'

const { AddressZero, MaxUint256 } = constants

describe('Billing', () => {
  let me: Account
  let collector1: Account
  let collector2: Account
  let user1: Account
  let user2: Account
  let user3: Account
  let governor: Account
  let l2TokenGatewayMock: Account
  let l1BillingConnectorMock: Account

  let l1BillingConnectorMockAlias: Signer

  let billing: Billing

  let token: Contract

  before(async function () {
    // eslint-disable-next-line @typescript-eslint/no-extra-semi
    ;[me, collector1, collector2, user1, user2, user3, governor, l2TokenGatewayMock, l1BillingConnectorMock] =
      await getAccounts()
    l1BillingConnectorMockAlias = await getL2SignerFromL1(l1BillingConnectorMock.address)
    // Send funds to the L1 BillingConnector's alias
    await me.signer.sendTransaction({
      to: await l1BillingConnectorMockAlias.getAddress(),
      value: parseUnits('1', 'ether'),
    })
  })

  const tenBillion = toGRT('10000000000')
  const oneHundred = toGRT('100')
  const oneMillion = toGRT('1000000')

  beforeEach(async function () {
    token = await deployment.deployToken([tenBillion], me.signer, true)
    billing = await deployment.deployBilling(
      [collector1.address, token.address, governor.address, l2TokenGatewayMock.address],
      me.signer,
      true,
    )
    await token.connect(me.signer).transfer(user1.address, oneMillion)
    await token.connect(me.signer).transfer(user2.address, oneMillion)
    await token.connect(user1.signer).approve(billing.address, oneMillion)
    await token.connect(user2.signer).approve(billing.address, oneMillion)
    await token.connect(user3.signer).approve(billing.address, oneMillion)
  })

  describe('admin', function () {
    it('should add a `collector`', async function () {
      expect(await billing.isCollector(collector1.address)).eq(true)
      const tx = billing.connect(governor.signer).setCollector(collector2.address, true)
      await expect(tx).emit(billing, 'CollectorUpdated').withArgs(collector2.address, true)
      expect(await billing.isCollector(collector1.address)).eq(true)
      expect(await billing.isCollector(collector2.address)).eq(true)
    })

    it('should remove a `collector`', async function () {
      expect(await billing.isCollector(collector1.address)).eq(true)
      const tx = billing.connect(governor.signer).setCollector(collector1.address, false)
      await expect(tx).emit(billing, 'CollectorUpdated').withArgs(collector1.address, false)
      expect(await billing.isCollector(collector1.address)).eq(false)
    })

    it('should fail to set `collector` if not governor', async function () {
      const tx = billing.connect(me.signer).setCollector(collector2.address, true)
      await expect(tx).revertedWith('Only Governor can call')
    })

    it('should fail to set `collector` for the zero address', async function () {
      const tx = billing.connect(governor.signer).setCollector(AddressZero, true)
      await expect(tx).revertedWith('Collector cannot be 0')
    })

    it('should set the L2 token gateway', async function () {
      expect(await billing.l2TokenGateway()).eq(l2TokenGatewayMock.address)
      const tx = billing.connect(governor.signer).setL2TokenGateway(user3.address)
      await expect(tx).emit(billing, 'L2TokenGatewayUpdated').withArgs(user3.address)
      expect(await billing.l2TokenGateway()).eq(user3.address)
    })

    it('should fail to set L2 token gateway if not governor', async function () {
      const tx = billing.connect(me.signer).setL2TokenGateway(user3.address)
      await expect(tx).revertedWith('Only Governor can call')
    })

    it('should fail to set L2 token gateway to the zero address', async function () {
      const tx = billing.connect(governor.signer).setL2TokenGateway(AddressZero)
      await expect(tx).revertedWith('L2 Token Gateway cannot be 0')
    })

    it('should set the L1 billing connector', async function () {
      expect(await billing.l1BillingConnector()).eq(AddressZero)
      const tx = billing.connect(governor.signer).setL1BillingConnector(user3.address)
      await expect(tx).emit(billing, 'L1BillingConnectorUpdated').withArgs(user3.address)
      expect(await billing.l1BillingConnector()).eq(user3.address)
    })

    it('should fail to set L1 billing connector if not governor', async function () {
      const tx = billing.connect(me.signer).setL1BillingConnector(user3.address)
      await expect(tx).revertedWith('Only Governor can call')
    })

    it('should fail to set L1 billing connector to the zero address', async function () {
      const tx = billing.connect(governor.signer).setL1BillingConnector(AddressZero)
      await expect(tx).revertedWith('L1 Billing Connector cannot be 0')
    })
  })

  describe('add', function () {
    it('should add', async function () {
      const beforeAdd = await billing.userBalances(user1.address)
      const beforeBalance = await token.balanceOf(user1.address)

      const tx = billing.connect(user1.signer).add(oneHundred)
      await expect(tx).emit(billing, 'TokensAdded').withArgs(user1.address, oneHundred)

      const afterAdd = await billing.userBalances(user1.address)
      const afterBalance = await token.balanceOf(user1.address)
      expect(afterAdd).eq(beforeAdd.add(oneHundred))
      expect(afterBalance).eq(beforeBalance.sub(oneHundred))
    })
  })

  describe('addTo', function () {
    it('should add to', async function () {
      const beforeAdd2 = await billing.userBalances(user2.address)
      const beforeBalance1 = await token.balanceOf(user1.address)

      const tx = billing.connect(user1.signer).addTo(user2.address, oneHundred)
      await expect(tx).emit(billing, 'TokensAdded').withArgs(user2.address, oneHundred)

      const afterAdd2 = await billing.userBalances(user2.address)
      const afterBalance1 = await token.balanceOf(user1.address)
      expect(afterAdd2).eq(beforeAdd2.add(oneHundred))
      expect(afterBalance1).eq(beforeBalance1.sub(oneHundred))
    })

    it('should fail add to on address(0)', async function () {
      const tx = billing.connect(user1.signer).addTo(AddressZero, oneHundred)
      await expect(tx).revertedWith('user != 0')
    })

    it('should fail on add if no tokens held by user', async function () {
      const tx = billing.connect(user3.signer).add(oneHundred)
      await expect(tx).revertedWith('ERC20: transfer amount exceeds balance')
    })

    it('should fail add zero tokens', async function () {
      const tx = billing.connect(user1.signer).addTo(user2.address, toBN(0))
      await expect(tx).revertedWith('Must add more than 0')
    })
  })

  describe('onTokenTransfer', function () {
    context('BillingConnector not set', function () {
      it('should fail if called by the token gateway but the billing connector is not set', async function () {
        const callhookData = defaultAbiCoder.encode(['address'], [user2.address])
        const tx = billing
          .connect(l2TokenGatewayMock.signer)
          .onTokenTransfer(l1BillingConnectorMock.address, oneHundred, callhookData)
        await expect(tx).revertedWith('BillingConnector not set')
      })
    })
    context('BillingConnector properly set', function () {
      beforeEach(async function () {
        await billing.connect(governor.signer).setL1BillingConnector(l1BillingConnectorMock.address)
      })

      it('should add to (without moving tokens)', async function () {
        const beforeUserBalance = await billing.userBalances(user2.address)
        const beforeContractBalance = await token.balanceOf(billing.address)

        const callhookData = defaultAbiCoder.encode(['address'], [user2.address])
        const tx = billing
          .connect(l2TokenGatewayMock.signer)
          .onTokenTransfer(l1BillingConnectorMock.address, oneHundred, callhookData)
        await expect(tx).emit(billing, 'TokensAdded').withArgs(user2.address, oneHundred)

        const afterUserBalance = await billing.userBalances(user2.address)
        const afterContractBalance = await token.balanceOf(billing.address)
        expect(beforeContractBalance).eq(afterContractBalance) // No tokens moved
        expect(afterUserBalance).eq(beforeUserBalance.add(oneHundred)) // But balance increased
      })

      it('should fail add if not called by the token gateway', async function () {
        const callhookData = defaultAbiCoder.encode(['address'], [user2.address])
        const tx = billing
          .connect(user1.signer)
          .onTokenTransfer(l1BillingConnectorMock.address, oneHundred, callhookData)
        await expect(tx).revertedWith('Caller must be L2 token gateway')
      })

      it('should fail if called by the token gateway but the L1 sender is not the billing connector', async function () {
        const callhookData = defaultAbiCoder.encode(['address'], [user2.address])
        const tx = billing.connect(l2TokenGatewayMock.signer).onTokenTransfer(user1.address, oneHundred, callhookData)
        await expect(tx).revertedWith('Invalid L1 sender!')
      })

      it('should fail on overflow using built-in Solidity 0.8 safe math', async function () {
        const callhookData = defaultAbiCoder.encode(['address'], [user2.address])
        const tx = billing
          .connect(l2TokenGatewayMock.signer)
          .onTokenTransfer(l1BillingConnectorMock.address, MaxUint256, callhookData)
        await expect(tx).emit(billing, 'TokensAdded').withArgs(user2.address, MaxUint256)

        const tx2 = billing
          .connect(l2TokenGatewayMock.signer)
          .onTokenTransfer(l1BillingConnectorMock.address, oneHundred, callhookData)
        await expect(tx2).revertedWithPanic(PANIC_CODES.ARITHMETIC_UNDER_OR_OVERFLOW)
      })
    })
  })

  describe('addToMany', function () {
    it('should add many', async function () {
      const beforeBalance = await token.balanceOf(billing.address)

      const users = [user1.address, user2.address]
      const amounts = [toGRT('1000'), toGRT('2000')]
      const totalAmount = amounts.reduce((a, b) => a.add(b), BigNumber.from(0))

      const tx = billing.connect(user1.signer).addToMany(users, amounts)
      await expect(tx)
        .emit(billing, 'TokensAdded')
        .withArgs(users[0], amounts[0])
        .emit(billing, 'TokensAdded')
        .withArgs(users[1], amounts[1])

      const afterBalance = await token.balanceOf(billing.address)
      expect(afterBalance).eq(beforeBalance.add(totalAmount))
    })

    it('reject add many to unequal lengths', async function () {
      const users = [AddressZero, user2.address, user2.address]
      const amounts = [toGRT('1000'), toGRT('2000')]

      const tx = billing.connect(user1.signer).addToMany(users, amounts)
      await expect(tx).revertedWith('Lengths not equal')
    })

    it('reject add many to empty address', async function () {
      const users = [AddressZero, user2.address]
      const amounts = [toGRT('1000'), toGRT('2000')]

      const tx = billing.connect(user1.signer).addToMany(users, amounts)
      await expect(tx).revertedWith('user != 0')
    })

    it('reject add many with empty amount', async function () {
      const users = [user1.address, user2.address]
      const amounts = [toGRT('0'), toGRT('2000')]

      const tx = billing.connect(user1.signer).addToMany(users, amounts)
      await expect(tx).revertedWith('Must add more than 0')
    })

    it('reject add many with not enough approval', async function () {
      const users = [user1.address, user2.address]
      const amounts = [toGRT('1000'), toGRT('2000')]

      await token.connect(user1.signer).approve(billing.address, 0)
      const tx = billing.connect(user1.signer).addToMany(users, amounts)
      await expect(tx).revertedWith('ERC20: insufficient allowance')
    })
  })

  describe('remove', function () {
    it('should remove', async function () {
      await billing.connect(user1.signer).add(oneHundred)
      const beforeRemove = await billing.userBalances(user1.address)
      const tx = billing.connect(user1.signer).remove(user1.address, oneHundred)
      await expect(tx).emit(billing, 'TokensRemoved').withArgs(user1.address, user1.address, oneHundred)
      const afterRemove = await billing.userBalances(user1.address)
      expect(afterRemove).eq(beforeRemove.sub(oneHundred))
    })

    it('should fail on removing too much', async function () {
      await billing.connect(user1.signer).add(oneHundred)
      const tx = billing.connect(user1.signer).remove(user1.address, oneMillion)
      await expect(tx).revertedWith('Too much removed')
    })

    it('should fail on removing zero', async function () {
      await billing.connect(user1.signer).add(oneHundred)
      const tx = billing.connect(user1.signer).remove(user1.address, toBN(0))
      await expect(tx).revertedWith('Must remove more than 0')
    })

    it('should fail on removing to the zero address', async function () {
      await billing.connect(user1.signer).add(oneHundred)
      const tx = billing.connect(user1.signer).remove(AddressZero, oneHundred)
      await expect(tx).revertedWith('destination != 0')
    })
  })

  describe('removeFromL1', function () {
    context('BillingConnector not set', function () {
      it('rejects calls if the billing connector was never set', async function () {
        await billing.connect(user1.signer).add(oneHundred)
        const tx = billing.connect(l1BillingConnectorMockAlias).removeFromL1(user1.address, user2.address, oneHundred)
        await expect(tx).revertedWith('BillingConnector not set')
      })
    })
    context('BillingConnector properly set', function () {
      beforeEach(async function () {
        await billing.connect(governor.signer).setL1BillingConnector(l1BillingConnectorMock.address)
      })

      it('should remove using a message from L1', async function () {
        await billing.connect(user1.signer).add(oneHundred)
        const beforeRemoveBalance = await billing.userBalances(user1.address)
        const beforeRemoveTokens = await token.balanceOf(user2.address)
        const tx = billing.connect(l1BillingConnectorMockAlias).removeFromL1(user1.address, user2.address, oneHundred)
        await expect(tx).emit(billing, 'TokensRemoved').withArgs(user1.address, user2.address, oneHundred)
        const afterRemoveBalance = await billing.userBalances(user1.address)
        const afterRemoveTokens = await token.balanceOf(user2.address)
        expect(afterRemoveBalance).eq(beforeRemoveBalance.sub(oneHundred))
        expect(afterRemoveTokens).eq(beforeRemoveTokens.add(oneHundred))
      })

      it('rejects calls from the unaliased L1 billing connector address', async function () {
        await billing.connect(user1.signer).add(oneHundred)
        const tx = billing.connect(l1BillingConnectorMock.signer).removeFromL1(user1.address, user2.address, oneHundred)
        await expect(tx).revertedWith('Caller must be L1 BillingConnector')
      })

      it('rejects calls from someone who is not the billing connector', async function () {
        await billing.connect(user1.signer).add(oneHundred)
        const tx = billing.connect(user1.signer).removeFromL1(user1.address, user2.address, oneHundred)
        await expect(tx).revertedWith('Caller must be L1 BillingConnector')
      })

      it('should emit an event when trying to remove too much', async function () {
        await billing.connect(user1.signer).add(oneHundred)
        const tx = billing
          .connect(l1BillingConnectorMockAlias)
          .removeFromL1(user1.address, user2.address, oneHundred.add(1))
        await expect(tx)
          .emit(billing, 'InsufficientBalanceForRemoval')
          .withArgs(user1.address, user2.address, oneHundred.add(1))
      })

      it('should fail on removing zero (even though it should never happen)', async function () {
        // BillingConnector should never send this message, but we still wanna test the behavior is correct
        await billing.connect(user1.signer).add(oneHundred)
        const tx = billing.connect(l1BillingConnectorMockAlias).removeFromL1(user1.address, user2.address, toBN(0))
        await expect(tx).revertedWith('Must remove more than 0')
      })

      it('should fail on removing to the zero address (even though it should never happen)', async function () {
        // BillingConnector should never send this message, but we still wanna test the behavior is correct
        await billing.connect(user1.signer).add(oneHundred)
        const tx = billing.connect(l1BillingConnectorMockAlias).removeFromL1(user1.address, AddressZero, oneHundred)
        await expect(tx).revertedWith('destination != 0')
      })
    })
  })

  describe('pull', function () {
    it('should pull', async function () {
      const collectorBalanceBefore = await token.balanceOf(collector1.address)
      const addBefore = await billing.userBalances(user1.address)

      await billing.connect(user1.signer).add(oneHundred)
      const tx = billing.connect(collector1.signer).pull(user1.address, oneHundred, collector1.address)
      await expect(tx).emit(billing, 'TokensPulled').withArgs(user1.address, oneHundred)

      const collectorBalanceAfter = await token.balanceOf(collector1.address)
      const addAfter = await billing.userBalances(user1.address)
      expect(collectorBalanceAfter).eq(collectorBalanceBefore.add(oneHundred))
      expect(addAfter).eq(addBefore) // What was added was then removed
    })

    it('should not revert when pullable amount is zero', async function () {
      const collectorBalanceBefore = await token.balanceOf(collector1.address)
      const addBefore = await billing.userBalances(user1.address)

      await billing.connect(user1.signer).add(oneHundred)
      await billing.connect(user1.signer).remove(user1.address, oneHundred) // Right before the pull!
      const tx = billing.connect(collector1.signer).pull(user1.address, oneHundred, collector1.address)
      await expect(tx).to.not.emit(billing, 'TokensPulled')

      const collectorBalanceAfter = await token.balanceOf(collector1.address)
      const addAfter = await billing.userBalances(user1.address)
      expect(collectorBalanceBefore).eq(collectorBalanceAfter)
      expect(addBefore).eq(addAfter)
    })

    it('should fail on pull when not collector', async function () {
      await billing.connect(user1.signer).add(oneHundred)
      const tx = billing.connect(me.signer).pull(user1.address, oneHundred, collector1.address)
      await expect(tx).revertedWith('Caller must be Collector')
    })

    it('should fail pull on empty destination address', async function () {
      await billing.connect(user1.signer).add(oneHundred)
      const tx = billing.connect(collector1.signer).pull(user1.address, oneHundred, AddressZero)
      await expect(tx).revertedWith('Cannot transfer to empty address')
    })
  })

  describe('pullMany', function () {
    it('should pull many', async function () {
      await billing.connect(user1.signer).add(oneHundred)
      await billing.connect(user2.signer).add(oneHundred)
      const addBefore1 = await billing.userBalances(user1.address)
      const addBefore2 = await billing.userBalances(user2.address)
      const collectorBalanceBefore = await token.balanceOf(collector1.address)

      await billing
        .connect(collector1.signer)
        .pullMany([user1.address, user2.address], [oneHundred, oneHundred], collector1.address)

      const addAfter1 = await billing.userBalances(user1.address)
      const addAfter2 = await billing.userBalances(user2.address)
      const collectorBalanceAfter = await token.balanceOf(collector1.address)

      expect(collectorBalanceAfter).eq(collectorBalanceBefore.add(oneHundred).add(oneHundred))
      expect(addAfter1).eq(addBefore1.sub(oneHundred))
      expect(addAfter2).eq(addBefore2.sub(oneHundred))
    })

    it('should pull many even with partial user balances', async function () {
      await billing.connect(user1.signer).add(oneHundred)
      await billing.connect(user2.signer).add(oneHundred)
      const addBefore1 = await billing.userBalances(user1.address)
      const addBefore2 = await billing.userBalances(user2.address)
      const collectorBalanceBefore = await token.balanceOf(collector1.address)

      await billing
        .connect(collector1.signer)
        .pullMany([user1.address, user2.address], [oneHundred, oneHundred.mul(2)], collector1.address)

      const addAfter1 = await billing.userBalances(user1.address)
      const addAfter2 = await billing.userBalances(user2.address)
      const collectorBalanceAfter = await token.balanceOf(collector1.address)

      expect(collectorBalanceAfter).eq(collectorBalanceBefore.add(oneHundred).add(oneHundred))
      expect(addAfter1).eq(addBefore1.sub(oneHundred))
      expect(addAfter2).eq(addBefore2.sub(oneHundred))
    })

    it('should fail to pull when not a collector', async function () {
      await billing.connect(user1.signer).add(oneHundred)
      await billing.connect(user2.signer).add(oneHundred)

      const tx = billing
        .connect(me.signer)
        .pullMany([user1.address, user2.address], [oneHundred, oneHundred], collector1.address)
      await expect(tx).rejectedWith('Caller must be Collector')
    })

    it('should fail pull on lengths not equal', async function () {
      await billing.connect(user1.signer).add(oneHundred)
      await billing.connect(user2.signer).add(oneHundred)
      const tx = billing
        .connect(collector1.signer)
        .pullMany([user1.address], [oneHundred, oneHundred], collector1.address)
      await expect(tx).revertedWith('Lengths not equal')
    })

    it('should fail pull many on empty destination address', async function () {
      await billing.connect(user1.signer).add(oneHundred)
      await billing.connect(user2.signer).add(oneHundred)
      const tx = billing
        .connect(collector1.signer)
        .pullMany([user1.address, user2.address], [oneHundred, oneHundred], AddressZero)
      await expect(tx).revertedWith('Cannot transfer to empty address')
    })
  })

  describe('rescue', function () {
    it('should rescue tokens', async function () {
      // deploy token2 and accidentally send to the Billing contract
      const token2 = await deployment.deployToken([tenBillion], me.signer, true)
      await token2.connect(me.signer).transfer(user1.address, oneMillion)
      await token2.connect(user1.signer).transfer(billing.address, oneMillion)

      // the bad transfer of GRT
      await token.connect(user1.signer).transfer(billing.address, oneMillion)

      const tokenBeforeUser = await token.balanceOf(user1.address)
      const token2BeforeUser = await token2.balanceOf(user1.address)
      const tokenBeforeBilling = await token.balanceOf(billing.address)
      const token2BeforeBilling = await token2.balanceOf(billing.address)

      const tx = await billing.connect(governor.signer).rescueTokens(user1.address, token.address, oneMillion)
      await expect(tx).emit(billing, 'TokensRescued').withArgs(user1.address, token.address, oneMillion)
      await billing.connect(governor.signer).rescueTokens(user1.address, token2.address, oneMillion)

      const tokenAfterUser = await token.balanceOf(user1.address)
      const token2AfterUser = await token2.balanceOf(user1.address)
      const tokenAfterBilling = await token.balanceOf(billing.address)
      const token2AfterBilling = await token2.balanceOf(billing.address)

      expect(tokenAfterUser).eq(tokenBeforeUser.add(oneMillion))
      expect(token2AfterUser).eq(token2BeforeUser.add(oneMillion))
      expect(tokenAfterBilling).eq(tokenBeforeBilling.sub(oneMillion))
      expect(token2AfterBilling).eq(token2BeforeBilling.sub(oneMillion))
    })

    it('should fail rescue tokens when not the governor', async function () {
      // the bad transfer of GRT
      await token.connect(user1.signer).transfer(billing.address, oneMillion)
      const tx = billing.connect(user1.signer).rescueTokens(user1.address, token.address, oneMillion)
      await expect(tx).revertedWith('Only Governor can call')
    })

    it('should fail when trying to send to address zero', async function () {
      // the bad transfer of GRT
      await token.connect(user1.signer).transfer(billing.address, oneMillion)
      const tx = billing.connect(governor.signer).rescueTokens(AddressZero, token.address, oneMillion)
      await expect(tx).revertedWith('Cannot send to address(0)')
    })

    it('should fail when trying to send zero tokens', async function () {
      // the bad transfer of GRT
      await token.connect(user1.signer).transfer(billing.address, oneMillion)
      const tx = billing.connect(governor.signer).rescueTokens(user1.address, token.address, toBN(0))
      await expect(tx).revertedWith('Cannot rescue 0 tokens')
    })
  })
})
