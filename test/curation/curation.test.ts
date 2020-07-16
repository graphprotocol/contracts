import { expect, use } from 'chai'
import { BigNumber, Event } from 'ethers'
import { solidity } from 'ethereum-waffle'

import { Curation } from '../../build/typechain/contracts/Curation'
import { GraphToken } from '../../build/typechain/contracts/GraphToken'

import { NetworkFixture } from '../lib/fixtures'
import { getAccounts, randomHexBytes, toBN, toGRT, Account } from '../lib/testHelpers'

use(solidity)

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
  const shareAmountFor1000Tokens = toGRT('3.162277660168379331')
  const subgraphDeploymentID = randomHexBytes()
  const curatorTokens = toGRT('1000000000')
  const tokensToStake = toGRT('1000')
  const tokensToCollect = toGRT('2000')

  const shouldStake = async (tokensToStake: BigNumber, expectedShares: BigNumber) => {
    const defaultReserveRatio = await curation.defaultReserveRatio()

    // Before state
    const beforeCuratorTokens = await grt.balanceOf(curator.address)
    const beforeCuratorShares = await curation.getCuratorShares(
      curator.address,
      subgraphDeploymentID,
    )
    const beforePool = await curation.pools(subgraphDeploymentID)
    const beforeTotalBalance = await grt.balanceOf(curation.address)

    // Curate
    const tx = curation.connect(curator.signer).stake(subgraphDeploymentID, tokensToStake)
    await expect(tx)
      .emit(curation, 'Staked')
      .withArgs(curator.address, subgraphDeploymentID, tokensToStake, expectedShares)

    // After state
    const afterCuratorTokens = await grt.balanceOf(curator.address)
    const afterCuratorShares = await curation.getCuratorShares(
      curator.address,
      subgraphDeploymentID,
    )
    const afterPool = await curation.pools(subgraphDeploymentID)
    const afterTotalBalance = await grt.balanceOf(curation.address)

    // Tokens transferred properly
    expect(afterCuratorTokens).eq(beforeCuratorTokens.sub(tokensToStake))
    expect(afterCuratorShares).eq(beforeCuratorShares.add(expectedShares))
    // Allocated and balance updated
    expect(afterPool.tokens).eq(beforePool.tokens.add(tokensToStake))
    expect(afterPool.shares).eq(beforePool.shares.add(expectedShares))
    expect(afterPool.reserveRatio).eq(defaultReserveRatio)
    // Contract balance updated
    expect(afterTotalBalance).eq(beforeTotalBalance.add(tokensToStake))
    // Uses default reserve ratio
    expect(afterPool.reserveRatio).eq(await curation.defaultReserveRatio())
  }

  const shouldRedeem = async (sharesToRedeem: BigNumber, expectedTokens: BigNumber) => {
    // Before balances
    const beforeTokenTotalSupply = await grt.totalSupply()
    const beforeCuratorTokens = await grt.balanceOf(curator.address)
    const beforeCuratorShares = await curation.getCuratorShares(
      curator.address,
      subgraphDeploymentID,
    )
    const poolBefore = await curation.pools(subgraphDeploymentID)
    const totalTokensBefore = await grt.balanceOf(curation.address)

    // Calculations
    const withdrawalFeePercentage = await curation.withdrawalFeePercentage()
    const withdrawalFees = toBN(withdrawalFeePercentage).mul(expectedTokens).div(toBN(MAX_PPM))

    // Redeem
    const tx = curation.connect(curator.signer).redeem(subgraphDeploymentID, sharesToRedeem)
    await expect(tx)
      .emit(curation, 'Redeemed')
      .withArgs(
        curator.address,
        subgraphDeploymentID,
        expectedTokens.sub(withdrawalFees),
        sharesToRedeem,
        withdrawalFees,
      )

    // After balances
    const afterTokenTotalSupply = await grt.totalSupply()
    const afterCuratorTokens = await grt.balanceOf(curator.address)
    const afterCuratorShares = await curation.getCuratorShares(
      curator.address,
      subgraphDeploymentID,
    )
    const afterPool = await curation.pools(subgraphDeploymentID)
    const afterTotalTokens = await grt.balanceOf(curation.address)

    // Curator balance updated
    expect(afterCuratorTokens).eq(beforeCuratorTokens.add(expectedTokens).sub(withdrawalFees))
    expect(afterCuratorShares).eq(beforeCuratorShares.sub(sharesToRedeem))
    // Curation balance updated
    expect(afterPool.tokens).eq(poolBefore.tokens.sub(expectedTokens))
    expect(afterPool.shares).eq(poolBefore.shares.sub(sharesToRedeem))
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

    it('reject convert shares to tokens if subgraph deployment not initted', async function () {
      const tx = curation.sharesToTokens(subgraphDeploymentID, toGRT('100'))
      await expect(tx).revertedWith('SubgraphDeployment must be curated to perform calculations')
    })

    it('convert shares to tokens', async function () {
      // Curate
      await curation.connect(curator.signer).stake(subgraphDeploymentID, tokensToStake)

      // Conversion
      const shares = (await curation.pools(subgraphDeploymentID)).shares
      const tokens = await curation.sharesToTokens(subgraphDeploymentID, shares)
      expect(tokens).eq(tokensToStake)
    })

    it('convert tokens to shares', async function () {
      // Conversion
      const tokens = toGRT('1000')
      const shares = await curation.tokensToShares(subgraphDeploymentID, tokens)
      expect(shares).eq(shareAmountFor1000Tokens)
    })
  })

  describe('curate', async function () {
    it('reject stake below minimum tokens required', async function () {
      const tokensToStake = (await curation.minimumCurationStake()).sub(toBN(1))
      const tx = curation.connect(curator.signer).stake(subgraphDeploymentID, tokensToStake)
      await expect(tx).revertedWith('Curation stake is below minimum required')
    })

    it('should stake on a subgraph deployment', async function () {
      const tokensToStake = await curation.minimumCurationStake()
      const expectedShares = toGRT('1')
      await shouldStake(tokensToStake, expectedShares)
    })

    it('should assign the right amount of shares according to bonding curve', async function () {
      const tokensToStake = toGRT('1000')
      const expectedShares = shareAmountFor1000Tokens
      await shouldStake(tokensToStake, expectedShares)
    })
  })

  describe('collect', async function () {
    context('> not curated', async function () {
      it('reject collect tokens distributed to the curation pool', async function () {
        // Source of tokens must be the staking for this to work
        const tx = curation
          .connect(stakingMock.signer)
          .collect(subgraphDeploymentID, tokensToCollect)
        await expect(tx).revertedWith('SubgraphDeployment must be curated to collect fees')
      })
    })

    context('> curated', async function () {
      beforeEach(async function () {
        await curation.connect(curator.signer).stake(subgraphDeploymentID, toGRT('1000'))
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
      await curation.connect(curator.signer).stake(subgraphDeploymentID, tokensToStake)
    })

    it('reject redeem more than a curator owns', async function () {
      const tx = curation.connect(me.signer).redeem(subgraphDeploymentID, toGRT('1'))
      await expect(tx).revertedWith('Cannot redeem more shares than you own')
    })

    it('reject redeem zero shares', async function () {
      const tx = curation.connect(me.signer).redeem(subgraphDeploymentID, toGRT('0'))
      await expect(tx).revertedWith('Cannot redeem zero shares')
    })

    it('should allow to redeem *partially*', async function () {
      // Redeem just one share
      const sharesToRedeem = toGRT('1')
      const expectedTokens = toGRT('532.455532033675866536')
      await shouldRedeem(sharesToRedeem, expectedTokens)
    })

    it('should allow to redeem *fully*', async function () {
      // Get all shares of the curator
      const sharesToRedeem = await curation.getCuratorShares(curator.address, subgraphDeploymentID)
      const expectedTokens = tokensToStake
      await shouldRedeem(sharesToRedeem, expectedTokens)
    })

    it('should allow to redeem back below minimum stake', async function () {
      // Redeem "almost" all shares
      const shares = await curation.getCuratorShares(curator.address, subgraphDeploymentID)
      const sharesToRedeem = shares.sub(toGRT('0.000001'))
      const expectedTokens = await curation.sharesToTokens(subgraphDeploymentID, sharesToRedeem)
      await shouldRedeem(sharesToRedeem, expectedTokens)

      // The pool should have less tokens that required by minimumCurationStake
      const afterPool = await curation.pools(subgraphDeploymentID)
      expect(afterPool.tokens).lt(await curation.minimumCurationStake())

      // Should be able to stake more after being under minimumCurationStake
      const tokensToStake = toGRT('1')
      const expectedShares = await curation.tokensToShares(subgraphDeploymentID, tokensToStake)
      await shouldStake(tokensToStake, expectedShares)
    })

    it('should allow to redeem and account for withdrawal fees', async function () {
      await curation.connect(governor.signer).setWithdrawalFeePercentage(50000)

      // Get all shares of the curator
      const sharesToRedeem = await curation.getCuratorShares(curator.address, subgraphDeploymentID)
      const expectedTokens = tokensToStake
      await shouldRedeem(sharesToRedeem, expectedTokens)
    })
  })

  describe('conservation', async function () {
    it('should match multiple stakes and redeems back to initial state', async function () {
      const totalStakes = toGRT('1000000000')

      // Stake multiple times
      let totalShares = toGRT('0')
      for (const tokensToStake of chunkify(totalStakes, 10)) {
        const tx = await curation.connect(curator.signer).stake(subgraphDeploymentID, tokensToStake)
        const receipt = await tx.wait()
        const event: Event = receipt.events.pop()
        const shares = event.args['shares']
        totalShares = totalShares.add(shares)
        // console.log('>', formatEther(tokensToStake), '=', formatEther(shares))
      }

      // Redeem shares multiple times
      let totalTokens = toGRT('0')
      for (const sharesToRedeem of chunkify(totalShares, 10)) {
        const tx = await curation
          .connect(curator.signer)
          .redeem(subgraphDeploymentID, sharesToRedeem)
        const receipt = await tx.wait()
        const event: Event = receipt.events.pop()
        const tokens = event.args['tokens']
        totalTokens = totalTokens.add(tokens)
        // console.log('<', formatEther(sharesToRedeem), '=', formatEther(tokens))
      }

      // Conservation of work
      const afterPool = await curation.pools(subgraphDeploymentID)
      expect(afterPool.tokens).eq(toGRT('0'))
      expect(afterPool.shares).eq(toGRT('0'))
      expect(await curation.isCurated(subgraphDeploymentID)).eq(false)
      expect(totalStakes).eq(totalTokens)
    })
  })
})
