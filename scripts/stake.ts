import { ethers, Wallet } from 'ethers'
import bs58 from 'bs58'

import { StakingFactory } from '../src/contracts/StakingFactory'
import { GraphTokenFactory } from '../src/contracts/GraphTokenFactory'

const util = require('util')
const config = require('../config/ganache')
const args = require('minimist')

let ethHttpEndpoint = args['eth-http-endpoint']
let eth = new ethers.providers.JsonRpcProvider(ethHttpEndpoint)

let addresses = config.contracts
let staking = StakingFactory.connect(addresses.staking, eth)
let graphToken = GraphTokenFactory.connect(
  addresses.graphToken,
  new Wallet(config.key.privateKey, eth),
)

// staking.functions.subgraphs(
//     "0x"+bs58.decode('QmVhCeJmrUxYj3MjAhBVB3T5QJL7X5Hfs8CQBha3UWTMBi').slice(2).toString('hex')
// )
//     .then((response) => {
//         console.log(`Subgraphs: ${response.totalCurationStake}`)
//     })
//     .catch((err) => {
//         console.error(`Subgraphs method failed due to error: ${err}`)
//     })

// Construct call data for GraphToken `transferWithDataCall`
// TokenReceivedAction and SubgraphId
let callData =
  '0x' +
  '01' +
  bs58
    .decode('QmVhCeJmrUxYj3MjAhBVB3T5QJL7X5Hfs8CQBha3UWTMBi')
    .slice(2)
    .toString('hex')
graphToken.functions
  .transferWithData(addresses.staking, ethers.utils.bigNumberify(200), callData)
  .then(transaction => {
    console.log('Successfully then `transferWithData` call')
    transaction
      .wait(0)
      .then(receipt => {
        let success = false
        if (receipt.events) {
          console.log('Found events')
          receipt.events.forEach(event => {
            let log = staking.interface.parseLog({
              topics: event.topics,
              data: event.data,
            })
            console.log(`Log: ${util.inspect(log, false, null, true)}`)
            if (
              log &&
              log.signature == staking.interface.events.CuratorStaked.signature
            ) {
              console.log(
                `Successfully called 'transferWithData' on GraphToken contract: ${receipt}`,
              )
              success = true
            }
          })
        }
        if (!success) {
          throw new Error(
            `Transaction calling 'transferWithData' failed to produce a 'CuratorStaked' event`,
          )
        }
      })
      .catch(err => {
        throw err
      })
  })
  .catch(err => {
    console.error(
      `Failed to call 'transferWithData' on Graph token contract due to error: ${err}`,
    )
  })
