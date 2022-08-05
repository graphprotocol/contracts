import { expect } from 'chai'
import hre from 'hardhat'
import { chainIdIsL2 } from '../../../cli/utils'

describe('Protocol configuration', () => {
  const { contracts } = hre.graph()

  it('protocol should be unpaused', async function () {
    const paused = await contracts.Controller.paused()
    expect(paused).eq(false)
  })

  it('bridge should be unpaused', async function () {
    const chainId = (await hre.ethers.provider.getNetwork()).chainId
    const isL2 = chainIdIsL2(chainId)
    const GraphTokenGateway = isL2 ? contracts.L2GraphTokenGateway : contracts.L1GraphTokenGateway
    const paused = await GraphTokenGateway.paused()
    expect(paused).eq(false)
  })
})
