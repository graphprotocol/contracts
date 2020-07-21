import { expect } from 'chai'
import { BigNumber, Event } from 'ethers'

import { Curation } from '../../build/typechain/contracts/Curation'
import { GraphToken } from '../../build/typechain/contracts/GraphToken'

import { NetworkFixture } from '../lib/fixtures'
import { getAccounts, randomHexBytes, toBN, toGRT, Account } from '../lib/testHelpers'

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

describe('Curation', () => {
  let me: Account
  let governor: Account
  let curator: Account
  let stakingMock: Account

  let fixture: NetworkFixture

  let curation: Curation
  let grt: GraphToken

  // Test values
  const signalAmountFor1000Tokens = toGRT('3.162277660168379331')
  const subgraphDeploymentID = randomHexBytes()
  const curatorTokens = toGRT('1000000000')
  const tokensToStake = toGRT('1000')
  const tokensToCollect = toGRT('2000')

  const shouldSignal = async (tokensToStake: BigNumber, expectedSignal: BigNumber) => {
    const defaultReserveRatio = await curation.defaultReserveRatio()

    // Before state
    const beforeCuratorTokens = await grt.balanceOf(curator.address)
    const beforeCuratorSignal = await curation.getCuratorSignal(
      curator.address,
      subgraphDeploymentID,
    )
    const beforePool = await curation.pools(subgraphDeploymentID)
    const beforeTotalBalance = await grt.balanceOf(curation.address)

    // Curate
    const tx = curation.connect(curator.signer).mint(subgraphDeploymentID, tokensToStake)
    await expect(tx)
      .emit(curation, 'Signalled')
      .withArgs(curator.address, subgraphDeploymentID, tokensToStake, expectedSignal)

    // After state
    const afterCuratorTokens = await grt.balanceOf(curator.address)
    const afterCuratorSignal = await curation.getCuratorSignal(
      curator.address,
      subgraphDeploymentID,
    )
    const afterPool = await curation.pools(subgraphDeploymentID)
    const afterTotalBalance = await grt.balanceOf(curation.address)

    // Tokens transferred properly
    expect(afterCuratorTokens).eq(beforeCuratorTokens.sub(tokensToStake))
    expect(afterCuratorSignal).eq(beforeCuratorSignal.add(expectedSignal))
    // Allocated and balance updated
    expect(afterPool.tokens).eq(beforePool.tokens.add(tokensToStake))
    expect(afterPool.signal).eq(beforePool.signal.add(expectedSignal))
    expect(afterPool.reserveRatio).eq(defaultReserveRatio)
    // Contract balance updated
    expect(afterTotalBalance).eq(beforeTotalBalance.add(tokensToStake))
    // Uses default reserve ratio
    expect(afterPool.reserveRatio).eq(await curation.defaultReserveRatio())
  }

  const shouldRedeem = async (signalToRedeem: BigNumber, expectedTokens: BigNumber) => {
    // Before balances
    const beforeTokenTotalSupply = await grt.totalSupply()
    const beforeCuratorTokens = await grt.balanceOf(curator.address)
    const beforeCuratorSignal = await curation.getCuratorSignal(
      curator.address,
      subgraphDeploymentID,
    )
    const poolBefore = await curation.pools(subgraphDeploymentID)
    const totalTokensBefore = await grt.balanceOf(curation.address)

    // Calculations
    const withdrawalFeePercentage = await curation.withdrawalFeePercentage()
    const withdrawalFees = toBN(withdrawalFeePercentage).mul(expectedTokens).div(toBN(MAX_PPM))

    // Redeem
    const tx = curation.connect(curator.signer).burn(subgraphDeploymentID, signalToRedeem)
    await expect(tx)
      .emit(curation, 'Burned')
      .withArgs(
        curator.address,
        subgraphDeploymentID,
        expectedTokens.sub(withdrawalFees),
        signalToRedeem,
        withdrawalFees,
      )

    // After balances
    const afterTokenTotalSupply = await grt.totalSupply()
    const afterCuratorTokens = await grt.balanceOf(curator.address)
    const afterCuratorSignal = await curation.getCuratorSignal(
      curator.address,
      subgraphDeploymentID,
    )
    const afterPool = await curation.pools(subgraphDeploymentID)
    const afterTotalTokens = await grt.balanceOf(curation.address)

    // Curator balance updated
    expect(afterCuratorTokens).eq(beforeCuratorTokens.add(expectedTokens).sub(withdrawalFees))
    expect(afterCuratorSignal).eq(beforeCuratorSignal.sub(signalToRedeem))
    // Curation balance updated
    expect(afterPool.tokens).eq(poolBefore.tokens.sub(expectedTokens))
    expect(afterPool.signal).eq(poolBefore.signal.sub(signalToRedeem))
    // Contract balance updated
    expect(afterTotalTokens).eq(totalTokensBefore.sub(expectedTokens))
    // Withdrawal fees are burned
    expect(afterTokenTotalSupply).eq(beforeTokenTotalSupply.sub(withdrawalFees))
  }

  const shouldCollect = async (tokensToCollect: BigNumber) => {
    // Before state
    const beforePool = await curation.pools(subgraphDeploymentID)
    const beforeTotalBalance = await grt.balanceOf(curation.address)

    // Source of tokens must be the staking for this to work
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
    ;[me, governor, curator, stakingMock] = await getAccounts()

    fixture = new NetworkFixture()
    ;({ curation, grt } = await fixture.load(governor.signer))

    // Replace the staking contract with a mock so we can call collect
    await curation.connect(governor.signer).setStaking(stakingMock.address)

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
    const tokensToStake = curatorTokens

    it('reject convert signal to tokens if subgraph deployment not initted', async function () {
      const tx = curation.signalToTokens(subgraphDeploymentID, toGRT('100'))
      await expect(tx).revertedWith('Subgraph deployment must be curated to perform calculations')
    })

    it('convert signal to tokens', async function () {
      // Curate
      await curation.connect(curator.signer).mint(subgraphDeploymentID, tokensToStake)

      // Conversion
      const signal = (await curation.pools(subgraphDeploymentID)).signal
      const tokens = await curation.signalToTokens(subgraphDeploymentID, signal)
      expect(tokens).eq(tokensToStake)
    })

    it('convert tokens to signal', async function () {
      // Conversion
      const tokens = toGRT('1000')
      const signal = await curation.tokensToSignal(subgraphDeploymentID, tokens)
      expect(signal).eq(signalAmountFor1000Tokens)
    })
  })

  describe('curate', async function () {
    it('reject stake below minimum tokens required', async function () {
      const tokensToStake = (await curation.minimumCurationStake()).sub(toBN(1))
      const tx = curation.connect(curator.signer).mint(subgraphDeploymentID, tokensToStake)
      await expect(tx).revertedWith('Curation stake is below minimum required')
    })

    it('should stake on a subgraph deployment', async function () {
      const tokensToStake = await curation.minimumCurationStake()
      const expectedSignal = toGRT('1')
      await shouldSignal(tokensToStake, expectedSignal)
    })

    it('should assign the right amount of signal according to bonding curve', async function () {
      const tokensToStake = toGRT('1000')
      const expectedSignal = signalAmountFor1000Tokens
      await shouldSignal(tokensToStake, expectedSignal)
    })
  })

  describe('collect', async function () {
    context('> not curated', async function () {
      it('reject collect tokens distributed to the curation pool', async function () {
        // Source of tokens must be the staking for this to work
        const tx = curation
          .connect(stakingMock.signer)
          .collect(subgraphDeploymentID, tokensToCollect)
        await expect(tx).revertedWith('Subgraph deployment must be curated to collect fees')
      })
    })

    context('> curated', async function () {
      beforeEach(async function () {
        await curation.connect(curator.signer).mint(subgraphDeploymentID, toGRT('1000'))
      })

      it('reject collect tokens distributed from invalid address', async function () {
        const tx = curation.connect(me.signer).collect(subgraphDeploymentID, tokensToCollect)
        await expect(tx).revertedWith('Caller must be the staking contract')
      })

      it('should collect tokens distributed to the curation pool', async function () {
        await shouldCollect(toGRT('1'))
        await shouldCollect(toGRT('10'))
        await shouldCollect(toGRT('100'))
        await shouldCollect(toGRT('200'))
        await shouldCollect(toGRT('500.25'))
      })
    })
  })

  describe('redeem', async function () {
    beforeEach(async function () {
      await curation.connect(curator.signer).mint(subgraphDeploymentID, tokensToStake)
    })

    it('reject redeem more than a curator owns', async function () {
      const tx = curation.connect(me.signer).burn(subgraphDeploymentID, toGRT('1'))
      await expect(tx).revertedWith('Cannot burn more signal than you own')
    })

    it('reject redeem zero signal', async function () {
      const tx = curation.connect(me.signer).burn(subgraphDeploymentID, toGRT('0'))
      await expect(tx).revertedWith('Cannot burn zero signal')
    })

    it('should allow to redeem *partially*', async function () {
      // Redeem just one signal
      const signalToRedeem = toGRT('1')
      const expectedTokens = toGRT('532.455532033675866536')
      await shouldRedeem(signalToRedeem, expectedTokens)
    })

    it('should allow to redeem *fully*', async function () {
      // Get all signal of the curator
      const signalToRedeem = await curation.getCuratorSignal(curator.address, subgraphDeploymentID)
      const expectedTokens = tokensToStake
      await shouldRedeem(signalToRedeem, expectedTokens)
    })

    it('should allow to redeem back below minimum stake', async function () {
      // Redeem "almost" all signal
      const signal = await curation.getCuratorSignal(curator.address, subgraphDeploymentID)
      const signalToRedeem = signal.sub(toGRT('0.000001'))
      const expectedTokens = await curation.signalToTokens(subgraphDeploymentID, signalToRedeem)
      await shouldRedeem(signalToRedeem, expectedTokens)

      // The pool should have less tokens that required by minimumCurationStake
      const afterPool = await curation.pools(subgraphDeploymentID)
      expect(afterPool.tokens).lt(await curation.minimumCurationStake())

      // Should be able to stake more after being under minimumCurationStake
      const tokensToStake = toGRT('1')
      const expectedSignal = await curation.tokensToSignal(subgraphDeploymentID, tokensToStake)
      await shouldSignal(tokensToStake, expectedSignal)
    })

    it('should allow to redeem and account for withdrawal fees', async function () {
      await curation.connect(governor.signer).setWithdrawalFeePercentage(50000)

      // Get all signal of the curator
      const signalToRedeem = await curation.getCuratorSignal(curator.address, subgraphDeploymentID)
      const expectedTokens = tokensToStake
      await shouldRedeem(signalToRedeem, expectedTokens)
    })
  })

  describe('conservation', async function () {
    it('should match multiple stakes and redeems back to initial state', async function () {
      const totalStakes = toGRT('1000000000')

      // Stake multiple times
      let totalSignal = toGRT('0')
      for (const tokensToStake of chunkify(totalStakes, 10)) {
        const tx = await curation.connect(curator.signer).mint(subgraphDeploymentID, tokensToStake)
        const receipt = await tx.wait()
        const event: Event = receipt.events.pop()
        const signal = event.args['signal']
        totalSignal = totalSignal.add(signal)
        // console.log('>', formatEther(tokensToStake), '=', formatEther(signal))
      }

      // Redeem signal multiple times
      let totalTokens = toGRT('0')
      for (const signalToRedeem of chunkify(totalSignal, 10)) {
        const tx = await curation.connect(curator.signer).burn(subgraphDeploymentID, signalToRedeem)
        const receipt = await tx.wait()
        const event: Event = receipt.events.pop()
        const tokens = event.args['tokens']
        totalTokens = totalTokens.add(tokens)
        // console.log('<', formatEther(signalToRedeem), '=', formatEther(tokens))
      }

      // Conservation of work
      const afterPool = await curation.pools(subgraphDeploymentID)
      expect(afterPool.tokens).eq(toGRT('0'))
      expect(afterPool.signal).eq(toGRT('0'))
      expect(await curation.isCurated(subgraphDeploymentID)).eq(false)
      expect(totalStakes).eq(totalTokens)
    })
  })
})
