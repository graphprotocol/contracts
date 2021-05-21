import { expect } from 'chai'
import hre from 'hardhat'
import '@nomiclabs/hardhat-ethers'

import { GraphProxy } from '../../build/types/GraphProxy'
import { Curation } from '../../build/types/Curation'
import { GraphProxyAdmin } from '../../build/types/GraphProxyAdmin'
import { Staking } from '../../build/types/Staking'

import * as deployment from '../lib/deployment'
import { NetworkFixture } from '../lib/fixtures'
import { getAccounts, Account } from '../lib/testHelpers'

import { getContractAt } from '../../cli/network'

const { ethers } = hre
const { AddressZero } = ethers.constants

describe('Upgrades', () => {
  let me: Account
  let governor: Account

  let fixture: NetworkFixture

  let proxyAdmin: GraphProxyAdmin
  let curation: Curation
  let staking: Staking
  let stakingProxy: GraphProxy

  before(async function () {
    ;[me, governor] = await getAccounts()

    fixture = new NetworkFixture()
    ;({ proxyAdmin, staking, curation } = await fixture.load(governor.signer))
    stakingProxy = getContractAt('GraphProxy', staking.address, governor.signer) as GraphProxy

    // Give some funds to the indexer and approve staking contract to use funds on indexer behalf
  })

  beforeEach(async function () {
    await fixture.setUp()
  })

  afterEach(async function () {
    await fixture.tearDown()
  })

  describe('GraphProxyAdmin & GraphProxy', function () {
    describe('getters', function () {
      describe('admin()', function () {
        it('should get the proxy admin of a proxy contract', async function () {
          const proxyAdminAddress = await proxyAdmin.getProxyAdmin(staking.address)
          expect(proxyAdmin.address).eq(proxyAdminAddress)
        })

        it('reject get admin from other than the ProxyAdmin', async function () {
          await expect(stakingProxy.admin()).revertedWith(
            "function selector was not recognized and there's no fallback function",
          )
        })
      })

      describe('implementation()', function () {
        it('should get implementation only from ProxyAdmin', async function () {
          const implementationAddress = await proxyAdmin.getProxyImplementation(staking.address)
          expect(implementationAddress).not.eq(AddressZero)
        })

        it('reject get implementation from other than the ProxyAdmin', async function () {
          await expect(stakingProxy.implementation()).revertedWith(
            "function selector was not recognized and there's no fallback function",
          )
        })
      })

      describe('pendingImplementation()', function () {
        it('should get pending implementation only from ProxyAdmin', async function () {
          const pendingImplementationAddress = await proxyAdmin.getProxyPendingImplementation(
            staking.address,
          )
          expect(pendingImplementationAddress).eq(AddressZero)
        })

        it('reject get pending implementation from other than the ProxyAdmin', async function () {
          await expect(stakingProxy.pendingImplementation()).revertedWith(
            "function selector was not recognized and there's no fallback function",
          )
        })
      })
    })

    describe('upgrade', function () {
      it('should be able to upgrade contract', async function () {
        // Get some other implementation to use just for the purpose of the test
        const oldImplementationAddress = await proxyAdmin.getProxyImplementation(staking.address)
        const newImplementationAddress = await proxyAdmin.getProxyImplementation(curation.address)

        const stakingProxy = getContractAt('GraphProxy', staking.address, governor.signer)

        // Upgrade the Staking:Proxy to a new implementation
        const tx1 = proxyAdmin
          .connect(governor.signer)
          .upgrade(staking.address, newImplementationAddress)
        await expect(tx1)
          .emit(stakingProxy, 'PendingImplementationUpdated')
          .withArgs(AddressZero, newImplementationAddress)

        const tx2 = proxyAdmin
          .connect(governor.signer)
          .acceptProxy(newImplementationAddress, staking.address)
        await expect(tx2)
          .emit(stakingProxy, 'ImplementationUpdated')
          .withArgs(oldImplementationAddress, newImplementationAddress)

        // Implementation should be the new one
        expect(await proxyAdmin.getProxyImplementation(curation.address)).eq(
          newImplementationAddress,
        )
      })

      it('reject upgrade if not the governor of the ProxyAdmin', async function () {
        const newImplementationAddress = await proxyAdmin.getProxyImplementation(curation.address)

        // Upgrade the Staking:Proxy to a new implementation
        const tx = proxyAdmin.connect(me.signer).upgrade(staking.address, newImplementationAddress)
        await expect(tx).revertedWith('Only Governor can call')
      })

      it('reject upgrade if not using the ProxyAdmin', async function () {
        const newImplementationAddress = await proxyAdmin.getProxyImplementation(curation.address)

        // Due to the transparent proxy we should not be able to upgrade from other than the proxy admin
        const tx = stakingProxy.connect(governor.signer).upgradeTo(newImplementationAddress)
        await expect(tx).revertedWith(
          "function selector was not recognized and there's no fallback function",
        )
      })
    })

    describe('acceptUpgrade', function () {
      it('reject accept upgrade if not using the ProxyAdmin', async function () {
        // Due to the transparent proxy we should not be able to accept upgrades from other than the proxy admin
        const tx = stakingProxy.connect(governor.signer).acceptUpgrade()
        await expect(tx).revertedWith(
          "function selector was not recognized and there's no fallback function",
        )
      })
    })

    describe('acceptProxy', function () {
      it('reject accept proxy if not using the ProxyAdmin', async function () {
        const newImplementationAddress = await proxyAdmin.getProxyImplementation(curation.address)
        const implementation = getContractAt('Curation', newImplementationAddress, governor.signer)

        // Start an upgrade to a new implementation
        await proxyAdmin.connect(governor.signer).upgrade(staking.address, newImplementationAddress)

        // Try to accept the proxy directly from the implementation, this should not work, only from the ProxyAdmin
        const tx = implementation.connect(governor.signer).acceptProxy(staking.address)
        await expect(tx).revertedWith('Caller must be the proxy admin')
      })
    })

    describe('changeProxyAdmin', function () {
      it('should set the proxy admin of a proxy', async function () {
        const otherProxyAdmin = await deployment.deployProxyAdmin(governor.signer)

        await proxyAdmin
          .connect(governor.signer)
          .changeProxyAdmin(staking.address, otherProxyAdmin.address)
        expect(await otherProxyAdmin.getProxyAdmin(staking.address)).eq(otherProxyAdmin.address)

        // Should not find the change admin function in the proxy due to transparent proxy
        // as this ProxyAdmin is not longer the owner
        const tx = proxyAdmin
          .connect(governor.signer)
          .changeProxyAdmin(staking.address, otherProxyAdmin.address)
        await expect(tx).revertedWith(
          "function selector was not recognized and there's no fallback function",
        )
      })

      it('reject change admin if not the governor of the ProxyAdmin', async function () {
        const otherProxyAdmin = await deployment.deployProxyAdmin(governor.signer)

        const tx = proxyAdmin
          .connect(me.signer)
          .changeProxyAdmin(staking.address, otherProxyAdmin.address)
        await expect(tx).revertedWith('Only Governor can call')
      })

      it('reject change admin if not using the ProxyAdmin', async function () {
        // Due to the transparent proxy we should not be able to set admin from other than the proxy admin
        const tx = stakingProxy.connect(governor.signer).setAdmin(me.address)
        await expect(tx).revertedWith(
          "function selector was not recognized and there's no fallback function",
        )
      })
    })
  })
})
