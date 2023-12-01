import { expect } from 'chai'
import { useEnvironment } from './helpers'
import path from 'path'

import { getAddressBookPath, getChains, getDefaultProviders, getGraphConfigPaths } from '../config'
import { getNetworkName } from '../helpers/network'

describe('GRE init functions', function () {
  describe('getAddressBookPath with graph-config project', function () {
    useEnvironment('graph-config')

    it('should use opts parameter if available', function () {
      const addressBook = getAddressBookPath(this.hre, {
        addressBook: 'addresses-opts.json',
      })
      expect(path.basename(addressBook)).to.equal('addresses-opts.json')
    })

    it('should use HH graph config if opts parameter not available ', function () {
      const addressBook = getAddressBookPath(this.hre, {})
      expect(path.basename(addressBook)).to.equal('addresses-hre.json')
    })
  })

  describe('getAddressBookPath with default-config project', function () {
    useEnvironment('default-config')

    it('should throw if no address book is specified', function () {
      expect(() => getAddressBookPath(this.hre, {})).to.throw('Must set a an addressBook path!')
    })
  })

  describe('getAddressBookPath with graph-config-bad project', function () {
    useEnvironment('graph-config-bad')

    it("should throw if address book doesn't exist", function () {
      expect(() => getAddressBookPath(this.hre, {})).to.throw(/Address book not found: /)
    })
  })

  describe('getChains', function () {
    it('should return L1 and L2 chain ids for a supported L1 chain', function () {
      const { l1ChainId, l2ChainId, isHHL1, isHHL2 } = getChains(5) // Goerli

      expect(l1ChainId).to.equal(5)
      expect(l2ChainId).to.equal(421613)
      expect(isHHL1).to.equal(true)
      expect(isHHL2).to.equal(false)
    })
    it('should return L1 and L2 chain ids for a supported L2 chain', function () {
      const { l1ChainId, l2ChainId, isHHL1, isHHL2 } = getChains(42161) // Arbitrum One

      expect(l1ChainId).to.equal(1)
      expect(l2ChainId).to.equal(42161)
      expect(isHHL1).to.equal(false)
      expect(isHHL2).to.equal(true)
    })
    it('should throw if provided chain is not supported', function () {
      const badChainId = 999
      expect(() => getChains(badChainId)).to.throw(`Chain ${badChainId} is not supported!`)
    })
  })

  describe('getDefaultProviders with graph-config project', function () {
    useEnvironment('graph-config')

    it('should return L1 and L2 providers for supported networks (HH L1)', function () {
      const { l1Provider, l2Provider } = getDefaultProviders(this.hre, 5, 421613, true)
      expect(l1Provider).to.be.an('object')
      expect(l2Provider).to.be.an('object')
    })

    it('should return L1 and L2 providers for supported networks (HH L2)', function () {
      const { l1Provider, l2Provider } = getDefaultProviders(this.hre, 5, 421613, false)
      expect(l1Provider).to.be.an('object')
      expect(l2Provider).to.be.an('object')
    })

    it('should return only L1 provider if L2 is not supported (HH L1)', function () {
      const { l1Provider, l2Provider } = getDefaultProviders(this.hre, 5, 123456, true)
      expect(l1Provider).to.be.an('object')
      expect(l2Provider).to.be.undefined
    })

    it('should return only L2 provider if L1 is not supported (HH L2)', function () {
      const { l1Provider, l2Provider } = getDefaultProviders(this.hre, 123456, 421613, false)
      expect(l1Provider).to.be.undefined
      expect(l2Provider).to.be.an('object')
    })
  })

  describe('getDefaultProviders with graph-config-bad project', function () {
    useEnvironment('graph-config-bad')

    it('should throw if main network is not defined in hardhat config (HH L1)', function () {
      expect(() => getDefaultProviders(this.hre, 4, 421611, true)).to.throw(
        /Must set a provider url for chain: /,
      )
    })

    it('should throw if main network is not defined in hardhat config (HH L2)', function () {
      expect(() => getDefaultProviders(this.hre, 5, 421613, false)).to.throw(
        /Must set a provider url for chain: /,
      )
    })
  })

  describe('getProviders with graph-config-desambiguate project', function () {
    useEnvironment('graph-config-desambiguate', 'localnitrol1')

    it('should use main network name to desambiguate if multiple chains are defined with same chainId', async function () {
      const { l1Provider, l2Provider } = getDefaultProviders(this.hre, 1337, 412346, true)
      expect(l1Provider).to.be.an('object')
      expect(l2Provider).to.be.an('object')

      const l1NetworkName = getNetworkName(this.hre.config.networks, 1337, 'localnitrol1')
      const l2NetworkName = getNetworkName(this.hre.config.networks, 412346, 'localnitrol1')
      expect(l1NetworkName).to.equal('localnitrol1')
      expect(l2NetworkName).to.equal('localnitrol2')
    })
  })

  describe('getProviders with graph-config-desambiguate project', function () {
    useEnvironment('graph-config-desambiguate', 'localnitrol2')

    it('should use secondary network name to desambiguate if multiple chains are defined with same chainId', async function () {
      const { l1Provider, l2Provider } = getDefaultProviders(this.hre, 1337, 412346, true)
      expect(l1Provider).to.be.an('object')
      expect(l2Provider).to.be.an('object')

      const l1NetworkName = getNetworkName(this.hre.config.networks, 1337, 'localnitrol2')
      const l2NetworkName = getNetworkName(this.hre.config.networks, 412346, 'localnitrol2')
      expect(l1NetworkName).to.equal('localnitrol1')
      expect(l2NetworkName).to.equal('localnitrol2')
    })
  })

  describe('getGraphConfigPaths with graph-config-full project', function () {
    useEnvironment('graph-config-full')

    it('should use opts parameters if available', function () {
      const { l1GraphConfigPath, l2GraphConfigPath } = getGraphConfigPaths(
        this.hre,
        { l1GraphConfig: 'config/graph.opts.yml', l2GraphConfig: 'config/graph.arbitrum-opts.yml' },
        5,
        421613,
        true,
      )
      expect(l1GraphConfigPath).not.to.be.undefined
      expect(l2GraphConfigPath).not.to.be.undefined
      expect(path.basename(l1GraphConfigPath!)).to.equal('graph.opts.yml')
      expect(path.basename(l2GraphConfigPath!)).to.equal('graph.arbitrum-opts.yml')
    })

    it('should use opts graphConfig parameter only for main network if available (HH L1)', function () {
      const { l1GraphConfigPath, l2GraphConfigPath } = getGraphConfigPaths(
        this.hre,
        { graphConfig: 'config/graph.opts.yml' },
        4,
        421611,
        true,
      )
      expect(l1GraphConfigPath).not.to.be.undefined
      expect(l2GraphConfigPath).not.to.be.undefined
      expect(path.basename(l1GraphConfigPath!)).to.equal('graph.opts.yml')
      expect(path.basename(l2GraphConfigPath!)).to.equal('graph.arbitrum-hre.yml')
    })

    it('should use opts graphConfig parameter only for main network if available (HH L2)', function () {
      const { l1GraphConfigPath, l2GraphConfigPath } = getGraphConfigPaths(
        this.hre,
        { graphConfig: 'config/graph.arbitrum-opts.yml' },
        4,
        421611,
        false,
      )
      expect(l1GraphConfigPath).not.to.be.undefined
      expect(l2GraphConfigPath).not.to.be.undefined
      expect(path.basename(l1GraphConfigPath!)).to.equal('graph.hre.yml')
      expect(path.basename(l2GraphConfigPath!)).to.equal('graph.arbitrum-opts.yml')
    })

    it('should ignore graphConfig parameter if both config paths are provided (HH L1)', function () {
      const { l1GraphConfigPath, l2GraphConfigPath } = getGraphConfigPaths(
        this.hre,
        {
          graphConfig: 'config/graph.opts2.yml',
          l1GraphConfig: 'config/graph.opts.yml',
          l2GraphConfig: 'config/graph.arbitrum-opts.yml',
        },
        5,
        421613,
        true,
      )
      expect(l1GraphConfigPath).not.to.be.undefined
      expect(l2GraphConfigPath).not.to.be.undefined
      expect(path.basename(l1GraphConfigPath!)).to.equal('graph.opts.yml')
      expect(path.basename(l2GraphConfigPath!)).to.equal('graph.arbitrum-opts.yml')
    })

    it('should ignore graphConfig parameter if both config paths are provided (HH L2)', function () {
      const { l1GraphConfigPath, l2GraphConfigPath } = getGraphConfigPaths(
        this.hre,
        {
          graphConfig: 'config/graph.opts2.yml',
          l1GraphConfig: 'config/graph.opts.yml',
          l2GraphConfig: 'config/graph.arbitrum-opts.yml',
        },
        5,
        421613,
        false,
      )
      expect(l1GraphConfigPath).not.to.be.undefined
      expect(l2GraphConfigPath).not.to.be.undefined
      expect(path.basename(l1GraphConfigPath!)).to.equal('graph.opts.yml')
      expect(path.basename(l2GraphConfigPath!)).to.equal('graph.arbitrum-opts.yml')
    })

    it('should use network specific config if no opts given', function () {
      const { l1GraphConfigPath, l2GraphConfigPath } = getGraphConfigPaths(
        this.hre,
        {},
        1,
        42161,
        false,
      )
      expect(l1GraphConfigPath).not.to.be.undefined
      expect(l2GraphConfigPath).not.to.be.undefined
      expect(path.basename(l1GraphConfigPath!)).to.equal('graph.mainnet.yml')
      expect(path.basename(l2GraphConfigPath!)).to.equal('graph.arbitrum-goerli.yml')
    })

    it('should use graph generic config if nothing else given', function () {
      const { l1GraphConfigPath, l2GraphConfigPath } = getGraphConfigPaths(
        this.hre,
        {},
        4,
        421611,
        false,
      )
      expect(l1GraphConfigPath).not.to.be.undefined
      expect(l2GraphConfigPath).not.to.be.undefined
      expect(path.basename(l1GraphConfigPath!)).to.equal('graph.hre.yml')
      expect(path.basename(l2GraphConfigPath!)).to.equal('graph.arbitrum-hre.yml')
    })
  })

  describe('getGraphConfigPaths with graph-config-bad project', function () {
    useEnvironment('graph-config-bad')

    it('should throw if no config file for main network (HH L1)', function () {
      expect(() => getGraphConfigPaths(this.hre, {}, 5, 421611, true)).to.throw(
        'Must specify a graph config file for L1!',
      )
    })

    it('should throw if no config file for main network (HH L2)', function () {
      expect(() => getGraphConfigPaths(this.hre, {}, 5, 421611, false)).to.throw(
        'Must specify a graph config file for L2!',
      )
    })

    it('should throw if config file does not exist', function () {
      expect(() => getGraphConfigPaths(this.hre, {}, 1, 421611, true)).to.throw(
        /Graph config file not found: /,
      )
    })
  })
})
