const Curation = artifacts.require('Curation')
const EpochManager = artifacts.require('EpochManager')
const GNS = artifacts.require('GNS')
const GraphToken = artifacts.require('GraphToken')
const RewardsManager = artifacts.require('RewardsManager')
const ServiceRegistry = artifacts.require('ServiceRegistry')
const Staking = artifacts.require('Staking')

const BN = web3.utils.BN

/**
 * @dev Parameters used in deploying the contracts.
 */

// 10,000,000 (in wei)  total supply of Graph Tokens at time of deployment
const initialSupply = web3.utils.toWei(new BN('10000000'))
// 100 (in wei) minimum amount allowed to be staked by Indexing Nodes
const minimumIndexingStakingAmount = web3.utils.toWei(new BN('100'))
// maximum number of Indexing Nodes staked higher than stake to consider
const maximumIndexers = 10
// 100 (in wei) minimum amount allowed to be staked by Indexing Nodes
const minimumCurationStake = web3.utils.toWei(new BN('100'))
// Reserve ratio to set bonding curve for curation (in PPM)
const reserveRatio = new BN('500000')
// percent of stake to slash in successful dispute
// const slashingPercentage = 10
// amount of seconds to wait until indexer can finish stake logout
const thawingPeriod = 60 * 60 * 24 * 7
// Epoch length
const epochLength = new BN((24 * 60 * 60) / 15) // One day in blocks

const deployed = {} // store deployed contracts in a JSON object
let simpleGraphTokenGovernorAddress

module.exports = (deployer, network, accounts) => {
  // governor NOTE - Governor of GraphToken is accounts[1], NOT accounts[0],
  // because of a require statement in GraphToken.sol
  simpleGraphTokenGovernorAddress = accounts[1]
  const deployAddress = accounts[0]
  deployer
    .deploy(
      GraphToken,
      simpleGraphTokenGovernorAddress,
      initialSupply, // initial supply
    )

    .then(deployedGraphToken => {
      deployed.GraphToken = deployedGraphToken
      return deployer.deploy(
        EpochManager,
        deployAddress, // <address> governor
        epochLength, // <uint256> epoch duration in blocks
      )
    })

    // Deploy Staking contract using deployed GraphToken address + constants defined above
    .then(deployedEpochManager => {
      deployed.EpochManager = deployedEpochManager
      return deployer.deploy(
        Staking,
        deployAddress, // <address> governor
        minimumIndexingStakingAmount, // <uint256> minimumIndexingStakingAmount
        maximumIndexers, // <uint256> maximumIndexers
        thawingPeriod, // <uint256> thawingPeriod NOTE - NO THAWING PERIOD
        deployed.GraphToken.address, // <address> token
      )
    })
    .catch(err => {
      console.log('There was an error with deploy: ', err)
    })

    /** @notice From this point on, the order of deployment does not matter. */
    // Deploy RewardsManager contract
    .then(deployedStaking => {
      deployed.Staking = deployedStaking
      return deployer.deploy(
        RewardsManager,
        deployAddress, // <address> governor
      )
    })
    .catch(err => {
      console.log('There was an error with deploy: ', err)
    })

    // Deploy Curation contract
    .then(deployedRewardsManager => {
      deployed.RewardsManager = deployedRewardsManager
      return deployer.deploy(
        Curation,
        deployAddress, // <address> governor
        deployed.GraphToken.address, // <address> token
        deployAddress, // <address> distributor
        reserveRatio, // <uint256> defaultReserveRatio,
        minimumCurationStake, // <uint256> minimumCurationStake
      )
    })
    .catch(err => {
      console.log('There was an error with deploy: ', err)
    })

    // Deploy ServiceRegistry contract
    .then(deployedCuration => {
      deployed.Curation = deployedCuration
      return deployer.deploy(
        ServiceRegistry,
        deployAddress, // <address> governor
      )
    })
    .catch(err => {
      console.log('There was an error with deploy: ', err)
    })

    // Deploy ServiceRegistry contract
    .then(deployedServiceRegistry => {
      deployed.ServiceRegistry = deployedServiceRegistry
      return deployer.deploy(
        GNS,
        deployAddress, // <address> governor
      )
    })
    .catch(err => {
      console.log('There was an error with deploy: ', err)
    })

    // All contracts have been deployed and we log the total
    .then(deployedGNS => {
      deployed.GNS = deployedGNS

      console.log('\n')
      console.log('> GOVERNOR:', simpleGraphTokenGovernorAddress)
      console.log('> GRAPH TOKEN:', deployed.GraphToken.address)
      console.log('> EPOCH MANAGER:', deployed.EpochManager.address)
      console.log('[Incentives]')
      console.log('> STAKING:', deployed.Staking.address)
      console.log('> CURATION:', deployed.Curation.address)
      console.log('> REWARDS MANAGER:', deployed.RewardsManager.address)
      console.log('[Discovery]')
      console.log('> SERVICE REGISTRY:', deployed.ServiceRegistry.address)
      console.log('> GNS:', deployed.GNS.address)
      console.log('\n')
      console.log(`>> Deployed ${Object.entries(deployed).length} contracts`)
    })
    .catch(err => {
      console.log('There was an error with deploy: ', err)
    })
}
