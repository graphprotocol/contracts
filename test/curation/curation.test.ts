import { expect } from 'chai'
import { utils, BigNumber, Event } from 'ethers'

import { Curation } from '../../build/types/Curation'
import { GraphToken } from '../../build/types/GraphToken'
import { Controller } from '../../build/types/Controller'

import { NetworkFixture } from '../lib/fixtures'
import { getAccounts, randomHexBytes, toBN, toGRT, formatGRT, Account } from '../lib/testHelpers'

const MAX_PPM = 1000000

const chunkify = (total: BigNumber, maxChunks = 10): Array<BigNumber> => {
  const chunks = []
  while (total.gt(0) && maxChunks > 0) {
    const m = 1000000
    const p = Math.floor(Math.random() * m)
    const n = total.mul(p).div(m)
    chunks.push(n)
    total = total.sub(n)
    maxChunks--
  }
  if (total.gt(0)) {
    chunks.push(total)
  }
  return chunks
}

const toFloat = (n: BigNumber) => parseFloat(formatGRT(n))
const toRound = (n: number) => n.toFixed(12)

describe('Curation', () => {
  let me: Account
  let governor: Account
  let curator: Account
  let stakingMock: Account

  let fixture: NetworkFixture

  let curation: Curation
  let grt: GraphToken
  let controller: Controller

  // Test values
  const signalAmountFor1000Tokens = toGRT('3.162277660168379331')
  const subgraphDeploymentID = randomHexBytes()
  const curatorTokens = toGRT('1000000000')
  const tokensToDeposit = toGRT('1000')
  const tokensToCollect = toGRT('2000')

  async function calcBondingCurve(
    supply: BigNumber,
    reserveBalance: BigNumber,
    reserveRatio: number,
    depositAmount: BigNumber,
  ) {
    // Handle the initialization of the bonding curve
    if (supply.eq(0)) {
      const minDeposit = await curation.minimumCurationDeposit()
      if (depositAmount.lt(minDeposit)) {
        throw new Error('deposit must be above minimum')
      }
      const defaultReserveRatio = await curation.defaultReserveRatio()
      const minSupply = toGRT('1')
      return (
        (await calcBondingCurve(
          minSupply,
          minDeposit,
          defaultReserveRatio,
          depositAmount.sub(minDeposit),
        )) + toFloat(minSupply)
      )
    }
    // Calculate bonding curve in the test
    return (
      toFloat(supply) *
      ((1 + toFloat(depositAmount) / toFloat(reserveBalance)) ** (reserveRatio / 1000000) - 1)
    )
  }

  const shouldMint = async (tokensToDeposit: BigNumber, expectedSignal: BigNumber) => {
    // Before state
    const beforeTokenTotalSupply = await grt.totalSupply()
    const beforeCuratorTokens = await grt.balanceOf(curator.address)
    const beforeCuratorSignal = await curation.getCuratorSignal(
      curator.address,
      subgraphDeploymentID,
    )
    const beforePool = await curation.pools(subgraphDeploymentID)
    const beforePoolSignal = await curation.getCurationPoolSignal(subgraphDeploymentID)
    const beforeTotalTokens = await grt.balanceOf(curation.address)

    // Calculations
    const curationTaxPercentage = await curation.curationTaxPercentage()
    const curationTax = tokensToDeposit.mul(toBN(curationTaxPercentage)).div(toBN(MAX_PPM))

    // Curate
    const tx = curation.connect(curator.signer).mint(subgraphDeploymentID, tokensToDeposit, 0)
    await expect(tx)
      .emit(curation, 'Signalled')
      .withArgs(curator.address, subgraphDeploymentID, tokensToDeposit, expectedSignal, curationTax)

    // After state
    const afterTokenTotalSupply = await grt.totalSupply()
    const afterCuratorTokens = await grt.balanceOf(curator.address)
    const afterCuratorSignal = await curation.getCuratorSignal(
      curator.address,
      subgraphDeploymentID,
    )
    const afterPool = await curation.pools(subgraphDeploymentID)
    const afterPoolSignal = await curation.getCurationPoolSignal(subgraphDeploymentID)
    const afterTotalTokens = await grt.balanceOf(curation.address)

    // Curator balance updated
    expect(afterCuratorTokens).eq(beforeCuratorTokens.sub(tokensToDeposit))
    expect(afterCuratorSignal).eq(beforeCuratorSignal.add(expectedSignal))
    // Allocated and balance updated
    expect(afterPool.tokens).eq(beforePool.tokens.add(tokensToDeposit.sub(curationTax)))
    expect(afterPoolSignal).eq(beforePoolSignal.add(expectedSignal))
    expect(afterPool.reserveRatio).eq(await curation.defaultReserveRatio())
    // Contract balance updated
    expect(afterTotalTokens).eq(beforeTotalTokens.add(tokensToDeposit.sub(curationTax)))
    // Total supply is reduced to curation tax burning
    expect(afterTokenTotalSupply).eq(beforeTokenTotalSupply.sub(curationTax))
  }

  const shouldBurn = async (signalToRedeem: BigNumber, expectedTokens: BigNumber) => {
    // Before balances
    const beforeTokenTotalSupply = await grt.totalSupply()
    const beforeCuratorTokens = await grt.balanceOf(curator.address)
    const beforeCuratorSignal = await curation.getCuratorSignal(
      curator.address,
      subgraphDeploymentID,
    )
    const beforePool = await curation.pools(subgraphDeploymentID)
    const beforePoolSignal = await curation.getCurationPoolSignal(subgraphDeploymentID)
    const beforeTotalTokens = await grt.balanceOf(curation.address)

    // Redeem
    const tx = curation.connect(curator.signer).burn(subgraphDeploymentID, signalToRedeem, 0)
    await expect(tx)
      .emit(curation, 'Burned')
      .withArgs(curator.address, subgraphDeploymentID, expectedTokens, signalToRedeem)

    // After balances
    const afterTokenTotalSupply = await grt.totalSupply()
    const afterCuratorTokens = await grt.balanceOf(curator.address)
    const afterCuratorSignal = await curation.getCuratorSignal(
      curator.address,
      subgraphDeploymentID,
    )
    const afterPool = await curation.pools(subgraphDeploymentID)
    const afterPoolSignal = await curation.getCurationPoolSignal(subgraphDeploymentID)
    const afterTotalTokens = await grt.balanceOf(curation.address)

    // Curator balance updated
    expect(afterCuratorTokens).eq(beforeCuratorTokens.add(expectedTokens))
    expect(afterCuratorSignal).eq(beforeCuratorSignal.sub(signalToRedeem))
    // Curation balance updated
    expect(afterPool.tokens).eq(beforePool.tokens.sub(expectedTokens))
    expect(afterPoolSignal).eq(beforePoolSignal.sub(signalToRedeem))
    // Contract balance updated
    expect(afterTotalTokens).eq(beforeTotalTokens.sub(expectedTokens))
    // Total supply is conserved
    expect(afterTokenTotalSupply).eq(beforeTokenTotalSupply)
  }

  const shouldCollect = async (tokensToCollect: BigNumber) => {
    // Before state
    const beforePool = await curation.pools(subgraphDeploymentID)
    const beforeTotalBalance = await grt.balanceOf(curation.address)

    // Source of tokens must be the staking for this to work
    await grt.connect(stakingMock.signer).transfer(curation.address, tokensToCollect)
    const tx = curation.connect(stakingMock.signer).collect(subgraphDeploymentID, tokensToCollect)
    await expect(tx).emit(curation, 'Collected').withArgs(subgraphDeploymentID, tokensToCollect)

    // After state
    const afterPool = await curation.pools(subgraphDeploymentID)
    const afterTotalBalance = await grt.balanceOf(curation.address)

    // State updated
    expect(afterPool.tokens).eq(beforePool.tokens.add(tokensToCollect))
    expect(afterTotalBalance).eq(beforeTotalBalance.add(tokensToCollect))
  }

  before(async function () {
    // Use stakingMock so we can call collect
    ;[me, governor, curator, stakingMock] = await getAccounts()

    fixture = new NetworkFixture()
    ;({ controller, curation, grt } = await fixture.load(governor.signer))

    // Give some funds to the curator and approve the curation contract
    await grt.connect(governor.signer).mint(curator.address, curatorTokens)
    await grt.connect(curator.signer).approve(curation.address, curatorTokens)

    // Give some funds to the staking contract and approve the curation contract
    await grt.connect(governor.signer).mint(stakingMock.address, tokensToCollect)
    await grt.connect(stakingMock.signer).approve(curation.address, tokensToCollect)
  })

  beforeEach(async function () {
    await fixture.setUp()
  })

  afterEach(async function () {
    await fixture.tearDown()
  })

  describe('bonding curve', function () {
    const tokensToDeposit = curatorTokens

    it('reject convert signal to tokens if subgraph deployment not initted', async function () {
      const tx = curation.signalToTokens(subgraphDeploymentID, toGRT('100'))
      await expect(tx).revertedWith('Subgraph deployment must be curated to perform calculations')
    })

    it('convert signal to tokens', async function () {
      // Curate
      await curation.connect(curator.signer).mint(subgraphDeploymentID, tokensToDeposit, 0)

      // Conversion
      const signal = await curation.getCurationPoolSignal(subgraphDeploymentID)
      const expectedTokens = await curation.signalToTokens(subgraphDeploymentID, signal)
      expect(expectedTokens).eq(tokensToDeposit)
    })

    it('convert signal to tokens (with curation tax)', async function () {
      // Set curation tax
      const curationTaxPercentage = 50000 // 5%
      await curation.connect(governor.signer).setCurationTaxPercentage(curationTaxPercentage)

      // Curate
      const expectedCurationTax = tokensToDeposit.mul(curationTaxPercentage).div(MAX_PPM)
      const { 1: curationTax } = await curation.tokensToSignal(
        subgraphDeploymentID,
        tokensToDeposit,
      )
      await curation.connect(curator.signer).mint(subgraphDeploymentID, tokensToDeposit, 0)

      // Conversion
      const signal = await curation.getCurationPoolSignal(subgraphDeploymentID)
      const tokens = await curation.signalToTokens(subgraphDeploymentID, signal)
      expect(tokens).eq(tokensToDeposit.sub(expectedCurationTax))
      expect(expectedCurationTax).eq(curationTax)
    })

    it('convert tokens to signal', async function () {
      // Conversion
      const tokens = toGRT('1000')
      const { 0: signal } = await curation.tokensToSignal(subgraphDeploymentID, tokens)
      expect(signal).eq(signalAmountFor1000Tokens)
    })

    it('convert tokens to signal if non-curated subgraph', async function () {
      // Conversion
      const nonCuratedSubgraphDeploymentID = randomHexBytes()
      const tokens = toGRT('1')
      const tx = curation.tokensToSignal(nonCuratedSubgraphDeploymentID, tokens)
      await expect(tx).revertedWith('Curation deposit is below minimum required')
    })
  })

  describe('curate', async function () {
    it('reject deposit below minimum tokens required', async function () {
      const tokensToDeposit = (await curation.minimumCurationDeposit()).sub(toBN(1))
      const tx = curation.connect(curator.signer).mint(subgraphDeploymentID, tokensToDeposit, 0)
      await expect(tx).revertedWith('Curation deposit is below minimum required')
    })

    it('should deposit on a subgraph deployment', async function () {
      const tokensToDeposit = await curation.minimumCurationDeposit()
      const expectedSignal = toGRT('1')
      await shouldMint(tokensToDeposit, expectedSignal)
    })

    it('should get signal according to bonding curve', async function () {
      const tokensToDeposit = toGRT('1000')
      const expectedSignal = signalAmountFor1000Tokens
      await shouldMint(tokensToDeposit, expectedSignal)
    })

    it('should get signal according to bonding curve (and account for curation tax)', async function () {
      // Set curation tax
      await curation.connect(governor.signer).setCurationTaxPercentage(50000) // 5%

      // Mint
      const tokensToDeposit = toGRT('1000')
      const { 0: expectedSignal } = await curation.tokensToSignal(
        subgraphDeploymentID,
        tokensToDeposit,
      )
      await shouldMint(tokensToDeposit, expectedSignal)
    })

    it('should revert curate if over slippage', async function () {
      const tokensToDeposit = toGRT('1000')
      const expectedSignal = signalAmountFor1000Tokens
      const tx = curation
        .connect(curator.signer)
        .mint(subgraphDeploymentID, tokensToDeposit, expectedSignal.add(1))
      await expect(tx).revertedWith('Slippage protection')
    })
  })

  describe('collect', async function () {
    context('> not curated', async function () {
      it('reject collect tokens distributed to the curation pool', async function () {
        // Source of tokens must be the staking for this to work
        await controller
          .connect(governor.signer)
          .setContractProxy(utils.id('Staking'), stakingMock.address)
        await curation.syncAllContracts() // call sync because we change the proxy for staking

        const tx = curation
          .connect(stakingMock.signer)
          .collect(subgraphDeploymentID, tokensToCollect)
        await expect(tx).revertedWith('Subgraph deployment must be curated to collect fees')
      })
    })

    context('> curated', async function () {
      beforeEach(async function () {
        await curation.connect(curator.signer).mint(subgraphDeploymentID, toGRT('1000'), 0)
      })

      it('reject collect tokens distributed from invalid address', async function () {
        const tx = curation.connect(me.signer).collect(subgraphDeploymentID, tokensToCollect)
        await expect(tx).revertedWith('Caller must be the staking contract')
      })

      it('should collect tokens distributed to the curation pool', async function () {
        await controller
          .connect(governor.signer)
          .setContractProxy(utils.id('Staking'), stakingMock.address)
        await curation.syncAllContracts() // call sync because we change the proxy for staking

        await shouldCollect(toGRT('1'))
        await shouldCollect(toGRT('10'))
        await shouldCollect(toGRT('100'))
        await shouldCollect(toGRT('200'))
        await shouldCollect(toGRT('500.25'))
      })

      it('should collect tokens and then unsignal all', async function () {
        await controller
          .connect(governor.signer)
          .setContractProxy(utils.id('Staking'), stakingMock.address)
        await curation.syncAllContracts() // call sync because we change the proxy for staking

        // Collect increase the pool reserves
        await shouldCollect(toGRT('100'))

        // When we burn signal we should get more tokens than initially curated
        const signalToRedeem = await curation.getCuratorSignal(
          curator.address,
          subgraphDeploymentID,
        )
        await shouldBurn(signalToRedeem, toGRT('1100'))
      })

      it('should collect tokens and then unsignal multiple times', async function () {
        await controller
          .connect(governor.signer)
          .setContractProxy(utils.id('Staking'), stakingMock.address)
        await curation.syncAllContracts() // call sync because we change the proxy for staking

        // Collect increase the pool reserves
        const tokensToCollect = toGRT('100')
        await shouldCollect(tokensToCollect)

        // Unsignal partially
        const signalOutRemainder = toGRT(1)
        const signalOutPartial = (
          await curation.getCuratorSignal(curator.address, subgraphDeploymentID)
        ).sub(signalOutRemainder)
        const tx1 = await curation
          .connect(curator.signer)
          .burn(subgraphDeploymentID, signalOutPartial, 0)
        const r1 = await tx1.wait()
        const event1 = curation.interface.parseLog(r1.events[2]).args
        const tokensOut1 = event1.tokens

        // Collect increase the pool reserves
        await shouldCollect(tokensToCollect)

        // Unsignal the rest
        const tx2 = await curation
          .connect(curator.signer)
          .burn(subgraphDeploymentID, signalOutRemainder, 0)
        const r2 = await tx2.wait()
        const event2 = curation.interface.parseLog(r2.events[2]).args
        const tokensOut2 = event2.tokens

        expect(tokensOut1.add(tokensOut2)).eq(toGRT('1000').add(tokensToCollect.mul(2)))
      })
    })
  })

  describe('burn', async function () {
    beforeEach(async function () {
      await curation.connect(curator.signer).mint(subgraphDeploymentID, tokensToDeposit, 0)
    })

    it('reject redeem more than a curator owns', async function () {
      const tx = curation.connect(me.signer).burn(subgraphDeploymentID, toGRT('1'), 0)
      await expect(tx).revertedWith('Cannot burn more signal than you own')
    })

    it('reject redeem zero signal', async function () {
      const tx = curation.connect(me.signer).burn(subgraphDeploymentID, toGRT('0'), 0)
      await expect(tx).revertedWith('Cannot burn zero signal')
    })

    it('should allow to redeem *partially*', async function () {
      // Redeem just one signal
      const signalToRedeem = toGRT('1')
      const expectedTokens = toGRT('532.455532033675866536')
      await shouldBurn(signalToRedeem, expectedTokens)
    })

    it('should allow to redeem *fully*', async function () {
      // Get all signal of the curator
      const signalToRedeem = await curation.getCuratorSignal(curator.address, subgraphDeploymentID)
      const expectedTokens = tokensToDeposit
      await shouldBurn(signalToRedeem, expectedTokens)
    })

    it('should allow to redeem back below minimum deposit', async function () {
      // Redeem "almost" all signal
      const signal = await curation.getCuratorSignal(curator.address, subgraphDeploymentID)
      const signalToRedeem = signal.sub(toGRT('0.000001'))
      const expectedTokens = await curation.signalToTokens(subgraphDeploymentID, signalToRedeem)
      await shouldBurn(signalToRedeem, expectedTokens)

      // The pool should have less tokens that required by minimumCurationDeposit
      const afterPool = await curation.pools(subgraphDeploymentID)
      expect(afterPool.tokens).lt(await curation.minimumCurationDeposit())

      // Should be able to deposit more after being under minimumCurationDeposit
      const tokensToDeposit = toGRT('1')
      const { 0: expectedSignal } = await curation.tokensToSignal(
        subgraphDeploymentID,
        tokensToDeposit,
      )
      await shouldMint(tokensToDeposit, expectedSignal)
    })

    it('should revert redeem if over slippage', async function () {
      const signalToRedeem = await curation.getCuratorSignal(curator.address, subgraphDeploymentID)
      const expectedTokens = tokensToDeposit

      const tx = curation
        .connect(curator.signer)
        .burn(subgraphDeploymentID, signalToRedeem, expectedTokens.add(1))
      await expect(tx).revertedWith('Slippage protection')
    })
  })

  describe('conservation', async function () {
    it('should match multiple deposits and redeems back to initial state', async function () {
      this.timeout(60000) // increase timeout for test runner

      const totalDeposits = toGRT('1000000000')

      // Signal multiple times
      let totalSignal = toGRT('0')
      for (const tokensToDeposit of chunkify(totalDeposits, 10)) {
        const tx = await curation
          .connect(curator.signer)
          .mint(subgraphDeploymentID, tokensToDeposit, 0)
        const receipt = await tx.wait()
        const event: Event = receipt.events.pop()
        const signal = event.args['signal']
        totalSignal = totalSignal.add(signal)
      }

      // Redeem signal multiple times
      let totalTokens = toGRT('0')
      for (const signalToRedeem of chunkify(totalSignal, 10)) {
        const tx = await curation
          .connect(curator.signer)
          .burn(subgraphDeploymentID, signalToRedeem, 0)
        const receipt = await tx.wait()
        const event: Event = receipt.events.pop()
        const tokens = event.args['tokens']
        totalTokens = totalTokens.add(tokens)
        // console.log('<', formatEther(signalToRedeem), '=', formatEther(tokens))
      }

      // Conservation of work
      const afterPool = await curation.pools(subgraphDeploymentID)
      const afterPoolSignal = await curation.getCurationPoolSignal(subgraphDeploymentID)
      expect(afterPool.tokens).eq(toGRT('0'))
      expect(afterPoolSignal).eq(toGRT('0'))
      expect(await curation.isCurated(subgraphDeploymentID)).eq(false)
      expect(totalDeposits).eq(totalTokens)
    })
  })

  describe('multiple minting', async function () {
    it('should mint less signal every time due to the bonding curve', async function () {
      const tokensToDepositMany = [
        toGRT('1000'), // should mint if we start with number above minimum deposit
        toGRT('1000'), // every time it should mint less GCS due to bonding curve...
        toGRT('1000'),
        toGRT('1000'),
        toGRT('2000'),
        toGRT('2000'),
        toGRT('123'),
        toGRT('1'), // should mint below minimum deposit
      ]
      for (const tokensToDeposit of tokensToDepositMany) {
        const expectedSignal = await calcBondingCurve(
          await curation.getCurationPoolSignal(subgraphDeploymentID),
          await curation.getCurationPoolTokens(subgraphDeploymentID),
          await curation.defaultReserveRatio(),
          tokensToDeposit,
        )

        const tx = await curation
          .connect(curator.signer)
          .mint(subgraphDeploymentID, tokensToDeposit, 0)
        const receipt = await tx.wait()
        const event: Event = receipt.events.pop()
        const signal = event.args['signal']
        expect(toRound(expectedSignal)).eq(toRound(toFloat(signal)))
      }
    })

    it('should mint when using the edge case of linear function', async function () {
      // Setup edge case like linear function: 1 GRT = 1 GCS
      await curation.setMinimumCurationDeposit(toGRT('1'))
      await curation.setDefaultReserveRatio(1000000)

      const tokensToDepositMany = [
        toGRT('1000'), // should mint if we start with number above minimum deposit
        toGRT('1000'), // every time it should mint less GCS due to bonding curve...
        toGRT('1000'),
        toGRT('1000'),
        toGRT('2000'),
        toGRT('2000'),
        toGRT('123'),
        toGRT('1'), // should mint below minimum deposit
      ]

      // Mint multiple times
      for (const tokensToDeposit of tokensToDepositMany) {
        const tx = await curation
          .connect(curator.signer)
          .mint(subgraphDeploymentID, tokensToDeposit, 0)
        const receipt = await tx.wait()
        const event: Event = receipt.events.pop()
        const signal = event.args['signal']
        expect(tokensToDeposit).eq(signal) // we compare 1:1 ratio
      }
    })
  })
})
