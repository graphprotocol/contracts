import path from 'path'

import { assert, expect } from 'chai'
import { loadHardhatContext, useHardhatProject } from './helpers'
import { GraphHorizonAddressBook } from '@graphprotocol/toolshed/deployments/horizon'

describe('GRE usage', function () {
  describe('Project not using GRE', function () {
    useHardhatProject('default-config', 'mainnet')

    it('should throw when accessing hre.graph()', function () {
      expect(() => this.hre.graph()).to.throw()
    })
  })

  describe(`Project using GRE - graph path`, function () {
    it('should add the graph path to the config', function () {
      this.hre = loadHardhatContext('no-path-config', 'mainnet')
      assert.equal(
        this.hre.config.paths.graph,
        path.join(__dirname, 'fixtures/no-path-config'),
      )
    })

    it('should add the graph path to the config from custom path', function () {
      this.hre = loadHardhatContext('path-config', 'mainnet')
      assert.equal(
        this.hre.config.paths.graph,
        path.join(__dirname, 'fixtures/files'),
      )
    })
  })

  describe(`Project using GRE - deployments`, function () {
    useHardhatProject('path-config', 'arbitrumSepolia')

    it('should load Horizon deployment', function () {
      const graph = this.hre.graph()
      assert.isDefined(graph.horizon)
      assert.isObject(graph.horizon)

      assert.isDefined(graph.horizon.contracts)
      assert.isObject(graph.horizon.contracts)

      assert.isDefined(graph.horizon.addressBook)
      assert.isObject(graph.horizon.addressBook)
      assert.instanceOf(
        graph.horizon.addressBook,
        GraphHorizonAddressBook,
      )
    })
  })
})
