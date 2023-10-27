// ### Scenario description ###
// Common protocol actions > Set up subgraphs: publish and signal
// This scenario will create a set of subgraphs and add signal to them. See fixtures for details.
// Run with:
//    npx hardhat e2e:scenario create-subgraphs --network <network> --graph-config config/graph.<network>.yml

import hre from 'hardhat'
import { getSubgraphFixtures, getSubgraphOwner } from './fixtures/subgraphs'
import { getCuratorFixtures } from './fixtures/curators'
import { getGREOptsFromArgv } from '@graphprotocol/sdk/gre'
import {
  ensureETHBalance,
  ensureGRTBalance,
  publishNewSubgraph,
  mintSignal,
} from '@graphprotocol/sdk'

async function main() {
  const graphOpts = getGREOptsFromArgv()
  const graph = hre.graph(graphOpts)
  const testAccounts = await graph.getTestAccounts()

  const subgraphFixtures = getSubgraphFixtures()
  const subgraphOwnerFixture = getSubgraphOwner(testAccounts)
  const curatorFixtures = getCuratorFixtures(testAccounts)

  const deployer = await graph.getDeployer()
  const subgraphOwners = [subgraphOwnerFixture.signer.address]
  const subgraphOwnerETHBalance = [subgraphOwnerFixture.ethBalance]
  const curators = curatorFixtures.map((c) => c.signer.address)
  const curatorETHBalances = curatorFixtures.map((i) => i.ethBalance)
  const curatorGRTBalances = curatorFixtures.map((i) => i.grtBalance)

  // == Fund participants
  console.log('\n== Fund subgraph owners and curators')
  await ensureETHBalance(graph.contracts, deployer, {
    beneficiaries: [...subgraphOwners, ...curators],
    amounts: [...subgraphOwnerETHBalance, ...curatorETHBalances],
  })
  await ensureGRTBalance(graph.contracts, deployer, {
    beneficiaries: curators,
    amounts: curatorGRTBalances,
  })

  // == Publish subgraphs
  console.log('\n== Publishing subgraphs')

  for (const subgraph of subgraphFixtures) {
    const id = await publishNewSubgraph(graph.contracts, subgraphOwnerFixture.signer, {
      deploymentId: subgraph.deploymentId,
    })
    const subgraphData = subgraphFixtures.find((s) => s.deploymentId === subgraph.deploymentId)
    if (subgraphData) subgraphData.subgraphId = id
  }

  // == Signal subgraphs
  console.log('\n== Signaling subgraphs')
  for (const curator of curatorFixtures) {
    for (const subgraph of curator.subgraphs) {
      const subgraphData = subgraphFixtures.find((s) => s.deploymentId === subgraph.deploymentId)
      if (subgraphData)
        await mintSignal(graph.contracts, curator.signer, {
          subgraphId: subgraphData.subgraphId,
          amount: subgraph.signal,
        })
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
