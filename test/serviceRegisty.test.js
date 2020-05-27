const { expectEvent, expectRevert } = require('@openzeppelin/test-helpers')

// contracts
const deployment = require('./lib/deployment')

contract('Service Registry', ([governor, indexer]) => {
  beforeEach(async function() {
    this.serviceRegisty = await deployment.deployServiceRegistry(governor)
    this.geohash = '69y7hdrhm6mp'

    this.shouldRegister = async function(url, geohash) {
      // Register the indexer service
      const { logs } = await this.serviceRegisty.register(url, geohash, {
        from: indexer,
      })

      // Updated state
      const indexerService = await this.serviceRegisty.services(indexer)
      expect(indexerService.url).to.be.eq(url)
      expect(indexerService.geohash).to.be.eq(geohash)

      // Event emitted
      expectEvent.inLogs(logs, 'ServiceRegistered', {
        indexer: indexer,
        url: url,
        geohash: geohash,
      })
    }
  })

  describe('register()', function() {
    it('should allow registering', async function() {
      const url = 'https://192.168.2.1/'
      await this.shouldRegister(url, this.geohash)
    })

    it('should allow registering with a very long string', async function() {
      const url = 'https://' + 'a'.repeat(125) + '.com'
      await this.shouldRegister(url, this.geohash)
    })

    it('should allow updating a registration', async function() {
      const [url1, geohash1] = ['https://thegraph.com', '69y7hdrhm6mp']
      const [url2, geohash2] = ['https://192.168.0.1', 'dr5regw2z6y']
      await this.shouldRegister(url1, geohash1)
      await this.shouldRegister(url2, geohash2)
    })

    it('reject registering empty URL', async function() {
      await expectRevert(
        this.serviceRegisty.register('', '', {
          from: indexer,
        }),
        'Service must specify a URL',
      )
    })
  })

  describe('unregister()', function() {
    it('should unregister existing registration', async function() {
      const url = 'https://thegraph.com'

      // Register the indexer service
      await this.serviceRegisty.register(url, this.geohash, {
        from: indexer,
      })

      // Unregister the indexer service
      const { logs } = await this.serviceRegisty.unregister({ from: indexer })

      // Event emitted
      expectEvent.inLogs(logs, 'ServiceUnregistered', {
        indexer: indexer,
      })
    })

    it('reject unregister non-existing registration', async function() {
      await expectRevert(
        this.serviceRegisty.unregister({ from: indexer }),
        'Service already unregistered',
      )
    })
  })
})
