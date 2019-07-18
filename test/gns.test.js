const { expectEvent, expectRevert } = require('openzeppelin-test-helpers')

// contracts
const GNS = artifacts.require('./GNS.sol')
const helpers = require('./lib/testHelpers')

contract('GNS', accounts => {
  let deployedGNS
  const topLevelDomainName = 'thegraph.com'
  const topLevelDomainHash = web3.utils.keccak256(topLevelDomainName)
  const subdomainName = 'david.thegraph.com'
  const hashedSubdomain = web3.utils.keccak256(subdomainName)
  const subgraphID = helpers.randomSubgraphIdBytes()
  const ipfsHash = helpers.randomSubgraphIdBytes()

  before(async () => {
    // deploy GNS contract
    deployedGNS = await GNS.new(
      accounts[0], // governor
      { from: accounts[0] }
    )
    assert.isObject(deployedGNS, 'Deploy GNS contract.')
  })

  it('...should allow a user to register a domain. And then prevent another user from being able to', async () => {
    const { logs } = await deployedGNS.registerDomain(topLevelDomainName, { from: accounts[1] })

    assert(await deployedGNS.domainOwners(topLevelDomainHash) === accounts[1], 'Name was not registered properly.')

    expectEvent.inLogs(logs, 'DomainAdded', {
      topLevelDomainHash: topLevelDomainHash,
      owner: accounts[1],
      domainName: topLevelDomainName
    })

    // Confirm another user cannot register this name
    await expectRevert(deployedGNS.registerDomain(topLevelDomainName, { from: accounts[1] }), 'This address must already be owned.')

  })

  it('...should allow a user to register a subgraph to a subdomain only once, and not allow a different user to do so. ', async () => {
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
    const { logs } = await deployedGNS.changeSubgraphMetadata(ipfsHash, topLevelDomainHash, hashedSubdomain, { from: accounts[1] })

    expectEvent.inLogs(logs, 'SubgraphMetadataChanged', {
      topLevelDomainHash: topLevelDomainHash,
      subdomainHash: hashedSubdomain,
      ipfsHash: web3.utils.bytesToHex(ipfsHash)
    })

    // Check that the owner can't call addSubgraphToDomain() twice
    await expectRevert(deployedGNS.changeSubgraphMetadata(ipfsHash, topLevelDomainHash, hashedSubdomain, { from: accounts[3] }), 'Only Domain owner can call')
  })

  it('...should allow subgraphID to be changed on a subdomain ', async () => {
    const changedSubgraphID = helpers.randomSubgraphIdBytes()
    const unregisteredDomain = helpers.randomSubgraphIdBytes()

    // Expect changing a domain subgraphID on a non-registered domain to fail
    await expectRevert(deployedGNS.changeDomainSubgraphId(topLevelDomainHash, unregisteredDomain, changedSubgraphID, { from: accounts[1] }), 'The subdomain must already be registered in order to change the ID')

    // Expect call from non-owner to fail
    await expectRevert(deployedGNS.changeDomainSubgraphId(topLevelDomainHash, hashedSubdomain, changedSubgraphID, { from: accounts[3] }), 'Only Domain owner can call')

    const { logs } = await deployedGNS.changeDomainSubgraphId(topLevelDomainHash, hashedSubdomain, changedSubgraphID, { from: accounts[1] })

    expectEvent.inLogs(logs, 'SubgraphIdChanged', {
      topLevelDomainHash: topLevelDomainHash,
      subdomainHash: hashedSubdomain,
      subgraphId: web3.utils.bytesToHex(changedSubgraphID)
    })

    const newID = await deployedGNS.domainsToSubgraphIDs(hashedSubdomain)
    assert(newID === web3.utils.bytesToHex(changedSubgraphID), 'SubgraphID was not changed')

  })

  it('...should allow a subdomain and subgraphID to be deleted', async () => {
    await expectRevert(deployedGNS.deleteSubdomain(topLevelDomainHash, hashedSubdomain, { from: accounts[3] }), 'Only Domain owner can call')

    const { logs } = await deployedGNS.deleteSubdomain(topLevelDomainHash, hashedSubdomain, { from: accounts[1] })

    expectEvent.inLogs(logs, 'SubgraphIdDeleted', {
      topLevelDomainHash: topLevelDomainHash,
      subdomainHash: hashedSubdomain,
    })

    const deletedID = await deployedGNS.domainsToSubgraphIDs(hashedSubdomain)
    const deletedSubdomain = await deployedGNS.subDomains(topLevelDomainHash, hashedSubdomain)
    assert(deletedID === helpers.zeroHex(), 'SubgraphID was not deleted')
    assert(deletedSubdomain === false, 'Subdomain was not deleted')

  })

  it('...should allow account metadata event to be emitted  ', async () => {
    const accountIPFSHash = helpers.randomSubgraphIdBytes()
    
    const { logs } = await deployedGNS.changeAccountMetadata(accountIPFSHash, { from: accounts[1] })

    expectEvent.inLogs(logs, 'AccountMetadataChanged', {
      account: accounts[1],
      ipfsHash: web3.utils.bytesToHex(accountIPFSHash),
    })
  })

})
