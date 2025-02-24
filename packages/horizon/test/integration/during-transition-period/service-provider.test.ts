import { expect } from 'chai'
import { ethers } from 'hardhat'
import hre from 'hardhat'
import { IHorizonStaking, IGraphToken } from '../../../typechain-types'
import { SignerWithAddress } from '@nomicfoundation/hardhat-ethers/signers'

import { stake, unstake, withdraw } from '../shared/staking'

describe('Service Provider', () => {
  let horizonStaking: IHorizonStaking
  let graphToken: IGraphToken
  let serviceProvider: SignerWithAddress

  const tokensToStake = ethers.parseEther('1000')

  before(async () => {
    const graph = hre.graph()

    horizonStaking = graph.horizon!.contracts.HorizonStaking as unknown as IHorizonStaking
    graphToken = graph.horizon!.contracts.L2GraphToken as unknown as IGraphToken

    [serviceProvider] = await ethers.getSigners()

    // Stake tokens to service provider
    await stake({ horizonStaking, graphToken, serviceProvider, tokens: tokensToStake })
  })

  it('should allow service provider to unstake and withdraw after thawing period', async () => {
    const tokensToUnstake = ethers.parseEther('100')
    const balanceBefore = await graphToken.balanceOf(serviceProvider.address)

    // First unstake request
    await unstake({ horizonStaking, serviceProvider, tokens: tokensToUnstake })
    
    // During transition period, tokens are locked by thawing period
    const thawingPeriod = await horizonStaking.__DEPRECATED_getThawingPeriod()
    
    // Mine remaining blocks to complete thawing period
    for (let i = 0; i < Number(thawingPeriod) + 1; i++) {
      await ethers.provider.send('evm_mine', [])
    }

    // Now we can withdraw
    await withdraw({ horizonStaking, serviceProvider })
    const balanceAfter = await graphToken.balanceOf(serviceProvider.address)

    expect(balanceAfter).to.equal(balanceBefore + tokensToUnstake, 'Tokens should be transferred back to service provider')
  })

  describe('Multiple unstake requests', () => {
    it('should handle multiple unstake requests correctly', async () => {
      // Make multiple unstake requests
      const request1 = ethers.parseEther('50')
      const request2 = ethers.parseEther('75')

      const thawingPeriod = await horizonStaking.__DEPRECATED_getThawingPeriod()

      // First unstake request
      await unstake({ horizonStaking, serviceProvider, tokens: request1 })

      // Mine half of thawing period blocks
      const halfThawingPeriod = Number(thawingPeriod) / 2
      for (let i = 0; i < halfThawingPeriod; i++) {
        await ethers.provider.send('evm_mine', [])
      }

      // Second unstake request
      await unstake({ horizonStaking, serviceProvider, tokens: request2 })

      // Mine remaining blocks to complete thawing period
      for (let i = 0; i < Number(thawingPeriod) + 1; i++) {
        await ethers.provider.send('evm_mine', [])
      }

      // Get balance before withdrawing
      const balanceBefore = await graphToken.balanceOf(serviceProvider.address)

      // Withdraw all thawed tokens
      await withdraw({ horizonStaking, serviceProvider })

      // Verify all tokens are withdrawn and transferred back to service provider
      const balanceAfter = await graphToken.balanceOf(serviceProvider.address)
      expect(balanceAfter).to.equal(balanceBefore + request1 + request2)
    })
  })
})
