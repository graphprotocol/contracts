// ### Scenario description ###
// Common protocol actions > Set up indexers: stake and open allocations
// This scenario will open several allocations. See fixtures for details.
// Run with:
//    npx hardhat e2e:scenario open-allocations --network <network> --graph-config config/graph.<network>.yml

import hre from 'hardhat'
import { getIndexerFixtures } from './fixtures/indexers'
import { getGREOptsFromArgv } from '@graphprotocol/sdk/gre'
import { allocateFrom, ensureETHBalance, ensureGRTBalance, stake } from '@graphprotocol/sdk'

async function main() {
  const graphOpts = getGREOptsFromArgv()
  const graph = hre.graph(graphOpts)
  const indexerFixtures = getIndexerFixtures(await graph.getTestAccounts())

  const deployer = await graph.getDeployer()
  const indexers = indexerFixtures.map((i) => i.signer.address)
  const indexerETHBalances = indexerFixtures.map((i) => i.ethBalance)
  const indexerGRTBalances = indexerFixtures.map((i) => i.grtBalance)

  // == Fund participants
  console.log('\n== Fund indexers')
  await ensureETHBalance(graph.contracts, deployer, {
    beneficiaries: indexers,
    amounts: indexerETHBalances,
  })
  await ensureGRTBalance(graph.contracts, deployer, {
    beneficiaries: indexers,
    amounts: indexerGRTBalances,
  })

  // == Stake
  console.log('\n== Staking tokens')

  for (const indexer of indexerFixtures) {
    await stake(graph.contracts, indexer.signer, { amount: indexer.stake })
  }

  // == Open allocations
  console.log('\n== Open allocations')

  for (const indexer of indexerFixtures) {
    for (const allocation of indexer.allocations) {
      await allocateFrom(graph.contracts, indexer.signer, {
        allocationSigner: allocation.signer,
        subgraphDeploymentID: allocation.subgraphDeploymentId,
        amount: allocation.amount,
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
