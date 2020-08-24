import { expect } from 'chai'

import { ServiceRegistry } from '../build/typechain/contracts/ServiceRegistry'

import * as deployment from './lib/deployment'
import { getAccounts, Account } from './lib/testHelpers'

describe('ServiceRegistry', () => {
  let me: Account
  let indexer: Account

  let serviceRegistry: ServiceRegistry
  const geohash = '69y7hdrhm6mp'

  const shouldRegister = async (url: string, geohash: string) => {
    // Register the indexer service
    const tx = serviceRegistry.connect(indexer.signer).register(url, geohash)
    await expect(tx)
      .emit(serviceRegistry, 'ServiceRegistered')
      .withArgs(indexer.address, url, geohash)

    // Updated state
    const indexerService = await serviceRegistry.services(indexer.address)
    expect(indexerService.url).eq(url)
    expect(indexerService.geohash).eq(geohash)
  }

  before(async function () {
    ;[me, indexer] = await getAccounts()
  })

  beforeEach(async function () {
    const controller = await deployment.deployController(me.signer)
    serviceRegistry = await deployment.deployServiceRegistry(me.signer, controller.address)
  })

  describe('register', function () {
    it('should allow registering', async function () {
      const url = 'https://192.168.2.1/'
      await shouldRegister(url, geohash)
    })

    it('should allow registering with a very long string', async function () {
      const url = 'https://' + 'a'.repeat(125) + '.com'
      await shouldRegister(url, geohash)
    })

    it('should allow updating a registration', async function () {
      const [url1, geohash1] = ['https://thegraph.com', '69y7hdrhm6mp']
      const [url2, geohash2] = ['https://192.168.0.1', 'dr5regw2z6y']
      await shouldRegister(url1, geohash1)
      await shouldRegister(url2, geohash2)
    })

    it('reject registering empty URL', async function () {
      const tx = serviceRegistry.connect(indexer.signer).register('', '')
      await expect(tx).revertedWith('Service must specify a URL')
    })
  })

  describe('unregister', function () {
    it('should unregister existing registration', async function () {
      const url = 'https://thegraph.com'

      // Register the indexer service
      await serviceRegistry.connect(indexer.signer).register(url, geohash)

      // Unregister the indexer service
      const tx = serviceRegistry.connect(indexer.signer).unregister()
      await expect(tx).emit(serviceRegistry, 'ServiceUnregistered').withArgs(indexer.address)
    })

    it('reject unregister non-existing registration', async function () {
      const tx = serviceRegistry.connect(indexer.signer).unregister()
      await expect(tx).revertedWith('Service already unregistered')
    })
  })
})
