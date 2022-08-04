// We require the Hardhat Runtime Environment explicitly here. This is optional
// but useful for running the script in a standalone fashion through `node <script>`.
//
// You can also run a script with `npx hardhat run <script>`. If you do that, Hardhat
// will compile your contracts, add the Hardhat Runtime Environment's members to the
// global scope, and execute the script.
import hre from 'hardhat'
import { allocateFrom, stake } from './lib/staking'
import { signal } from './lib/curation'
import { publishNewSubgraph } from './lib/subgraph'
import { setupAccounts } from './lib/accounts'
import { setFixtureSigners } from './lib/helpers'
import { fixture as importedFixture } from './fixtures/fixture1'

let fixture: any

async function main() {
  const graph = hre.graph()
  fixture = await setFixtureSigners(hre, importedFixture)

  const deployer = await graph.getDeployer()

  // == Fund participants
  console.log('\n== Accounts setup')
  await setupAccounts(graph.contracts, fixture, deployer)

  // == Stake
  console.log('\n== Staking tokens')

  for (const indexer of fixture.indexers) {
    await stake(graph.contracts, indexer.signer, indexer.stake)
  }

  // == Publish subgraphs
  console.log('\n== Publishing subgraphs')

  for (const subgraph of fixture.subgraphs) {
    const id = await publishNewSubgraph(
      graph.contracts,
      fixture.subgraphOwner,
      subgraph.deploymentId,
    )
    const subgraphData = fixture.subgraphs.find((s) => s.deploymentId === subgraph.deploymentId)
    if (subgraphData) subgraphData.subgraphId = id
  }

  // == Signal subgraphs
  console.log('\n== Signaling subgraphs')

  for (const curator of fixture.curators) {
    for (const subgraph of curator.subgraphs) {
      const subgraphData = fixture.subgraphs.find((s) => s.deploymentId === subgraph.deploymentId)
      if (subgraphData)
        await signal(graph.contracts, curator.signer, subgraphData.subgraphId, subgraph.signal)
    }
  }

  // == Open allocations
  console.log('\n== Open allocations')

  for (const indexer of fixture.indexers) {
    for (const allocation of indexer.allocations) {
      await allocateFrom(
        graph.contracts,
        indexer.signer,
        allocation.signer,
        allocation.subgraphDeploymentId,
        allocation.amount,
      )
    }
  }
}

// We recommend this pattern to be able to use async/await everywhere
// and properly handle errors.
main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error)
    process.exitCode = 1
  })
