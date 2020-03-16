const { expectEvent } = require('openzeppelin-test-helpers')

// contracts
const ServiceRegisty = artifacts.require('./ServiceRegistry.sol')
const helpers = require('../lib/testHelpers')

contract('Service Registry', accounts => {
  let deployedServiceRegistry

  before(async () => {
    // deploy ServiceRegistry contract
    deployedServiceRegistry = await ServiceRegisty.new(
      accounts[0], // governor
      { from: accounts[0] },
    )
  })

  it('...should allow setting URL 10 times', async () => {
    for (let i = 0; i < 10; i++) {
      const url = helpers.testServiceRegistryURLS[i]

      // Set the url
      const { logs } = await deployedServiceRegistry.setUrl(url, {
        from: accounts[i],
      })

      expectEvent.inLogs(logs, 'ServiceUrlSet', {
        serviceProvider: accounts[i],
        urlString: url,
      })
    }
  })
})
