// We require the Hardhat Runtime Environment explicitly here. This is optional
// but useful for running the script in a standalone fashion through `node <script>`.
//
// You can also run a script with `npx hardhat run <script>`. If you do that, Hardhat
// will compile your contracts, add the Hardhat Runtime Environment's members to the
// global scope, and execute the script.
import hre from 'hardhat'
import { closeAllocation } from './lib/staking'
import { advanceToNextEpoch } from '../../test/lib/testHelpers'
import { setFixtureSigners } from './lib/helpers'
import { fixture as importedFixture } from './scenario1'

let fixture: any

async function main() {
  const graph = hre.graph()
  fixture = await setFixtureSigners(hre, importedFixture)

  // == Time travel on local networks, ensure allocations can be closed
  if (['hardhat', 'localhost'].includes(hre.network.name)) {
    console.log('\n== Advancing to next epoch')
    await advanceToNextEpoch(graph.contracts.EpochManager)
  }

  // == Close allocations
  console.log('\n== Close allocations')

  for (const indexer of fixture.indexers) {
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
