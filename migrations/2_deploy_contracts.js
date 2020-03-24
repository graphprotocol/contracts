const GNS = artifacts.require('GNS')
const GraphToken = artifacts.require('GraphToken')
const MultiSigWallet = artifacts.require('MultiSigWallet')
const RewardsManager = artifacts.require('RewardsManager')
const ServiceRegistry = artifacts.require('ServiceRegistry')
const Staking = artifacts.require('Staking')

const BN = web3.utils.BN

/**
 * @dev Parameters used in deploying the contracts.
 */

// 10,000,000 * 10^18  total supply of Graph Tokens at time of deployment
const initialSupply = new BN('10000000000000000000000000')
// 100 * 10^18 minimum amount allowed to be staked by Market Curators
const minimumCurationStakingAmount = new BN('100000000000000000000')
// reserve ratio (percent as PPM)
const defaultReserveRatio = 500000
// 100 * 10^18 minimum amount allowed to be staked by Indexing Nodes
const minimumIndexingStakingAmount = new BN('100000000000000000000')
// maximum number of Indexing Nodes staked higher than stake to consider
const maximumIndexers = 10
// percent of stake to slash in successful dispute
// const slashingPercentage = 10
// amount of seconds to wait until indexer can finish stake logout
const thawingPeriod = 60 * 60 * 24 * 7
// votes required (setting a required amount here will override a formula used later)
const multiSigRequiredVote = 0
// add addresses of the owners of the multisig contract here
const multiSigOwners = []

const deployed = {} // store deployed contracts in a JSON object
let simpleGraphTokenGovernorAddress

module.exports = (deployer, network, accounts) => {
  // Simple deployment means we do not use the multisig wallet for deployment
  if (network === 'noMultisigRopsten' || network === 'noMultisigDevelopment') {
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
          minimumCurationStakingAmount, // <uint256> minimumCurationStakingAmount
          defaultReserveRatio, // <uint256> defaultReserveRatio
          minimumIndexingStakingAmount, // <uint256> minimumIndexingStakingAmount
          maximumIndexers, // <uint256> maximumIndexers
          0, // <uint256> thawingPeriod NOTE - NO THAWING PERIOD
          deployed.GraphToken.address, // <address> token
        )
      })
      .catch(err => {
        console.log('There was an error with deploy: ', err)
      })
      /** @notice From this point on, the order of deployment does not matter. */
      // Deploy RewardsManager contract with MultiSigWallet as the `governor`
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

      // Deploy ServiceRegistry contract with MultiSigWallet as the `governor`
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

      // Deploy ServiceRegistry contract with MultiSigWallet as the `governor`
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
        console.log(
          'SIMPLE GOVERNOR ADDRESS: ',
          simpleGraphTokenGovernorAddress,
        )
        console.log('GRAPH TOKEN ADDRESS: ', deployed.GraphToken.address)
        console.log('STAKING ADDRESS: ', deployed.Staking.address)
        console.log(
          'REWARDS MANAGER ADDRESS: ',
          deployed.RewardsManager.address,
        )
        console.log('Service Registry: ', deployed.ServiceRegistry.address)
        console.log('GNS: ', deployed.GNS.address)
        console.log(`Deployed ${Object.entries(deployed).length} contracts.`)
      })
      .catch(err => {
        console.log('There was an error with deploy: ', err)
      })
  } else {
    // We need the Multisig contract address to set as governor for all upgradable contracts
    deployer
      .deploy(
        MultiSigWallet,
        multiSigOwners.concat(accounts), // owners
        multiSigRequiredVote || // require number of votes set above or
          Math.floor(accounts.length / 2) + 1 ||
          1, // require a majority
      )

      // Deploy the GraphToken contract before deploying the Staking contract
      .then(deployedMultiSigWallet => {
        deployed.MultiSigWallet = deployedMultiSigWallet
        return deployer.deploy(
          GraphToken,
          deployed.MultiSigWallet.address, // governor
          initialSupply, // initial supply
        )
      })
      .catch(err => {
        console.log('There was an error with deploy: ', err)
      })

      // Deploy Staking contract using deployed GraphToken address + constants defined above
      .then(deployedGraphToken => {
        deployed.GraphToken = deployedGraphToken
        return deployer.deploy(
          Staking,
          deployed.MultiSigWallet.address, // <address> governor
          minimumCurationStakingAmount, // <uint256> minimumCurationStakingAmount
          defaultReserveRatio, // <uint256> defaultReserveRatio
          minimumIndexingStakingAmount, // <uint256> minimumIndexingStakingAmount
          maximumIndexers, // <uint256> maximumIndexers
          thawingPeriod, // <uint256> thawingPeriod
          deployed.GraphToken.address, // <address> token
        )
      })
      .catch(err => {
        console.log('There was an error with deploy: ', err)
      })
      /** @notice From this point on, the order of deployment does not matter. */
      // Deploy RewardsManager contract with MultiSigWallet as the `governor`
      .then(deployedStaking => {
        deployed.Staking = deployedStaking
        return deployer.deploy(
          RewardsManager,
          deployed.MultiSigWallet.address, // <address> governor
        )
      })
      .catch(err => {
        console.log('There was an error with deploy: ', err)
      })

      // Deploy ServiceRegistry contract with MultiSigWallet as the `governor`
      .then(deployedRewardsManager => {
        deployed.RewardsManager = deployedRewardsManager
        return deployer.deploy(
          ServiceRegistry,
          deployed.MultiSigWallet.address, // <address> governor
        )
      })
      .catch(err => {
        console.log('There was an error with deploy: ', err)
      })

      // Deploy ServiceRegistry contract with MultiSigWallet as the `governor`
      .then(deployedServiceRegistry => {
        deployed.ServiceRegistry = deployedServiceRegistry
        return deployer.deploy(
          GNS,
          deployed.MultiSigWallet.address, // <address> governor
        )
      })
      .catch(err => {
        console.log('There was an error with deploy: ', err)
      })
      // All contracts have been deployed and we log the total
      .then(deployedGNS => {
        deployed.GNS = deployedGNS
        console.log('\n')
        console.log('MULTISIG ADDRESS: ', deployed.MultiSigWallet.address)
        console.log('GRAPH TOKEN ADDRESS: ', deployed.GraphToken.address)
        console.log('STAKING ADDRESS: ', deployed.Staking.address)
        console.log(
          'REWARDS MANAGER ADDRESS: ',
          deployed.RewardsManager.address,
        )
        console.log('Service Registry: ', deployed.ServiceRegistry.address)
        console.log('GNS: ', deployed.GNS.address)
        console.log(`Deployed ${Object.entries(deployed).length} contracts.`)
      })
      .catch(err => {
        console.log('There was an error with deploy: ', err)
      })
  }
}
