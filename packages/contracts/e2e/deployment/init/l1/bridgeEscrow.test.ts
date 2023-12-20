import { expect } from 'chai'
import hre from 'hardhat'
import { isGraphL2ChainId } from '@graphprotocol/sdk'

describe('[L1] BridgeEscrow initialization', () => {
  const graph = hre.graph()
  const { BridgeEscrow, GraphToken, L1GraphTokenGateway } = graph.contracts

  before(async function () {
    if (isGraphL2ChainId(graph.chainId)) this.skip()
  })

  it("should allow L1GraphTokenGateway contract to spend MAX_UINT256 tokens on BridgeEscrow's behalf", async function () {
    const allowance = await GraphToken.allowance(BridgeEscrow.address, L1GraphTokenGateway.address)
    expect(allowance).eq(hre.ethers.constants.MaxUint256)
  })
})
