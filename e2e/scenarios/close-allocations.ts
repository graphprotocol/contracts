import hre from 'hardhat'
import { closeAllocation } from './lib/staking'
import { advanceToNextEpoch } from '../../test/lib/testHelpers'
import { fundAccountsEth } from './lib/accounts'
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

  // == Time travel on local networks, ensure allocations can be closed
  if (['hardhat', 'localhost'].includes(hre.network.name)) {
    console.log('\n== Advancing to next epoch')
    await advanceToNextEpoch(graph.contracts.EpochManager)
  }

  // == Close allocations
  console.log('\n== Close allocations')

  for (const indexer of indexerFixtures) {
    for (const allocation of indexer.allocations.filter((a) => a.close)) {
      await closeAllocation(graph.contracts, indexer.signer, allocation.signer.address)
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
