import hre from 'hardhat'
import { expect } from 'chai'
import { BigNumber, Event, utils } from 'ethers'

import { NetworkFixture } from '../lib/fixtures'
import { parseEther } from 'ethers/lib/utils'
import {
  formatGRT,
  GraphNetworkContracts,
  helpers,
  randomHexBytes,
  toBN,
  toGRT,
} from '@graphprotocol/sdk'
import { SignerWithAddress } from '@nomiclabs/hardhat-ethers/signers'

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
  return chunks as BigNumber[]
}

const toFloat = (n: BigNumber) => parseFloat(formatGRT(n))
const toRound = (n: number) => n.toFixed(12)

describe('Curation', () => {
  let me: SignerWithAddress
  let governor: SignerWithAddress
  let curator: SignerWithAddress
  let stakingMock: SignerWithAddress
  let gnsImpersonator: SignerWithAddress

  let fixture: NetworkFixture

  let contracts: GraphNetworkContracts

  const graph = hre.graph()

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
  ): Promise<number> {
    // Handle the initialization of the bonding curve
    if (supply.eq(0)) {
      const minDeposit = await contracts.Curation.minimumCurationDeposit()
      if (depositAmount.lt(minDeposit)) {
        throw new Error('deposit must be above minimum')
      }
      const defaultReserveRatio = await contracts.Curation.defaultReserveRatio()
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
      toFloat(supply)
      * ((1 + toFloat(depositAmount) / toFloat(reserveBalance)) ** (reserveRatio / 1000000) - 1)
    )
  }

  const shouldMint = async (tokensToDeposit: BigNumber, expectedSignal: BigNumber) => {
    // Before state
    const beforeTokenTotalSupply = await contracts.GraphToken.totalSupply()
    const beforeCuratorTokens = await contracts.GraphToken.balanceOf(curator.address)
    const beforeCuratorSignal = await contracts.Curation.getCuratorSignal(
      curator.address,
      subgraphDeploymentID,
    )
    const beforePool = await contracts.Curation.pools(subgraphDeploymentID)
    const beforePoolSignal = await contracts.Curation.getCurationPoolSignal(subgraphDeploymentID)
    const beforeTotalTokens = await contracts.GraphToken.balanceOf(contracts.Curation.address)

    // Calculations
    const curationTaxPercentage = await contracts.Curation.curationTaxPercentage()
    const curationTax = tokensToDeposit.mul(toBN(curationTaxPercentage)).div(toBN(MAX_PPM))

    // Curate
    const tx = contracts.Curation.connect(curator).mint(subgraphDeploymentID, tokensToDeposit, 0)
    await expect(tx)
      .emit(contracts.Curation, 'Signalled')
      .withArgs(curator.address, subgraphDeploymentID, tokensToDeposit, expectedSignal, curationTax)

    // After state
    const afterTokenTotalSupply = await contracts.GraphToken.totalSupply()
    const afterCuratorTokens = await contracts.GraphToken.balanceOf(curator.address)
    const afterCuratorSignal = await contracts.Curation.getCuratorSignal(
      curator.address,
      subgraphDeploymentID,
    )
    const afterPool = await contracts.Curation.pools(subgraphDeploymentID)
    const afterPoolSignal = await contracts.Curation.getCurationPoolSignal(subgraphDeploymentID)
    const afterTotalTokens = await contracts.GraphToken.balanceOf(contracts.Curation.address)

    // Curator balance updated
    expect(afterCuratorTokens).eq(beforeCuratorTokens.sub(tokensToDeposit))
    expect(afterCuratorSignal).eq(beforeCuratorSignal.add(expectedSignal))
    // Allocated and balance updated
    expect(afterPool.tokens).eq(beforePool.tokens.add(tokensToDeposit.sub(curationTax)))
    expect(afterPoolSignal).eq(beforePoolSignal.add(expectedSignal))
    expect(afterPool.reserveRatio).eq(await contracts.Curation.defaultReserveRatio())
    // Contract balance updated
    expect(afterTotalTokens).eq(beforeTotalTokens.add(tokensToDeposit.sub(curationTax)))
    // Total supply is reduced to curation tax burning
    expect(afterTokenTotalSupply).eq(beforeTokenTotalSupply.sub(curationTax))
  }

  const shouldBurn = async (signalToRedeem: BigNumber, expectedTokens: BigNumber) => {
    // Before balances
    const beforeTokenTotalSupply = await contracts.GraphToken.totalSupply()
    const beforeCuratorTokens = await contracts.GraphToken.balanceOf(curator.address)
    const beforeCuratorSignal = await contracts.Curation.getCuratorSignal(
      curator.address,
      subgraphDeploymentID,
    )
    const beforePool = await contracts.Curation.pools(subgraphDeploymentID)
    const beforePoolSignal = await contracts.Curation.getCurationPoolSignal(subgraphDeploymentID)
    const beforeTotalTokens = await contracts.GraphToken.balanceOf(contracts.Curation.address)

    // Redeem
    const tx = contracts.Curation.connect(curator).burn(subgraphDeploymentID, signalToRedeem, 0)
    await expect(tx)
      .emit(contracts.Curation, 'Burned')
      .withArgs(curator.address, subgraphDeploymentID, expectedTokens, signalToRedeem)

    // After balances
    const afterTokenTotalSupply = await contracts.GraphToken.totalSupply()
    const afterCuratorTokens = await contracts.GraphToken.balanceOf(curator.address)
    const afterCuratorSignal = await contracts.Curation.getCuratorSignal(
      curator.address,
      subgraphDeploymentID,
    )
    const afterPool = await contracts.Curation.pools(subgraphDeploymentID)
    const afterPoolSignal = await contracts.Curation.getCurationPoolSignal(subgraphDeploymentID)
    const afterTotalTokens = await contracts.GraphToken.balanceOf(contracts.Curation.address)

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
    const beforePool = await contracts.Curation.pools(subgraphDeploymentID)
    const beforeTotalBalance = await contracts.GraphToken.balanceOf(contracts.Curation.address)

    // Source of tokens must be the staking for this to work
    await contracts.GraphToken.connect(stakingMock).transfer(
      contracts.Curation.address,
      tokensToCollect,
    )
    const tx = contracts.Curation.connect(stakingMock).collect(
      subgraphDeploymentID,
      tokensToCollect,
    )
    await expect(tx)
      .emit(contracts.Curation, 'Collected')
      .withArgs(subgraphDeploymentID, tokensToCollect)

    // After state
    const afterPool = await contracts.Curation.pools(subgraphDeploymentID)
    const afterTotalBalance = await contracts.GraphToken.balanceOf(contracts.Curation.address)

    // State updated
    expect(afterPool.tokens).eq(beforePool.tokens.add(tokensToCollect))
    expect(afterTotalBalance).eq(beforeTotalBalance.add(tokensToCollect))
  }

  before(async function () {
    // Use stakingMock so we can call collect
    [me, curator, stakingMock] = await graph.getTestAccounts()
    ;({ governor } = await graph.getNamedAccounts())

    fixture = new NetworkFixture(graph.provider)
    contracts = await fixture.load(governor)

    gnsImpersonator = await helpers.impersonateAccount(contracts.GNS.address)
    await helpers.setBalance(contracts.GNS.address, parseEther('1'))
    // Give some funds to the curator and GNS impersonator and approve the curation contract
    await contracts.GraphToken.connect(governor).mint(curator.address, curatorTokens)
    await contracts.GraphToken.connect(curator).approve(contracts.Curation.address, curatorTokens)
    await contracts.GraphToken.connect(governor).mint(contracts.GNS.address, curatorTokens)
    await contracts.GraphToken.connect(gnsImpersonator).approve(
      contracts.Curation.address,
      curatorTokens,
    )

    // Give some funds to the staking contract and approve the curation contract
    await contracts.GraphToken.connect(governor).mint(stakingMock.address, tokensToCollect)
    await contracts.GraphToken.connect(stakingMock).approve(
      contracts.Curation.address,
      tokensToCollect,
    )
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
      const tx = contracts.Curation.signalToTokens(subgraphDeploymentID, toGRT('100'))
      await expect(tx).revertedWith('Subgraph deployment must be curated to perform calculations')
    })

    it('convert signal to tokens', async function () {
      // Curate
      await contracts.Curation.connect(curator).mint(subgraphDeploymentID, tokensToDeposit, 0)

      // Conversion
      const signal = await contracts.Curation.getCurationPoolSignal(subgraphDeploymentID)
      const expectedTokens = await contracts.Curation.signalToTokens(subgraphDeploymentID, signal)
      expect(expectedTokens).eq(tokensToDeposit)
    })

    it('convert signal to tokens (with curation tax)', async function () {
      // Set curation tax
      const curationTaxPercentage = 50000 // 5%
      await contracts.Curation.connect(governor).setCurationTaxPercentage(curationTaxPercentage)

      // Curate
      const expectedCurationTax = tokensToDeposit.mul(curationTaxPercentage).div(MAX_PPM)
      const { 1: curationTax } = await contracts.Curation.tokensToSignal(
        subgraphDeploymentID,
        tokensToDeposit,
      )
      await contracts.Curation.connect(curator).mint(subgraphDeploymentID, tokensToDeposit, 0)

      // Conversion
      const signal = await contracts.Curation.getCurationPoolSignal(subgraphDeploymentID)
      const tokens = await contracts.Curation.signalToTokens(subgraphDeploymentID, signal)
      expect(tokens).eq(tokensToDeposit.sub(expectedCurationTax))
      expect(expectedCurationTax).eq(curationTax)
    })

    it('convert tokens to signal', async function () {
      // Conversion
      const tokens = toGRT('1000')
      const { 0: signal } = await contracts.Curation.tokensToSignal(subgraphDeploymentID, tokens)
      expect(signal).eq(signalAmountFor1000Tokens)
    })

    it('convert tokens to signal if non-curated subgraph', async function () {
      // Conversion
      const nonCuratedSubgraphDeploymentID = randomHexBytes()
      const tokens = toGRT('1')
      const tx = contracts.Curation.tokensToSignal(nonCuratedSubgraphDeploymentID, tokens)
      await expect(tx).revertedWith('Curation deposit is below minimum required')
    })
  })

  describe('curate', function () {
    it('reject deposit below minimum tokens required', async function () {
      const tokensToDeposit = (await contracts.Curation.minimumCurationDeposit()).sub(toBN(1))
      const tx = contracts.Curation.connect(curator).mint(subgraphDeploymentID, tokensToDeposit, 0)
      await expect(tx).revertedWith('Curation deposit is below minimum required')
    })

    it('should deposit on a subgraph deployment', async function () {
      const tokensToDeposit = await contracts.Curation.minimumCurationDeposit()
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
      await contracts.Curation.connect(governor).setCurationTaxPercentage(50000) // 5%

      // Mint
      const tokensToDeposit = toGRT('1000')
      const { 0: expectedSignal } = await contracts.Curation.tokensToSignal(
        subgraphDeploymentID,
        tokensToDeposit,
      )
      await shouldMint(tokensToDeposit, expectedSignal)
    })

    it('should revert curate if over slippage', async function () {
      const tokensToDeposit = toGRT('1000')
      const expectedSignal = signalAmountFor1000Tokens
      const tx = contracts.Curation.connect(curator).mint(
        subgraphDeploymentID,
        tokensToDeposit,
        expectedSignal.add(1),
      )
      await expect(tx).revertedWith('Slippage protection')
    })
  })

  describe('collect', function () {
    context('> not curated', function () {
      it('reject collect tokens distributed to the curation pool', async function () {
        // Source of tokens must be the staking for this to work
        await contracts.Controller.connect(governor).setContractProxy(
          utils.id('Staking'),
          stakingMock.address,
        )
        await contracts.Curation.connect(governor).syncAllContracts() // call sync because we change the proxy for staking

        const tx = contracts.Curation.connect(stakingMock).collect(
          subgraphDeploymentID,
          tokensToCollect,
        )
        await expect(tx).revertedWith('Subgraph deployment must be curated to collect fees')
      })
    })

    context('> curated', function () {
      beforeEach(async function () {
        await contracts.Curation.connect(curator).mint(subgraphDeploymentID, toGRT('1000'), 0)
      })

      it('reject collect tokens distributed from invalid address', async function () {
        const tx = contracts.Curation.connect(me).collect(subgraphDeploymentID, tokensToCollect)
        await expect(tx).revertedWith('Caller must be the staking contract')
      })

      it('should collect tokens distributed to the curation pool', async function () {
        await contracts.Controller.connect(governor).setContractProxy(
          utils.id('Staking'),
          stakingMock.address,
        )
        await contracts.Curation.connect(governor).syncAllContracts() // call sync because we change the proxy for staking

        await shouldCollect(toGRT('1'))
        await shouldCollect(toGRT('10'))
        await shouldCollect(toGRT('100'))
        await shouldCollect(toGRT('200'))
        await shouldCollect(toGRT('500.25'))
      })

      it('should collect tokens and then unsignal all', async function () {
        await contracts.Controller.connect(governor).setContractProxy(
          utils.id('Staking'),
          stakingMock.address,
        )
        await contracts.Curation.connect(governor).syncAllContracts() // call sync because we change the proxy for staking

        // Collect increase the pool reserves
        await shouldCollect(toGRT('100'))

        // When we burn signal we should get more tokens than initially curated
        const signalToRedeem = await contracts.Curation.getCuratorSignal(
          curator.address,
          subgraphDeploymentID,
        )
        await shouldBurn(signalToRedeem, toGRT('1100'))
      })

      it('should collect tokens and then unsignal multiple times', async function () {
        await contracts.Controller.connect(governor).setContractProxy(
          utils.id('Staking'),
          stakingMock.address,
        )
        await contracts.Curation.connect(governor).syncAllContracts() // call sync because we change the proxy for staking

        // Collect increase the pool reserves
        const tokensToCollect = toGRT('100')
        await shouldCollect(tokensToCollect)

        // Unsignal partially
        const signalOutRemainder = toGRT(1)
        const signalOutPartial = (
          await contracts.Curation.getCuratorSignal(curator.address, subgraphDeploymentID)
        ).sub(signalOutRemainder)
        const tx1 = await contracts.Curation.connect(curator).burn(
          subgraphDeploymentID,
          signalOutPartial,
          0,
        )
        const r1 = await tx1.wait()
        const event1 = contracts.Curation.interface.parseLog(r1.events[2]).args
        const tokensOut1 = event1.tokens

        // Collect increase the pool reserves
        await shouldCollect(tokensToCollect)

        // Unsignal the rest
        const tx2 = await contracts.Curation.connect(curator).burn(
          subgraphDeploymentID,
          signalOutRemainder,
          0,
        )
        const r2 = await tx2.wait()
        const event2 = contracts.Curation.interface.parseLog(r2.events[2]).args
        const tokensOut2 = event2.tokens

        expect(tokensOut1.add(tokensOut2)).eq(toGRT('1000').add(tokensToCollect.mul(2)))
      })
    })
  })

  describe('burn', function () {
    beforeEach(async function () {
      await contracts.Curation.connect(curator).mint(subgraphDeploymentID, tokensToDeposit, 0)
    })

    it('reject redeem more than a curator owns', async function () {
      const tx = contracts.Curation.connect(me).burn(subgraphDeploymentID, toGRT('1'), 0)
      await expect(tx).revertedWith('Cannot burn more signal than you own')
    })

    it('reject redeem zero signal', async function () {
      const tx = contracts.Curation.connect(me).burn(subgraphDeploymentID, toGRT('0'), 0)
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
      const signalToRedeem = await contracts.Curation.getCuratorSignal(
        curator.address,
        subgraphDeploymentID,
      )
      const expectedTokens = tokensToDeposit
      await shouldBurn(signalToRedeem, expectedTokens)
    })

    it('should allow to redeem back below minimum deposit', async function () {
      // Redeem "almost" all signal
      const signal = await contracts.Curation.getCuratorSignal(
        curator.address,
        subgraphDeploymentID,
      )
      const signalToRedeem = signal.sub(toGRT('0.000001'))
      const expectedTokens = await contracts.Curation.signalToTokens(
        subgraphDeploymentID,
        signalToRedeem,
      )
      await shouldBurn(signalToRedeem, expectedTokens)

      // The pool should have less tokens that required by minimumCurationDeposit
      const afterPool = await contracts.Curation.pools(subgraphDeploymentID)
      expect(afterPool.tokens).lt(await contracts.Curation.minimumCurationDeposit())

      // Should be able to deposit more after being under minimumCurationDeposit
      const tokensToDeposit = toGRT('1')
      const { 0: expectedSignal } = await contracts.Curation.tokensToSignal(
        subgraphDeploymentID,
        tokensToDeposit,
      )
      await shouldMint(tokensToDeposit, expectedSignal)
    })

    it('should revert redeem if over slippage', async function () {
      const signalToRedeem = await contracts.Curation.getCuratorSignal(
        curator.address,
        subgraphDeploymentID,
      )
      const expectedTokens = tokensToDeposit

      const tx = contracts.Curation.connect(curator).burn(
        subgraphDeploymentID,
        signalToRedeem,
        expectedTokens.add(1),
      )
      await expect(tx).revertedWith('Slippage protection')
    })

    it('should not re-deploy the curation token when signal is reset', async function () {
      const beforeSubgraphPool = await contracts.Curation.pools(subgraphDeploymentID)

      // Burn all the signal
      const signalToRedeem = await contracts.Curation.getCuratorSignal(
        curator.address,
        subgraphDeploymentID,
      )
      const expectedTokens = tokensToDeposit
      await shouldBurn(signalToRedeem, expectedTokens)

      // Mint again on the same subgraph
      await contracts.Curation.connect(curator).mint(subgraphDeploymentID, tokensToDeposit, 0)

      // Check state
      const afterSubgraphPool = await contracts.Curation.pools(subgraphDeploymentID)
      expect(afterSubgraphPool.gcs).eq(beforeSubgraphPool.gcs)
    })
  })

  describe('conservation', function () {
    it('should match multiple deposits and redeems back to initial state', async function () {
      this.timeout(60000) // increase timeout for test runner

      const totalDeposits = toGRT('1000000000')

      // Signal multiple times
      let totalSignal = toGRT('0')
      for (const tokensToDeposit of chunkify(totalDeposits, 10)) {
        const tx = await contracts.Curation.connect(curator).mint(
          subgraphDeploymentID,
          tokensToDeposit,
          0,
        )
        const receipt = await tx.wait()
        const event: Event = receipt.events.pop()
        const signal = event.args['signal']
        totalSignal = totalSignal.add(signal)
      }

      // Redeem signal multiple times
      let totalTokens = toGRT('0')
      for (const signalToRedeem of chunkify(totalSignal, 10)) {
        const tx = await contracts.Curation.connect(curator).burn(
          subgraphDeploymentID,
          signalToRedeem,
          0,
        )
        const receipt = await tx.wait()
        const event: Event = receipt.events.pop()
        const tokens = event.args['tokens']
        totalTokens = totalTokens.add(tokens)
        // console.log('<', formatEther(signalToRedeem), '=', formatEther(tokens))
      }

      // Conservation of work
      const afterPool = await contracts.Curation.pools(subgraphDeploymentID)
      const afterPoolSignal = await contracts.Curation.getCurationPoolSignal(subgraphDeploymentID)
      expect(afterPool.tokens).eq(toGRT('0'))
      expect(afterPoolSignal).eq(toGRT('0'))
      expect(await contracts.Curation.isCurated(subgraphDeploymentID)).eq(false)
      expect(totalDeposits).eq(totalTokens)
    })
  })

  describe('multiple minting', function () {
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
          await contracts.Curation.getCurationPoolSignal(subgraphDeploymentID),
          await contracts.Curation.getCurationPoolTokens(subgraphDeploymentID),
          await contracts.Curation.defaultReserveRatio(),
          tokensToDeposit,
        )

        const tx = await contracts.Curation.connect(curator).mint(
          subgraphDeploymentID,
          tokensToDeposit,
          0,
        )
        const receipt = await tx.wait()
        const event: Event = receipt.events.pop()
        const signal = event.args['signal']
        expect(toRound(expectedSignal)).eq(toRound(toFloat(signal)))
      }
    })

    it('should mint when using the edge case of linear function', async function () {
      this.timeout(60000) // increase timeout for test runner

      // Setup edge case like linear function: 1 GRT = 1 GCS
      await contracts.Curation.connect(governor).setMinimumCurationDeposit(toGRT('1'))
      await contracts.Curation.connect(governor).setDefaultReserveRatio(1000000)

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
        const tx = await contracts.Curation.connect(curator).mint(
          subgraphDeploymentID,
          tokensToDeposit,
          0,
        )
        const receipt = await tx.wait()
        const event: Event = receipt.events.pop()
        const signal = event.args['signal']
        expect(tokensToDeposit).eq(signal) // we compare 1:1 ratio
      }
    })
  })
})
