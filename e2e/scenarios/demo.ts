// We require the Hardhat Runtime Environment explicitly here. This is optional
// but useful for running the script in a standalone fashion through `node <script>`.
//
// You can also run a script with `npx hardhat run <script>`. If you do that, Hardhat
// will compile your contracts, add the Hardhat Runtime Environment's members to the
// global scope, and execute the script.
import hre from 'hardhat'
import { toGRT } from '../../cli/network'
import { stake } from './lib/staking'

async function main() {
  const graph = hre.graph()
  const [indexer1] = await graph.getAccounts()
  await stake(graph.contracts, indexer1.signer, toGRT(10_000))
}

// We recommend this pattern to be able to use async/await everywhere
// and properly handle errors.
main().catch((error) => {
  console.error(error)
  process.exitCode = 1
})
