const { expectEvent, expectRevert } = require('openzeppelin-test-helpers')

// contracts
const ServiceRegisty = artifacts.require('./ServiceRegistry.sol')
const helpers = require('./lib/testHelpers')


contract('Service Registry', accounts => {
  let deployedServiceRegistry

  beforeEach(async () => {
    // deploy GraphToken contract
    deployedServiceRegistry = await ServiceRegisty.new(
      accounts[0], // governor
      { from: accounts[0] }
    )
    assert.isObject(deployedServiceRegistry, 'Deploy ServiceRegistry contract.')
  })

  it('...should allow setting URL', async () => {
    const randomBytes = helpers.randomSubgraphIdBytes()

    // Set the url
    const { logs } = await deployedServiceRegistry.setUrl(accounts[1], randomBytes, { from: accounts[1] })
    assert(await deployedServiceRegistry.urls(accounts[1]) === web3.utils.bytesToHex(randomBytes), 'SetUrl did not store the URL properly.')

    expectEvent.inLogs(logs, 'ServiceUrlSet', { serviceProvider: accounts[1], url: web3.utils.bytesToHex(randomBytes) });

  })

  it('...should prevent non msg.sender from setting URL', async () => {
    const randomBytes = helpers.randomSubgraphIdBytes()

    // We expect the revert, and confirm it fails on the correct require statement be checking the error message
    await expectRevert(deployedServiceRegistry.setUrl(accounts[1], randomBytes, { from: accounts[2] }), "msg.sender must call")



  })

})
