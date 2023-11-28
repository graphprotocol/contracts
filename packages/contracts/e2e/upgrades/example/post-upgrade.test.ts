import chai, { expect } from 'chai'
import chaiAsPromised from 'chai-as-promised'
import hre from 'hardhat'

chai.use(chaiAsPromised)

describe('GNS contract', () => {
  it(`'test' storage variable should exist`, async function () {
    const graph = hre.graph()
    const { GNS } = graph.contracts
    // eslint-disable-next-line @typescript-eslint/ban-ts-comment
    // @ts-ignore (we know this property doesn't exist)
    await expect(GNS.test()).to.eventually.be.fulfilled
  })
})
