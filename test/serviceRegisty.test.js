const { expectEvent, expectRevert } = require('openzeppelin-test-helpers')

// contracts
const ServiceRegisty = artifacts.require('./ServiceRegistry.sol')
const helpers = require('./lib/testHelpers')

contract('Service Registry', accounts => {
  let deployedServiceRegistry

  before(async () => {
    // deploy ServiceRegistry contract
    deployedServiceRegistry = await ServiceRegisty.new(
      accounts[0], // governor
      { from: accounts[0] },
    )
    assert.isObject(deployedServiceRegistry, 'Deploy ServiceRegistry contract.')
  })

  it('...should allow setting URL with arbitrary length string', async () => {
    const url = "https://192.168.2.1/"
    const urlBytes = web3.utils.utf8ToHex(url)

    // Set the url
    const { logs } = await deployedServiceRegistry.setUrl(
      accounts[1],
      url,
      { from: accounts[1] },
    )
    assert(
      (await deployedServiceRegistry.urls(accounts[1])) ===
      urlBytes,
      'SetUrl did not store the URL properly.',
    )

    expectEvent.inLogs(logs, 'ServiceUrlSet', {
      serviceProvider: accounts[1],
      urlString: url,
      urlBytes: urlBytes
    })
  })

  it('...should allow setting URL with a very long string', async () => {
    const url = "https://aaaaanksgrhlqghqrefgerqfgnsqgjklsohfdhjkfkjsdhrhesrhkfshkfehkusefhkjesjhfsehjfhkserhkjsehkrhesjkrhsjhrshjkerhjkshjerhjkse.com"
    const urlBytes = web3.utils.utf8ToHex(url)

    // Set the url
    const { logs } = await deployedServiceRegistry.setUrl(
      accounts[1],
      url,
      { from: accounts[1] },
    )
    assert(
      (await deployedServiceRegistry.urls(accounts[1])) ===
      urlBytes,
      'SetUrl did not store the URL properly.',
    )

    expectEvent.inLogs(logs, 'ServiceUrlSet', {
      serviceProvider: accounts[1],
      urlString: url,
      urlBytes: urlBytes
    })
  })


  it('...should prevent non msg.sender from setting URL', async () => {
    const url = "https://192.168.2.1/"

    // We expect the revert, and confirm it fails on the correct require statement be checking the error message
    await expectRevert(
      deployedServiceRegistry.setUrl(accounts[1], url, {
        from: accounts[2],
      }),
      'msg.sender must call',
    )
  })
})
