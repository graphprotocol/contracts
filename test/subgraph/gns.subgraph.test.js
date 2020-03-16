const { expectEvent } = require('openzeppelin-test-helpers')

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
  })

  it('...should allow a 10 users to register 10 domains', async () => {
    let accountCount = 0
    for (let i = 0; i < 10; i++) {
      // Not in use, use when testing more than 10 in the loop
      // if (i % 10 === 0 && i !== 0) {
      //   accountCount++
      // }
      const { logs } = await deployedGNS.registerDomain(
        helpers.topLevelDomainNames[i],
        {
          from: accounts[accountCount],
        },
      )
      const topLevelDomainHash = web3.utils.soliditySha3(
        helpers.topLevelDomainNames[i],
      )
      const domain = await deployedGNS.domains(topLevelDomainHash)
      assert(
        domain.owner === accounts[accountCount],
        'Name was not registered properly.',
      )

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
      const topLevelDomainHash = web3.utils.soliditySha3(
        helpers.topLevelDomainNames[i],
      )
      const ipfsHash = helpers.testIPFSHashes[i]

      // Not in use, use when testing more than 10 in the loop
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
        const hashedSubdomain = web3.utils.soliditySha3(
          web3.utils.soliditySha3(helpers.subdomainNames[i]),
          topLevelDomainHash,
        )
        const subdomain = await deployedGNS.domains(hashedSubdomain)
        assert(
          subdomain.owner === accounts[accountCount],
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
          '',
          ipfsHash,
          { from: accounts[accountCount] },
        )
        const domain = await deployedGNS.domains(topLevelDomainHash)
        assert(
          domain.owner === accounts[accountCount],
          'Subdomain was not created properly.',
        )

        expectEvent.inLogs(logs, 'SubgraphCreated', {
          topLevelDomainHash: topLevelDomainHash,
          registeredHash: topLevelDomainHash,
          subdomainName: '',
        })

        expectEvent.inLogs(logs, 'SubgraphMetadataChanged', {
          domainHash: topLevelDomainHash,
          ipfsHash: ipfsHash,
        })
      }
      accountCount++
    }
  })

  it('...should register 10 subgraph ids for 10 different subgraphs. ', async () => {
    for (let i = 0; i < 10; i++) {
      const topLevelDomainHash = web3.utils.soliditySha3(
        helpers.topLevelDomainNames[i],
      )
      const hashedSubdomain = web3.utils.soliditySha3(
        web3.utils.soliditySha3(helpers.subdomainNames[i]),
        topLevelDomainHash,
      )

      if (i % 2 === 0) {
        const {
          logs,
        } = await deployedGNS.updateDomainSubgraphID(
          hashedSubdomain,
          helpers.testSubgraphIDs[i],
          { from: accounts[i] },
        )
        const domain = await deployedGNS.domains(hashedSubdomain)
        assert(
          (await domain.subgraphID) === helpers.testSubgraphIDs[i],
          'Subdomain was not registered properly.',
        )
        expectEvent.inLogs(logs, 'SubgraphIDUpdated', {
          domainHash: hashedSubdomain,
          subgraphID: helpers.testSubgraphIDs[i],
        })
      } else {
        const {
          logs,
        } = await deployedGNS.updateDomainSubgraphID(
          topLevelDomainHash,
          helpers.testSubgraphIDs[i],
          { from: accounts[i] },
        )
        const domain = await deployedGNS.domains(topLevelDomainHash)
        assert(
          (await domain.subgraphID) === helpers.testSubgraphIDs[i],
          'Subdomain was not registered properly.',
        )
        expectEvent.inLogs(logs, 'SubgraphIDUpdated', {
          domainHash: topLevelDomainHash,
          subgraphID: helpers.testSubgraphIDs[i],
        })
      }
    }
  })

  it('...should update the 5 tlds with no data to test data from  scaffold-metadata.json', async () => {
    for (let i = 0; i < 10; i++) {
      const topLevelDomainHash = web3.utils.soliditySha3(
        helpers.topLevelDomainNames[i],
      )
      if (i % 2 === 0) {
        const { logs } = await deployedGNS.changeSubgraphMetadata(
          topLevelDomainHash,
          '0xe2f321f2a488e2cae1a05229f730be3cc77b730246cc08641e515afda0fe0ba6', // dummy hash for scaffold-metadata.json
          { from: accounts[i] },
        )

        expectEvent.inLogs(logs, 'SubgraphMetadataChanged', {
          domainHash: topLevelDomainHash,
          ipfsHash:
            '0xe2f321f2a488e2cae1a05229f730be3cc77b730246cc08641e515afda0fe0ba6',
        })
      }
    }
  })

  it('...should delete the melonport subgraph', async () => {
    const topLevelDomainHash = web3.utils.soliditySha3(
      helpers.topLevelDomainNames[6],
    )
    const hashedSubdomain = web3.utils.soliditySha3(
      web3.utils.soliditySha3(helpers.subdomainNames[6]),
      topLevelDomainHash,
    )
    const { logs } = await deployedGNS.deleteSubdomain(hashedSubdomain, {
      from: accounts[6],
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
})

// Not going to bother with testing accountMetadata or transferDomain for now. Might not need ever
