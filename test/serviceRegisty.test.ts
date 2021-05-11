import { expect } from 'chai'

import { ServiceRegistry } from '../build/types/ServiceRegistry'
import { Staking } from '../build/types/Staking'

import { getAccounts, Account } from './lib/testHelpers'
import { NetworkFixture } from './lib/fixtures'

describe('ServiceRegistry', () => {
  let governor: Account
  let indexer: Account
  let operator: Account

  let fixture: NetworkFixture

  let serviceRegistry: ServiceRegistry
  let staking: Staking

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
    ;[governor, indexer, operator] = await getAccounts()

    fixture = new NetworkFixture()
    ;({ serviceRegistry, staking } = await fixture.load(governor.signer, governor.signer))
  })

  beforeEach(async function () {
    await fixture.setUp()
  })

  afterEach(async function () {
    await fixture.tearDown()
  })

  describe('register', function () {
    const url = 'https://192.168.2.1/'
    const geo = '69y7hdrhm6mp'

    it('should allow registering', async function () {
      await shouldRegister(url, geo)
    })

    it('should allow registering with a very long string', async function () {
      const url = 'https://' + 'a'.repeat(125) + '.com'
      await shouldRegister(url, geo)
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

    describe('operator', function () {
      it('reject register from unauthorized operator', async function () {
        const tx = serviceRegistry
          .connect(operator.signer)
          .registerFor(indexer.address, 'http://thegraph.com', '')
        await expect(tx).revertedWith('!auth')
      })

      it('should register from operator', async function () {
        // Auth and register
        await staking.connect(indexer.signer).setOperator(operator.address, true)
        await serviceRegistry.connect(operator.signer).registerFor(indexer.address, url, geo)

        // Updated state
        const indexerService = await serviceRegistry.services(indexer.address)
        expect(indexerService.url).eq(url)
        expect(indexerService.geohash).eq(geo)
      })
    })
  })

  describe('unregister', function () {
    const url = 'https://192.168.2.1/'
    const geo = '69y7hdrhm6mp'

    it('should unregister existing registration', async function () {
      // Register the indexer service
      await serviceRegistry.connect(indexer.signer).register(url, geo)

      // Unregister the indexer service
      const tx = serviceRegistry.connect(indexer.signer).unregister()
      await expect(tx).emit(serviceRegistry, 'ServiceUnregistered').withArgs(indexer.address)
    })

    it('reject unregister non-existing registration', async function () {
      const tx = serviceRegistry.connect(indexer.signer).unregister()
      await expect(tx).revertedWith('Service already unregistered')
    })

    describe('operator', function () {
      it('reject unregister from unauthorized operator', async function () {
        // Register the indexer service
        await serviceRegistry.connect(indexer.signer).register(url, geo)

        // Unregister
        const tx = serviceRegistry.connect(operator.signer).unregisterFor(indexer.address)
        await expect(tx).revertedWith('!auth')
      })

      it('should unregister from operator', async function () {
        // Register the indexer service
        await serviceRegistry.connect(indexer.signer).register(url, geo)

        // Auth and unregister
        await staking.connect(indexer.signer).setOperator(operator.address, true)
        await serviceRegistry.connect(operator.signer).unregisterFor(indexer.address)

        // Updated state
        const indexerService = await serviceRegistry.services(indexer.address)
        expect(indexerService.url).eq('')
        expect(indexerService.geohash).eq('')
      })
    })
  })
})
