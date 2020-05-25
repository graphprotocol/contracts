// contracts
const Curation = artifacts.require('./Curation.sol')
const DisputeManager = artifacts.require('./DisputeManager')
const EpochManager = artifacts.require('./EpochManager')
const GNS = artifacts.require('./GNS')
const GraphToken = artifacts.require('./GraphToken.sol')
const ServiceRegisty = artifacts.require('./ServiceRegistry.sol')
const Staking = artifacts.require('./Staking.sol')

// helpers
const { defaults } = require('./testHelpers')

function deployGRT(owner, params) {
  return GraphToken.new(owner, defaults.token.initialSupply, params)
}

function deployCurationContract(owner, graphToken, params) {
  return Curation.new(
    owner,
    graphToken,
    defaults.curation.reserveRatio,
    defaults.curation.minimumCurationStake,
    params,
  )
}

function deployDisputeManagerContract(owner, graphToken, arbitrator, staking, params) {
  return DisputeManager.new(
    owner,
    arbitrator,
    graphToken,
    staking,
    defaults.dispute.minimumDeposit,
    defaults.dispute.fishermanRewardPercentage,
    defaults.dispute.slashingPercentage,
    params,
  )
}

function deployEpochManagerContract(owner, params) {
  return EpochManager.new(owner, defaults.epochs.lengthInBlocks, params)
}

function deployGNS(owner, params) {
  return GNS.new(owner, params)
}

function deployServiceRegistry(owner) {
  return ServiceRegisty.new({ from: owner })
}

async function deployStakingContract(owner, graphToken, epochManager, curation, params) {
  const contract = await Staking.new(owner, graphToken, epochManager, params)
  await contract.setCuration(curation, { from: owner })
  await contract.setChannelDisputeEpochs(defaults.staking.channelDisputeEpochs, { from: owner })
  await contract.setMaxAllocationEpochs(defaults.staking.maxAllocationEpochs, { from: owner })
  await contract.setThawingPeriod(defaults.staking.thawingPeriod, { from: owner })
  return contract
}

module.exports = {
  deployCurationContract,
  deployDisputeManagerContract,
  deployEpochManagerContract,
  deployGNS,
  deployGRT,
  deployServiceRegistry,
  deployStakingContract,
}
