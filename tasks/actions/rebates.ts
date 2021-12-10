import { createClient } from '@urql/core'
import gql from 'graphql-tag'
import fetch from 'isomorphic-fetch'
import { task } from 'hardhat/config'

const range = (min, max) => [...Array(max - min + 1).keys()].map((i) => i + min)

task('action:claim-rebates', 'Claim rebates')
  .addParam('poolRange', 'Pool range to claim in "a,b" format')
  .setAction(async ({ poolRange }) => {
    // const { contracts } = hre

    // Parse input
    const [fromEpoch, toEpoch] = poolRange.split(',').map((e) => parseInt(e))
    const epochs = range(fromEpoch, toEpoch)
    console.log(`Scanning rebate pools (from ${fromEpoch} to ${toEpoch})...`)

    // Get allocations
    const url = 'https://api.thegraph.com/subgraphs/name/graphprotocol/graph-network-mainnet'
    const networkSubgraph = createClient({
      url,
      fetch,
      requestPolicy: 'network-only',
    })
    const query = gql`
      query ($epochs: [Int!]!) {
        allocations(first: 1000, where: { closedAtEpoch_in: $epochs, status_not: "Claimed" }) {
          id
        }
      }
    `
    const res = await networkSubgraph.query(query, { epochs }).toPromise()
    const allocationIDs = res.data.allocations.map((allo) => allo.id)
    console.log(`Found ${allocationIDs.length} allocations`)
    console.log(allocationIDs)

    // Claim
    // TODO: perform gas estimation
    // TODO: add confirmation question
    // TODO: batch into multiple calls
    // const tx = await contracts.Staking.claimMany(allocationIDs, false)
    // console.log(tx.hash)
  })
