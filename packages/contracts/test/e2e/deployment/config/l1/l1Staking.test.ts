import { expect } from 'chai'
import hre from 'hardhat'
import { isGraphL2ChainId } from '@graphprotocol/sdk'

describe('[L1] Staking', () => {
  const graph = hre.graph()
  const { L1Staking, L1GraphTokenGateway } = graph.contracts

  before(function () {
    if (isGraphL2ChainId(graph.chainId)) this.skip()
  })

  describe('L1Staking', () => {
    it('counterpartStakingAddress should match the L2Staking address', async () => {
      // counterpartStakingAddress is internal so we access the storage directly
      const l2StakingData = await hre.ethers.provider.getStorageAt(L1Staking.address, 24)
      const l2Staking = hre.ethers.utils.defaultAbiCoder.decode(['address'], l2StakingData)[0]
      expect(l2Staking).eq(graph.l2.contracts.L2Staking.address)
    })

    it('should be added to callhookAllowlist', async () => {
      const isAllowed = await L1GraphTokenGateway.callhookAllowlist(L1Staking.address)
      expect(isAllowed).true
    })
  })
})
