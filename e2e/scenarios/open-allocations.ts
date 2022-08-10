import hre from 'hardhat'
import { allocateFrom, stake } from './lib/staking'
import { fundAccountsEth, fundAccountsGRT } from './lib/accounts'
import { getIndexerFixtures } from './fixtures/indexers'
import { fund } from './fixtures/funds'

async function main() {
  const graph = hre.graph()
  const indexerFixtures = getIndexerFixtures(await graph.getTestAccounts())

  const deployer = await graph.getDeployer()
  const indexers = indexerFixtures.map((i) => i.signer.address)

  // == Fund participants
  console.log('\n== Fund indexers')
  await fundAccountsEth(deployer, indexers, fund.ethAmount)
  await fundAccountsGRT(deployer, indexers, fund.grtAmount, graph.contracts.GraphToken)

  // == Stake
  console.log('\n== Staking tokens')

  for (const indexer of indexerFixtures) {
    await stake(graph.contracts, indexer.signer, indexer.stake)
  }

  // == Open allocations
  console.log('\n== Open allocations')

  for (const indexer of indexerFixtures) {
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
