import '@nomicfoundation/hardhat-chai-matchers'

import { expect } from 'chai'
import { constants, Contract } from 'ethers'
import * as deployment from '../utils/deploy'
import { getAccounts, Account, toGRT, toBN } from '../utils/helpers'

import { BanxaWrapper } from '../build/types/contracts/BanxaWrapper'
import { Billing } from '../build/types/contracts/Billing'

const { AddressZero } = constants

describe('BanxaWrapper', () => {
  // Accounts
  let me: Account
  let collector1: Account
  let user1: Account
  let governor: Account
  let l2TokenGatewayMock: Account
  let banxaFulfillmentService: Account

  // Contracts
  let banxaWrapper: BanxaWrapper
  let billing: Billing
  let token: Contract

  before(async function () {
    // eslint-disable-next-line @typescript-eslint/no-extra-semi
    ;[me, collector1, user1, governor, l2TokenGatewayMock, banxaFulfillmentService] = await getAccounts()
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
    banxaWrapper = await deployment.deployBanxaWrapper(
      [token.address, billing.address, governor.address],
      me.signer,
      true,
    )

    await token.connect(me.signer).transfer(banxaFulfillmentService.address, oneMillion)
    await token.connect(me.signer).transfer(user1.address, oneMillion)
    await token.connect(banxaFulfillmentService.signer).approve(banxaWrapper.address, oneMillion)
  })

  describe('constructor', function () {
    it('should set the token address', async function () {
      expect(await banxaWrapper.graphToken()).to.eq(token.address)
    })

    it('should set the billing address', async function () {
      expect(await banxaWrapper.billing()).to.eq(billing.address)
    })
  })

  describe('fulfil', function () {
    it('should fulfil orders', async function () {
      const beforeBillingBalance = await billing.userBalances(user1.address)
      const beforeServiceBalance = await token.balanceOf(banxaFulfillmentService.address)

      const tx = banxaWrapper.connect(banxaFulfillmentService.signer).fulfil(user1.address, oneHundred)
      await expect(tx)
        .emit(banxaWrapper, 'OrderFulfilled')
        .withArgs(banxaFulfillmentService.address, user1.address, oneHundred)

      const afterBillingBalance = await billing.userBalances(user1.address)
      const afterServiceBalance = await token.balanceOf(banxaFulfillmentService.address)

      expect(afterBillingBalance).eq(beforeBillingBalance.add(oneHundred))
      expect(afterServiceBalance).eq(beforeServiceBalance.sub(oneHundred))
    })

    it('should fail to fulfil orders for address(0)', async function () {
      const tx = banxaWrapper.connect(banxaFulfillmentService.signer).fulfil(AddressZero, oneHundred)
      await expect(tx).revertedWithCustomError(banxaWrapper, 'InvalidZeroAddress')
    })

    it('should fail to fulfil orders with zero tokens', async function () {
      const tx = banxaWrapper.connect(banxaFulfillmentService.signer).fulfil(user1.address, toBN(0))
      await expect(tx).revertedWithCustomError(banxaWrapper, 'InvalidZeroAmount')
    })
  })

  describe('rescue', function () {
    it('should rescue tokens', async function () {
      // deploy token2 and accidentally send to the BanxaWrapper contract
      const token2 = await deployment.deployToken([tenBillion], me.signer, true)
      await token2.connect(me.signer).transfer(user1.address, oneMillion)
      await token2.connect(user1.signer).transfer(banxaWrapper.address, oneMillion)

      // the bad transfer of GRT
      await token.connect(user1.signer).transfer(banxaWrapper.address, oneMillion)

      const tokenBeforeUser = await token.balanceOf(user1.address)
      const token2BeforeUser = await token2.balanceOf(user1.address)
      const tokenBeforeBanxa = await token.balanceOf(banxaWrapper.address)
      const token2BeforeBanxa = await token2.balanceOf(banxaWrapper.address)

      const tx = await banxaWrapper.connect(governor.signer).rescueTokens(user1.address, token.address, oneMillion)
      await expect(tx).emit(banxaWrapper, 'TokensRescued').withArgs(user1.address, token.address, oneMillion)
      await banxaWrapper.connect(governor.signer).rescueTokens(user1.address, token2.address, oneMillion)

      const tokenAfterUser = await token.balanceOf(user1.address)
      const token2AfterUser = await token2.balanceOf(user1.address)
      const tokenAfterBanxa = await token.balanceOf(banxaWrapper.address)
      const token2AfterBanxa = await token2.balanceOf(banxaWrapper.address)

      expect(tokenAfterUser).eq(tokenBeforeUser.add(oneMillion))
      expect(token2AfterUser).eq(token2BeforeUser.add(oneMillion))
      expect(tokenAfterBanxa).eq(tokenBeforeBanxa.sub(oneMillion))
      expect(token2AfterBanxa).eq(token2BeforeBanxa.sub(oneMillion))
    })

    it('should fail rescue tokens when not the governor', async function () {
      // the bad transfer of GRT
      await token.connect(user1.signer).transfer(banxaWrapper.address, oneMillion)
      const tx = banxaWrapper.connect(user1.signer).rescueTokens(user1.address, token.address, oneMillion)
      await expect(tx).revertedWith('Only Governor can call')
    })

    it('should fail when trying to send to address zero', async function () {
      // the bad transfer of GRT
      await token.connect(user1.signer).transfer(banxaWrapper.address, oneMillion)
      const tx = banxaWrapper.connect(governor.signer).rescueTokens(AddressZero, token.address, oneMillion)
      await expect(tx).revertedWith('Cannot send to address(0)')
    })

    it('should fail when trying to send zero tokens', async function () {
      // the bad transfer of GRT
      await token.connect(user1.signer).transfer(banxaWrapper.address, oneMillion)
      const tx = banxaWrapper.connect(governor.signer).rescueTokens(user1.address, token.address, toBN(0))
      await expect(tx).revertedWith('Cannot rescue 0 tokens')
    })
  })
})
