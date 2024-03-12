import { expect } from 'chai'
import hre from 'hardhat'
import { isGraphL1ChainId } from '@graphprotocol/sdk'

describe('[L2] Staking', () => {
  const graph = hre.graph()
  const { L2Staking } = graph.l2.contracts

  before(function () {
    if (isGraphL1ChainId(graph.chainId)) this.skip()
  })

  describe('L2Staking', () => {
    it('counterpartStakingAddress should match the L1Staking address', async () => {
      // counterpartStakingAddress is internal so we access the storage directly
      const l1StakingData = await hre.ethers.provider.getStorageAt(L2Staking.address, 24)
      const l1Staking = hre.ethers.utils.defaultAbiCoder.decode(['address'], l1StakingData)[0]
      expect(l1Staking).eq(graph.l1.contracts.L1Staking.address)
    })
  })
})
