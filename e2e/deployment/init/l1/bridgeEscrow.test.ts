import { expect } from 'chai'
import hre from 'hardhat'

describe('BridgeEscrow initialization', () => {
  const {
    contracts: { BridgeEscrow, GraphToken, L1GraphTokenGateway },
  } = hre.graph()

  it("should allow L1GraphTokenGateway contract to spend MAX_UINT256 tokens on BridgeEscrow's behalf", async function () {
    const allowance = await GraphToken.allowance(BridgeEscrow.address, L1GraphTokenGateway.address)
    expect(allowance).eq(hre.ethers.constants.MaxUint256)
  })
})
