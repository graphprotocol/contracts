import { expect } from 'chai'
import hre from 'hardhat'
import { chainIdIsL2 } from '../../../../cli/utils'

describe('[L1] GraphToken configuration', () => {
  const {
    contracts: { GraphToken, L1Reservoir },
  } = hre.graph()

  before(async function () {
    const chainId = (await hre.ethers.provider.getNetwork()).chainId
    if (chainIdIsL2(chainId)) this.skip()
  })

  it('L1Reservoir should be a minter', async function () {
    const deployerIsMinter = await GraphToken.isMinter(L1Reservoir.address)
    expect(deployerIsMinter).eq(true)
  })
})
