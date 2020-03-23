const GNS = artifacts.require('GNS')
const GraphToken = artifacts.require('GraphToken')
const RewardsManager = artifacts.require('RewardsManager')
const ServiceRegistry = artifacts.require('ServiceRegistry')
const Staking = artifacts.require('Staking')

const BN = web3.utils.BN

/**
 * @dev Parameters used in deploying the contracts.
 */

// 10,000,000 * 10^18  total supply of Graph Tokens at time of deployment
const initialSupply = new BN('10000000000000000000000000')
// 100 * 10^18 minimum amount allowed to be staked by Indexing Nodes
const minimumIndexingStakingAmount = new BN('100000000000000000000')
// maximum number of Indexing Nodes staked higher than stake to consider
const maximumIndexers = 10
// percent of stake to slash in successful dispute
// const slashingPercentage = 10
// amount of seconds to wait until indexer can finish stake logout
const thawingPeriod = 60 * 60 * 24 * 7

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

    // Deploy Staking contract using deployed GraphToken address + constants defined above
    .then(deployedGraphToken => {
      deployed.GraphToken = deployedGraphToken
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

    // Deploy ServiceRegistry contract
    .then(deployedRewardsManager => {
      deployed.RewardsManager = deployedRewardsManager
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
      console.log('SIMPLE GOVERNOR ADDRESS: ', simpleGraphTokenGovernorAddress)
      console.log('GRAPH TOKEN ADDRESS: ', deployed.GraphToken.address)
      console.log('STAKING ADDRESS: ', deployed.Staking.address)
      console.log('REWARDS MANAGER ADDRESS: ', deployed.RewardsManager.address)
      console.log('Service Registry: ', deployed.ServiceRegistry.address)
      console.log('GNS: ', deployed.GNS.address)
      console.log(`Deployed ${Object.entries(deployed).length} contracts.`)
    })
    .catch(err => {
      console.log('There was an error with deploy: ', err)
    })
}
