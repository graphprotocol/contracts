const { expectEvent, expectRevert } = require('openzeppelin-test-helpers')

// contracts
const GNS = artifacts.require('./GNS.sol')
const helpers = require('../lib/testHelpers')

contract('GNS', accounts => {
  let deployedGNS
  const topLevelDomainNames = [
    'tld1', 'tld2', 'tld3', 'tld4', 'tld5', 'tld6', 'tld7', 'tld8', 'tld9', 'tld10',
    'tld11', 'tld12', 'tld13', 'tld14', 'tld15', 'tld16', 'tld17', 'tld18', 'tld19', 'tld20',
    'tld21', 'tld22', 'tld23', 'tld24', 'tld25', 'tld26', 'tld27', 'tld28', 'tld29', 'tld30',
    'tld31', 'tld32', 'tld33', 'tld34', 'tld35', 'tld36', 'tld37', 'tld38', 'tld39', 'tld40',
    'tld41', 'tld42', 'tld43', 'tld44', 'tld45', 'tld46', 'tld47', 'tld48', 'tld49', 'tld50',
    'tld51', 'tld52', 'tld53', 'tld54', 'tld55', 'tld56', 'tld57', 'tld58', 'tld59', 'tld60',
    'tld61', 'tld62', 'tld63', 'tld64', 'tld65', 'tld66', 'tld67', 'tld68', 'tld69', 'tld70',
    'tld71', 'tld72', 'tld73', 'tld74', 'tld75', 'tld76', 'tld77', 'tld78', 'tld79', 'tld80',
    'tld81', 'tld82', 'tld83', 'tld84', 'tld85', 'tld86', 'tld87', 'tld88', 'tld89', 'tld90',
    'tld91', 'tld92', 'tld93', 'tld94', 'tld95', 'tld96', 'tld97', 'tld98', 'tld99', 'tld100'
  ]
  const subdomainNames = [
    'subDomain1', 'subDomain2', 'subDomain3', 'subDomain4', 'subDomain5',
    'subDomain6', 'subDomain7', 'subDomain8', 'subDomain9', 'subDomain10',
    'subDomain11', 'subDomain12', 'subDomain13', 'subDomain14', 'subDomain15',
    'subDomain16', 'subDomain17', 'subDomain18', 'subDomain19', 'subDomain20',
    'subDomain21', 'subDomain22', 'subDomain23', 'subDomain24', 'subDomain25',
    'subDomain26', 'subDomain27', 'subDomain28', 'subDomain29', 'subDomain30',
    'subDomain31', 'subDomain32', 'subDomain33', 'subDomain34', 'subDomain35',
    'subDomain36', 'subDomain37', 'subDomain38', 'subDomain39', 'subDomain40',
    'subDomain41', 'subDomain42', 'subDomain43', 'subDomain44', 'subDomain45',
    'subDomain46', 'subDomain47', 'subDomain48', 'subDomain49', 'subDomain50',
    'subDomain51', 'subDomain52', 'subDomain53', 'subDomain54', 'subDomain55',
    'subDomain56', 'subDomain57', 'subDomain58', 'subDomain59', 'subDomain60',
    'subDomain61', 'subDomain62', 'subDomain63', 'subDomain64', 'subDomain65',
    'subDomain66', 'subDomain67', 'subDomain68', 'subDomain69', 'subDomain70',
    'subDomain71', 'subDomain72', 'subDomain73', 'subDomain74', 'subDomain75',
    'subDomain76', 'subDomain77', 'subDomain78', 'subDomain79', 'subDomain80',
    'subDomain81', 'subDomain82', 'subDomain83', 'subDomain84', 'subDomain85',
    'subDomain86', 'subDomain87', 'subDomain88', 'subDomain89', 'subDomain90',
    'subDomain91', 'subDomain92', 'subDomain93', 'subDomain94', 'subDomain95',
    'subDomain96', 'subDomain97', 'subDomain98', 'subDomain99', 'subDomain100'
  ]

  const testIPFSHashes = [
    "0xeb50d096ba95573ae31640e38e4ef64fd02eec174f586624a37ea04e7bd8c751",
    "0x3ab4598d9c0b61477f7b91502944a8e216d9e64de2116a840ca5f75692230864",
    "0x50b537c6aa4956b2acb13322fe8d3508daf0714a94888bd1a3fc26c92d62e422",
    "0x1566216996cf5f8b9ff98d86b846bb370917bdd0a3498d4adc5ba353668f815c",
    "0xeba476b133f270d2717337e2537fed25c7f3a88b4953fba5f1f02e794dcb2b9c",
    "0x8e05bf18a8289544b93222f183d2e44698438283daf5f72bee7e246f0f07d936",
    "0x2b8a60dd231a6e7477ad32f801b38c583ea25650a24a04d5905cea452c2e7d94",
    "0x18b2f2152d0ab77b56f1d881d489183e6fd700a5d18f42f31a7f7078fda5b011",
    "0x067fe1fb5d0c3896ddc762f41d26acac6f00e9d9fd2fb67ca434228751148a14",
    "0x217b212d19df6d06147c96409704a2896b5b4d2a8c620b27dce3140235c909cb"
  ]

  // NOTE: There is a bug with web3.utils.keccak256() when using multiple inputs. soliditySha3() must be used
  // const subgraphID = helpers.randomSubgraphIdBytes()
  // const ipfsHash = helpers.randomSubgraphIdBytes()

  before(async () => {
    // deploy GNS contract
    deployedGNS = await GNS.new(
      accounts[0], // governor
      { from: accounts[0] },
    )
    assert.isObject(deployedGNS, 'Deploy GNS contract.')
  })

  it('...should allow a 10 users to register 10 domains each', async () => {
    let accountCount = 0
    for (let i = 0; i < topLevelDomainNames.length; i++) {
      if (i % 10 === 0 && i !== 0) {
        accountCount++
      }
      const { logs } = await deployedGNS.registerDomain(topLevelDomainNames[i], {
        from: accounts[accountCount],
      })
      const topLevelDomainHash = web3.utils.soliditySha3(topLevelDomainNames[i])
      const domain = await deployedGNS.domains(topLevelDomainHash)
      assert(domain.owner === accounts[accountCount], 'Name was not registered properly.',)

      expectEvent.inLogs(logs, 'DomainAdded', {
        topLevelDomainHash: topLevelDomainHash,
        owner: accounts[accountCount],
        domainName: topLevelDomainNames[i],
      })
    }
  })

  /*
   * Here I set up 10 real IPFS hashes for subgraph metadata, so that we can see the mapping work
   * in action. They can be found in the graph network subgraph repository. The other 40 are just
   * set to 0xffffff....ffff to obfuscate them
   */
  it('...should allow 50 subdomains to be registered to 50 tlds, and 50 tlds to have subgraphs registered ', async () => {
    let accountCount = 0
    for (let i = 0; i < topLevelDomainNames.length; i++) {
      if (i % 10 === 0 && i !== 0) {
        accountCount++
      }
      const topLevelDomainHash = web3.utils.soliditySha3(topLevelDomainNames[i])

      let ipfsHash
      if (i < 10){
        ipfsHash = testIPFSHashes[i]
      } else {
        ipfsHash = "0xffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff"
      }

      // if even, create a sub domain. if odd, create a subgraph at top level domain
      if (i % 2 === 0) {
        const { logs } = await deployedGNS.createSubgraph(
          topLevelDomainHash,
          subdomainNames[i],
          ipfsHash,
          { from: accounts[accountCount] },
        )
        const hashedSubdomain = web3.utils.soliditySha3(web3.utils.soliditySha3(subdomainNames[i]), topLevelDomainHash)
        const subdomain = await deployedGNS.domains(hashedSubdomain)
        assert(subdomain.owner === accounts[accountCount],
          'Subdomain was not created properly.',
        )

        expectEvent.inLogs(logs, 'SubgraphCreated', {
          topLevelDomainHash: topLevelDomainHash,
          registeredHash: hashedSubdomain,
          subdomainName: subdomainNames[i],
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
