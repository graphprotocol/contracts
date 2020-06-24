/*
 * Steps to populate data
 * - graph token
 *  - send GRT to these 10 accounts
 *  - send GRT to all the coworkers accounts
 *  - add in the add minter function
 *  - make them all minters
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

