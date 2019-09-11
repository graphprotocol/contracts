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
    assert.isObject(deployedServiceRegistry, 'Deploy ServiceRegistry contract.')
  })

  it('...should allow setting URL with arbitrary length string', async () => {
    const url = 'https://192.168.2.1/'
    const urlBytes = web3.utils.utf8ToHex(url)

    // Set the url
    const { logs } = await deployedServiceRegistry.setUrl(
      url,
      { from: indexer },
    )

    expectEvent.inLogs(logs, 'ServiceUrlSet', {
      serviceProvider: indexer,
      urlString: url,
      urlBytes: urlBytes
    })
  })

  it('...should allow setting URL with a very long string', async () => {
    const url = 'https://aaaaanksgrhlqghqrefgerqfgnsqgjklsohfdhjkfkjsdhrhesrhkfshkfehkusefhkjesjhfsehjfhkserhkjsehkrhesjkrhsjhrshjkerhjkshjerhjkse.com'
    const urlBytes = web3.utils.utf8ToHex(url)

    // Set the url
    const { logs } = await deployedServiceRegistry.setUrl(
      url,
      { from: indexer },
    )

    expectEvent.inLogs(logs, 'ServiceUrlSet', {
      serviceProvider: indexer,
      urlString: url,
      urlBytes: urlBytes
    })
  })


  it('...should allow setting multiple graph network service providers URL, getting the length, and removing an indexer', async () => {
    const url = 'https://192.168.2.1/'
    const urlBytes = web3.utils.utf8ToHex(url)
    const indexers = accounts.slice(5,8)
    for (let i = 0; i < 3; i++) {

      // Set the url, only governor can
      const { logs } = await deployedServiceRegistry.setGraphNetworkServiceProviderURLs(
        indexers[i],
        url,
        { from: governor },
      )

      expectEvent.inLogs(logs, 'ServiceUrlSet', {
        serviceProvider: indexers[i],
        urlString: url,
        urlBytes: urlBytes
      })
    }

    const indexersSetLength = await deployedServiceRegistry.numberOfGraphNetworkServiceProviderURLs()
    assert(indexersSetLength.toNumber() === indexers.length, 'The amount of indexers are not matching.')

    // Remove a URL, only governor can
    await deployedServiceRegistry.removeGraphNetworkIndexerURL(
      indexers[1],
      { from: governor },
    )

    for (let i = 0; i < 3; i++) {
      let serviceProvider = await deployedServiceRegistry.graphNetworkServiceProviderURLs(i)
      if (i == 1) {
        assert(serviceProvider.indexer === helpers.zeroAddress() , `Indexer address ${i} was not deleted .`)
        assert(null === serviceProvider.url, `Indexer url ${i} was not deleted.`)
      } else {
        assert(serviceProvider.indexer === indexers[i], `Indexer address ${i} does not match.`)
        assert(web3.utils.utf8ToHex(url) === serviceProvider.url, `Indexer url ${i} does not match.`)
      }
    }
  })

})
