import path from 'path'

import { expect } from 'chai'
import { getAddressBookPath } from '../src/config'
import { useEnvironment } from './helpers'

describe('GRE init functions', function () {
  // No address book - should throw
  describe('getAddressBookPath', function () {
    useEnvironment('default-config', 'mainnet')

    it('should throw if no address book is specified', function () {
      expect(() => getAddressBookPath(this.hre, {})).to.throw('Must set a an addressBook path!')
    })
  })

  describe('getAddressBookPath', function () {
    useEnvironment('network-address-book', 'mainnet')

    // Address book via opts should be used
    it('should use opts parameter if available', function () {
      const addressBook = getAddressBookPath(this.hre, {
        addressBook: 'addresses-opt.json',
      })
      expect(path.basename(addressBook)).to.equal('addresses-opt.json')
    })

    // Address book via network config should be used
    it('should use HH network config', function () {
      const addressBook = getAddressBookPath(this.hre, {})
      expect(path.basename(addressBook)).to.equal('addresses-network.json')
    })
  })

  describe('getAddressBookPath', function () {
    useEnvironment('global-address-book', 'mainnet')

    // Address book via global config should be used
    it('should use HH global config', function () {
      const addressBook = getAddressBookPath(this.hre, {})
      expect(path.basename(addressBook)).to.equal('addresses-global.json')
    })
  })

  describe('getAddressBookPath with a non existent address book', function () {
    useEnvironment('invalid-address-book', 'mainnet')

    it('should throw if address book doesn\'t exist', function () {
      expect(() => getAddressBookPath(this.hre, {})).to.throw(/Address book not found: /)
    })
  })
})
