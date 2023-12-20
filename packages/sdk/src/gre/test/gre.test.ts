import { expect } from 'chai'
import { useEnvironment } from './helpers'

describe('GRE usage', function () {
  describe('graph-config project setting --network to an L1', function () {
    useEnvironment('graph-config', 'mainnet')

    it('should return L1 and L2 configured objects', function () {
      const g = this.hre.graph()

      expect(g).to.be.an('object')
      expect(g.l1).to.be.an('object')
      expect(g.l2).to.be.an('object')
      expect(g.l1?.chainId).to.equal(1)
      expect(g.l2?.chainId).to.equal(42161)
      expect(g.chainId).to.equal(1)
    })
  })

  describe('graph-config project setting --network to an L2', function () {
    useEnvironment('graph-config', 'arbitrum-goerli')

    it('should return L1 and L2 configured objects', function () {
      const g = this.hre.graph()

      expect(g).to.be.an('object')
      expect(g.l1).to.be.an('object')
      expect(g.l2).to.be.an('object')
      expect(g.l1?.chainId).to.equal(5)
      expect(g.l2?.chainId).to.equal(421613)
      expect(g.chainId).to.equal(421613)
    })
  })

  describe('graph-config project setting --network to hardhat network', function () {
    useEnvironment('graph-config', 'hardhat')

    it('should return L1 configured object and L2 unconfigured', function () {
      const g = this.hre.graph()

      expect(g).to.be.an('object')
      expect(g.l1).to.be.an('object')
      expect(g.l2).to.be.null
      expect(g.l1?.chainId).to.equal(1337)
      expect(g.chainId).to.equal(1337)
    })
  })

  describe('graph-config project setting --network to an L1 with no configured counterpart', function () {
    useEnvironment('graph-config', 'localhost')

    it('should return L1 configured object and L2 unconfigured', function () {
      const g = this.hre.graph()

      expect(g).to.be.an('object')
      expect(g.l1).to.be.an('object')
      expect(g.l2).to.be.null
      expect(g.l1?.chainId).to.equal(1337)
      expect(g.chainId).to.equal(1337)
    })
  })

  describe('graph-config project setting --network to an L2 with no configured counterpart', function () {
    useEnvironment('graph-config', 'arbitrum-rinkeby')

    it('should return L2 configured object and L1 unconfigured', function () {
      const g = this.hre.graph()

      expect(g).to.be.an('object')
      expect(g.l1).to.be.null
      expect(g.l2).to.be.an('object')
      expect(g.l2?.chainId).to.equal(421611)
      expect(g.chainId).to.equal(421611)
    })
  })

  describe('default-config project', function () {
    useEnvironment('default-config', 'mainnet')

    it('should throw', function () {
      expect(() => this.hre.graph()).to.throw()
    })
  })
})
