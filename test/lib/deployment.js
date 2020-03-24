// contracts
const GraphToken = artifacts.require('./GraphToken.sol')
const Staking = artifacts.require('./Staking.sol')
const DisputeManager = artifacts.require('./DisputeManager')

// helpers
const helpers = require('./testHelpers')

function deployGraphToken(owner, params) {
  const initialTokenSupply = helpers.graphTokenConstants.initialTokenSupply

  return GraphToken.new(owner, initialTokenSupply, params)
}

function deployStakingContract(owner, graphToken, params) {
  const minimumCurationStakingAmount =
    helpers.stakingConstants.minimumCurationStakingAmount
  const minimumIndexingStakingAmount =
    helpers.stakingConstants.minimumIndexingStakingAmount
  const defaultReserveRatio = helpers.stakingConstants.defaultReserveRatio
  const maximumIndexers = helpers.stakingConstants.maximumIndexers
  const thawingPeriod = helpers.stakingConstants.thawingPeriod

  return Staking.new(
    owner, // <address> governor
    minimumCurationStakingAmount, // <uint256> minimumCurationStakingAmount
    defaultReserveRatio, // <uint256> defaultReserveRatio (ppm)
    minimumIndexingStakingAmount, // <uint256> minimumIndexingStakingAmount
    maximumIndexers, // <uint256> maximumIndexers
    thawingPeriod, // <uint256> thawingPeriod
    graphToken, // <address> token
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

module.exports = {
  deployGraphToken,
  deployStakingContract,
  deployDisputeManagerContract,
}
