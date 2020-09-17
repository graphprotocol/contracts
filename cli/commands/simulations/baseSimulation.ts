// #!/usr/bin/env ts-node
// import * as dotenv from 'dotenv'

// import { Wallet, utils } from 'ethers'

// TODO - uncomment and rebuild this all, most the functions have been renamed, so it needs
// a full overhaul

// import {
//   ConnectedCuration,
//   ConnectedGNS,
//   ConnectedGraphToken,
//   ConnectedENS,
//   ConnectedEthereumDIDRegistry,
//   ConnectedServiceRegistry,
//   ConnectedStaking,
// } from '../../../contracts/connectedContracts'
// import { connectContracts } from '../../../contracts/connectedNetwork'
// import { AccountMetadata, SubgraphMetadata } from '../../../mockData/metadataHelpers'
// import * as AccountDatas from '../../../mockData/account-metadata/accountMetadatas'
// import * as SubgraphDatas from '../../../mockData/subgraph-metadata/subgraphMetadatas'
// import {
//   userAccounts,
//   proxyAccounts,
//   channelAccounts,
//   executeTransaction,
//   checkGovernor,
//   mockChannelPubKeys,
//   mockDeploymentIDsBase58,
//   mockDeploymentIDsBytes32,
// } from '../../../contracts/helpers'

// dotenv.config()
// const accountMetadatas = AccountDatas.default
// const subgraphMetadatas = SubgraphDatas.default

// // Send ETH to accounts that will act as indexers, curators, etc, to interact with the contracts
// const sendEth = async (
//   network: string,
//   governor: Wallet,
//   signers: Array<Wallet>,
//   proxies: Array<Wallet>,
//   amount: string,
// ) => {
//   console.log('Sending ETH...')
//   checkGovernor(governor.address, network)
//   const amountEther = utils.parseEther(amount)
//   for (let i = 1; i < signers.length; i++) {
//     const data = {
//       to: signers[i].address,
//       value: amountEther,
//     }
//     await executeTransaction(governor.sendTransaction(data), network)
//   }
//   for (let i = 0; i < proxies.length; i++) {
//     const data = {
//       to: proxies[i].address,
//       value: amountEther,
//     }
//     await executeTransaction(governor.sendTransaction(data), network)
//   }
// }

// // Send GRT to accounts that will act as indexers, curators, etc, to interact with the contracts
// const populateGraphToken = async (
//   network: string,
//   signers: Array<Wallet>,
//   proxies: Array<Wallet>,
//   amount: string,
// ) => {
//   console.log('Running graph token contract calls...')
//   const graphToken = new ConnectedGraphToken(network, signers[0]) // defaults to governor
//   console.log('Sending GRT to indexers, curators, and proxies...')
//   for (let i = 0; i < signers.length; i++) {
//     await executeTransaction(graphToken.transferWithDecimals(signers[i].address, amount), network)
//     await executeTransaction(graphToken.transferWithDecimals(proxies[i].address, amount), network)
//   }
// }

// // Call set attribute for the signers
// const populateEthereumDIDRegistry = async (network: string, signers: Array<Wallet>) => {
//   console.log('Running did registry contract calls...')
//   let i = 0
//   for (const account in accountMetadatas) {
//     const edr = new ConnectedEthereumDIDRegistry(network, signers[i])
//     const name = accountMetadatas[account].name
//     console.log(
//       `Calling setAttribute on DID registry for ${name} and account ${edr.configuredWallet.address} ...`,
//     )
//     const ipfs = 'https://api.thegraph.com/ipfs/'
//     await executeTransaction(
//       edr.pinIPFSAndSetAttribute(ipfs, accountMetadatas[account] as AccountMetadata),
//       network,
//     )
//     i++
//   }
// }

// // Register ENS names for the signers
// // Do this manually, in the Rinkeby UI. No need to test it multiple times

// // Publish 10 subgraphs
// // Publish new versions for them all
// // Deprecate 1
// const populateGNS = async (network: string, signers: Array<Wallet>) => {
//   console.log('Running GNS contract calls...')
//   let i = 0
//   for (const subgraph in subgraphMetadatas) {
//     const gns = new ConnectedGNS(network, signers[i])
//     const ipfs = 'https://api.thegraph.com/ipfs/'
//     let name = subgraphMetadatas[subgraph].displayName
//     // edge case - graph is only ens name that doesn't match display name in mock data
//     if (name == 'The Graph') name = 'graphprotocol'
//     const nameIdentifier = utils.namehash(`${name}.test`)
//     console.log(`Publishing ${name} for ${gns.configuredWallet.address} on GNS ...`)
//     await executeTransaction(
//       gns.pinIPFSAndNewSubgraph(
//         ipfs,
//         gns.configuredWallet.address,
//         mockDeploymentIDsBase58[i],
//         nameIdentifier,
//         name,
//         subgraphMetadatas[subgraph] as SubgraphMetadata,
//       ),
//       network,
//     )
//     console.log(`Updating version of ${name} for ${gns.configuredWallet.address} on GNS ...`)
//     await executeTransaction(
//       gns.pinIPFSAndNewVersion(
//         ipfs,
//         gns.configuredWallet.address,
//         mockDeploymentIDsBase58[i],
//         nameIdentifier,
//         name,
//         subgraphMetadatas[subgraph] as SubgraphMetadata,
//         '0', // TODO, only works on the first run right now, make more robust
//       ),
//       network,
//     )
//     i++
//   }

//   // Deprecation one subgraph for account 5
//   const gns = new ConnectedGNS(network, signers[5])
//   await executeTransaction(gns.gns.deprecate(gns.configuredWallet.address, '0'), network)
// }

// //  Each GraphAccount curates on their own
// //  Then we signal on a few to make them higher, and see bonding curves in action
// //  Then we run some redeems
// const populateCuration = async (network: string, signers: Array<Wallet>) => {
//   console.log('Running curation contract calls...')
//   const signalAmount = '5000'
//   const signalAmountBig = '10000'
//   const totalAmount = '25000'
//   for (let i = 0; i < signers.length; i++) {
//     const curation = new ConnectedCuration(network, signers[i])
//     const connectedGT = new ConnectedGraphToken(network, signers[i])
//     console.log('First calling approve() to ensure curation contract can call transferFrom()...')
//     await executeTransaction(
//       connectedGT.approveWithDecimals(curation.contract.address, totalAmount),
//       network,
//     )
//     console.log('Now calling multiple signal() txs on curation...')
//     await executeTransaction(
//       curation.signalWithDecimals(mockDeploymentIDsBytes32[i], signalAmount),
//       network,
//     )
//     await executeTransaction(
//       curation.signalWithDecimals(mockDeploymentIDsBytes32[0], signalAmount),
//       network,
//     )
//     await executeTransaction(
//       curation.signalWithDecimals(mockDeploymentIDsBytes32[1], signalAmount),
//       network,
//     )
//     await executeTransaction(
//       curation.signalWithDecimals(mockDeploymentIDsBytes32[2], signalAmountBig),
//       network,
//     )
//   }
//   const redeemAmount = '1' // Redeeming SHARES/Signal, NOT tokens. 1 share can be a lot of tokens
//   console.log('Running redeem transactions...')
//   for (let i = 0; i < signers.length / 2; i++) {
//     const curation = new ConnectedCuration(network, signers[i])
//     await executeTransaction(
//       curation.redeemWithDecimals(mockDeploymentIDsBytes32[1], redeemAmount),
//       network,
//     )
//   }
// }

// // Register 10 indexers
// // Unregister them all
// // Register all 10 again
// const populateServiceRegistry = async (network: string, signers: Array<Wallet>) => {
//   console.log('Running service registry contract calls...')
//   // Lat = 43.651 Long = -79.382, resolves to the geohash dpz83d (downtown toronto)
//   // TODO = implement GEOHASH in the exportable code. For now, we just use 10 geohashes
//   const geoHashes: Array<string> = [
//     'dpz83d',
//     'dpz83a',
//     'dpz83b',
//     'dpz83c',
//     'dpz83e',
//     'dpz83f',
//     'dpz83g',
//     'dpz83h',
//     'dpz83i',
//     'dpz83j',
//   ]

//   const urls: Array<string> = [
//     'https://indexer1.com',
//     'https://indexer2.com',
//     'https://indexer3.com',
//     'https://indexer4.com',
//     'https://indexer5.com',
//     'https://indexer6.com',
//     'https://indexer7.com',
//     'https://indexer8.com',
//     'https://indexer9.com',
//     'https://indexer10.com',
//   ]

//   for (let i = 0; i < signers.length; i++) {
//     const serviceRegistry = new ConnectedServiceRegistry(network, signers[i])
//     console.log(`Registering an indexer in the service registry...`)
//     await executeTransaction(serviceRegistry.contract.register(urls[i], geoHashes[i]), network)
//     if (i < 2) {
//       // Just need to test a few
//       console.log(`Unregistering a few to test...`)
//       await executeTransaction(serviceRegistry.contract.unregister(), network)
//       console.log(`Re-registering them...`)
//       await executeTransaction(serviceRegistry.contract.register(urls[i], geoHashes[i]), network)
//     }
//   }
// }

// // Deposit for 10 users
// // Set thawing period to 0
// // Unstake for a few users, then withdraw
// // Set epochs to one block
// // Create 10 allocations
// // Close 5 allocations (Close is called by the proxies)
// // Set back thawing period and epoch manager to default
// const populateStaking = async (network: string, signers: Array<Wallet>, proxies: Array<Wallet>) => {
//   console.log('Running staking contract calls...')
//   checkGovernor(signers[0].address, network)
//   const networkContracts = await connectContracts(signers[0], network)
//   const epochManager = networkContracts.epochManager
//   const stakeAmount = '10000'

//   for (let i = 0; i < signers.length; i++) {
//     const staking = new ConnectedStaking(network, signers[i])
//     const connectedGT = new ConnectedGraphToken(network, signers[i])
//     console.log(
//       'First calling approve() to ensure staking contract can call transferFrom() from the stakers...',
//     )
//     await executeTransaction(
//       connectedGT.approveWithDecimals(staking.contract.address, stakeAmount),
//       network,
//     )
//     console.log('Now calling stake()...')
//     await executeTransaction(staking.stakeWithDecimals(stakeAmount), network)
//   }

//   console.log('Calling governor function to set epoch length to 1...')
//   await executeTransaction(epochManager.setEpochLength(1), network)
//   console.log('Calling governor function to set thawing period to 0...')
//   await executeTransaction(networkContracts.staking.setThawingPeriod(0), network)
//   console.log('Approve, stake extra, initialize unstake and withdraw for 3 signers...')
//   for (let i = 0; i < 3; i++) {
//     const staking = new ConnectedStaking(network, signers[i])
//     const connectedGT = new ConnectedGraphToken(network, signers[i])
//     await executeTransaction(
//       connectedGT.approveWithDecimals(staking.contract.address, stakeAmount),
//       network,
//     )
//     await executeTransaction(staking.stakeWithDecimals(stakeAmount), network)
//     await executeTransaction(staking.unstakeWithDecimals(stakeAmount), network)
//     await executeTransaction(staking.contract.withdraw(), network)
//   }

//   console.log('Create 10 allocations...')
//   for (let i = 0; i < signers.length; i++) {
//     const staking = new ConnectedStaking(network, signers[i])
//     await executeTransaction(
//       staking.allocateWithDecimals(
//         stakeAmount,
//         '0',
//         proxies[i].address,
//         mockDeploymentIDsBytes32[i],
//         mockChannelPubKeys[i],
//       ),
//       network,
//     )
//   }

//   console.log('Run Epoch....')
//   await executeTransaction(epochManager.runEpoch(), network)
//   console.log('Close 5 allocations...')
//   for (let i = 0; i < 5; i++) {
//     // Note that the array of proxy wallets is used, not the signers
//     const connectedGT = new ConnectedGraphToken(network, proxies[i])
//     const staking = new ConnectedStaking(network, proxies[i])
//     console.log(
//       'First calling approve() to ensure staking contract can call transferFrom() from the proxies...',
//     )
//     await executeTransaction(
//       connectedGT.approveWithDecimals(staking.contract.address, stakeAmount),
//       network,
//     )
//     console.log('Settling a channel...')
//     await executeTransaction(staking.closeWithDecimals(stakeAmount), network)
//   }
//   const defaultThawingPeriod = 20
//   const defaultEpochLength = 5760
//   console.log('Setting epoch length back to default')
//   await executeTransaction(epochManager.setEpochLength(defaultEpochLength), network)
//   console.log('Setting back the thawing period to default')
//   await executeTransaction(networkContracts.staking.setThawingPeriod(defaultThawingPeriod), network)
// }

// const baseSimulation = async (mnemonic: string, provider: string, network: string): Promise<void> => {
//   const users = userAccounts(mnemonic, provider)
//   const proxies = proxyAccounts(mnemonic, provider)
//   const channels = channelAccounts(mnemonic, provider)
//   const governor = signers[0]
//   // await sendEth(network, governor, userAccounts, proxyAccounts, '0.25') // only use at the start. TODO - make this a cli option or something
//   await populateGraphToken(network, users, proxies, '100000') // only use at the start. TODO - make this a cli option or something
//   await populateEthereumDIDRegistry(network, users)
//   await populateGNS(network, users)
//   await populateCuration(network, users)
//   await populateServiceRegistry(network, users)
//   await populateStaking(network, users, proxies)
// }

export const baseSimulation = async (): Promise<void> => {}
