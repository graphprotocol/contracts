import path from 'path'

import { assert, expect } from 'chai'
import { useEnvironment } from './helpers'

describe('GRE usage', function () {
  describe('Project not using GRE', function () {
    useEnvironment('default-config', 'mainnet')

    it('should throw when accessing hre.graph()', function () {
      expect(() => this.hre.graph()).to.throw()
    })
  })

  describe(`Project using GRE: path-config`, function () {
    useEnvironment('path-config', 'mainnet')

    it('should add the graph path to the config', function () {
      assert.equal(
        this.hre.config.paths.graph,
        path.join(__dirname, 'fixtures/files'),
      )
    })
  })

  describe(`Project using GRE: no-path-config`, function () {
    useEnvironment('no-path-config', 'mainnet')

    it('should add the graph path to the config', function () {
      assert.equal(
        this.hre.config.paths.graph,
        path.join(__dirname, 'fixtures/no-path-config'),
      )
    })
  })

  describe(`Project using GRE: global-address-book`, function () {
    useEnvironment('global-address-book', 'mainnet')

    it('should use the global address book', function () {
      assert.equal(
        this.hre.graph().addressBook.file,
        path.join(__dirname, 'fixtures/files/addresses-global.json'),
      )
    })
  })

  describe(`Project using GRE: network-address-book`, function () {
    useEnvironment('network-address-book', 'mainnet')

    it('should use the network address book', function () {
      assert.equal(
        this.hre.graph().addressBook.file,
        path.join(__dirname, 'fixtures/files/addresses-network.json'),
      )
    })
  })
})
