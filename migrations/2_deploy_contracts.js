const config = require('./deploy.config.js')

const Curation = artifacts.require('Curation')
const DisputeManager = artifacts.require('DisputeManager')
const EpochManager = artifacts.require('EpochManager')
const GNS = artifacts.require('GNS')
const GraphToken = artifacts.require('GraphToken')
const RewardsManager = artifacts.require('RewardsManager')
const ServiceRegistry = artifacts.require('ServiceRegistry')
const Staking = artifacts.require('Staking')

module.exports = async (deployer, network, accounts) => {
  const log = (msg, ...params) => {
    deployer.logger.log(msg, ...params)
  }
  const executeAndLog = async (fn, msg, ...params) => {
    const { tx } = await fn
    log(msg, tx, ...params)
  }

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
      const staking = await deployer.deploy(
        Staking,
        governor,
        graphToken.address,
        epochManager.address,
      )
      const rewardsManager = await deployer.deploy(RewardsManager, governor)
      const disputeManager = await deployer.deploy(
        DisputeManager,
        governor,
        governor,
        graphToken.address,
        staking.address,
        config.dispute.minimumDeposit,
        config.dispute.fishermanRewardPercentage,
        config.dispute.slashingPercentage,
      )
      const serviceRegistry = await deployer.deploy(ServiceRegistry, governor)
      const gns = await deployer.deploy(GNS, governor)

      // Set Curation parameters
      log('   Configuring Contracts')
      log('   ---------------------')
      await executeAndLog(staking.setCuration(curation.address), '\t> Staking -> Set curation: ')
      await executeAndLog(
        staking.setMaxAllocationEpochs(config.staking.maxAllocationEpochs),
        '\t> Staking -> Set maxAllocationEpochs: ',
      )
      await executeAndLog(
        staking.setThawingPeriod(config.staking.thawingPeriod),
        '\t> Staking -> Set thawingPeriod: ',
      )
      await executeAndLog(
        staking.setChannelDisputeEpochs(config.staking.channelDisputeEpochs),
        '\t> Staking -> Set channelDisputeEpochs: ',
      )
      await executeAndLog(curation.setStaking(staking.address), '\t> Curation -> Set staking: ')

      // Summary
      log('\n')
      log('Contract Addresses')
      log('==================')
      log('> GOVERNOR:', governor)
      log('> GRAPH TOKEN:', graphToken.address)
      log('> EPOCH MANAGER:', epochManager.address)
      log('> DISPUTE MANAGER', disputeManager.address)
      log('> STAKING:', staking.address)
      log('> CURATION:', curation.address)
      log('> REWARDS MANAGER:', rewardsManager.address)
      log('> SERVICE REGISTRY:', serviceRegistry.address)
      log('> GNS:', gns.address)
    })
    .catch(err => log(err))
}
