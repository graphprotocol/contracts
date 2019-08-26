import { ethers } from 'ethers'
import { GraphTokenFactory } from '../src/contracts/GraphTokenFactory'
import { MultiSigWalletFactory } from '../src/contracts/MultiSigWalletFactory'

var config = require('../config/ganache')
var args = require('minimist')

let indexerPublicKey = config.key.publicKey
let indexerPrivateKey = config.key.privateKey

let ethHttpEndpoint = args['eth-http-endpoint']
let eth = new ethers.providers.JsonRpcProvider(ethHttpEndpoint)

let addresses = config.contracts
let graphToken = GraphTokenFactory.connect(addresses.graphToken, eth)
let multiSigWallet = MultiSigWalletFactory.connect(addresses.multiSigWallet, eth)

multiSigWallet.functions.getOwners()
  .then(owners => {
    console.log(`Multi signature wallet owners: ${owners}`)
  })
  .catch(err => {
    console.error(`Retrieving multi sig wallet owners failed with err: ${err}`)
  })

graphToken.functions
  .balanceOf(config.key.publicKey)
  .then(balance => {
    console.log(`GNT balance of ${config.key.publicKey} is ${balance}`)
  })
  .catch(err => {
    console.error(
      `Retrieving GNT balance of ${config.key.publicKey} failed with error: ${err}`,
    )
  })
