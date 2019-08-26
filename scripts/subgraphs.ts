import { ethers, Wallet } from 'ethers'
import bs58 from 'bs58'

import { StakingFactory } from '../src/contracts/StakingFactory'

const util = require('util')
const config = require('../config/ganache')
const args = require('minimist')

let ethHttpEndpoint = args['eth-http-endpoint']
let eth = new ethers.providers.JsonRpcProvider(ethHttpEndpoint)

let addresses = config.contracts
let staking = StakingFactory.connect(addresses.staking, eth)

staking.functions
  .subgraphs(
    '0x' +
      bs58
        .decode('QmVhCeJmrUxYj3MjAhBVB3T5QJL7X5Hfs8CQBha3UWTMBi')
        .slice(2)
        .toString('hex'),
  )
  .then(response => {
    console.log(`Subgraphs: ${response}`)
  })
  .catch(err => {
    console.error(`Subgraphs method failed due to error: ${err}`)
  })
