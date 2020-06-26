#!/usr/bin/env ts-node
import * as dotenv from 'dotenv'

import { Wallet, utils } from 'ethers'

import {
  ConnectedCuration,
  ConnectedGNS,
  ConnectedGraphToken,
  ConnectedENS,
  ConnectedEthereumDIDRegistry,
  ConnectedServiceRegistry,
  ConnectedStaking,
} from './connectedContracts'
import { AccountMetadata, SubgraphMetadata } from '../common'
import * as AccountDatas from '../mockData/account-metadata/accountMetadatas'
import * as SubgraphDatas from '../mockData/subgraph-metadata/subgraphMetadatas'
import { configureWallet, executeTransaction, IPFS } from './helpers'

dotenv.config()
const accountMetadatas = AccountDatas.default
const subgraphMetadatas = SubgraphDatas.default

// Creates an array of signers, that are not connected to providers
const createManySigners = (count: number, mnemonic?: string): Array<Wallet> => {
  if (mnemonic == undefined) {
    const ganacheDeterministicMnemonic =
      'myth like bonus scare over problem client lizard pioneer submit female collect'
    mnemonic = ganacheDeterministicMnemonic
  }
  const createSigner = (index: number): Wallet => {
    const wallet = Wallet.fromMnemonic(mnemonic, `m/44'/60'/0'/0/${index}`)
    return wallet
  }
  const signers: Array<Wallet> = []
  for (let i = 0; i < count; i++) {
    signers.push(createSigner(i))
  }
  console.log(`Created ${count} wallets!`)
  return signers
}

// Send ETH to the accounts so they can transact on the network
const sendEth = async (signers: Array<Wallet>, amount: string) => {
  const sender = configureWallet(signers[0])
  const amountEther = utils.parseEther(amount)
  for (let i = 3; i < signers.length; i++) {
    const data = {
      to: signers[i].address,
      value: amountEther,
    }
    await executeTransaction(sender.sendTransaction(data))
  }
}

// Send GRT to accounts that will act as indexers, curators, etc, to interact with the contracts
const populateGraphToken = async (signers: Array<Wallet>, amount: string) => {
  // since no wallet is passed, it defaults to process.env
  // Which is desired, as long as this account is the governor, or has been sent coins
  const graphToken = new ConnectedGraphToken(true)
  for (let i = 0; i < signers.length; i++) {
    await executeTransaction(graphToken.transferWithOverrides(signers[i].address, amount))
  }
}

// Call set attribute for the 10 accounts
const populateEthereumDIDRegistry = async (signers: Array<Wallet>) => {
  let i = 0
  for (const account in accountMetadatas) {
    const edr = new ConnectedEthereumDIDRegistry(true, undefined, undefined, signers[i])
    const name = accountMetadatas[account].name
    console.log(
      `Calling setAttribute on DID registry for ${name} and account ${edr.wallet.address} ...`,
    )
    const ipfs = 'https://api.thegraph.com/ipfs/'
    await executeTransaction(
      edr.setAttributeWithOverrides(ipfs, accountMetadatas[account] as AccountMetadata),
    )
    i++
  }
}

// Register 10 names on ens // TODO - should register 10 Graph Accounts then, this func doesnt exist yet though
const populateENS = async (signers: Array<Wallet>) => {
  let i = 0
  for (const subgraph in subgraphMetadatas) {
    const ens = new ConnectedENS(true, undefined, undefined, signers[i])
    let name = subgraphMetadatas[subgraph].subgraphDisplayName
    if (name == 'The Graph') name = 'graphprotocol' // edge case - graph is only ens name that doesn't match display name
    console.log(`Setting ${name} for ${ens.wallet.address} on ens ...`)
    await executeTransaction(ens.setTestRecord(name))
    await executeTransaction(ens.setText(name))
    i++
  }
}

// Publish 10 subgraphs
// Publish new versions for them all
// Deprecate 2
const populateGNS = async (signers: Array<Wallet>) => {
  let i = 0
  const testDeploymentID = 'QmTXzATwNfgGVukV1fX2T6xw9f6LAYRVWpsdXyRWzUR2H9' // TODO - get 10 real subgraph IDs for 10 real subgraphs. For now we just use the same for all
  for (const subgraph in subgraphMetadatas) {
    const gns = new ConnectedGNS(true, undefined, undefined, signers[i])
    const ipfs = 'https://api.thegraph.com/ipfs/'
    let name = subgraphMetadatas[subgraph].subgraphDisplayName
    if (name == 'The Graph') name = 'graphprotocol' // edge case - graph is only ens name that doesn't match display name
    const nameIdentifier = utils.namehash(`${name}.test`)
    console.log(`Publishing ${name} for ${gns.wallet.address} on GNS ...`)
    await executeTransaction(
      gns.publishNewSubgraphWithOverrides(
        ipfs,
        gns.wallet.address,
        testDeploymentID,
        nameIdentifier,
        name,
        subgraphMetadatas[subgraph] as SubgraphMetadata,
      ),
    )
    console.log(`Updating version of ${name} for ${gns.wallet.address} on GNS ...`)
    await executeTransaction(
      gns.publishNewVersionWithOverrides(
        ipfs,
        gns.wallet.address,
        testDeploymentID,
        nameIdentifier,
        name,
        subgraphMetadatas[subgraph] as SubgraphMetadata,
        '0', // TODO, only works on the first run right now, make more robust
      ),
    )
    i++
  }

  // Deprecation of 5 subgraphs // TODO - implement fully, they need to be created first
  // const gns = new ConnectedGNS(true, undefined, undefined, signers[0])
  // await executeTransaction(gns.deprecateWithOverrides(gns.wallet.address, '1'))
  // await executeTransaction(gns.deprecateWithOverrides(gns.wallet.address, '2'))
  // await executeTransaction(gns.deprecateWithOverrides(gns.wallet.address, '3'))
  // await executeTransaction(gns.deprecateWithOverrides(gns.wallet.address, '4'))
  // await executeTransaction(gns.deprecateWithOverrides(gns.wallet.address, '5'))
}

// const populateCuration = async () => {
//   // todo
// }

// const populateServiceRegistry = async () => {
//   // todo
// }

// const populateStaking = async () => {
//   // todo
//   // will need t make many more wallets here, for channel proxies
// }

// const populateAll = async () => {}

const main = async () => {
  try {
    const signers = createManySigners(20, process.env.MNEMONIC)
    const userAccounts = signers.slice(0, 10)
    const proxyAccounts = signers.slice(10, 20)
    // await sendEth(userAccounts, '0.25') // only use at the start. TODO - make this a cli option or something
    // await populateGraphToken(userAccounts, '100000')
    // await populateEthereumDIDRegistry(userAccounts)
    // await populateENS(userAccounts)
    // await populateGNS(userAccounts)
  } catch (e) {
    console.log(`  ..failed within main: ${e.message}`)
    process.exit(1)
  }
}

main()

/*
 * - curation
 *  - curate on ten of them, that were not deprecated
 *  - make sure that there are multiple curations by different users, and
 *    get some bonding curves high
 *  - run some redeeming through (5?)
 *
 * - service Registry
 *  - register all ten
 *  - unregister 5, then reregister them
 *
 * - staking
 *  - deposit
 *    - for all ten users
 *    - Withdraw a bit 5, then stake it back
 *  - unstake and withdraw
 *    - set thawing period to 0
 *    - unstake for 3
 *    - withdraw for 3
 *    - restake
 *  - createAllocation
 *    - call epoch manager, set epoch to 1 block
 *    - create allocation for all ten users
 *  - settleAllocation
 *    - TODO - implement this function
 *    - settle 5 of them
 *  - fixing parameters
 *    - set thawing period back to default
 *    - set epoch manager back to default
 *
 * - TODO FUTURE
 *  - handle all parameter updates
 *  - staking - rebate claimed, stake slashed
 */
