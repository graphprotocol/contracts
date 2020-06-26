import { expect, use } from 'chai'
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
  const shareAmountFor1000Tokens = toBN('3162277660168379331')
  const subgraphDeploymentID = randomHexBytes()
  const curatorTokens = toGRT('1000')
  const tokensToCollect = toGRT('1000')

  beforeEach(async function() {
    ;({ curation, grt } = await loadFixture(governor, staking))

    // Give some funds to the curator and approve the curation contract
    await grt.connect(governor).mint(curator.address, curatorTokens)
    await grt.connect(curator).approve(curation.address, curatorTokens)

    // Give some funds to the staking contract and approve the curation contract
    await grt.connect(governor).mint(staking.address, tokensToCollect)
    await grt.connect(staking).approve(curation.address, tokensToCollect)
  })

  describe('bonding curve', function() {
    it('reject convert shares to tokens if subgraph deployment not initted', async function() {
      const tx = curation.sharesToTokens(subgraphDeploymentID, toGRT('100'))
      await expect(tx).revertedWith('SubgraphDeployment must be curated to perform calculations')
    })

    it('convert shares to tokens', async function() {
      // Curate
      await curation.connect(curator).stake(subgraphDeploymentID, curatorTokens)

      // Conversion
      const shares = (await curation.pools(subgraphDeploymentID)).shares
      const tokens = await curation.sharesToTokens(subgraphDeploymentID, shares)
      expect(tokens).eq(curatorTokens)
    })

    it('convert tokens to shares', async function() {
      // Conversion
      const tokens = toGRT('1000')
      const shares = await curation.tokensToShares(subgraphDeploymentID, tokens)
      expect(shares).eq(shareAmountFor1000Tokens)
    })
  })

  describe('curate', async function() {
    it('reject stake below minimum tokens required', async function() {
      const tokensToStake = (await curation.minimumCurationStake()).sub(toBN(1))
      const tx = curation.connect(curator).stake(subgraphDeploymentID, tokensToStake)
      await expect(tx).revertedWith('Curation stake is below minimum required')
    })

    it('should stake on a subgraph deployment', async function() {
      // Before state
      const beforeCuratorTokens = await grt.balanceOf(curator.address)
      const beforeCuratorShares = await curation.getCuratorShares(
        curator.address,
        subgraphDeploymentID,
      )
      const beforePool = await curation.pools(subgraphDeploymentID)
      const beforeTotalBalance = await grt.balanceOf(curation.address)

      // Calculate stake the minimum required = 1 share
      const tokensToStake = await curation.minimumCurationStake()
      const sharesToReceive = toGRT('1')

      // Curate
      const tx = curation.connect(curator).stake(subgraphDeploymentID, tokensToStake)
      await expect(tx)
        .emit(curation, 'Staked')
        .withArgs(curator.address, subgraphDeploymentID, tokensToStake, sharesToReceive)

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
      expect(afterCuratorShares).eq(beforeCuratorShares.add(sharesToReceive))
      // Allocated and balance updated
      expect(afterPool.tokens).eq(beforePool.tokens.add(tokensToStake))
      expect(afterPool.shares).eq(beforePool.shares.add(sharesToReceive))
      expect(afterPool.reserveRatio).eq(defaults.curation.reserveRatio)
      // Contract balance updated
      expect(afterTotalBalance).eq(beforeTotalBalance.add(tokensToStake))
      // Uses default reserve ratio
      expect(afterPool.reserveRatio).eq(await curation.defaultReserveRatio())
    })

    it('should assign the right amount of shares according to bonding curve', async function() {
      await curation.connect(curator).stake(subgraphDeploymentID, toGRT('1000'))

      // Shares should be the ones bought with minimum stake (1) + more shares
      const curatorShares = await curation.getCuratorShares(curator.address, subgraphDeploymentID)
      expect(curatorShares).eq(shareAmountFor1000Tokens)
    })
  })

  describe('collect', async function() {
    context('> not curated', async function() {
      it('reject collect tokens distributed to the curation pool', async function() {
        // Source of tokens must be the staking for this to work
        const tx = curation.connect(staking).collect(subgraphDeploymentID, tokensToCollect)
        await expect(tx).revertedWith('SubgraphDeployment must be curated to collect fees')
      })
    })

    context('> curated', async function() {
      beforeEach(async function() {
        await curation.connect(curator).stake(subgraphDeploymentID, toGRT('1000'))
      })

      it('should collect tokens distributed to the curation pool', async function() {
        // Before state
        const beforePool = await curation.pools(subgraphDeploymentID)
        const beforeTotalBalance = await grt.balanceOf(curation.address)

        // Source of tokens must be the staking for this to work
        const tx = curation.connect(staking).collect(subgraphDeploymentID, tokensToCollect)
        await expect(tx)
          .emit(curation, 'Collected')
          .withArgs(subgraphDeploymentID, tokensToCollect)

        // After state
        const afterPool = await curation.pools(subgraphDeploymentID)
        const afterTotalBalance = await grt.balanceOf(curation.address)

        // State updated
        expect(afterPool.tokens).eq(beforePool.tokens.add(tokensToCollect))
        expect(afterTotalBalance).eq(beforeTotalBalance.add(tokensToCollect))
      })
    })
  })

  describe('redeem', async function() {
    beforeEach(async function() {
      await curation.connect(curator).stake(subgraphDeploymentID, curatorTokens)
    })

    it('reject redeem more than a curator owns', async function() {
      const tx = curation.connect(me).redeem(subgraphDeploymentID, toGRT('1'))
      await expect(tx).revertedWith('Cannot redeem more shares than you own')
    })

    it('reject redeem zero shares', async function() {
      const tx = curation.connect(me).redeem(subgraphDeploymentID, toGRT('0'))
      await expect(tx).revertedWith('Cannot redeem zero shares')
    })

    it('should allow to redeem *partially*', async function() {
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
      const sharesToRedeem = toBN(1) // Curator want to sell 1 share
      const tokensToRedeem = await curation.sharesToTokens(subgraphDeploymentID, sharesToRedeem)
      const withdrawalFeePercentage = await curation.withdrawalFeePercentage()
      const withdrawalFees = withdrawalFeePercentage.mul(tokensToRedeem).div(toBN(MAX_PPM))

      // Redeem
      const tx = curation.connect(curator).redeem(subgraphDeploymentID, sharesToRedeem)
      await expect(tx)
        .emit(curation, 'Redeemed')
        .withArgs(
          curator.address,
          subgraphDeploymentID,
          tokensToRedeem,
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
      expect(afterCuratorTokens).eq(beforeCuratorTokens.add(tokensToRedeem))
      expect(afterCuratorShares).eq(beforeCuratorShares.sub(sharesToRedeem))
      // Curation balance updated
      expect(afterPool.tokens).eq(poolBefore.tokens.sub(tokensToRedeem))
      expect(afterPool.shares).eq(poolBefore.shares.sub(sharesToRedeem))
      // Contract balance updated
      expect(afterTotalTokens).eq(totalTokensBefore.sub(tokensToRedeem))
      // Withdrawal fees are burned
      expect(afterTokenTotalSupply).eq(beforeTokenTotalSupply.sub(withdrawalFees))
    })

    it('should allow to redeem *fully*', async function() {
      // Before state
      const beforeTokenTotalSupply = await grt.totalSupply()
      const beforePool = await curation.pools(subgraphDeploymentID)

      // Calculations
      const sharesToRedeem = beforePool.shares // we are selling all shares in the subgraph
      const tokensToRedeem = beforePool.tokens // we are withdrawing all funds
      const withdrawalFeePercentage = await curation.withdrawalFeePercentage()
      const withdrawalFees = withdrawalFeePercentage.mul(tokensToRedeem).div(toBN(MAX_PPM))

      // Redeem
      const tx = curation.connect(curator).redeem(subgraphDeploymentID, sharesToRedeem)
      await expect(tx)
        .emit(curation, 'Redeemed')
        .withArgs(
          curator.address,
          subgraphDeploymentID,
          tokensToRedeem,
          sharesToRedeem,
          withdrawalFees,
        )

      // After state
      const afterTokenTotalSupply = await grt.totalSupply()
      const afterCuratorTokens = await grt.balanceOf(curator.address)
      const afterCuratorShares = await curation.getCuratorShares(
        curator.address,
        subgraphDeploymentID,
      )
      const afterPool = await curation.pools(subgraphDeploymentID)
      const afterTotalTokens = await grt.balanceOf(curation.address)

      // Curator balance updated
      expect(afterCuratorTokens).eq(tokensToRedeem)
      expect(afterCuratorShares).eq(toBN(0))
      // Curation deallocated
      expect(afterPool.tokens).eq(toBN(0))
      expect(afterPool.shares).eq(toBN(0))
      expect(afterPool.reserveRatio).eq(toBN(0))
      // Contract balance updated
      expect(afterTotalTokens).eq(toBN(0))
      // Withdrawal fees are burned
      expect(afterTokenTotalSupply).eq(beforeTokenTotalSupply.sub(withdrawalFees))
    })
  })
})
