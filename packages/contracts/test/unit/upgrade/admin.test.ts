import { expect } from 'chai'
import hre from 'hardhat'
import '@nomiclabs/hardhat-ethers'

import { GraphProxy } from '../../../build/types/GraphProxy'
import { Curation } from '../../../build/types/Curation'
import { GraphProxyAdmin } from '../../../build/types/GraphProxyAdmin'
import { IStaking } from '../../../build/types/IStaking'

import { NetworkFixture } from '../lib/fixtures'

import { SignerWithAddress } from '@nomiclabs/hardhat-ethers/signers'
import { DeployType, GraphNetworkContracts, deploy, loadContractAt } from '@graphprotocol/sdk'

const { ethers } = hre
const { AddressZero } = ethers.constants

describe('Upgrades', () => {
  const graph = hre.graph()
  let me: SignerWithAddress
  let governor: SignerWithAddress

  let fixture: NetworkFixture

  let contracts: GraphNetworkContracts
  let proxyAdmin: GraphProxyAdmin
  let curation: Curation
  let staking: IStaking
  let stakingProxy: GraphProxy

  before(async function () {
    ;[me, governor] = await graph.getTestAccounts()

    fixture = new NetworkFixture(graph.provider)
    contracts = await fixture.load(governor)
    staking = contracts.Staking as IStaking
    proxyAdmin = contracts.GraphProxyAdmin as GraphProxyAdmin
    curation = contracts.Curation as Curation
    stakingProxy = loadContractAt('GraphProxy', staking.address, undefined, governor) as GraphProxy

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
          await expect(stakingProxy.connect(governor).admin()).revertedWith(
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
          await expect(stakingProxy.connect(governor).pendingImplementation()).revertedWith(
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

        const stakingProxy = loadContractAt('GraphProxy', staking.address, undefined, governor)

        // Upgrade the Staking:Proxy to a new implementation
        const tx1 = proxyAdmin.connect(governor).upgrade(staking.address, newImplementationAddress)
        await expect(tx1)
          .emit(stakingProxy, 'PendingImplementationUpdated')
          .withArgs(AddressZero, newImplementationAddress)

        const tx2 = proxyAdmin
          .connect(governor)
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
        const tx = proxyAdmin.connect(me).upgrade(staking.address, newImplementationAddress)
        await expect(tx).revertedWith('Only Governor can call')
      })

      it('reject upgrade if not using the ProxyAdmin', async function () {
        const newImplementationAddress = await proxyAdmin.getProxyImplementation(curation.address)

        // Due to the transparent proxy we should not be able to upgrade from other than the proxy admin
        const tx = stakingProxy.connect(governor).upgradeTo(newImplementationAddress)
        await expect(tx).revertedWith(
          "function selector was not recognized and there's no fallback function",
        )
      })
    })

    describe('acceptUpgrade', function () {
      it('reject accept upgrade if not using the ProxyAdmin', async function () {
        // Due to the transparent proxy we should not be able to accept upgrades from other than the proxy admin
        const tx = stakingProxy.connect(governor).acceptUpgrade()
        await expect(tx).revertedWith(
          "function selector was not recognized and there's no fallback function",
        )
      })
    })

    describe('acceptProxy', function () {
      it('reject accept proxy if not using the ProxyAdmin', async function () {
        const newImplementationAddress = await proxyAdmin.getProxyImplementation(curation.address)
        const implementation = loadContractAt(
          'Curation',
          newImplementationAddress,
          undefined,
          governor,
        )

        // Start an upgrade to a new implementation
        await proxyAdmin.connect(governor).upgrade(staking.address, newImplementationAddress)

        // Try to accept the proxy directly from the implementation, this should not work, only from the ProxyAdmin
        const tx = implementation.connect(governor).acceptProxy(staking.address)
        await expect(tx).revertedWith('Caller must be the proxy admin')
      })
    })

    describe('changeProxyAdmin', function () {
      it('should set the proxy admin of a proxy', async function () {
        const { contract: otherProxyAdmin } = await deploy(DeployType.Deploy, governor, {
          name: 'GraphProxyAdmin',
        })

        await proxyAdmin
          .connect(governor)
          .changeProxyAdmin(staking.address, otherProxyAdmin.address)
        expect(await otherProxyAdmin.getProxyAdmin(staking.address)).eq(otherProxyAdmin.address)

        // Should not find the change admin function in the proxy due to transparent proxy
        // as this ProxyAdmin is not longer the owner
        const tx = proxyAdmin
          .connect(governor)
          .changeProxyAdmin(staking.address, otherProxyAdmin.address)
        await expect(tx).revertedWith(
          "function selector was not recognized and there's no fallback function",
        )
      })

      it('reject change admin if not the governor of the ProxyAdmin', async function () {
        const { contract: otherProxyAdmin } = await deploy(DeployType.Deploy, governor, {
          name: 'GraphProxyAdmin',
        })

        const tx = proxyAdmin.connect(me).changeProxyAdmin(staking.address, otherProxyAdmin.address)
        await expect(tx).revertedWith('Only Governor can call')
      })

      it('reject change admin if not using the ProxyAdmin', async function () {
        // Due to the transparent proxy we should not be able to set admin from other than the proxy admin
        const tx = stakingProxy.connect(governor).setAdmin(me.address)
        await expect(tx).revertedWith(
          "function selector was not recognized and there's no fallback function",
        )
      })
    })
  })
})
