import path from 'path'

import { expect } from 'chai'
import { getAddressBookPath } from '../src/config'
import { loadHardhatContext } from './helpers'

describe('GRE init functions', function () {
  // No address book - should throw
  describe('getAddressBookPath', function () {
    it('should throw if no address book is specified', function () {
      this.hre = loadHardhatContext('default-config', 'mainnet')
      expect(() => getAddressBookPath('horizon', this.hre, {})).to.throw('Must set a an addressBook path!')
    })

    it('should throw if address book doesn\'t exist', function () {
      this.hre = loadHardhatContext('invalid-address-book', 'mainnet')
      expect(() => getAddressBookPath('horizon', this.hre, {})).to.throw(/Address book not found: /)
    })

    // Address book via opts should be used
    it('should use opts parameter if available', function () {
      this.hre = loadHardhatContext('network-address-book', 'mainnet')
      const addressBook = getAddressBookPath('horizon', this.hre, {
        deployments: {
          horizon: 'addresses-opt.json',
        },
      })
      expect(path.basename(addressBook)).to.equal('addresses-opt.json')
    })

    it('should use opts parameter if available - shortcut syntax', function () {
      this.hre = loadHardhatContext('network-address-book', 'mainnet')
      const addressBook = getAddressBookPath('horizon', this.hre, {
        deployments: {
          horizon: 'addresses-opt.json',
        },
      })
      expect(path.basename(addressBook)).to.equal('addresses-opt.json')
    })

    // Address book via network config should be used
    it('should use HH network config', function () {
      this.hre = loadHardhatContext('network-address-book', 'mainnet')
      const addressBook = getAddressBookPath('horizon', this.hre, {})
      expect(path.basename(addressBook)).to.equal('addresses-network.json')
    })

    it('should use HH network config - shortcut syntax', function () {
      this.hre = loadHardhatContext('network-address-book', 'mainnet')
      if (this.hre.network.config.deployments) {
        this.hre.network.config.deployments.horizon = 'addresses-network-short.json'
      }
      const addressBook = getAddressBookPath('horizon', this.hre, {})
      expect(path.basename(addressBook)).to.equal('addresses-network-short.json')
    })

    // Address book via global config should be used
    it('should use HH global config', function () {
      this.hre = loadHardhatContext('global-address-book', 'mainnet')
      const addressBook = getAddressBookPath('horizon', this.hre, {})
      expect(path.basename(addressBook)).to.equal('addresses-global.json')
    })

    it('should use HH global config - shortcut syntax', function () {
      this.hre = loadHardhatContext('global-address-book', 'mainnet')
      if (this.hre.config.graph.deployments) {
        this.hre.config.graph.deployments.horizon = 'addresses-global-short.json'
      }
      const addressBook = getAddressBookPath('horizon', this.hre, {})
      expect(path.basename(addressBook)).to.equal('addresses-global-short.json')
    })
  })
})
