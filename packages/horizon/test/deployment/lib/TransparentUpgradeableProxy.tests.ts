import hre from 'hardhat'

import { assert, expect } from 'chai'
import { AddressBookEntry } from '@graphprotocol/toolshed/deployments'
import { zeroPadValue } from 'ethers'

export function transparentUpgradeableProxyTests(contractName: string, addressBookEntry: AddressBookEntry, owner: string): void {
  describe(`${contractName}: implementation`, function () {
    it('should be locked for initialization', async function () {
      if (!addressBookEntry.implementation) {
        assert.fail('Implementation address is not set')
      }
      const initialized = await hre.ethers.provider.getStorage(addressBookEntry.implementation, '0xf0c57e16840df040f15088dc2f81fe391c3923bec73e23a9662efc9c229c6a00')
      expect(initialized).to.equal(zeroPadValue('0xffffffffffffffff', 32))
    })
  })

  describe(`${contractName}: TransparentUpgradeableProxy`, function () {
    it('should be initialized', async function () {
      // https://github.com/OpenZeppelin/openzeppelin-contracts/blob/dbb6104ce834628e473d2173bbc9d47f81a9eec3/contracts/proxy/utils/Initializable.sol#L77
      const initialized = await hre.ethers.provider.getStorage(addressBookEntry.address, '0xf0c57e16840df040f15088dc2f81fe391c3923bec73e23a9662efc9c229c6a00')
      expect(initialized).to.equal(zeroPadValue('0x01', 32))
    })

    it('should target the correct implementation', async function () {
      // https:// github.com/OpenZeppelin/openzeppelin-contracts/blob/dbb6104ce834628e473d2173bbc9d47f81a9eec3/contracts/proxy/ERC1967/ERC1967Utils.sol#L37C53-L37C119
      const implementation = await hre.ethers.provider.getStorage(addressBookEntry.address, '0x360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc')
      if (!addressBookEntry.implementation) {
        assert.fail('Implementation address is not set')
      }
      expect(implementation).to.equal(zeroPadValue(addressBookEntry.implementation, 32))
    })

    it('should be owned by the proxy admin', async function () {
      // https://github.com/OpenZeppelin/openzeppelin-contracts/blob/dbb6104ce834628e473d2173bbc9d47f81a9eec3/contracts/proxy/ERC1967/ERC1967Utils.sol#L99
      const admin = await hre.ethers.provider.getStorage(addressBookEntry.address, '0xb53127684a568b3173ae13b9f8a6016e243e63b6e8ee1178d6a717850b5d6103')
      if (!addressBookEntry.proxyAdmin) {
        assert.fail('Proxy admin address is not set')
      }
      expect(admin).to.equal(zeroPadValue(addressBookEntry.proxyAdmin, 32))
    })
  })

  describe(`${contractName}: ProxyAdmin`, function () {
    it('should be owned by the governor', async function () {
      if (process.env.IGNITION_DEPLOYMENT_TYPE === 'protocol') {
        assert.fail('Deployment type "protocol": unknown governor address')
      }
      if (!addressBookEntry.proxyAdmin) {
        assert.fail('Proxy admin address is not set')
      }
      const ownerStorage = await hre.ethers.provider.getStorage(addressBookEntry.proxyAdmin, 0)
      expect(ownerStorage).to.equal(zeroPadValue(owner, 32))
    })
  })
}
