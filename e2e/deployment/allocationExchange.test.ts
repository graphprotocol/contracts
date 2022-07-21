import { expect } from 'chai'
import hre from 'hardhat'
import { getItemValue } from '../../cli/config'

describe('AllocationExchange deployment', () => {
  const {
    graphConfig,
    contracts: { AllocationExchange, GraphToken, Staking },
  } = hre.graph()

  it('should be owned by edgeAndNode', async function () {
    const owner = await AllocationExchange.governor()
    const edgeAndNode = getItemValue(graphConfig, 'general/edgeAndNode')
    expect(owner).eq(edgeAndNode)
  })

  it('should accept vouchers from authority', async function () {
    const authorityAddress = getItemValue(graphConfig, 'general/authority')
    const allowed = await AllocationExchange.authority(authorityAddress)
    expect(allowed).eq(true)
  })

  // graphToken and staking are private variables so we can't verify
  it.skip('graphToken should match the GraphToken deployment address')
  it.skip('staking should match the Staking deployment address')

  it('should allow Staking contract to spend MAX_UINT256 tokens on AllocationExchange behalf', async function () {
    const allowance = await GraphToken.allowance(AllocationExchange.address, Staking.address)
    expect(allowance).eq(hre.ethers.constants.MaxUint256)
  })
})
