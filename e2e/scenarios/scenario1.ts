// We require the Hardhat Runtime Environment explicitly here. This is optional
// but useful for running the script in a standalone fashion through `node <script>`.
//
// You can also run a script with `npx hardhat run <script>`. If you do that, Hardhat
// will compile your contracts, add the Hardhat Runtime Environment's members to the
// global scope, and execute the script.
import hre from 'hardhat'
import { toGRT } from '../../cli/network'
import { stake } from './lib/staking'
import { signal } from './lib/curation'
import { publishNewSubgraph } from './lib/subgraph'
import { airdrop } from './lib/token'

export const fixture = {
  grtAmount: toGRT(100_000_000),
  indexer1: {
    stake: toGRT(100_000),
  },
  indexer2: {
    stake: toGRT(100_000),
  },
  subgraphs: [
    '0xbbde25a2c85f55b53b7698b9476610c3d1202d88870e66502ab0076b7218f98a',
    '0x0653445635cc1d06bd2370d2a9a072406a420d86e7fa13ea5cde100e2108b527',
    '0x3093dadafd593b5c2d10c16bf830e96fc41ea7b91d7dabd032b44331fb2a7e51',
  ],
}

async function main() {
  const graph = hre.graph()
  const [indexer1, indexer2, subgraphOwner, curator1, curator2, curator3] =
    await graph.getTestAccounts()
  const deployer = await graph.getDeployer()

  // Airdrop some GRT
  console.log('- Sending GRT to indexers, curators and subgraph owner...')
  await airdrop(
    graph.contracts,
    deployer,
    [
      indexer1.address,
      indexer2.address,
      subgraphOwner.address,
      curator1.address,
      curator2.address,
      curator3.address,
    ],
    fixture.grtAmount,
  )

  // Two indexers with stake
  console.log('- Staking tokens...')
  await stake(graph.contracts, indexer1, fixture.indexer1.stake)
  await stake(graph.contracts, indexer2, fixture.indexer2.stake)
  console.log('done')

  // Four subgraphs
  // console.log('- Publishing subgraphs...')
  // await publishNewSubgraph(graph.contracts, subgraphOwner.signer, fixture.subgraphs[0])
  // await publishNewSubgraph(graph.contracts, subgraphOwner.signer, fixture.subgraphs[1])
  // await publishNewSubgraph(graph.contracts, subgraphOwner.signer, fixture.subgraphs[2])

  // Signal subgraphs
  // console.log('- Signaling subgraphs...')
  // await signal(graph.contracts, curator1.signer, fixture.subgraphs[0], toGRT(1_000_000))
}

// We recommend this pattern to be able to use async/await everywhere
// and properly handle errors.
main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error)
    process.exitCode = 1
  })
