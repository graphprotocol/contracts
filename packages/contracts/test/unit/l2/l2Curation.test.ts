import hre from 'hardhat'
import { expect } from 'chai'
import { BigNumber, constants, Event, Signer, utils } from 'ethers'

import { L2Curation } from '../../../build/types/L2Curation'
import { GraphToken } from '../../../build/types/GraphToken'
import { Controller } from '../../../build/types/Controller'

import { NetworkFixture } from '../lib/fixtures'
import { GNS } from '../../../build/types/GNS'
import { parseEther } from 'ethers/lib/utils'
import {
  formatGRT,
  GraphNetworkContracts,
  helpers,
  randomAddress,
  randomHexBytes,
  toBN,
  toGRT,
} from '@graphprotocol/sdk'
import { SignerWithAddress } from '@nomiclabs/hardhat-ethers/signers'

const { AddressZero } = constants

const MAX_PPM = 1000000

const chunkify = (total: BigNumber, maxChunks = 10): Array<BigNumber> => {
  const chunks: BigNumber[] = []
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
const toRound = (n: number) => n.toPrecision(11)

describe('L2Curation:Config', () => {
  const graph = hre.graph()
  const defaults = graph.graphConfig.defaults
  let me: SignerWithAddress
  let governor: SignerWithAddress

  let fixture: NetworkFixture

  let contracts: GraphNetworkContracts
  let curation: L2Curation

  before(async function () {
    [me] = await graph.getTestAccounts()
    ;({ governor } = await graph.getNamedAccounts())

    fixture = new NetworkFixture(graph.provider)
    contracts = await fixture.load(governor, true)
    curation = contracts.L2Curation
  })

  beforeEach(async function () {
    await fixture.setUp()
  })

  afterEach(async function () {
    await fixture.tearDown()
  })

  describe('defaultReserveRatio', function () {
    it('should be fixed to MAX_PPM', async function () {
      // Set right in the constructor
      expect(await curation.connect(me).defaultReserveRatio()).eq(MAX_PPM)
    })
    it('cannot be changed because the setter is not implemented', async function () {
      const tx = curation.connect(governor).setDefaultReserveRatio(10)
      await expect(tx).revertedWith('Not implemented in L2')
    })
  })

  describe('minimumCurationDeposit', function () {
    it('should set `minimumCurationDeposit`', async function () {
      // Set right in the constructor
      expect(await curation.minimumCurationDeposit()).eq(defaults.curation.l2MinimumCurationDeposit)

      // Can set if allowed
      const newValue = toBN('100')
      await curation.connect(governor).setMinimumCurationDeposit(newValue)
      expect(await curation.minimumCurationDeposit()).eq(newValue)
    })

    it('reject set `minimumCurationDeposit` if out of bounds', async function () {
      const tx = curation.connect(governor).setMinimumCurationDeposit(0)
      await expect(tx).revertedWith('Minimum curation deposit cannot be 0')
    })

    it('reject set `minimumCurationDeposit` if not allowed', async function () {
      const tx = curation
        .connect(me)
        .setMinimumCurationDeposit(defaults.curation.minimumCurationDeposit)
      await expect(tx).revertedWith('Only Controller governor')
    })
  })

  describe('curationTaxPercentage', function () {
    it('should set `curationTaxPercentage`', async function () {
      const curationTaxPercentage = defaults.curation.curationTaxPercentage

      // Set new value
      await curation.connect(governor).setCurationTaxPercentage(0)
      await curation.connect(governor).setCurationTaxPercentage(curationTaxPercentage)
    })

    it('reject set `curationTaxPercentage` if out of bounds', async function () {
      const tx = curation.connect(governor).setCurationTaxPercentage(MAX_PPM + 1)
      await expect(tx).revertedWith('Curation tax percentage must be below or equal to MAX_PPM')
    })

    it('reject set `curationTaxPercentage` if not allowed', async function () {
      const tx = curation.connect(me).setCurationTaxPercentage(0)
      await expect(tx).revertedWith('Only Controller governor')
    })
  })

  describe('curationTokenMaster', function () {
    it('should set `curationTokenMaster`', async function () {
      const newCurationTokenMaster = curation.address
      await curation.connect(governor).setCurationTokenMaster(newCurationTokenMaster)
    })

    it('reject set `curationTokenMaster` to empty value', async function () {
      const newCurationTokenMaster = AddressZero
      const tx = curation.connect(governor).setCurationTokenMaster(newCurationTokenMaster)
      await expect(tx).revertedWith('Token master must be non-empty')
    })

    it('reject set `curationTokenMaster` to non-contract', async function () {
      const newCurationTokenMaster = randomAddress()
      const tx = curation.connect(governor).setCurationTokenMaster(newCurationTokenMaster)
      await expect(tx).revertedWith('Token master must be a contract')
    })

    it('reject set `curationTokenMaster` if not allowed', async function () {
      const newCurationTokenMaster = curation.address
      const tx = curation.connect(me).setCurationTokenMaster(newCurationTokenMaster)
      await expect(tx).revertedWith('Only Controller governor')
    })
  })
})

describe('L2Curation', () => {
  const graph = hre.graph()
  let me: SignerWithAddress
  let governor: SignerWithAddress
  let curator: SignerWithAddress
  let stakingMock: SignerWithAddress
  let gnsImpersonator: Signer

  let fixture: NetworkFixture

  let contracts: GraphNetworkContracts
  let curation: L2Curation
  let grt: GraphToken
  let controller: Controller
  let gns: GNS

  // Test values
  const signalAmountFor1000Tokens = toGRT('1000.0')
  const signalAmountForMinimumCuration = toBN('1')
  const subgraphDeploymentID = randomHexBytes()
  const curatorTokens = toGRT('1000000000')
  const tokensToDeposit = toGRT('1000')
  const tokensToCollect = toGRT('2000')

  async function calcLinearBondingCurve(
    supply: BigNumber,
    reserveBalance: BigNumber,
    depositAmount: BigNumber,
  ): Promise<number> {
    // Handle the initialization of the bonding curve
    if (supply.eq(0)) {
      const minDeposit = await curation.minimumCurationDeposit()
      if (depositAmount.lt(minDeposit)) {
        throw new Error('deposit must be above minimum')
      }
      const minSupply = signalAmountForMinimumCuration
      return (
        (await calcLinearBondingCurve(minSupply, minDeposit, depositAmount.sub(minDeposit)))
        + toFloat(minSupply)
      )
    }
    // Calculate bonding curve in the test
    return toFloat(supply) * (toFloat(depositAmount) / toFloat(reserveBalance))
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
    const tx = curation.connect(curator).mint(subgraphDeploymentID, tokensToDeposit, 0)
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
    // Pool reserveRatio is deprecated and therefore always zero in L2
    expect(afterPool.reserveRatio).eq(0)
    // Contract balance updated
    expect(afterTotalTokens).eq(beforeTotalTokens.add(tokensToDeposit.sub(curationTax)))
    // Total supply is reduced to curation tax burning
    expect(afterTokenTotalSupply).eq(beforeTokenTotalSupply.sub(curationTax))
  }

  const shouldMintTaxFree = async (tokensToDeposit: BigNumber, expectedSignal: BigNumber) => {
    // Before state
    const beforeTokenTotalSupply = await grt.totalSupply()
    const beforeCuratorTokens = await grt.balanceOf(gns.address)
    const beforeCuratorSignal = await curation.getCuratorSignal(gns.address, subgraphDeploymentID)
    const beforePool = await curation.pools(subgraphDeploymentID)
    const beforePoolSignal = await curation.getCurationPoolSignal(subgraphDeploymentID)
    const beforeTotalTokens = await grt.balanceOf(curation.address)

    // Curate
    const tx = curation.connect(gnsImpersonator).mintTaxFree(subgraphDeploymentID, tokensToDeposit)
    await expect(tx)
      .emit(curation, 'Signalled')
      .withArgs(gns.address, subgraphDeploymentID, tokensToDeposit, expectedSignal, 0)

    // After state
    const afterTokenTotalSupply = await grt.totalSupply()
    const afterCuratorTokens = await grt.balanceOf(gns.address)
    const afterCuratorSignal = await curation.getCuratorSignal(gns.address, subgraphDeploymentID)
    const afterPool = await curation.pools(subgraphDeploymentID)
    const afterPoolSignal = await curation.getCurationPoolSignal(subgraphDeploymentID)
    const afterTotalTokens = await grt.balanceOf(curation.address)

    // Curator balance updated
    expect(afterCuratorTokens).eq(beforeCuratorTokens.sub(tokensToDeposit))
    expect(afterCuratorSignal).eq(beforeCuratorSignal.add(expectedSignal))
    // Allocated and balance updated
    expect(afterPool.tokens).eq(beforePool.tokens.add(tokensToDeposit))
    expect(afterPoolSignal).eq(beforePoolSignal.add(expectedSignal))
    // Pool reserveRatio is deprecated and therefore always zero in L2
    expect(afterPool.reserveRatio).eq(0)
    // Contract balance updated
    expect(afterTotalTokens).eq(beforeTotalTokens.add(tokensToDeposit))
    // Total supply is reduced to curation tax burning
    expect(afterTokenTotalSupply).eq(beforeTokenTotalSupply)
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
    const tx = curation.connect(curator).burn(subgraphDeploymentID, signalToRedeem, 0)
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
    await grt.connect(stakingMock).transfer(curation.address, tokensToCollect)
    const tx = curation.connect(stakingMock).collect(subgraphDeploymentID, tokensToCollect)
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
    [me, curator, stakingMock] = await graph.getTestAccounts()
    ;({ governor } = await graph.getNamedAccounts())
    fixture = new NetworkFixture(graph.provider)
    contracts = await fixture.load(governor, true)
    curation = contracts.Curation as L2Curation
    grt = contracts.GraphToken as GraphToken
    controller = contracts.Controller
    gns = contracts.GNS as GNS

    gnsImpersonator = await helpers.impersonateAccount(gns.address)
    await helpers.setBalance(gns.address, parseEther('1'))
    // Give some funds to the curator and GNS impersonator and approve the curation contract
    await grt.connect(governor).mint(curator.address, curatorTokens)
    await grt.connect(curator).approve(curation.address, curatorTokens)
    await grt.connect(governor).mint(gns.address, curatorTokens)
    await grt.connect(gnsImpersonator).approve(curation.address, curatorTokens)

    // Give some funds to the staking contract and approve the curation contract
    await grt.connect(governor).mint(stakingMock.address, tokensToCollect)
    await grt.connect(stakingMock).approve(curation.address, tokensToCollect)
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
      await curation.connect(curator).mint(subgraphDeploymentID, tokensToDeposit, 0)

      // Conversion
      const signal = await curation.getCurationPoolSignal(subgraphDeploymentID)
      const expectedTokens = await curation.signalToTokens(subgraphDeploymentID, signal)
      expect(expectedTokens).eq(tokensToDeposit)
    })

    it('convert signal to tokens (with curation tax)', async function () {
      // Set curation tax
      const curationTaxPercentage = 50000 // 5%
      await curation.connect(governor).setCurationTaxPercentage(curationTaxPercentage)

      // Curate
      const expectedCurationTax = tokensToDeposit.mul(curationTaxPercentage).div(MAX_PPM)
      const { 1: curationTax } = await curation.tokensToSignal(
        subgraphDeploymentID,
        tokensToDeposit,
      )
      await curation.connect(curator).mint(subgraphDeploymentID, tokensToDeposit, 0)

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
      const tokens = toGRT('0')
      const tx = curation.tokensToSignal(nonCuratedSubgraphDeploymentID, tokens)
      await expect(tx).revertedWith('Curation deposit is below minimum required')
    })
  })

  describe('curate', function () {
    it('reject deposit below minimum tokens required', async function () {
      // Set the minimum to a value greater than 1 so that we can test
      await curation.connect(governor).setMinimumCurationDeposit(toBN('2'))
      const tokensToDeposit = (await curation.minimumCurationDeposit()).sub(toBN(1))
      const tx = curation.connect(curator).mint(subgraphDeploymentID, tokensToDeposit, 0)
      await expect(tx).revertedWith('Curation deposit is below minimum required')
    })

    it('should deposit on a subgraph deployment', async function () {
      const tokensToDeposit = await curation.minimumCurationDeposit()
      const expectedSignal = signalAmountForMinimumCuration // tax = 0 due to rounding
      await shouldMint(tokensToDeposit, expectedSignal)
    })

    it('should get signal according to bonding curve', async function () {
      const tokensToDeposit = toGRT('1000')
      const expectedSignal = signalAmountFor1000Tokens
      await shouldMint(tokensToDeposit, expectedSignal)
    })

    it('should get signal according to bonding curve (and account for curation tax)', async function () {
      // Set curation tax
      await curation.connect(governor).setCurationTaxPercentage(50000) // 5%

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
        .connect(curator)
        .mint(subgraphDeploymentID, tokensToDeposit, expectedSignal.add(1))
      await expect(tx).revertedWith('Slippage protection')
    })

    it('should pay a minimum of 1 wei GRT in tax when depositing small amounts', async function () {
      // Set minimum curation deposit
      await contracts.Curation.connect(governor).setMinimumCurationDeposit('1')

      // Set curation tax to 1%
      await contracts.Curation.connect(governor).setCurationTaxPercentage(10000)

      // Deposit a small amount where tax would be less than 1 wei
      const tokensToDeposit = '99'

      const expectedTokens = '98'
      const expectedSignal = '98'
      const expectedTax = 1

      const tx = contracts.Curation.connect(curator).mint(
        subgraphDeploymentID,
        tokensToDeposit,
        expectedSignal,
      )

      await expect(tx)
        .emit(contracts.Curation, 'Signalled')
        .withArgs(
          curator.address,
          subgraphDeploymentID,
          tokensToDeposit,
          expectedSignal,
          expectedTax,
        )

      const burnTx = contracts.Curation.connect(curator).burn(
        subgraphDeploymentID,
        expectedSignal,
        expectedTokens,
      )

      await expect(burnTx)
        .emit(contracts.Curation, 'Burned')
        .withArgs(curator.address, subgraphDeploymentID, expectedTokens, expectedSignal)
    })
  })

  describe('curate tax free (from GNS)', function () {
    it('can not be called by anyone other than GNS', async function () {
      const tokensToDeposit = await curation.minimumCurationDeposit()
      const tx = curation.connect(curator).mintTaxFree(subgraphDeploymentID, tokensToDeposit)
      await expect(tx).revertedWith('Only the GNS can call this')
    })

    it('reject deposit below minimum tokens required', async function () {
      // Set the minimum to a value greater than 1 so that we can test
      await curation.connect(governor).setMinimumCurationDeposit(toBN('2'))
      const tokensToDeposit = (await curation.minimumCurationDeposit()).sub(toBN(1))
      const tx = curation
        .connect(gnsImpersonator)
        .mintTaxFree(subgraphDeploymentID, tokensToDeposit)
      await expect(tx).revertedWith('Curation deposit is below minimum required')
    })

    it('should deposit on a subgraph deployment', async function () {
      const tokensToDeposit = await curation.minimumCurationDeposit()
      const expectedSignal = signalAmountForMinimumCuration
      await shouldMintTaxFree(tokensToDeposit, expectedSignal)
    })

    it('should get signal according to bonding curve', async function () {
      const tokensToDeposit = toGRT('1000')
      const expectedSignal = signalAmountFor1000Tokens
      await shouldMintTaxFree(tokensToDeposit, expectedSignal)
    })

    it('should get signal according to bonding curve (and with zero tax)', async function () {
      // Set curation tax
      await curation.connect(governor).setCurationTaxPercentage(50000) // 5%

      // Mint
      const tokensToDeposit = toGRT('1000')
      const expectedSignal = await curation.tokensToSignalNoTax(
        subgraphDeploymentID,
        tokensToDeposit,
      )
      await shouldMintTaxFree(tokensToDeposit, expectedSignal)
    })
  })

  describe('collect', function () {
    context('> not curated', function () {
      it('reject collect tokens distributed to the curation pool', async function () {
        // Source of tokens must be the staking for this to work
        await controller
          .connect(governor)
          .setContractProxy(utils.id('Staking'), stakingMock.address)
        await curation.connect(governor).syncAllContracts() // call sync because we change the proxy for staking

        const tx = curation.connect(stakingMock).collect(subgraphDeploymentID, tokensToCollect)
        await expect(tx).revertedWith('Subgraph deployment must be curated to collect fees')
      })
    })

    context('> curated', function () {
      beforeEach(async function () {
        await curation.connect(curator).mint(subgraphDeploymentID, toGRT('1000'), 0)
      })

      it('reject collect tokens distributed from invalid address', async function () {
        const tx = curation.connect(me).collect(subgraphDeploymentID, tokensToCollect)
        await expect(tx).revertedWith('Caller must be the staking contract')
      })

      it('should collect tokens distributed to the curation pool', async function () {
        await controller
          .connect(governor)
          .setContractProxy(utils.id('Staking'), stakingMock.address)
        await curation.connect(governor).syncAllContracts() // call sync because we change the proxy for staking

        await shouldCollect(toGRT('1'))
        await shouldCollect(toGRT('10'))
        await shouldCollect(toGRT('100'))
        await shouldCollect(toGRT('200'))
        await shouldCollect(toGRT('500.25'))
      })

      it('should collect tokens and then unsignal all', async function () {
        await controller
          .connect(governor)
          .setContractProxy(utils.id('Staking'), stakingMock.address)
        await curation.connect(governor).syncAllContracts() // call sync because we change the proxy for staking

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
          .connect(governor)
          .setContractProxy(utils.id('Staking'), stakingMock.address)
        await curation.connect(governor).syncAllContracts() // call sync because we change the proxy for staking

        // Collect increase the pool reserves
        const tokensToCollect = toGRT('100')
        await shouldCollect(tokensToCollect)

        // Unsignal partially
        const signalOutRemainder = toGRT(1)
        const signalOutPartial = (
          await curation.getCuratorSignal(curator.address, subgraphDeploymentID)
        ).sub(signalOutRemainder)
        const tx1 = await curation.connect(curator).burn(subgraphDeploymentID, signalOutPartial, 0)
        const r1 = await tx1.wait()
        const event1 = curation.interface.parseLog(r1.events[2]).args
        const tokensOut1 = event1.tokens

        // Collect increase the pool reserves
        await shouldCollect(tokensToCollect)

        // Unsignal the rest
        const tx2 = await curation
          .connect(curator)
          .burn(subgraphDeploymentID, signalOutRemainder, 0)
        const r2 = await tx2.wait()
        const event2 = curation.interface.parseLog(r2.events[2]).args
        const tokensOut2 = event2.tokens

        expect(tokensOut1.add(tokensOut2)).eq(toGRT('1000').add(tokensToCollect.mul(2)))
      })
    })
  })

  describe('burn', function () {
    beforeEach(async function () {
      await curation.connect(curator).mint(subgraphDeploymentID, tokensToDeposit, 0)
    })

    it('reject redeem more than a curator owns', async function () {
      const tx = curation.connect(me).burn(subgraphDeploymentID, toGRT('1'), 0)
      await expect(tx).revertedWith('Cannot burn more signal than you own')
    })

    it('reject redeem zero signal', async function () {
      const tx = curation.connect(me).burn(subgraphDeploymentID, toGRT('0'), 0)
      await expect(tx).revertedWith('Cannot burn zero signal')
    })

    it('should allow to redeem *partially*', async function () {
      // Redeem just one signal
      const signalToRedeem = toGRT('1')
      const expectedTokens = toGRT('1')
      await shouldBurn(signalToRedeem, expectedTokens)
    })

    it('should allow to redeem *fully*', async function () {
      // Get all signal of the curator
      const signalToRedeem = await curation.getCuratorSignal(curator.address, subgraphDeploymentID)
      const expectedTokens = tokensToDeposit
      await shouldBurn(signalToRedeem, expectedTokens)
    })

    it('should allow to redeem back below minimum deposit', async function () {
      // Set the minimum to a value greater than 1 so that we can test
      await curation.connect(governor).setMinimumCurationDeposit(toGRT('1'))

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
        .connect(curator)
        .burn(subgraphDeploymentID, signalToRedeem, expectedTokens.add(1))
      await expect(tx).revertedWith('Slippage protection')
    })

    it('should not re-deploy the curation token when signal is reset', async function () {
      const beforeSubgraphPool = await curation.pools(subgraphDeploymentID)

      // Burn all the signal
      const signalToRedeem = await curation.getCuratorSignal(curator.address, subgraphDeploymentID)
      const expectedTokens = tokensToDeposit
      await shouldBurn(signalToRedeem, expectedTokens)

      // Mint again on the same subgraph
      await curation.connect(curator).mint(subgraphDeploymentID, tokensToDeposit, 0)

      // Check state
      const afterSubgraphPool = await curation.pools(subgraphDeploymentID)
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
        const tx = await curation.connect(curator).mint(subgraphDeploymentID, tokensToDeposit, 0)
        const receipt = await tx.wait()
        const event: Event = receipt.events.pop()
        const signal = event.args['signal']
        totalSignal = totalSignal.add(signal)
      }

      // Redeem signal multiple times
      let totalTokens = toGRT('0')
      for (const signalToRedeem of chunkify(totalSignal, 10)) {
        const tx = await curation.connect(curator).burn(subgraphDeploymentID, signalToRedeem, 0)
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

  describe('multiple minting', function () {
    it('should mint the same signal every time due to the flat bonding curve', async function () {
      const tokensToDepositMany = [
        toGRT('1000'), // should mint if we start with number above minimum deposit
        toGRT('1000'), // every time it should mint the same GCS due to bonding curve!
        toGRT('1000'),
        toGRT('1000'),
        toGRT('2000'),
        toGRT('2000'),
        toGRT('123'),
        toGRT('1'), // should mint below minimum deposit
      ]
      for (const tokensToDeposit of tokensToDepositMany) {
        const expectedSignal = await calcLinearBondingCurve(
          await curation.getCurationPoolSignal(subgraphDeploymentID),
          await curation.getCurationPoolTokens(subgraphDeploymentID),
          tokensToDeposit,
        )
        // SIGNAL_PER_MINIMUM_DEPOSIT should always give the same ratio
        expect(tokensToDeposit.div(toGRT(expectedSignal))).eq(1)

        const tx = await curation.connect(curator).mint(subgraphDeploymentID, tokensToDeposit, 0)
        const receipt = await tx.wait()
        const event: Event = receipt.events.pop()
        const signal = event.args['signal']
        expect(toRound(toFloat(toBN(signal)))).eq(toRound(expectedSignal))
      }
    })

    it('should mint when using a different ratio between GRT and signal', async function () {
      this.timeout(60000) // increase timeout for test runner

      // Setup edge case with 1 GRT = 1 wei signal
      await curation.connect(governor).setMinimumCurationDeposit(toGRT('1'))

      const tokensToDepositMany = [
        toGRT('1000'), // should mint if we start with number above minimum deposit
        toGRT('1000'), // every time it should mint proportionally the same GCS due to linear bonding curve...
        toGRT('1000'),
        toGRT('1000'),
        toGRT('2000'),
        toGRT('2000'),
        toGRT('123'),
        toGRT('1'),
      ]

      // Mint multiple times
      for (const tokensToDeposit of tokensToDepositMany) {
        const tx = await curation.connect(curator).mint(subgraphDeploymentID, tokensToDeposit, 0)
        const receipt = await tx.wait()
        const event: Event = receipt.events.pop()
        const signal = event.args['signal']
        expect(tokensToDeposit).eq(signal.mul(toGRT('1'))) // we compare 1 GRT : 1 wei ratio
      }
    })
  })
})
