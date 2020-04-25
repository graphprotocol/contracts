// contracts
const Curation = artifacts.require('./Curation.sol')
const DisputeManager = artifacts.require('./DisputeManager')
const EpochManager = artifacts.require('./EpochManager')
const GraphToken = artifacts.require('./GraphToken.sol')
const Staking = artifacts.require('./Staking.sol')

// helpers
const { defaults } = require('./testHelpers')

function deployGraphToken(owner, params) {
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
    defaults.dispute.rewardPercentage,
    defaults.dispute.slashingPercentage,
    params,
  )
}

function deployEpochManagerContract(owner, params) {
  return EpochManager.new(owner, defaults.epochs.lengthInBlocks, params)
}

async function deployStakingContract(owner, graphToken, epochManager, curation, params) {
  return Staking.new(
    owner,
    graphToken,
    epochManager,
    curation,
    defaults.staking.maxSettlementDuration,
    defaults.staking.thawingPeriod,
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
