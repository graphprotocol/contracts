import { expect, use } from 'chai'
import { BigNumber } from 'ethers'
import { solidity } from 'ethereum-waffle'

import { Curation } from '../../build/typechain/contracts/Curation'
import { GraphToken } from '../../build/typechain/contracts/GraphToken'

import { defaults, provider, randomHexBytes, toBN, toGRT } from '../lib/testHelpers'
import { loadFixture } from './fixture.test'

use(solidity)

const MAX_PPM = 1000000

describe('Curation', () => {
  const [me, governor, curator, staking] = provider().getWallets()

  let curation: Curation
  let grt: GraphToken

  // Test values
  const shareAmountFor1000Tokens = toGRT('3.162277660168379331')
  const subgraphDeploymentID = randomHexBytes()
  const curatorTokens = toGRT('1000')
  const tokensToCollect = toGRT('2000')

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
    // const tokensToRedeem = await curation.sharesToTokens(subgraphDeploymentID, sharesToRedeem)
    const withdrawalFeePercentage = await curation.withdrawalFeePercentage()
    const withdrawalFees = withdrawalFeePercentage.mul(expectedTokens).div(toBN(MAX_PPM))

    // Redeem
    const tx = curation.connect(curator).redeem(subgraphDeploymentID, sharesToRedeem)
    await expect(tx)
      .emit(curation, 'Redeemed')
      .withArgs(
        curator.address,
        subgraphDeploymentID,
        expectedTokens,
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
    expect(afterCuratorTokens).eq(beforeCuratorTokens.add(expectedTokens))
    expect(afterCuratorShares).eq(beforeCuratorShares.sub(sharesToRedeem))
    // Curation balance updated
    expect(afterPool.tokens).eq(poolBefore.tokens.sub(expectedTokens))
    expect(afterPool.shares).eq(poolBefore.shares.sub(sharesToRedeem))
    // Contract balance updated
    expect(afterTotalTokens).eq(totalTokensBefore.sub(expectedTokens))
    // Withdrawal fees are burned
    expect(afterTokenTotalSupply).eq(beforeTokenTotalSupply.sub(withdrawalFees))
  }

  beforeEach(async function () {
    ;({ curation, grt } = await loadFixture(governor, staking))

    // Give some funds to the curator and approve the curation contract
    await grt.connect(governor).mint(curator.address, curatorTokens)
    await grt.connect(curator).approve(curation.address, curatorTokens)

    // Give some funds to the staking contract and approve the curation contract
    await grt.connect(governor).mint(staking.address, tokensToCollect)
    await grt.connect(staking).approve(curation.address, tokensToCollect)
  })

  describe('bonding curve', function () {
    const tokensToStake = curatorTokens

    it('reject convert shares to tokens if subgraph deployment not initted', async function () {
      const tx = curation.sharesToTokens(subgraphDeploymentID, toGRT('100'))
      await expect(tx).revertedWith('SubgraphDeployment must be curated to perform calculations')
    })

    it('convert shares to tokens', async function () {
      // Curate
      await curation.connect(curator).stake(subgraphDeploymentID, tokensToStake)

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
    const shouldStake = async (tokensToStake: BigNumber, expectedShares: BigNumber) => {
      // Before state
      const beforeCuratorTokens = await grt.balanceOf(curator.address)
      const beforeCuratorShares = await curation.getCuratorShares(
        curator.address,
        subgraphDeploymentID,
      )
      const beforePool = await curation.pools(subgraphDeploymentID)
      const beforeTotalBalance = await grt.balanceOf(curation.address)

      // Curate
      const tx = curation.connect(curator).stake(subgraphDeploymentID, tokensToStake)
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
      expect(afterPool.reserveRatio).eq(defaults.curation.reserveRatio)
      // Contract balance updated
      expect(afterTotalBalance).eq(beforeTotalBalance.add(tokensToStake))
      // Uses default reserve ratio
      expect(afterPool.reserveRatio).eq(await curation.defaultReserveRatio())
    }

    it('reject stake below minimum tokens required', async function () {
      const tokensToStake = (await curation.minimumCurationStake()).sub(toBN(1))
      const tx = curation.connect(curator).stake(subgraphDeploymentID, tokensToStake)
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
        const tx = curation.connect(staking).collect(subgraphDeploymentID, tokensToCollect)
        await expect(tx).revertedWith('SubgraphDeployment must be curated to collect fees')
      })
    })

    context('> curated', async function () {
      const shouldCollect = async (tokensToCollect: BigNumber) => {
        // Before state
        const beforePool = await curation.pools(subgraphDeploymentID)
        const beforeTotalBalance = await grt.balanceOf(curation.address)

        // Source of tokens must be the staking for this to work
        const tx = curation.connect(staking).collect(subgraphDeploymentID, tokensToCollect)
        await expect(tx).emit(curation, 'Collected').withArgs(subgraphDeploymentID, tokensToCollect)

        // After state
        const afterPool = await curation.pools(subgraphDeploymentID)
        const afterTotalBalance = await grt.balanceOf(curation.address)

        // State updated
        expect(afterPool.tokens).eq(beforePool.tokens.add(tokensToCollect))
        expect(afterTotalBalance).eq(beforeTotalBalance.add(tokensToCollect))
      }

      beforeEach(async function () {
        await curation.connect(curator).stake(subgraphDeploymentID, toGRT('1000'))
      })

      it('reject collect tokens distributed from invalid address', async function () {
        const tx = curation.connect(me).collect(subgraphDeploymentID, tokensToCollect)
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
    const tokensToStake = curatorTokens

    beforeEach(async function () {
      await curation.connect(curator).stake(subgraphDeploymentID, tokensToStake)
    })

    it('reject redeem more than a curator owns', async function () {
      const tx = curation.connect(me).redeem(subgraphDeploymentID, toGRT('1'))
      await expect(tx).revertedWith('Cannot redeem more shares than you own')
    })

    it('reject redeem zero shares', async function () {
      const tx = curation.connect(me).redeem(subgraphDeploymentID, toGRT('0'))
      await expect(tx).revertedWith('Cannot redeem zero shares')
    })

    it('should allow to redeem *partially*', async function () {
      // Redeem just one share
      await shouldRedeem(toGRT('1'), toGRT('532.455532033675866536'))
    })

    it('should allow to redeem *fully*', async function () {
      // Get all shares of the curator
      const shares = await curation.getCuratorShares(curator.address, subgraphDeploymentID)
      await shouldRedeem(shares, tokensToStake)
    })
  })
})
