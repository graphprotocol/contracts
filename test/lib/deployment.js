// contracts
const Curation = artifacts.require('./Curation.sol')
const DisputeManager = artifacts.require('./DisputeManager')
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

function deployDisputeManagerContract(
  owner,
  graphToken,
  arbitrator,
  staking,
  params,
) {
  const slashingPercentage = helpers.stakingConstants.slashingPercentage
  const minimumDisputeDepositAmount =
    helpers.stakingConstants.minimumDisputeDepositAmount

  return DisputeManager.new(
    owner,
    graphToken,
    arbitrator,
    staking,
    slashingPercentage,
    minimumDisputeDepositAmount,
    params,
  )
}

function deployStakingContract(owner, graphToken, params) {
  const minimumIndexingStakingAmount =
    helpers.stakingConstants.minimumIndexingStakingAmount
  const maximumIndexers = helpers.stakingConstants.maximumIndexers
  const thawingPeriod = helpers.stakingConstants.thawingPeriod

  return Staking.new(
    owner, // <address> governor
    minimumIndexingStakingAmount, // <uint256> minimumIndexingStakingAmount
    maximumIndexers, // <uint256> maximumIndexers
    thawingPeriod, // <uint256> thawingPeriod
    graphToken, // <address> token
    params,
  )
}

module.exports = {
  deployCurationContract,
  deployDisputeManagerContract,
  deployGraphToken,
  deployStakingContract,
}
