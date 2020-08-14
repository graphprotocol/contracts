import { expect } from 'chai'
import { constants, BigNumber } from 'ethers'

import { GsrManager } from '../../build/typechain/contracts/GsrManager'
import { Gdai } from '../../build/typechain/contracts/Gdai'

import * as deployment from '../lib/deployment'
import { defaults } from '../lib/deployment'
import { getAccounts, toGRT, Account } from '../lib/testHelpers'

const { AddressZero, MaxUint256 } = constants

describe('Gdai and Gsr', () => {
  let me: Account
  let governor: Account

  let gsrManager: GsrManager
  let gdai: Gdai

  const ISSUANCE_RATE_DECIMALS = constants.WeiPerEther

  const getExpectedRateStringCompare = (p: BigNumber, r: BigNumber, t: BigNumber): string => {
    return p.mul(r).pow(t).toString().slice(0, 19)
  }

  const runJoin = async (): Promise<void> => {
    const savingsRate = await gsrManager.savingsRate()
    const nSeconds = 3 // seems 3 seconds between blocks for join()

    // Before values
    const beforeCumulativeInterestRate = await gsrManager.cumulativeInterestRate()
    expect(beforeCumulativeInterestRate).eq(ISSUANCE_RATE_DECIMALS)
    const beforeDripTime = await gsrManager.lastDripTime()
    const beforeTokenSupply = await gdai.totalSupply()
    const beforeReserves = await gsrManager.reserves()
    const beforeBalance = await gsrManager.balances(governor.address)

    // Expected Values
    const expectedRateCompare = getExpectedRateStringCompare(
      beforeCumulativeInterestRate,
      savingsRate,
      BigNumber.from(nSeconds),
    )

    const expectedDripTime = beforeDripTime.add(BigNumber.from(nSeconds))
    const joinAmount = toGRT('10000000')
    const expectedSavingsBalance = joinAmount
      .mul(ISSUANCE_RATE_DECIMALS)
      .div(BigNumber.from(expectedRateCompare))

    // Run join() tx and check events
    const joinTx = gsrManager.connect(governor.signer).join(joinAmount)
    await joinTx
    await expect(joinTx)
      .emit(gsrManager, 'Drip')
      .withArgs(expectedRateCompare, expectedDripTime)
      .emit(gsrManager, 'Join')
      .withArgs(governor.address, joinAmount, expectedSavingsBalance)

    // Check cumulative rate was updated correctly
    const afterCumulativeInterestRate = await gsrManager.cumulativeInterestRate()
    expect(afterCumulativeInterestRate).eq(expectedRateCompare)

    // Check drip time was updated
    const afterDripTime = await gsrManager.lastDripTime()
    expect(afterDripTime).eq(expectedDripTime)

    // Check tokens were NOT minted (since reserves started off at zero)
    const afterTokenSupply = await gdai.totalSupply()
    expect(beforeTokenSupply).eq(afterTokenSupply)

    // Check reserve balance was updated
    const afterJoinReserves = await gsrManager.reserves()
    expect(beforeReserves.add(expectedSavingsBalance)).eq(afterJoinReserves)

    // Check user balance was updated
    const afterJoinBalance = await gsrManager.balances(governor.address)
    expect(beforeBalance).eq(afterJoinBalance.sub(expectedSavingsBalance))
  }

  before(async function () {
    ;[governor] = await getAccounts()
  })

  beforeEach(async function () {
    gdai = await deployment.deployGDAI(governor.signer)
    gsrManager = await deployment.deployGSR(governor.signer, gdai.address)
    await gdai.setGSR(gsrManager.address)
    await gdai.approve(gsrManager.address, MaxUint256)
    const initialSupply = await gdai.balanceOf(governor.address)
    expect(initialSupply).eq(defaults.gdai.initialSupply)
  })

  describe('gdai', () => {
    it('should set `governor`', async function () {
      expect(await gdai.governor()).eq(governor.address)
      expect(await gsrManager.governor()).eq(governor.address)
    })

    it('should allow governor to mint', async function () {
      // Constructor set to default correctly
      expect(await gdai.totalSupply()).eq(defaults.gdai.initialSupply)

      // Update and check event was emitted
      const tokensToMint = toGRT('1000000')
      const tx = gdai.connect(governor.signer).mint(governor.address, tokensToMint)
      await expect(tx).emit(gdai, 'Transfer').withArgs(AddressZero, governor.address, tokensToMint)
    })
  })

  describe('gsr', () => {
    it('should set `governor`', async function () {
      expect(await gsrManager.governor()).eq(governor.address)
    })

    it('should set savings rate', async function () {
      // Constructor set to default correctly
      expect(await gsrManager.savingsRate()).eq(defaults.gdai.savingsRate)

      // Update and check new value
      const tx = gsrManager.connect(governor.signer).setRate(0)
      await expect(tx).emit(gsrManager, 'SetRate').withArgs(0)
      expect(await gsrManager.savingsRate()).eq(0)
    })

    it('should test drip() and join()', async function () {
      await runJoin()
    })
    it('should test drip() and join() and exit', async function () {
      // Run join first
      await runJoin()

      const savingsRate = await gsrManager.savingsRate()
      const nSeconds = 1 // seems 1 second between blocks when running exit()

      // Before values
      const beforeCumulativeInterestRate = await gsrManager.cumulativeInterestRate()
      const beforeDripTime = await gsrManager.lastDripTime()
      const beforeTokenSupply = await gdai.totalSupply()
      const beforeBalance = await gsrManager.balances(governor.address)
      const beforeGDAIBalance = await gdai.balanceOf(governor.address)

      // Expected Values
      const expectedRateCompare = getExpectedRateStringCompare(
        beforeCumulativeInterestRate,
        savingsRate,
        BigNumber.from(nSeconds),
      )

      const expectedGDAIWithdrawn = beforeBalance
        .mul(BigNumber.from(expectedRateCompare))
        .div(ISSUANCE_RATE_DECIMALS)
      const expectedDripTime = beforeDripTime.add(BigNumber.from(nSeconds))

      // Run exit() tx and check events
      const exitTx = gsrManager.connect(governor.signer).exit(beforeBalance)
      await expect(exitTx)
        .emit(gsrManager, 'Drip')
        .withArgs(expectedRateCompare, expectedDripTime)
        .emit(gsrManager, 'Exit')
        .withArgs(governor.address, beforeBalance, expectedGDAIWithdrawn)

      // Checking drip()
      // Check cumulative rate was updated correctly
      const afterCumulativeInterestRate = await gsrManager.cumulativeInterestRate()
      expect(afterCumulativeInterestRate).eq(expectedRateCompare)

      // Check drip time was updated
      const afterDripTime = await gsrManager.lastDripTime()
      expect(afterDripTime).eq(expectedDripTime)

      // Check tokens were minted
      const rateChange = afterCumulativeInterestRate.sub(beforeCumulativeInterestRate)
      const expectedAdditionalSupply = beforeBalance
        .mul(BigNumber.from(rateChange))
        .div(ISSUANCE_RATE_DECIMALS)
      const afterTokenSupply = await gdai.totalSupply()
      expect(expectedAdditionalSupply.add(beforeTokenSupply)).eq(afterTokenSupply)

      // Check users GDAI balance has gone up
      const afterGDAIBalance = await gdai.balanceOf(governor.address)
      expect(afterGDAIBalance).eq(expectedGDAIWithdrawn.add(beforeGDAIBalance))

      // Check reserve balance was updated
      const afterExitReserves = await gsrManager.reserves()
      expect(afterExitReserves).eq(0)

      // Check user savings balance was updated
      const afterExitBalance = await gsrManager.balances(governor.address)
      expect(afterExitBalance).eq(0)
    })
  })
})
