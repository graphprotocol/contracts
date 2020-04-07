// contracts
const Curation = artifacts.require('./Curation.sol')
const DisputeManager = artifacts.require('./DisputeManager')
const EpochManager = artifacts.require('./EpochManager')
const GraphToken = artifacts.require('./GraphToken.sol')
const Staking = artifacts.require('./Staking.sol')

// helpers
const helpers = require('./testHelpers')
const { defaults } = require('./testHelpers')

function deployGraphToken(owner, params) {
  return GraphToken.new(owner, defaults.token.initialSupply, params)
}

function deployCurationContract(owner, graphToken, distributor, params) {
  return Curation.new(
    owner,
    graphToken,
    distributor,
    defaults.curation.reserveRatio,
    defaults.curation.minimumCurationStake,
    params,
  )
}

function deployDisputeManagerContract(owner, graphToken, arbitrator, staking, params) {
  return DisputeManager.new(
    owner,
    graphToken,
    arbitrator,
    staking,
    defaults.dispute.rewardPercentage,
    defaults.dispute.minimumDeposit,
    params,
  )
}

function deployEpochManagerContract(owner, params) {
  return EpochManager.new(owner, defaults.epochs.lengthInBlocks, params)
}

function deployStakingContract(owner, graphToken, epochManager, params) {
  return Staking.new(
    owner,
    graphToken,
    epochManager,
    defaults.staking.maxSettlementDuration,
    defaults.staking.slashingPercentage,
    params,
  )
}

module.exports = {
  deployCurationContract,
  deployDisputeManagerContract,
  deployEpochManagerContract,
  deployGraphToken,
  deployStakingContract,
}
