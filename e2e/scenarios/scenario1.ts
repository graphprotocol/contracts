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
import { toGRT } from '../../cli/network'

export let fixture = {
  ethAmount: toGRT(0.05),
  grtAmount: toGRT(100_000),
  indexers: [
    // indexer1
    {
      signer: null,
      stake: toGRT(100_000),
      allocations: [
        {
          signer: null,
          subgraphDeploymentId:
            '0xbbde25a2c85f55b53b7698b9476610c3d1202d88870e66502ab0076b7218f98a',
          amount: toGRT(25_000),
          close: false,
        },
        {
          signer: null,
          subgraphDeploymentId:
            '0x0653445635cc1d06bd2370d2a9a072406a420d86e7fa13ea5cde100e2108b527',
          amount: toGRT(50_000),
          close: true,
        },
        {
          signer: null,
          subgraphDeploymentId:
            '0xbbde25a2c85f55b53b7698b9476610c3d1202d88870e66502ab0076b7218f98a',
          amount: toGRT(10_000),
          close: true,
        },
      ],
    },
    // indexer2
    {
      signer: null,
      stake: toGRT(100_000),
      allocations: [
        {
          signer: null,
          subgraphDeploymentId:
            '0x3093dadafd593b5c2d10c16bf830e96fc41ea7b91d7dabd032b44331fb2a7e51',
          amount: toGRT(25_000),
          close: true,
        },
        {
          signer: null,
          subgraphDeploymentId:
            '0x0653445635cc1d06bd2370d2a9a072406a420d86e7fa13ea5cde100e2108b527',
          amount: toGRT(10_000),
          close: false,
        },
        {
          signer: null,
          subgraphDeploymentId:
            '0x3093dadafd593b5c2d10c16bf830e96fc41ea7b91d7dabd032b44331fb2a7e51',
          amount: toGRT(10_000),
          close: true,
        },
        {
          signer: null,
          subgraphDeploymentId:
            '0xb3fc2abc303c70a16ab9d5fc38d7e8aeae66593a87a3d971b024dd34b97e94b1',
          amount: toGRT(45_000),
          close: true,
        },
      ],
    },
  ],
  curators: [
    // curator1
    {
      signer: null,
      signalled: toGRT(10_400),
      subgraphs: [
        {
          deploymentId: '0x0653445635cc1d06bd2370d2a9a072406a420d86e7fa13ea5cde100e2108b527',
          signal: toGRT(400),
        },
        {
          deploymentId: '0x3093dadafd593b5c2d10c16bf830e96fc41ea7b91d7dabd032b44331fb2a7e51',
          signal: toGRT(4_000),
        },
        {
          deploymentId: '0xb3fc2abc303c70a16ab9d5fc38d7e8aeae66593a87a3d971b024dd34b97e94b1',
          signal: toGRT(6_000),
        },
      ],
    },
    // curator2
    {
      signer: null,
      signalled: toGRT(4_500),
      subgraphs: [
        {
          deploymentId: '0x3093dadafd593b5c2d10c16bf830e96fc41ea7b91d7dabd032b44331fb2a7e51',
          signal: toGRT(2_000),
        },
        {
          deploymentId: '0xb3fc2abc303c70a16ab9d5fc38d7e8aeae66593a87a3d971b024dd34b97e94b1',
          signal: toGRT(2_500),
        },
      ],
    },
    // curator3
    {
      signer: null,
      signalled: toGRT(8_000),
      subgraphs: [
        {
          deploymentId: '0x3093dadafd593b5c2d10c16bf830e96fc41ea7b91d7dabd032b44331fb2a7e51',
          signal: toGRT(4_000),
        },
        {
          deploymentId: '0xb3fc2abc303c70a16ab9d5fc38d7e8aeae66593a87a3d971b024dd34b97e94b1',
          signal: toGRT(4_000),
        },
      ],
    },
  ],
  subgraphOwner: null,
  subgraphs: [
    {
      deploymentId: '0xbbde25a2c85f55b53b7698b9476610c3d1202d88870e66502ab0076b7218f98a',
      subgraphId: null,
    },
    {
      deploymentId: '0x0653445635cc1d06bd2370d2a9a072406a420d86e7fa13ea5cde100e2108b527',
      subgraphId: null,
    },
    {
      deploymentId: '0x3093dadafd593b5c2d10c16bf830e96fc41ea7b91d7dabd032b44331fb2a7e51',
      subgraphId: null,
    },
    {
      deploymentId: '0xb3fc2abc303c70a16ab9d5fc38d7e8aeae66593a87a3d971b024dd34b97e94b1',
      subgraphId: null,
    },
  ],
}

async function main() {
  const graph = hre.graph()
  fixture = await setFixtureSigners(hre, fixture)

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
