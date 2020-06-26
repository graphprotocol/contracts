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

const testDeploymentIDsBase58: Array<string> = [
  'Qmb7e8bYoj93F9u33R3JY1H764626C8KHUgWMeVjWPiwdD', //compound
  'QmXenxBqM7uBbRq6y7EAcy86mfcaBkWE53Tz53H3dVeeit', //used synthetix
  'QmY8Uzg61ttrogeTyCKLcDDR4gKNK44g9qkGDqeProkSHE', //ens
  'QmRkqEVeZ8bRmMfvBHJvoB4NbnPgXNcuszLZWNNF49skY8', //livepeer
  'Qmb3hd2hYd2nWFgcmRswykF1dUBSrDUrinYCgN1dmE1tNy', //maker
  'QmcqrL62BHSasBsk47tNT1G66BHbaANwY213cX841NWE61', //melon
  'QmTXzATwNfgGVukV1fX2T6xw9f6LAYRVWpsdXyRWzUR2H9', // moloch
  'QmNoMRb9c5nGi5gETeyeAc7V14XvubAMAA7sxEJzsXnpTF', //used aave
  'QmUVKS3W7G7Kog6pGq2ttZtXfE89pRvw45vEJM2YEYwpQz', //thegraph
  'QmNPKaPqgTqKdCv2k3SF9vAhbHo4PVb2cKx2Gs4PzNQkZx', //uniswap
]

const testDeploymentIDsBytes32: Array<string> = [
  '0xbdd2b9eb5e4d2a1435b2858874e22e17a681263e86bc941bed345b58b8b8e634', //compound
  '0x8a5ef5005250f06a2787be70894cf00d4b45df94035a18217e0ac15358d7a239', //used synthetix
  '0x9176ea5ef5ebdca64119feb40bd96c54075622caab4917249e6557a8ede61769', //ens
  '0x32c4e64f2b5ecfedbcd41c1d1c469f837d2f3f4f9cdaff496fc7332d92090449', //livepeer
  '0xbcd059746c62617c5c96a3e2b5ce88516039393f34266f3485e60ded2321e476', //maker
  '0xd77e99802f1e0019722c1050e1e0ff5f96956dbbd534b00c3724c7b5d0b9950e', //melon
  '0x4d31d21d389263c98d1e83a031e8fed17cdcef15bd62ee8153f34188a83c7b1c', // moloch
  '0x06d7234c76d0fb43247537246a4384b06b4caa02978788bfe45e17ef13000b76', //used aave
  '0x5b5e8d658fd5ad6b84d7ad79a4f86ce4f97518863b393509d8750705d2e997cb', //thegraph
  '0x00af1bd4a2c640b4425577ce842959ff3b7259f6d93309c3ca1287137f4c360b', //uniswap
]

// Publish 10 subgraphs
// Publish new versions for them all
// Deprecate 2
const populateGNS = async (signers: Array<Wallet>) => {
  let i = 0

  //'QmTXzATwNfgGVukV1fX2T6xw9f6LAYRVWpsdXyRWzUR2H9' // TODO - get 10 real subgraph IDs for 10 real subgraphs. For now we just use the same for all
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
        testDeploymentIDsBase58[i],
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
        testDeploymentIDsBase58[i],
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

//  Each GraphAccount curates on their own
//  Then we stake on a few to make them higher
//  Then we run some redeems to make them lower
const populateCuration = async (signers: Array<Wallet>) => {
  const curation = new ConnectedCuration(true)
  const connectedGT = new ConnectedGraphToken(true)
  const stakeAmount = '5000'
  const stakeAmountBig = '10000'
  const totalAmount = '25000'
  for (let i = 0; i < signers.length; i++) {
    console.log('First calling approve() to ensure curation contract can call transferFrom()...')
    await executeTransaction(
      connectedGT.approveWithOverrides(curation.curation.address, totalAmount),
    )
    console.log('Now calling multiple txs stake() on curation...')
    await executeTransaction(curation.stakeWithOverrides(testDeploymentIDsBytes32[i], stakeAmount))
    await executeTransaction(curation.stakeWithOverrides(testDeploymentIDsBytes32[0], stakeAmount))
    await executeTransaction(curation.stakeWithOverrides(testDeploymentIDsBytes32[1], stakeAmount))
    await executeTransaction(
      curation.stakeWithOverrides(testDeploymentIDsBytes32[2], stakeAmountBig),
    )
  }
  const redeemAmount = '2' // Redeeming SHARES/Signal, NOT tokens. 2 shares can be a lot of tokens
  console.log('Running 10 redeem transactions...')
  for (let i = 0; i < signers.length; i++) {
    await executeTransaction(
      curation.redeemWithOverrides(testDeploymentIDsBytes32[1], redeemAmount),
    )
  }
}

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
    // await populateCuration(userAccounts)
  } catch (e) {
    console.log(`  ..failed within main: ${e.message}`)
    process.exit(1)
  }
}

main()

/*
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
