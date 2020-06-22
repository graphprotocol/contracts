import { expect } from 'chai'

import { ServiceRegistry } from '../build/typechain/contracts/ServiceRegistry'

import * as deployment from './lib/deployment'
import { provider } from './lib/testHelpers'

describe('ServiceRegistry', () => {
  const [governor, indexer] = provider().getWallets()

  let serviceRegistry: ServiceRegistry
  const geohash = '69y7hdrhm6mp'

  beforeEach(async function () {
    serviceRegistry = await deployment.deployServiceRegistry()

    this.shouldRegister = async function (url: string, geohash: string) {
      // Register the indexer service
      const tx = serviceRegistry.connect(indexer).register(url, geohash)
      await expect(tx)
        .to.emit(serviceRegistry, 'ServiceRegistered')
        .withArgs(indexer.address, url, geohash)

      // Updated state
      const indexerService = await serviceRegistry.services(indexer.address)
      expect(indexerService.url).to.be.eq(url)
      expect(indexerService.geohash).to.be.eq(geohash)
    }
  })

  describe('register()', function () {
    it('should allow registering', async function () {
      const url = 'https://192.168.2.1/'
      await this.shouldRegister(url, geohash)
    })

    it('should allow registering with a very long string', async function () {
      const url = 'https://' + 'a'.repeat(125) + '.com'
      await this.shouldRegister(url, geohash)
    })

    it('should allow updating a registration', async function () {
      const [url1, geohash1] = ['https://thegraph.com', '69y7hdrhm6mp']
      const [url2, geohash2] = ['https://192.168.0.1', 'dr5regw2z6y']
      await this.shouldRegister(url1, geohash1)
      await this.shouldRegister(url2, geohash2)
    })

    it('reject registering empty URL', async function () {
      const tx = serviceRegistry.connect(indexer).register('', '')
      await expect(tx).to.be.revertedWith('Service must specify a URL')
    })
  })

  describe('unregister()', function () {
    it('should unregister existing registration', async function () {
      const url = 'https://thegraph.com'

      // Register the indexer service
      await serviceRegistry.connect(indexer).register(url, geohash)

      // Unregister the indexer service
      const tx = serviceRegistry.connect(indexer).unregister()
      await expect(tx).to.emit(serviceRegistry, 'ServiceUnregistered').withArgs(indexer.address)
    })

    it('reject unregister non-existing registration', async function () {
      const tx = serviceRegistry.connect(indexer).unregister()
      await expect(tx).to.be.revertedWith('Service already unregistered')
    })
  })
})
