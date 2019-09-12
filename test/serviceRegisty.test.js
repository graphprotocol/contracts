const { expectEvent, expectRevert } = require('openzeppelin-test-helpers')

// contracts
const ServiceRegisty = artifacts.require('./ServiceRegistry.sol')
const helpers = require('./lib/testHelpers')

contract('Service Registry', accounts => {
  let deployedServiceRegistry
  const governor = accounts[0]
  const indexer = accounts[1]

  before(async () => {
    // deploy ServiceRegistry contract
    deployedServiceRegistry = await ServiceRegisty.new(
      governor, // governor
      { from: governor },
    )
  })

  it('...should allow setting URL with arbitrary length string', async () => {
    const url = 'https://192.168.2.1/'

    // Set the url
    const { logs } = await deployedServiceRegistry.setUrl(url, {
      from: indexer,
    })

    expectEvent.inLogs(logs, 'ServiceUrlSet', {
      serviceProvider: indexer,
      urlString: url,
    })
  })

  it('...should allow setting URL with a very long string', async () => {
    const url =
      'https://aaaaanksgrhlqghqrefgerqfgnsqgjklsohfdhjkfkjsdhrhesrhkfshkfehkusefhkjesjhfsehjfhkserhkjsehkrhesjkrhsjhrshjkerhjkshjerhjkse.com'

    // Set the url
    const { logs } = await deployedServiceRegistry.setUrl(url, {
      from: indexer,
    })

    expectEvent.inLogs(logs, 'ServiceUrlSet', {
      serviceProvider: indexer,
      urlString: url,
    })
  })

  it('...should allow setting multiple graph bootstrap indexer URLs', async () => {
    const url = 'https://192.168.2.1/'
    const urlBytes = web3.utils.utf8ToHex(url)

    const indexers = accounts.slice(5, 8)

    for (let i = 0; i < 3; i++) {
      // Set the url, only governor can
      const { logs } = await deployedServiceRegistry.setBootstrapIndexerURL(
        indexers[i],
        url,
        { from: governor },
      )

      // Verify that the the ServiceUrlSet event is emitted
      expectEvent.inLogs(logs, 'ServiceUrlSet', {
        serviceProvider: indexers[i],
        urlString: url,
      })

      // Verify that the indexer URL has been updated
      let indexerUrlBytes = await deployedServiceRegistry.bootstrapIndexerURLs(
        indexers[i],
      )
      assert(
        indexerUrlBytes === urlBytes,
        `Indexer ${i} URL was not set to ${url}`,
      )
    }
  })
})
