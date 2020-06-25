#!/usr/bin/env ts-node
import { Wallet } from 'ethers'

// import { ConnectedCuration } from './curation'
// import { ConnectedENS } from './ens'
// import { ConnectedEthereumDIDRegistry } from './ethereumDIDRegistry'
// import { ConnectedGNS } from './gns'
import { ConnectedGraphToken } from './graph-token'
// import { ConnectedServiceRegistry } from './service-registry'
// import { ConnectedStaking } from './staking'

// Creates an array of signers, that are not connected to providers
const createManySigners = (count: number, mnemonic?: string): Array<Wallet> => {
  if (mnemonic == undefined) {
    const ganacheDeterministicMnemonic =
      'myth like bonus scare over problem client lizard pioneer submit female collect'
    mnemonic = ganacheDeterministicMnemonic
  }
  const createSigner = (index: number): Wallet => {
    const wallet = Wallet.fromMnemonic(mnemonic, `m/44'/60'/0'/${index}`)
    return wallet
  }
  const signers: Array<Wallet> = []
  for (let i = 0; i < count; i++) {
    signers.push(createSigner(i))
  }
  return signers
}

// Send GRT to accounts that will act as indexers, curators, etc, to interact with the contracts
const populateGraphToken = async (signers: Array<Wallet>) => {
  // since no wallet is passed, it defaults to process.env
  // Which is desired, as long as this account is the governor, or has been sent coins
  const graphToken = new ConnectedGraphToken()
  for (let i = 0; i < signers.length; i++){
    await graphToken.transfer(signers[i].address, "90000")
  }


}

// const populateENS = async () => {
//   // todo
// }

// const populateEthereumDIDRegistry = async () => {
//   // todo
// }

// const populateGNS = async () => {
//   // todo
// }

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
    const signers = createManySigners(50)
    const oneSigner = signers.slice(0, 1)
    const threeSigners = signers.slice(0, 3)
    const fiveSigners = signers.slice(0, 5)
    const tenSigners = signers.slice(0, 10)
    populateGraphToken(tenSigners)
  } catch (e) {
    console.log(`  ..failed within main: ${e.message}`)
    process.exit(1)
  }
}

main()

/*
 * Steps to populate data
  //  * - graph token
  //  *  - send GRT to these 10 accounts
 * - ens
 *  - register 10 graph accounts, each with names that I have mock data for
 *    need to somehow
 *
 * - ethereumDIDRegistry
 *  - call set attribute for the 10 accounts
 *
 * - gns
 *  - publish 30 (3x10) subgraphs (will need to get 10 real subgraphIDs)
 *  - publish new versions for them all
 *  - deprecate 10 of them
 *
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
 *
 *  - fixing parameters
 *    - set thawing period back to default
 *    - set epoch manager back to default
 *
 * - TODO FUTURE
 *  - handle all parameter updates
 *  - staking - rebate claimed, stake slashed
 */
// TODO , set up groups of 1, 3, 5, and 10 accounts
// todo - import all functions into here
// todo - make an all() call, that groups the six types of calls. incase the script goes haywire
