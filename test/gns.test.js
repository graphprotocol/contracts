const { expectEvent, expectRevert } = require('openzeppelin-test-helpers')

// contracts
const GNS = artifacts.require('./GNS.sol')
const helpers = require('./lib/testHelpers')

contract('GNS', accounts => {
  let deployedGNS
  const topLevelDomainName = 'thegraph.com'
  const topLevelDomainHash = web3.utils.soliditySha3(topLevelDomainName)
  const subdomainName = 'david'
  const hashedSubdomain = web3.utils.soliditySha3(
    web3.utils.soliditySha3(subdomainName),
    topLevelDomainHash,
  ) // NOTE: There is a bug with web3.utils.keccak256() when using multiple inputs. soliditySha3() must be used
  const subgraphID = helpers.randomSubgraphIdBytes()
  const ipfsHash = helpers.randomSubgraphIdBytes()

  before(async () => {
    // deploy GNS contract
    deployedGNS = await GNS.new(
      accounts[0], // governor
      { from: accounts[0] },
    )
    assert.isObject(deployedGNS, 'Deploy GNS contract.')
  })

  it('...should allow a user to register a domain. And then prevent another user from being able to', async () => {
    const { logs } = await deployedGNS.registerDomain(topLevelDomainName, {
      from: accounts[1],
    })
    const domain = await deployedGNS.domains(topLevelDomainHash)
    assert(
      (await domain.owner) === accounts[1],
      'Name was not registered properly.',
    )

    expectEvent.inLogs(logs, 'DomainAdded', {
      topLevelDomainHash: topLevelDomainHash,
      owner: accounts[1],
      domainName: topLevelDomainName,
    })

    // Confirm another user cannot register this name
    await expectRevert(
      deployedGNS.registerDomain(topLevelDomainName, { from: accounts[3] }),
      'Domain is already owned.',
    )
  })

  it('...should allow a user to create a subgraph only once, and not allow a different user to do so. ', async () => {
    const { logs } = await deployedGNS.createSubgraph(
      topLevelDomainHash,
      subdomainName,
      ipfsHash,
      { from: accounts[1] },
    )
    const domain = await deployedGNS.domains(hashedSubdomain)
    assert(
      (await domain.owner) === accounts[1],
      'Subdomain was not created properly.',
    )

    expectEvent.inLogs(logs, 'SubgraphCreated', {
      topLevelDomainHash: topLevelDomainHash,
      registeredHash: hashedSubdomain,
      subdomainName: subdomainName,
    })

    expectEvent.inLogs(logs, 'SubgraphMetadataChanged', {
      domainHash: hashedSubdomain,
      ipfsHash: web3.utils.bytesToHex(ipfsHash),
    })

    // Check that another user can't create
    await expectRevert(
      deployedGNS.createSubgraph(topLevelDomainHash, subdomainName, ipfsHash, {
        from: accounts[3],
      }),
      'Only domain owner can call.',
    )

    // Check that the owner can't call createSubgraph() twice
    await expectRevert(
      deployedGNS.createSubgraph(topLevelDomainHash, subdomainName, ipfsHash, {
        from: accounts[1],
      }),
      'Someone already owns this subdomain.',
    )
  })

  it('...should allow a user to register a subgraph to a subdomain, and not allow a different user to do so. ', async () => {
    const { logs } = await deployedGNS.updateDomainSubgraphID(
      hashedSubdomain,
      subgraphID,
      { from: accounts[1] },
    )
    const domain = await deployedGNS.domains(hashedSubdomain)
    assert(
      (await domain.subgraphID) === web3.utils.bytesToHex(subgraphID),
      'Subdomain was not registered properly.',
    )

    expectEvent.inLogs(logs, 'SubgraphIDUpdated', {
      domainHash: hashedSubdomain,
      subgraphID: web3.utils.bytesToHex(subgraphID),
    })

    // Check that another user can't register
    await expectRevert(
      deployedGNS.updateDomainSubgraphID(hashedSubdomain, subgraphID, {
        from: accounts[3],
      }),
      'Only domain owner can call.',
    )
  })

  it('...should allow subgraph metadata to be updated', async () => {
    const { logs } = await deployedGNS.changeSubgraphMetadata(
      hashedSubdomain,
      ipfsHash,
      { from: accounts[1] },
    )

    expectEvent.inLogs(logs, 'SubgraphMetadataChanged', {
      domainHash: hashedSubdomain,
      ipfsHash: web3.utils.bytesToHex(ipfsHash),
    })

    // Check that a different owner can't call
    await expectRevert(
      deployedGNS.changeSubgraphMetadata(ipfsHash, hashedSubdomain, {
        from: accounts[3],
      }),
      'Only domain owner can call.',
    )
  })

  it('...should allow a user to transfer a domain', async () => {
    const { logs } = await deployedGNS.transferDomainOwnership(
      hashedSubdomain,
      accounts[2],
      { from: accounts[1] },
    )

    expectEvent.inLogs(logs, 'DomainTransferred', {
      domainHash: hashedSubdomain,
      newOwner: accounts[2],
    })

    // Check that a different owner can't call
    await expectRevert(
      deployedGNS.transferDomainOwnership(hashedSubdomain, accounts[4], {
        from: accounts[3],
      }),
      'Only domain owner can call.',
    )
  })

  it('...should allow a domain and subgraphID to be deleted', async () => {
    await expectRevert(
      deployedGNS.deleteSubdomain(hashedSubdomain, { from: accounts[3] }),
      'Only domain owner can call.',
    )

    const { logs } = await deployedGNS.deleteSubdomain(hashedSubdomain, {
      from: accounts[2],
    })

    expectEvent.inLogs(logs, 'DomainDeleted', {
      domainHash: hashedSubdomain,
    })

    const deletedDomain = await deployedGNS.domains(hashedSubdomain)
    assert(
      deletedDomain.subgraphID === helpers.zeroHex(),
      'SubgraphID was not deleted',
    )
    assert(
      deletedDomain.owner === helpers.zeroAddress(),
      'Owner was not removed',
    )
  })

  it('...should allow account metadata event to be emitted  ', async () => {
    const accountIPFSHash = helpers.randomSubgraphIdBytes()

    const { logs } = await deployedGNS.changeAccountMetadata(accountIPFSHash, {
      from: accounts[2],
    })

    expectEvent.inLogs(logs, 'AccountMetadataChanged', {
      account: accounts[2],
      ipfsHash: web3.utils.bytesToHex(accountIPFSHash),
    })
  })
})

/*TODO
 * test that both the tld and subdomains are properly registered
 *

 */
