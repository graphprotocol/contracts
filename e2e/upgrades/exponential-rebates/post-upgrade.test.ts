import chai, { expect } from 'chai'
import chaiAsPromised from 'chai-as-promised'
import hre from 'hardhat'

chai.use(chaiAsPromised)

// describe('GNS contract', () => {
//   it(`'test' storage variable should exist`, async function () {
//     const graph = hre.graph()
//     const { GNS } = graph.contracts

//     await expect(GNS.test()).to.eventually.be.fulfilled
//   })
// })
