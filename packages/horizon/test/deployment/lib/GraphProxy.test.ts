import hre from 'hardhat'

import { assert, expect } from 'chai'
import { AddressBookEntry } from '@graphprotocol/toolshed/deployments'
import { zeroPadValue } from 'ethers'

export function graphProxyTests(contractName: string, addressBookEntry: AddressBookEntry, proxyAdmin: string): void {
  describe(`${contractName}: GraphProxy`, function () {
    it('should target the correct implementation', async function () {
      const implementation = await hre.ethers.provider.getStorage(addressBookEntry.address, '0x360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc')
      if (!addressBookEntry.implementation) {
        assert.fail('Implementation address is not set')
      }
      expect(implementation).to.equal(zeroPadValue(addressBookEntry.implementation, 32))
    })

    it('should be owned by the proxy admin', async function () {
      const admin = await hre.ethers.provider.getStorage(addressBookEntry.address, '0xb53127684a568b3173ae13b9f8a6016e243e63b6e8ee1178d6a717850b5d6103')
      expect(admin).to.equal(zeroPadValue(proxyAdmin, 32))
    })
  })
}
