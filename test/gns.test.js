const { expectEvent, expectRevert } = require('openzeppelin-test-helpers')

// contracts
const GNS = artifacts.require('./GNS.sol')
const helpers = require('./lib/testHelpers')

/*
What to test
- all events ( within each test)
- all data is publically callable (should see when verifying in each test
- a user can register a domain (and others cannot do this)
  - that user can now begin adding subdomains, subgraphs, and metadata (addSubgraphToDomain)
  - the domain can be transferred
  - subgraph metadata can be updated
  - subdomain can be deleted
  - subgraph ID can be changed
- account metadata can be updated by msg.sender only
 */

contract('GNS', accounts => {
  let deployedGNS

  before(async () => {
    // deploy GNS contract
    deployedGNS = await GNS.new(
      accounts[0], // governor
      { from: accounts[0] }
    )
    assert.isObject(deployedGNS, 'Deploy GNS contract.')
  })

  it('...should allow a user to register a domain. And then prevent another user from being able to', async () => {
    const domainName = 'thegraph.com'
    const hashedName = web3.utils.keccak256(domainName)

    const { logs } = await deployedGNS.registerDomain(domainName, { from: accounts[1] })

    assert(await deployedGNS.domainOwners(hashedName) === accounts[1], 'Name was not registered properly.')

    expectEvent.inLogs(logs, 'DomainAdded', {
      topLevelDomainHash: hashedName,
      owner: accounts[1],
      domainName: domainName
    })

    // Confirm another user cannot register this name

    await expectRevert(deployedGNS.registerDomain(domainName, { from: accounts[1] }), 'This address must already be owned.')

  })

  it('...should allow a user to register a subgraph to a subdomain only once, and not allow a different user to do so. ', async () => {
    const topLevelDomainName = 'thegraph.com'
    const topLevelDomainHash = web3.utils.keccak256(topLevelDomainName)
    const subdomainName = 'david.thegraph.com'
    const hashedSubdomain = web3.utils.keccak256(subdomainName)
    const subgraphID = helpers.randomSubgraphIdBytes()
    const ipfsHash = helpers.randomSubgraphIdBytes()

    const { logs } = await deployedGNS.addSubgraphToDomain(topLevelDomainHash, subdomainName, subgraphID, ipfsHash, { from: accounts[1] })

    assert(await deployedGNS.subDomains(topLevelDomainHash, hashedSubdomain) === true, 'Subdomain was not registered properly.')

    expectEvent.inLogs(logs, 'SubgraphIdAdded', {
      topLevelDomainHash: topLevelDomainHash,
      subdomainHash: hashedSubdomain,
      subgraphId: web3.utils.bytesToHex(subgraphID),
      subdomainName: subdomainName,
      ipfsHash: web3.utils.bytesToHex(ipfsHash)
    })

    // Check that another user can't register
    await expectRevert(deployedGNS.addSubgraphToDomain(topLevelDomainHash, subdomainName, subgraphID, ipfsHash, { from: accounts[3] }), 'Only Domain owner can call')

    // Check that the owner can't call addSubgraphToDomain() twice
    await expectRevert(deployedGNS.addSubgraphToDomain(topLevelDomainHash, subdomainName, subgraphID, ipfsHash, { from: accounts[1] }), 'The subgraphID must not be set yet in order to call this function.')
  })

  it('...should allow subgraph metadata to be updated', async () => {
    const topLevelDomainName = 'thegraph.com'
    const topLevelDomainHash = web3.utils.keccak256(topLevelDomainName)
    const subdomainName = 'david.thegraph.com'
    const hashedSubdomain = web3.utils.keccak256(subdomainName)
    const ipfsHash = helpers.randomSubgraphIdBytes()

    const { logs } = await deployedGNS.changeSubgraphMetadata(ipfsHash, topLevelDomainHash, hashedSubdomain, { from: accounts[1] })

    expectEvent.inLogs(logs, 'SubgraphMetadataChanged', {
      topLevelDomainHash: topLevelDomainHash,
      subdomainHash: hashedSubdomain,
      ipfsHash: web3.utils.bytesToHex(ipfsHash)
    })

    // Check that the owner can't call addSubgraphToDomain() twice
    await expectRevert(deployedGNS.changeSubgraphMetadata(ipfsHash, topLevelDomainHash, hashedSubdomain, { from: accounts[3] }), 'Only Domain owner can call')
  })

  it('...should allow a user to transfer a domain', async () => {
    const topLevelDomainName = 'thegraph.com'
    const topLevelDomainHash = web3.utils.keccak256(topLevelDomainName)
    const subdomainName = 'david.thegraph.com'
    const hashedSubdomain = web3.utils.keccak256(subdomainName)
    const ipfsHash = helpers.randomSubgraphIdBytes()

    const { logs } = await deployedGNS.changeSubgraphMetadata(ipfsHash, topLevelDomainHash, hashedSubdomain, { from: accounts[1] })

    expectEvent.inLogs(logs, 'SubgraphMetadataChanged', {
      topLevelDomainHash: topLevelDomainHash,
      subdomainHash: hashedSubdomain,
      ipfsHash: web3.utils.bytesToHex(ipfsHash)
    })

    // Check that the owner can't call addSubgraphToDomain() twice
    await expectRevert(deployedGNS.changeSubgraphMetadata(ipfsHash, topLevelDomainHash, hashedSubdomain, { from: accounts[3] }), 'Only Domain owner can call')
  })

  it('...should allow a subdomain and subgraphID to be deleted', async () => {
    const topLevelDomainName = 'thegraph.com'
    const topLevelDomainHash = web3.utils.keccak256(topLevelDomainName)
    const subdomainName = 'david.thegraph.com'
    const hashedSubdomain = web3.utils.keccak256(subdomainName)

    await expectRevert(deployedGNS.deleteSubdomain(topLevelDomainHash, hashedSubdomain, { from: accounts[3] }), 'Only Domain owner can call')

    const { logs } = await deployedGNS.deleteSubdomain(topLevelDomainHash, hashedSubdomain, { from: accounts[1] })

    expectEvent.inLogs(logs, 'SubgraphIdDeleted', {
      topLevelDomainHash: topLevelDomainHash,
      subdomainHash: hashedSubdomain,
    })

    // should be bytes(0)
    let deletedID = await deployedGNS.domainsToSubgraphIDs(hashedSubdomain)
    // should be false
    let deletedSubdomain = await deployedGNS.subDomains(topLevelDomainHash, hashedSubdomain)

  })

  it('...should allow subgraphID to be changed on a subdomain ', async () => {

  })

  it('...should allow account metadata to be updated by msg.sender only  ', async () => {

  })

  it('...should ', async () => {

  })
})
