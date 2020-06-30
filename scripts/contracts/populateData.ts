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
import { connectContracts } from './connectedNetwork'
import { AccountMetadata, SubgraphMetadata } from '../metadataHelpers'
import * as AccountDatas from '../mockData/account-metadata/accountMetadatas'
import * as SubgraphDatas from '../mockData/subgraph-metadata/subgraphMetadatas'
import {
  configureWallet,
  executeTransaction,
  checkGovernor,
  basicOverrides,
  mockChannelPubKeys,
  mockDeploymentIDsBase58,
  mockDeploymentIDsBytes32,
} from './helpers'

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

// Send ETH to accounts that will act as indexers, curators, etc, to interact with the contracts
const sendEth = async (signers: Array<Wallet>, proxies: Array<Wallet>, amount: string) => {
  checkGovernor(signers[0].address)
  const sender = configureWallet(signers[0])
  const amountEther = utils.parseEther(amount)
  for (let i = 1; i < signers.length; i++) {
    const data = {
      to: signers[i].address,
      value: amountEther,
    }
    await executeTransaction(sender.sendTransaction(data))
  }
  for (let i = 0; i < proxies.length; i++) {
    const data = {
      to: proxies[i].address,
      value: amountEther,
    }
    await executeTransaction(sender.sendTransaction(data))
  }
}

// Send GRT to accounts that will act as indexers, curators, etc, to interact with the contracts
const populateGraphToken = async (
  signers: Array<Wallet>,
  proxies: Array<Wallet>,
  amount: string,
) => {
  const graphToken = new ConnectedGraphToken(true) // defaults to governor
  console.log('Sending GRT to indexers, curators, and proxies...')
  for (let i = 0; i < signers.length; i++) {
    await executeTransaction(graphToken.transferWithOverrides(signers[i].address, amount))
    await executeTransaction(graphToken.transferWithOverrides(proxies[i].address, amount))
  }
}

// Call set attribute for the signers
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

// Register ENS names for the signers
const populateENS = async (signers: Array<Wallet>) => {
  let i = 0
  for (const subgraph in subgraphMetadatas) {
    const ens = new ConnectedENS(true, undefined, undefined, signers[i])
    let name = subgraphMetadatas[subgraph].subgraphDisplayName
    // edge case - graph is only ens name that doesn't match display name in mock data
    if (name == 'The Graph') name = 'graphprotocol'
    console.log(`Setting ${name} for ${ens.wallet.address} on ens ...`)
    await executeTransaction(ens.setTestRecord(name))
    await executeTransaction(ens.setText(name))
    i++
  }
}

// Publish 10 subgraphs
// Publish new versions for them all
// Deprecate 1
const populateGNS = async (signers: Array<Wallet>) => {
  let i = 0
  for (const subgraph in subgraphMetadatas) {
    const gns = new ConnectedGNS(true, undefined, undefined, signers[i])
    const ipfs = 'https://api.thegraph.com/ipfs/'
    let name = subgraphMetadatas[subgraph].subgraphDisplayName
    // edge case - graph is only ens name that doesn't match display name in mock data
    if (name == 'The Graph') name = 'graphprotocol'
    const nameIdentifier = utils.namehash(`${name}.test`)
    console.log(`Publishing ${name} for ${gns.wallet.address} on GNS ...`)
    await executeTransaction(
      gns.publishNewSubgraphWithOverrides(
        ipfs,
        gns.wallet.address,
        mockDeploymentIDsBase58[i],
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
        mockDeploymentIDsBase58[i],
        nameIdentifier,
        name,
        subgraphMetadatas[subgraph] as SubgraphMetadata,
        '0', // TODO, only works on the first run right now, make more robust
      ),
    )
    i++
  }

  // Deprecation one subgraph for account 5
  const gns = new ConnectedGNS(true, undefined, undefined, signers[5])
  await executeTransaction(gns.deprecateWithOverrides(gns.wallet.address, '0'))
}

//  Each GraphAccount curates on their own
//  Then we stake on a few to make them higher, and see bonding curves in action
//  Then we run some redeems
const populateCuration = async (signers: Array<Wallet>) => {
  const stakeAmount = '5000'
  const stakeAmountBig = '10000'
  const totalAmount = '25000'
  for (let i = 0; i < signers.length; i++) {
    const curation = new ConnectedCuration(true, undefined, undefined, signers[i])
    const connectedGT = new ConnectedGraphToken(true, undefined, undefined, signers[i])
    console.log('First calling approve() to ensure curation contract can call transferFrom()...')
    await executeTransaction(
      connectedGT.approveWithOverrides(curation.curation.address, totalAmount),
    )
    console.log('Now calling multiple stake() txs on curation...')
    await executeTransaction(curation.stakeWithOverrides(mockDeploymentIDsBytes32[i], stakeAmount))
    await executeTransaction(curation.stakeWithOverrides(mockDeploymentIDsBytes32[0], stakeAmount))
    await executeTransaction(curation.stakeWithOverrides(mockDeploymentIDsBytes32[1], stakeAmount))
    await executeTransaction(
      curation.stakeWithOverrides(mockDeploymentIDsBytes32[2], stakeAmountBig),
    )
  }
  const redeemAmount = '1' // Redeeming SHARES/Signal, NOT tokens. 1 share can be a lot of tokens
  console.log('Running redeem transactions...')
  for (let i = 0; i < signers.length / 2; i++) {
    const curation = new ConnectedCuration(true, undefined, undefined, signers[i])
    await executeTransaction(
      curation.redeemWithOverrides(mockDeploymentIDsBytes32[1], redeemAmount),
    )
  }
}

// Register 10 indexers
// Unregister them all
// Register all 10 again
const populateServiceRegistry = async (signers: Array<Wallet>) => {
  // Lat = 43.651 Long = -79.382, resolves to the geohash dpz83d (downtown toronto)
  // TODO = implement GEOHASH in the exportable code. For now, we just use 10 geohashes
  const geoHashes: Array<string> = [
    'dpz83d',
    'dpz83a',
    'dpz83b',
    'dpz83c',
    'dpz83e',
    'dpz83f',
    'dpz83g',
    'dpz83h',
    'dpz83i',
    'dpz83j',
  ]

  const urls: Array<string> = [
    'https://indexer1.com',
    'https://indexer2.com',
    'https://indexer3.com',
    'https://indexer4.com',
    'https://indexer5.com',
    'https://indexer6.com',
    'https://indexer7.com',
    'https://indexer8.com',
    'https://indexer9.com',
    'https://indexer10.com',
  ]

  for (let i = 0; i < signers.length; i++) {
    const serviceRegistry = new ConnectedServiceRegistry(true, undefined, undefined, signers[i])
    console.log(`Registering an indexer in the service registry...`)
    await executeTransaction(serviceRegistry.registerWithOverrides(urls[i], geoHashes[i]))
    if (i < 2) {
      // Just need to test a few
      console.log(`Unregistering a few to test...`)
      await executeTransaction(serviceRegistry.unRegisterWithOverrides())
      console.log(`Re-registering them...`)
      await executeTransaction(serviceRegistry.registerWithOverrides(urls[i], geoHashes[i]))
    }
  }
}

// Deposit for 10 users
// Set thawing period to 0
// Unstake for a few users, then withdraw
// Set epochs to one block
// Create 10 allocations
// Settle 5 allocations (Settle is called by the proxies)
// Set back thawing period and epoch manager to default
const populateStaking = async (signers: Array<Wallet>, proxies: Array<Wallet>) => {
  checkGovernor(signers[0].address)
  const networkContracts = await connectContracts(signers[0])
  const epochManager = networkContracts.epochManager
  const stakeAmount = '10000'

  for (let i = 0; i < signers.length; i++) {
    const staking = new ConnectedStaking(true, undefined, undefined, signers[i])
    const connectedGT = new ConnectedGraphToken(true, undefined, undefined, signers[i])
    console.log(
      'First calling approve() to ensure staking contract can call transferFrom() from the stakers...',
    )
    await executeTransaction(connectedGT.approveWithOverrides(staking.staking.address, stakeAmount))
    console.log('Now calling stake()...')
    await executeTransaction(staking.stakeWithOverrides(stakeAmount))
  }

  console.log('Calling governor function to set epoch length to 1...')
  await executeTransaction(epochManager.setEpochLength(1, basicOverrides()))
  console.log('Calling governor function to set thawing period to 0...')
  await executeTransaction(networkContracts.staking.setThawingPeriod(0, basicOverrides()))
  console.log('Approve, stake extra, initialize unstake and withdraw for 3 signers...')
  for (let i = 0; i < 3; i++) {
    const staking = new ConnectedStaking(true, undefined, undefined, signers[i])
    const connectedGT = new ConnectedGraphToken(true, undefined, undefined, signers[i])
    await executeTransaction(connectedGT.approveWithOverrides(staking.staking.address, stakeAmount))
    await executeTransaction(staking.stakeWithOverrides(stakeAmount))
    await executeTransaction(staking.unstakeWithOverrides(stakeAmount))
    await executeTransaction(staking.withdrawWithOverrides())
  }

  console.log('Create 10 allocations...')
  for (let i = 0; i < signers.length; i++) {
    const staking = new ConnectedStaking(true, undefined, undefined, signers[i])
    await executeTransaction(
      staking.allocateWithOverrides(
        stakeAmount,
        '0',
        proxies[i].address,
        mockDeploymentIDsBytes32[i],
        mockChannelPubKeys[i],
      ),
    )
  }

  console.log('Run Epoch....')
  await executeTransaction(epochManager.runEpoch(basicOverrides()))
  console.log('Settle 5 allocations...')
  for (let i = 0; i < 5; i++) {
    // Note that the array of proxy wallets is used, not the signers
    const connectedGT = new ConnectedGraphToken(true, undefined, undefined, proxies[i])
    const staking = new ConnectedStaking(true, undefined, undefined, proxies[i])
    console.log(
      'First calling approve() to ensure staking contract can call transferFrom() from the proxies...',
    )
    await executeTransaction(connectedGT.approveWithOverrides(staking.staking.address, stakeAmount))
    console.log('Settling a channel...')
    await executeTransaction(staking.settleWithOverrides(stakeAmount))
  }
  const defaultThawingPeriod = 20
  const defaultEpochLength = 5760
  console.log('Setting epoch length back to default')
  await executeTransaction(epochManager.setEpochLength(defaultEpochLength, basicOverrides()))
  console.log('Setting back the thawing period to default')
  await executeTransaction(
    networkContracts.staking.setThawingPeriod(defaultThawingPeriod, basicOverrides()),
  )
}

const populateAll = async () => {
  const signers = createManySigners(20, process.env.MNEMONIC)
  const userAccounts = signers.slice(0, 10)
  const proxyAccounts = signers.slice(10, 20)
  // await sendEth(userAccounts, proxyAccounts, '0.25') // only use at the start. TODO - make this a cli option or something
  // await populateGraphToken(userAccounts, proxyAccounts, '100000') // only use at the start. TODO - make this a cli option or something
  await populateEthereumDIDRegistry(userAccounts)
  await populateENS(userAccounts)
  await populateGNS(userAccounts)
  await populateCuration(userAccounts)
  await populateServiceRegistry(userAccounts)
  await populateStaking(userAccounts, proxyAccounts)
}

const main = async () => {
  try {
    await populateAll()
  } catch (e) {
    console.log(`  ..failed within main: ${e.message}`)
    process.exit(1)
  }
}

main()
