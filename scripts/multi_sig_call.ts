import { ethers, Wallet } from 'ethers'

import { MultiSigWalletFactory } from '../src/contracts/MultiSigWalletFactory'
import { GraphTokenFactory } from '../src/contracts/GraphTokenFactory'
import { BigNumber } from 'ethers/utils'
import { EtherscanProvider } from 'ethers/providers'
import { TransactionOverrides } from '../src/contracts';

const util = require('util')
const config = require('../config/ganache')
const args = require('minimist')

let ethHttpEndpoint = args['eth-http-endpoint']
let eth = new ethers.providers.JsonRpcProvider(ethHttpEndpoint)

let addresses = config.contracts
let graphToken = GraphTokenFactory.connect(addresses.graphToken, eth)
let multiSigWallet = MultiSigWalletFactory.connect(
  addresses.multiSigWallet,
  eth,
)

multiSigWallet.functions
  .getOwners()
  .then(owners => {
    console.log(`Multi signature wallet owners: ${owners}`)
  })
  .catch(err => {
    console.error(`Retrieving multi sig wallet owners failed with err: ${err}`)
  })
multiSigWallet.functions
  .required()
  .then((required) => {
    console.log(`Number of required signatures is: ${required}`)
  })
  .catch((err) => {
    console.error(`Retrieving multi sig wallet required signatures failed with err: ${err}`)
  })

// Add transaction
let callData = graphToken.interface.functions.transfer.encode([
  config.key.publicKey,
  100000,
])
MultiSigWalletFactory.connect(
  addresses.multiSigWallet,
  new Wallet(config.key.privateKey, eth),
)
  .functions.submitTransaction(addresses.graphToken, 0, callData)
  .then(transaction => {
    console.log("Successfully sent `submitTransaction` call")
    // Parse response data (transaction id for transaction proposal)
    return transaction.wait(0)
      .then(receipt => {
        if (receipt.events) {
          var transactionId
          receipt.events.forEach(event => {
            let log = multiSigWallet.interface.parseLog({
              topics: event.topics,
              data: event.data,
            })
            if (
              log.signature ==
              multiSigWallet.interface.events.Submission.signature
            ) {
              transactionId = log.values.transactionId as ethers.utils.BigNumberish
            }
          })
          if (transactionId) {
            return transactionId
          }
        }
        throw new Error("Transaction receipt did not include a Submission event")
      })
    })
  .then(txId => {
    console.log(`Transaction id for multi sig call is ${txId}`)
    let confirmations: Promise<ethers.ContractTransaction>[] = []
    interface KeyPair {
      privateKey: string
      publicKey: string
    }
    let keys = config.keys as KeyPair[]
    let requiredVotes = (keys.length / 2) + 1
    for (let votes = 1; votes < requiredVotes; votes++) {
      let pair = config.keys[votes]
      if (pair.publicKey && pair.privateKey) {
        confirmations.push(
          MultiSigWalletFactory.connect(
            addresses.multiSigWallet,
            new Wallet(pair.privateKey, eth),
          ).functions.confirmTransaction(txId, {
            gasLimit: 5000000
          })
            .then((transaction) => {
              console.log(`Account with public key ${pair.publicKey} confirmed transaction`)
              return transaction
            })
            .catch((err) => {
              console.error(`Account with public key ${pair.publicKey} failed to confirm transaction: ${err}`)
              throw err
            }),
        )
      }
    }
    return Promise.all(confirmations)
      .then(() => {
        return txId
      })
  })
  .catch(err => {
    console.error(
      `Failed to submit, confirm and execute MultiSig contract call due to error: ${err}`,
    )
  })
  .then(txId => {
    console.log(`Successfully completed transaction ${txId}`)
  })

// Confirm transaction by all owners

// Execute transaction
