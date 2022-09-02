// ### Scenario description ###
// Common protocol actions > Close some allocations
// This scenario will close several open allocations. See fixtures for details.
// Need to wait at least 1 epoch after the allocations have been created before running it.
// On localhost, the epoch is automatically advanced to guarantee this.
// Run with:
//    npx hardhat e2e:scenario close-allocations --network <network> --graph-config config/graph.<network>.yml

import hre from 'hardhat'
import { closeAllocation } from './lib/staking'
import { advanceToNextEpoch } from '../../test/lib/testHelpers'
import { fundAccountsETH } from './lib/accounts'
import { getIndexerFixtures } from './fixtures/indexers'
import { getGraphOptsFromArgv } from './lib/helpers'

async function main() {
  const graphOpts = getGraphOptsFromArgv()
  const graph = hre.graph(graphOpts)
  const indexerFixtures = getIndexerFixtures(await graph.getTestAccounts())

  const deployer = await graph.getDeployer()
  const indexers = indexerFixtures.map((i) => i.signer.address)
  const indexerETHBalances = indexerFixtures.map((i) => i.ethBalance)

  // == Fund participants
  console.log('\n== Fund indexers')
  await fundAccountsETH(deployer, indexers, indexerETHBalances)

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
