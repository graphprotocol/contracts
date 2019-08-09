const { expectEvent, expectRevert } = require('openzeppelin-test-helpers')

// contracts
const GNS = artifacts.require('./GNS.sol')
const helpers = require('../lib/testHelpers')

contract('GNS', accounts => {
  let deployedGNS
  // NOTE: There is a bug with web3.utils.keccak256() when using multiple inputs. soliditySha3() must be used
  // const subgraphID = helpers.randomSubgraphIdBytes()

  before(async () => {
    // deploy GNS contract
    deployedGNS = await GNS.new(
      accounts[0], // governor
      { from: accounts[0] },
    )
    assert.isObject(deployedGNS, 'Deploy GNS contract.')
  })

  it('...should allow a 10 users to register 10 domains', async () => {
    let accountCount = 0
    for (let i = 0; i < 10; i++) {
      // Not in use
      // if (i % 10 === 0 && i !== 0) {
      //   accountCount++
      // }
      const { logs } = await deployedGNS.registerDomain(helpers.topLevelDomainNames[i], {
        from: accounts[accountCount],
      })
      const topLevelDomainHash = web3.utils.soliditySha3(helpers.topLevelDomainNames[i])
      const domain = await deployedGNS.domains(topLevelDomainHash)
      assert(domain.owner === accounts[accountCount], 'Name was not registered properly.',)

      expectEvent.inLogs(logs, 'DomainAdded', {
        topLevelDomainHash: topLevelDomainHash,
        owner: accounts[accountCount],
        domainName: helpers.topLevelDomainNames[i],
      })
      accountCount++
    }
  })

  /*
   * Here I set up 10 real IPFS hashes for subgraph metadata, so that we can see the mapping work
   * in action. They can be found in the graph network subgraph repository. Above 10 are just
   * set to 0xffffff....ffff to obfuscate them
   *
   */
  it('...should allow multiple subdomains to be registered to tlds  ', async () => {
    let accountCount = 0
    for (let i = 0; i < 10; i++) {
      const topLevelDomainHash = web3.utils.soliditySha3(helpers.topLevelDomainNames[i])
      let ipfsHash
      ipfsHash = helpers.testIPFSHashes[i]

      // Not in use
      // if (i < 10){
      //   ipfsHash = helpers.testIPFSHashes[i]
      // } else {
      //   ipfsHash = "0xffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff"
      // }

      // if even, create a sub domain. if odd, create a subgraph at top level domain
      if (i % 2 === 0) {
        const { logs } = await deployedGNS.createSubgraph(
          topLevelDomainHash,
          helpers.subdomainNames[i],
          ipfsHash,
          { from: accounts[accountCount] },
        )
        const hashedSubdomain = web3.utils.soliditySha3(web3.utils.soliditySha3(helpers.subdomainNames[i]), topLevelDomainHash)
        const subdomain = await deployedGNS.domains(hashedSubdomain)
        assert(subdomain.owner === accounts[accountCount],
          'Subdomain was not created properly.',
        )

        expectEvent.inLogs(logs, 'SubgraphCreated', {
          topLevelDomainHash: topLevelDomainHash,
          registeredHash: hashedSubdomain,
          subdomainName: helpers.subdomainNames[i],
        })

        expectEvent.inLogs(logs, 'SubgraphMetadataChanged', {
          domainHash: hashedSubdomain,
          ipfsHash: ipfsHash,
        })
      } else {
        const { logs } = await deployedGNS.createSubgraph(
          topLevelDomainHash,
          "",
          ipfsHash,
          { from: accounts[accountCount] },
        )
        const domain = await deployedGNS.domains(topLevelDomainHash)
        assert(domain.owner === accounts[accountCount],
          'Subdomain was not created properly.',
        )

        expectEvent.inLogs(logs, 'SubgraphCreated', {
          topLevelDomainHash: topLevelDomainHash,
          registeredHash: topLevelDomainHash,
          subdomainName: "",
        })

        expectEvent.inLogs(logs, 'SubgraphMetadataChanged', {
          domainHash: topLevelDomainHash,
          ipfsHash: ipfsHash,
        })
      }
      accountCount++
    }
  })
//
//   it('...should allow a user to register a subgraph to a subdomain, and not allow a different user to do so. ', async () => {
//     const { logs } = await deployedGNS.updateDomainSubgraphID(
//       hashedSubdomain,
//       subgraphID,
//       { from: accounts[1] },
//     )
//     const domain = await deployedGNS.domains(hashedSubdomain)
//     assert(
//       (await domain.subgraphID) === web3.utils.bytesToHex(subgraphID),
//       'Subdomain was not registered properly.',
//     )
//
//     expectEvent.inLogs(logs, 'SubgraphIDUpdated', {
//       domainHash: hashedSubdomain,
//       subgraphID: web3.utils.bytesToHex(subgraphID),
//     })
//
//     // Check that another user can't register
//     await expectRevert(
//       deployedGNS.updateDomainSubgraphID(hashedSubdomain, subgraphID, {
//         from: accounts[3],
//       }),
//       'Only domain owner can call.',
//     )
//   })
//
//   it('...should allow subgraph metadata to be updated', async () => {
//     const { logs } = await deployedGNS.changeSubgraphMetadata(
//       hashedSubdomain,
//       ipfsHash,
//       { from: accounts[1] },
//     )
//
//     expectEvent.inLogs(logs, 'SubgraphMetadataChanged', {
//       domainHash: hashedSubdomain,
//       ipfsHash: web3.utils.bytesToHex(ipfsHash),
//     })
//
//     // Check that a different owner can't call
//     await expectRevert(
//       deployedGNS.changeSubgraphMetadata(ipfsHash, hashedSubdomain, {
//         from: accounts[3],
//       }),
//       'Only domain owner can call.',
//     )
//   })
//
//   it('...should allow a user to transfer a domain', async () => {
//     const { logs } = await deployedGNS.transferDomainOwnership(
//       hashedSubdomain,
//       accounts[2],
//       { from: accounts[1] },
//     )
//
//     expectEvent.inLogs(logs, 'DomainTransferred', {
//       domainHash: hashedSubdomain,
//       newOwner: accounts[2],
//     })
//
//     // Check that a different owner can't call
//     await expectRevert(
//       deployedGNS.transferDomainOwnership(hashedSubdomain, accounts[4], {
//         from: accounts[3],
//       }),
//       'Only domain owner can call.',
//     )
//   })
//
//   it('...should allow a domain and subgraphID to be deleted', async () => {
//     await expectRevert(
//       deployedGNS.deleteSubdomain(hashedSubdomain, { from: accounts[3] }),
//       'Only domain owner can call.',
//     )
//
//     const { logs } = await deployedGNS.deleteSubdomain(hashedSubdomain, {
//       from: accounts[2],
//     })
//
//     expectEvent.inLogs(logs, 'DomainDeleted', {
//       domainHash: hashedSubdomain,
//     })
//
//     const deletedDomain = await deployedGNS.domains(hashedSubdomain)
//     assert(
//       deletedDomain.subgraphID === helpers.zeroHex(),
//       'SubgraphID was not deleted',
//     )
//     assert(
//       deletedDomain.owner === helpers.zeroAddress(),
//       'Owner was not removed',
//     )
//   })
//
//   it('...should allow account metadata event to be emitted  ', async () => {
//     const accountIPFSHash = helpers.randomSubgraphIdBytes()
//
//     const { logs } = await deployedGNS.changeAccountMetadata(accountIPFSHash, {
//       from: accounts[2],
//     })
//
//     expectEvent.inLogs(logs, 'AccountMetadataChanged', {
//       account: accounts[2],
//       ipfsHash: web3.utils.bytesToHex(accountIPFSHash),
//     })
//   })
})
//
// /*TODO
//  * test that both the tld and subdomains are properly registered
//  *
//
//  */
