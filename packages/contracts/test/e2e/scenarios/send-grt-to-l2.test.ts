import { expect } from 'chai'
import hre from 'hardhat'
import { BridgeFixture, getBridgeFixture } from './fixtures/bridge'

describe('Bridge GRT to L2', () => {
  const graph = hre.graph()
  let bridgeFixture: BridgeFixture

  before(async () => {
    const l1Deployer = await graph.l1.getDeployer()
    const l2Deployer = await graph.l2.getDeployer()
    bridgeFixture = getBridgeFixture([l1Deployer, l2Deployer])
  })

  describe('GRT balances', () => {
    it(`L2 balances should match bridged amount`, async function () {
      for (const account of bridgeFixture.accountsToFund) {
        const l2GrtBalance = await graph.l2.contracts.GraphToken.balanceOf(account.signer.address)
        expect(l2GrtBalance).eq(account.amount)
      }
    })
  })
})
