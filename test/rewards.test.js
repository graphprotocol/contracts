const { shouldFail } = require('openzeppelin-test-helpers');

// contracts
const GraphToken = artifacts.require("./GraphToken.sol")
const Staking = artifacts.require("./Staking.sol")

// helpers
const GraphProtocol = require('../graphProtocol.js')
const helpers = require('./lib/testHelpers')

contract('Rewards protection', ([
  deploymentAddress,
  daoContract,
  curationStaker,
  ...accounts
]) => {
  /** 
   * testing constants & variables
   */
  const minimumCurationStakingAmount = 100,
    defaultReserveRatio = 1000000, // 100%
    minimumIndexingStakingAmount = 100,
    maximumIndexers = 10,
    slashingPercent = 10,
    thawingPeriod = 60 * 60 * 24 * 7 // seconds
  let deployedStaking,
    deployedGraphToken,
    initialTokenSupply = 1000000,
    tokensMintedForStaker = 10001 * minimumCurationStakingAmount,
    subgraphIdHex = helpers.randomSubgraphIdHex(),
    subgraphIdBytes = helpers.randomSubgraphIdBytes(subgraphIdHex),
    gp

  before(async () => {
    // deploy GraphToken contract
    deployedGraphToken = await GraphToken.new(
      daoContract, // governor
      initialTokenSupply, // initial supply
      { from: deploymentAddress }
    )
    assert.isObject(deployedGraphToken, "Deploy GraphToken contract.")

    // send some tokens to the staking account
    const tokensForCurator = await deployedGraphToken.mint(
      curationStaker, // to
      tokensMintedForStaker, // value
      { from: daoContract }
    )
    assert(tokensForCurator, "Mints Graph Tokens for Curator.")

    // deploy Staking contract
    deployedStaking = await Staking.new(
      daoContract, // <address> governor
      minimumCurationStakingAmount, // <uint256> minimumCurationStakingAmount
      defaultReserveRatio, // <uint256> defaultReserveRatio
      minimumIndexingStakingAmount, // <uint256> minimumIndexingStakingAmount
      maximumIndexers, // <uint256> maximumIndexers
      slashingPercent, // <uint256> slashingPercent
      thawingPeriod, // <uint256> thawingPeriod
      deployedGraphToken.address, // <address> token
      { from: deploymentAddress }
    )
    assert.isObject(deployedStaking, "Deploy Staking contract.")

    // init Graph Protocol JS library with deployed staking contract
    gp = GraphProtocol({
      Staking: deployedStaking,
      GraphToken: deployedGraphToken
    })
    assert.isObject(gp, "Initialize the Graph Protocol library.")
  })

  it('...should allow staking of 10,000 shares', async () => {
    let totalBalance = await deployedGraphToken.balanceOf(deployedStaking.address)
    let curatorBalance = await deployedGraphToken.balanceOf(curationStaker)
    assert(
      curatorBalance.toNumber() === tokensMintedForStaker && 
      totalBalance.toNumber() === 0,
      "Balances before transfer are correct."
    )

    // stake 10,000 shares
    const data = web3.utils.hexToBytes('0x01' + subgraphIdHex)
    const curationStake = await deployedGraphToken.transferWithData(
      deployedStaking.address, // to
      10000 * minimumCurationStakingAmount, // value
      data, // data
      { from: curationStaker }
    )
    assert(curationStake, "Stake Graph Tokens for curation.")
    
    // check balances
    totalBalance = await deployedGraphToken.balanceOf(deployedStaking.address)
    curatorBalance = await deployedGraphToken.balanceOf(curationStaker)
    assert(
      curatorBalance.toNumber() === 100 && 
      totalBalance.toNumber() === tokensMintedForStaker - curatorBalance.toNumber(),
      "Balances after transfer are correct."
    )
  })

  it('...should not allow staking 1 more than the existing 10,000 shares', async () => {
    // stake 1 more share
    const data = web3.utils.hexToBytes('0x01' + subgraphIdHex)
    const curationStake = deployedGraphToken.transferWithData(
      deployedStaking.address, // to
      1 * minimumCurationStakingAmount, // value
      data, // data
      { from: curationStaker }
    )

    // assert a failure due to `stakingAmount` being too high
    await shouldFail.reverting( curationStake )
  })
})
