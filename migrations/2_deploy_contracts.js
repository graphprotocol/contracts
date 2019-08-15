const GNS = artifacts.require('GNS')
const GraphToken = artifacts.require('GraphToken')
const MultiSigWallet = artifacts.require('MultiSigWallet')
const RewardsManager = artifacts.require('RewardsManager')
const ServiceRegistry = artifacts.require('ServiceRegistry')
const Staking = artifacts.require('Staking')

/**
 * @dev Parameters used in deploying the contracts.
 */
const initialSupply = 1000000, // total supply of Graph Tokens at time of deployment
  minimumCurationStakingAmount = 100, // minimum amount allowed to be staked by Market Curators
  defaultReserveRatio = 500000, // reserve ratio (percent as PPM)
  minimumIndexingStakingAmount = 100, // minimum amount allowed to be staked by Indexing Nodes
  maximumIndexers = 10, // maximum number of Indexing Nodes staked higher than stake to consider
  slashingPercent = 10, // percent of stake to slash in successful dispute
  thawingPeriod = 60 * 60 * 24 * 7, // amount of seconds to wait until indexer can finish stake logout
  multiSigRequiredVote = 0, // votes required (setting a required amount here will override a formula used later)
  multiSigOwners = [] // add addresses of the owners of the multisig contract here

let deployed = {} // store deployed contracts in a JSON object

module.exports = (deployer, network, accounts) => {
  // Simple deployment means we do not use the multisig wallet for deployment
  if (network === 'simpleRopsten' || network === 'simpleDevelopment') {
    let deployAddress = accounts[0]
    deployer.deploy(
      GraphToken,
      accounts[1], // governor NOTE - Governor of GraphToken is accounts[1], NOT accounts[0], because of a require statement in GraphToken.sol
      initialSupply // initial supply
    )

    // Deploy Staking contract using deployed GraphToken address + constants defined above
      .then(deployedGraphToken => {
        deployed.GraphToken = deployedGraphToken
        console.log('GRAPH TOKEN ADDRESS: ', deployed.GraphToken.address)
        return deployer.deploy(
          Staking,
          deployAddress, // <address> governor
          minimumCurationStakingAmount, // <uint256> minimumCurationStakingAmount
          defaultReserveRatio, // <uint256> defaultReserveRatio
          minimumIndexingStakingAmount, // <uint256> minimumIndexingStakingAmount
          maximumIndexers, // <uint256> maximumIndexers
          slashingPercent, // <uint256> slashingPercent
          thawingPeriod, // <uint256> thawingPeriod
          deployed.GraphToken.address // <address> token
        )
      })

      /** @notice From this point on, the order of deployment does not matter. */
      // Deploy RewardsManager contract with MultiSigWallet as the `governor`
      .then(deployedStaking => {
        deployed.Staking = deployedStaking
        console.log('STAKING ADDRESS: ', deployed.Staking.address)
        return deployer.deploy(
          RewardsManager,
          deployAddress, // <address> governor
        )
      })

      // Deploy ServiceRegistry contract with MultiSigWallet as the `governor`
      .then(deployedRewardsManager => {
        deployed.RewardsManager = deployedRewardsManager
        console.log('REWARDS MANAGER ADDRESS: ', deployed.RewardsManager.address)
        return deployer.deploy(
          ServiceRegistry,
          deployAddress, // <address> governor
        )
      })

      // Deploy ServiceRegistry contract with MultiSigWallet as the `governor`
      .then(deployedServiceRegistry => {
        deployed.ServiceRegistry = deployedServiceRegistry
        console.log('Service Registry: ', deployed.ServiceRegistry.address)
        return deployer.deploy(
          GNS,
          deployAddress, // <address> governor
        )
      })
      // All contracts have been deployed and we log the total
      .then(deployedGNS => {
        deployed.GNS = deployedGNS
        console.log('\n')
        console.log('SIMPLE GOVERNOR ADDRESS: ', accounts[1])
        console.log('GRAPH TOKEN ADDRESS: ', deployed.GraphToken.address)
        console.log('STAKING ADDRESS: ', deployed.Staking.address)
        console.log('REWARDS MANAGER ADDRESS: ', deployed.RewardsManager.address)
        console.log('Service Registry: ', deployed.ServiceRegistry.address)
        console.log('GNS: ', deployed.GNS.address)
        console.log(`Deployed ${Object.entries(deployed).length} contracts.`)
      })
  } else {
    // We need the Multisig contract address to set as governor for all upgradable contracts
    deployer.deploy(
      MultiSigWallet,
      multiSigOwners.concat(accounts), // owners
      multiSigRequiredVote || // require number of votes set above or
      (Math.floor(accounts.length / 2) + 1 || 1) // require a majority
    )

    // Deploy the GraphToken contract before deploying the Staking contract
      .then(deployedMultiSigWallet => {
        deployed.MultiSigWallet = deployedMultiSigWallet
        console.log('MULTISIG ADDRESS: ', deployed.MultiSigWallet.address)
        return deployer.deploy(
          GraphToken,
          deployed.MultiSigWallet.address, // governor
          initialSupply // initial supply
        )
      })

      // Deploy Staking contract using deployed GraphToken address + constants defined above
      .then(deployedGraphToken => {
        deployed.GraphToken = deployedGraphToken
        console.log('GRAPH TOKEN ADDRESS: ', deployed.GraphToken.address)
        return deployer.deploy(
          Staking,
          deployed.MultiSigWallet.address, // <address> governor
          minimumCurationStakingAmount, // <uint256> minimumCurationStakingAmount
          defaultReserveRatio, // <uint256> defaultReserveRatio
          minimumIndexingStakingAmount, // <uint256> minimumIndexingStakingAmount
          maximumIndexers, // <uint256> maximumIndexers
          slashingPercent, // <uint256> slashingPercent
          thawingPeriod, // <uint256> thawingPeriod
          deployed.GraphToken.address // <address> token
        )
      })

      /** @notice From this point on, the order of deployment does not matter. */
      // Deploy RewardsManager contract with MultiSigWallet as the `governor`
      .then(deployedStaking => {
        deployed.Staking = deployedStaking
        console.log('STAKING ADDRESS: ', deployed.Staking.address)
        return deployer.deploy(
          RewardsManager,
          deployed.MultiSigWallet.address, // <address> governor
        )
      })

      // Deploy ServiceRegistry contract with MultiSigWallet as the `governor`
      .then(deployedRewardsManager => {
        deployed.RewardsManager = deployedRewardsManager
        console.log('REWARDS MANAGER ADDRESS: ', deployed.RewardsManager.address)
        return deployer.deploy(
          ServiceRegistry,
          deployed.MultiSigWallet.address, // <address> governor
        )
      })

      // Deploy ServiceRegistry contract with MultiSigWallet as the `governor`
      .then(deployedServiceRegistry => {
        deployed.ServiceRegistry = deployedServiceRegistry
        console.log('Service Registry: ', deployed.ServiceRegistry.address)
        return deployer.deploy(
          GNS,
          deployed.MultiSigWallet.address, // <address> governor
        )
      })
      // All contracts have been deployed and we log the total
      .then(deployedGNS => {
        deployed.GNS = deployedGNS
        console.log('\n')
        console.log('MULTISIG ADDRESS: ', deployed.MultiSigWallet.address)
        console.log('GRAPH TOKEN ADDRESS: ', deployed.GraphToken.address)
        console.log('STAKING ADDRESS: ', deployed.Staking.address)
        console.log('REWARDS MANAGER ADDRESS: ', deployed.RewardsManager.address)
        console.log('Service Registry: ', deployed.ServiceRegistry.address)
        console.log('GNS: ', deployed.GNS.address)
        console.log(`Deployed ${Object.entries(deployed).length} contracts.`)
      })
  }
}
