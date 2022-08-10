import hre from 'hardhat'
import { publishNewSubgraph } from './lib/subgraph'
import { fundAccountsEth, fundAccountsGRT } from './lib/accounts'
import { signal } from './lib/curation'
import { getSubgraphFixtures, getSubgraphOwner } from './fixtures/subgraphs'
import { getCuratorFixtures } from './fixtures/curators'
import { fund } from './fixtures/funds'

async function main() {
  const graph = hre.graph()
  const testAccounts = await graph.getTestAccounts()

  const subgraphFixtures = getSubgraphFixtures()
  const subgraphOwnerFixture = getSubgraphOwner(testAccounts)
  const curatorFixtures = getCuratorFixtures(testAccounts)

  const deployer = await graph.getDeployer()
  const subgraphOwners = [subgraphOwnerFixture.address]
  const curators = curatorFixtures.map((c) => c.signer.address)

  // == Fund participants
  console.log('\n== Fund subgraph owners and curators')
  await fundAccountsEth(deployer, [...subgraphOwners, ...curators], fund.ethAmount)
  await fundAccountsGRT(deployer, curators, fund.grtAmount, graph.contracts.GraphToken)

  // == Publish subgraphs
  console.log('\n== Publishing subgraphs')

  for (const subgraph of subgraphFixtures) {
    const id = await publishNewSubgraph(
      graph.contracts,
      subgraphOwnerFixture,
      subgraph.deploymentId,
    )
    const subgraphData = subgraphFixtures.find((s) => s.deploymentId === subgraph.deploymentId)
    if (subgraphData) subgraphData.subgraphId = id
  }

  // == Signal subgraphs
  console.log('\n== Signaling subgraphs')
  for (const curator of curatorFixtures) {
    for (const subgraph of curator.subgraphs) {
      const subgraphData = subgraphFixtures.find((s) => s.deploymentId === subgraph.deploymentId)
      if (subgraphData)
        await signal(graph.contracts, curator.signer, subgraphData.subgraphId, subgraph.signal)
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
