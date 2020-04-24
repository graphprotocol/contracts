const config = require('./deploy.config.js')

const Curation = artifacts.require('Curation')
const DisputeManager = artifacts.require('DisputeManager')
const EpochManager = artifacts.require('EpochManager')
const GNS = artifacts.require('GNS')
const GraphToken = artifacts.require('GraphToken')
const RewardsManager = artifacts.require('RewardsManager')
const ServiceRegistry = artifacts.require('ServiceRegistry')
const Staking = artifacts.require('Staking')

const ChannelFactory = artifacts.require('channel/funding/proxies/ProxyFactory')
const ChannelMaster = artifacts.require(
  'channel/funding/state-deposit-holders/MinimumViableMultisig',
)

module.exports = function(deployer, network, accounts) {
  deployer
    .then(async () => {
      const governor = accounts[0]

      const graphToken = await deployer.deploy(GraphToken, governor, config.token.initialSupply)
      const epochManager = await deployer.deploy(
        EpochManager,
        governor,
        config.epochs.lengthInBlocks,
      )
      const curation = await deployer.deploy(
        Curation,
        governor,
        graphToken.address,
        config.curation.reserveRatio,
        config.curation.minimumCurationStake,
      )
      const channelFactory = await deployer.deploy(ChannelFactory)
      const channelMaster = await deployer.deploy(ChannelMaster)
      const staking = await deployer.deploy(
        Staking,
        governor,
        graphToken.address,
        epochManager.address,
        curation.address,
        config.staking.maxSettlementDuration,
        config.staking.thawingPeriod,
        channelFactory.address,
        channelMaster.address,
        config.staking.channelHub,
      )
      const rewardsManager = await deployer.deploy(RewardsManager, governor)
      const disputeManager = await deployer.deploy(
        DisputeManager,
        governor,
        governor,
        graphToken.address,
        staking.address,
        config.dispute.minimumDeposit,
        config.dispute.rewardPercentage,
        config.dispute.slashingPercentage,
      )
      const serviceRegistry = await deployer.deploy(ServiceRegistry, governor)
      const gns = await deployer.deploy(GNS, governor)

      // Set Curation parameters
      await curation.setDistributor(staking.address)

      deployer.logger.log('Contract Addresses')
      deployer.logger.log('==================')
      deployer.logger.log('> GOVERNOR:', governor)
      deployer.logger.log('> GRAPH TOKEN:', graphToken.address)
      deployer.logger.log('> EPOCH MANAGER:', epochManager.address)
      deployer.logger.log('> DISPUTE MANAGER', disputeManager.address)
      deployer.logger.log('> STAKING:', staking.address)
      deployer.logger.log('> CURATION:', curation.address)
      deployer.logger.log('> REWARDS MANAGER:', rewardsManager.address)
      deployer.logger.log('> SERVICE REGISTRY:', serviceRegistry.address)
      deployer.logger.log('> GNS:', gns.address)
    })
    .catch(err => deployer.logger.log(err))
}
