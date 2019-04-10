const { expectEvent, shouldFail } = require('openzeppelin-test-helpers');

// contracts
const GraphToken = artifacts.require("./GraphToken.sol")
const Staking = artifacts.require("./Staking.sol")

// helpers
const GraphProtocol = require('../../graphProtocol.js')
const helpers = require('../lib/testHelpers')

contract('Staking (Indexing)', ([
  deploymentAddress,
  daoContract,
  indexingStaker,
  ...accounts
]) => {
  /** 
   * testing constants
   */
  const minimumCurationStakingAmount = 100,
    defaultReserveRatio = 500000, // PPM
    minimumIndexingStakingAmount = 100,
    maximumIndexers = 10,
    slashingPercent = 10,
    coolingPeriod = 7
  let deployedStaking,
    deployedGraphToken,
    initialTokenSupply = 1000000,
    stakingAmount = 1000,
    tokensMintedForStaker = stakingAmount * 10,
    subgraphIdHex = helpers.randomSubgraphIdHex(),
    subgraphIdBytes = helpers.randomSubgraphIdBytes(subgraphIdHex),
    gp

  beforeEach(async () => {
    // deploy GraphToken contract
    deployedGraphToken = await GraphToken.new(
      daoContract, // governor
      initialTokenSupply, // initial supply
      { from: deploymentAddress }
    )
    assert.isObject(deployedGraphToken, "Deploy GraphToken contract.")

    // send some tokens to the staking account
    const tokensForIndexer = await deployedGraphToken.mint(
      indexingStaker, // to
      tokensMintedForStaker, // value
      { from: daoContract }
    )
    assert(tokensForIndexer, "Mints Graph Tokens for Indexer.")

    // deploy Staking contract
    deployedStaking = await Staking.new(
      daoContract, // <address> governor
      minimumCurationStakingAmount, // <uint256> minimumCurationStakingAmount
      defaultReserveRatio, // <uint256> defaultReserveRatio (ppm)
      minimumIndexingStakingAmount, // <uint256> minimumIndexingStakingAmount
      maximumIndexers, // <uint256> maximumIndexers
      slashingPercent, // <uint256> slashingPercent
      coolingPeriod, // <uint256> coolingPeriod
      deployedGraphToken.address, // <address> token
      { from: deploymentAddress }
    )
    assert.isObject(deployedStaking, "Deploy Staking contract.")
    assert(web3.utils.isAddress(deployedStaking.address), "Staking address is address.")

    // init Graph Protocol JS library with deployed staking contract
    gp = GraphProtocol({
      Staking: deployedStaking,
      GraphToken: deployedGraphToken
    })
    assert.isObject(gp, "Initialize the Graph Protocol library.")
  })

  describe("staking", () => {
    it('...should allow staking directly', async () => {
      let totalBalance = await deployedGraphToken.balanceOf(deployedStaking.address)
      let stakerBalance = await deployedGraphToken.balanceOf(indexingStaker)
      assert(
        stakerBalance.toNumber() === tokensMintedForStaker && 
        totalBalance.toNumber() === 0,
        "Balances before transfer are correct."
      )

      const data = web3.utils.hexToBytes('0x00' + subgraphIdHex)
      const indexingStake = await deployedGraphToken.transferWithData(
        deployedStaking.address, // to
        stakingAmount, // value
        data, // data
        { from: indexingStaker }
      )
      assert(indexingStake, "Stake Graph Tokens for indexing directly.")

      const { amountStaked, logoutStarted } = await gp.staking.indexingNodes(
        indexingStaker,
        subgraphIdBytes
      )
      assert(
        amountStaked.toNumber() === stakingAmount &&
        logoutStarted.toNumber() === 0,
        "Staked indexing amount confirmed."
      )
      
      totalBalance = await deployedGraphToken.balanceOf(deployedStaking.address)
      stakerBalance = await deployedGraphToken.balanceOf(indexingStaker)
      assert(
        stakerBalance.toNumber() === tokensMintedForStaker - stakingAmount && 
        totalBalance.toNumber() === stakingAmount,
        "Balances after transfer are correct."
      )
    })
  
    it('...should allow staking through JS module', async () => {
      let totalBalance = await deployedGraphToken.balanceOf(deployedStaking.address)
      let stakerBalance = await deployedGraphToken.balanceOf(indexingStaker)
      assert(
        stakerBalance.toNumber() === tokensMintedForStaker && 
        totalBalance.toNumber() === 0,
        "Balances before transfer are correct."
      )

      const indexingStake = await gp.staking.stakeForIndexing(
        subgraphIdHex, // subgraphId
        indexingStaker, // from
        stakingAmount // value
      )
      assert(indexingStake, "Stake Graph Tokens for indexing through module.")

      const { amountStaked, logoutStarted } = await gp.staking.indexingNodes(
        indexingStaker,
        subgraphIdBytes
      )
      assert(
        amountStaked.toNumber() === stakingAmount &&
        logoutStarted.toNumber() === 0,
        "Staked indexing amount confirmed."
      )

      totalBalance = await deployedGraphToken.balanceOf(deployedStaking.address)
      stakerBalance = await deployedGraphToken.balanceOf(indexingStaker)
      assert(
        stakerBalance.toNumber() === tokensMintedForStaker - stakingAmount && 
        totalBalance.toNumber() === stakingAmount,
        "Balances after transfer are correct."
      )
    })
  })

  describe("logout", () => {
    let logout

    it("...should begin logout", async () => {
      // stake some tokens
      const indexingStake = await gp.staking.stakeForIndexing(
        subgraphIdHex, // subgraphId
        indexingStaker, // from
        stakingAmount // value
      )
      assert(indexingStake, "Stake Graph Tokens for indexing through module.")

      // begin log out after staking
      logout = await gp.staking.beginLogout(subgraphIdBytes, indexingStaker)
      assert.isObject(logout, "Begins log out.")
    })

    it("...should emit IndexingNodeLogout event", async () => {
      expectEvent.inLogs(logout.logs, 'IndexingNodeLogout', {
        staker: indexingStaker,
      })
    })

    /**
     * @dev Staking involves a cooling period, so we need to mock that in order to test `finalizeLogout`
     */
    it("...should fail to finalize logout before cooling period", async () => {
      await shouldFail(
        gp.staking.finalizeLogout(subgraphIdHex, indexingStaker)
      )
    })

    it("...should finalize logout after cooling period", async () => {
      // redeploy Staking contract
      deployedStaking = await Staking.new(
        daoContract,
        minimumCurationStakingAmount,
        defaultReserveRatio,
        minimumIndexingStakingAmount,
        maximumIndexers,
        slashingPercent,
        0, /** @dev No Cooling Period */
        deployedGraphToken.address,
        { from: deploymentAddress }
      )
      assert.isObject(deployedStaking, "Deploy Staking contract.")
      assert(web3.utils.isAddress(deployedStaking.address), "Staking address is address.")

      // finalize logout
      const finalizedLogout = await deployedStaking.finalizeLogout(
        subgraphIdBytes, // subgraphId
        { from: indexingStaker }
      )
      assert.isObject(finalizedLogout, "Finalized Logout process.")
    })
  })
})
