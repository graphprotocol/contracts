const { expectEvent, expectRevert } = require('openzeppelin-test-helpers')
const BN = web3.utils.BN

// contracts
const GraphToken = artifacts.require('./GraphToken.sol')
const Staking = artifacts.require('./Staking.sol')

// helpers
const GraphProtocol = require('../../graphProtocol.js')
const helpers = require('../lib/testHelpers')

contract('Staking (Indexing)', ([
                                  deploymentAddress,
                                  daoContract,
                                  indexingStaker,
                                  ...accounts
                                ]) => {
  const
    minimumCurationStakingAmount = helpers.stakingConstants.minimumCurationStakingAmount,
    minimumIndexingStakingAmount = helpers.stakingConstants.minimumIndexingStakingAmount,
    defaultReserveRatio = helpers.stakingConstants.defaultReserveRatio,
    maximumIndexers = helpers.stakingConstants.maximumIndexers,
    slashingPercent = helpers.stakingConstants.slashingPercent,
    thawingPeriod = helpers.stakingConstants.thawingPeriod,
    initialTokenSupply = helpers.graphTokenConstants.initialTokenSupply,
    stakingAmount = helpers.graphTokenConstants.stakingAmount,
    tokensMintedForStaker = helpers.graphTokenConstants.tokensMintedForStaker
  let
    deployedStaking,
    deployedGraphToken,
    subgraphIdHex0x = helpers.randomSubgraphIdHex0x(),
    subgraphIdHex = helpers.randomSubgraphIdHex(subgraphIdHex0x),
    subgraphIdBytes = web3.utils.hexToBytes(subgraphIdHex0x),
    gp

  beforeEach(async () => {
    // deploy GraphToken contract
    deployedGraphToken = await GraphToken.new(
      daoContract, // governor
      initialTokenSupply, // initial supply
      { from: deploymentAddress }
    )
    assert.isObject(deployedGraphToken, 'Deploy GraphToken contract tx failed.')

    // send some tokens to the staking account
    const tokensForIndexer = await deployedGraphToken.mint(
      indexingStaker, // to
      tokensMintedForStaker, // value
      { from: daoContract }
    )
    assert(tokensForIndexer, 'Mints Graph Tokens for Indexer tx failed.')

    // deploy Staking contract
    deployedStaking = await Staking.new(
      daoContract, // <address> governor
      minimumCurationStakingAmount, // <uint256> minimumCurationStakingAmount
      defaultReserveRatio, // <uint256> defaultReserveRatio (ppm)
      minimumIndexingStakingAmount, // <uint256> minimumIndexingStakingAmount
      maximumIndexers, // <uint256> maximumIndexers
      slashingPercent, // <uint256> slashingPercent
      thawingPeriod, // <uint256> thawingPeriod
      deployedGraphToken.address, // <address> token
      { from: deploymentAddress }
    )
    assert.isObject(deployedStaking, 'Deploy Staking contract tx failed.')

    // init Graph Protocol JS library with deployed staking contract
    gp = GraphProtocol({
      Staking: deployedStaking,
      GraphToken: deployedGraphToken
    })
    assert.isObject(gp, 'Initialize the Graph Protocol library.')
  })

  describe('staking', () => {
    it('...should allow staking directly', async () => {
      let totalBalance = await deployedGraphToken.balanceOf(deployedStaking.address)
      let stakerBalance = await deployedGraphToken.balanceOf(indexingStaker)
      assert(
        stakerBalance.toString() === tokensMintedForStaker.toString() &&
        totalBalance.toNumber() === 0,
        'Balances before transfer are incorrect.'
      )

      const depositTx = await deployedGraphToken.transferWithData(
        deployedStaking.address, // to
        stakingAmount, // value
        { from: indexingStaker },
      )
      assert(depositTx, 'Deposit in the standby pool tx failed')

      expectEvent.inTransaction(depositTx.tx, Staking, 'Deposit', {
        user: indexingStaker,
        amount: stakingAmount
      })

      const standbyTokensDeposited = await deployedStaking.standbyTokens(indexingStaker)
      assert(
        standbyTokensDeposited.toString() === stakingAmount.toString(),
        'Standby tokens were not deposited correctly.'
      )

      const data = web3.utils.hexToBytes('0x00' + subgraphIdHex)
      const stakeTx = await deployedStaking.stake(
        stakingAmount, // value
        data,
        { from: indexingStaker },
      )
      assert(stakeTx, 'Stake Graph Tokens for indexing directly.')

      const subgraph = await deployedStaking.subgraphs(subgraphIdBytes)
      assert(subgraph.totalIndexingStake.toString() === stakingAmount.toString(), 'Subgraph did not increase its total stake')

      expectEvent.inLogs(stakeTx.logs, 'IndexingNodeStaked', {
        staker: indexingStaker,
        amountStaked: stakingAmount,
        subgraphID: subgraphIdHex0x,
        subgraphTotalIndexingStake: subgraph.totalIndexingStake
      })

      const standbyTokensZero = await deployedStaking.standbyTokens(indexingStaker)
      assert(
        standbyTokensZero.toNumber() === 0,
        'Standby token were not staked properly.'
      )

      const { amountStaked, logoutStarted } = await gp.staking.indexingNodes(
        subgraphIdBytes,
        indexingStaker
      )
      assert(
        amountStaked.toString() === stakingAmount.toString() &&
        logoutStarted.toNumber() === 0,
        'Staked indexing amount incorrect.'
      )

      totalBalance = await deployedGraphToken.balanceOf(deployedStaking.address)
      stakerBalance = await deployedGraphToken.balanceOf(indexingStaker)

      assert(
        stakerBalance.toString() === tokensMintedForStaker.sub(stakingAmount).toString() &&
        totalBalance.toString() === stakingAmount.toString(),
        'Balances after transfer are incorrect.'
      )

    })

    it('...should allow staking through JS module', async () => {
      let totalBalance = await deployedGraphToken.balanceOf(deployedStaking.address)
      let stakerBalance = await deployedGraphToken.balanceOf(indexingStaker)
      assert(
        stakerBalance.toString() === tokensMintedForStaker.toString() &&
        totalBalance.toNumber() === 0,
        'Balances before transfer are incorrect.'
      )

      const indexingStake = await gp.staking.stakeForIndexing(
        subgraphIdHex, // subgraphId
        indexingStaker, // from
        stakingAmount // value
      )
      assert(indexingStake, 'Stake Graph Tokens tx through graph module failed.')

      const { amountStaked, logoutStarted } = await gp.staking.indexingNodes(
        subgraphIdBytes,
        indexingStaker
      )
      assert(
        amountStaked.toString() === stakingAmount.toString() &&
        logoutStarted.toNumber() === 0,
        'Staked indexing amount is not correct.'
      )

      totalBalance = await deployedGraphToken.balanceOf(deployedStaking.address)
      stakerBalance = await deployedGraphToken.balanceOf(indexingStaker)
      assert(
        stakerBalance.toString() === tokensMintedForStaker.sub(stakingAmount).toString() &&
        totalBalance.toString() === stakingAmount.toString(),
        'Balances after transfer are incorrect.'
      )
    })

    it('...should allow withdrawing tokens', async () => {
      let totalBalance = await deployedGraphToken.balanceOf(deployedStaking.address)
      let stakerBalance = await deployedGraphToken.balanceOf(indexingStaker)
      assert(
        stakerBalance.toString() === tokensMintedForStaker.toString() &&
        totalBalance.toNumber() === 0,
        'Balances before transfer are incorrect.'
      )

      const depositTx = await deployedGraphToken.transferWithData(
        deployedStaking.address, // to
        stakingAmount, // value
        { from: indexingStaker },
      )
      assert(depositTx, 'Deposit in the standby pool Tx failed')

      expectEvent.inTransaction(depositTx.tx, Staking, 'Deposit', {
        user: indexingStaker,
        amount: stakingAmount
      })

      const standbyTokensDeposited = await deployedStaking.standbyTokens(indexingStaker)
      assert(
        standbyTokensDeposited.toString() === stakingAmount.toString(),
        'Standby tokens were not deposited correctly.'
      )

      const withdrawTx = await deployedStaking.tokensWithdrawn(
        stakingAmount, // value
        { from: indexingStaker },
      )
      expectEvent.inLogs(withdrawTx.logs, 'Withdraw', {
        user: indexingStaker,
        amount: stakingAmount
      })
      totalBalance = await deployedGraphToken.balanceOf(deployedStaking.address)
      stakerBalance = await deployedGraphToken.balanceOf(indexingStaker)
      assert(
        stakerBalance.toString() === tokensMintedForStaker.toString() &&
        totalBalance.toNumber() === 0,
        'Balances after withdraw are incorrect.'
      )

    })

  })

  describe('logout', () => {
    it('...should begin logout and fail finalize logout', async () => {
      // stake some tokens
      const indexingStake = await gp.staking.stakeForIndexing(
        subgraphIdHex, // subgraphId
        indexingStaker, // from
        stakingAmount // value
      )
      assert(indexingStake, 'Stake Graph Tokens for indexing through module tx failed.')

      const subgraphWithStake = await deployedStaking.subgraphs(subgraphIdBytes)
      const previousTotalIndexingStake = subgraphWithStake.totalIndexingStake

      // begin log out after staking
      let logout = await gp.staking.beginLogout(subgraphIdBytes, indexingStaker)
      assert.isObject(logout, 'beginLogout tx failed.')

      const blockNumber = logout.receipt.blockNumber
      const block = await web3.eth.getBlock(blockNumber)

      const indexNode = await gp.staking.indexingNodes(
        subgraphIdBytes,
        indexingStaker
      )

      assert(indexNode.amountStaked.toNumber() === 0, 'Amount staked was not reduced to 0.')
      assert(indexNode.feesAccrued.toNumber() === 0, 'Fees accrued was not reduced to 0.')

      assert(indexNode.logoutStarted.toNumber() === block.timestamp,
        'Logout start is not equal to block timestamp'
      )

      const subgraph = await deployedStaking.subgraphs(subgraphIdBytes)
      assert(previousTotalIndexingStake.sub(stakingAmount).toString() === subgraph.totalIndexingStake.toString(), 'Subgraph did not decrease its total stake')

      const thawingTokens = await deployedStaking.thawingTokens(indexingStaker)
      assert(thawingTokens.toString() === stakingAmount.toString(), 'Thawing tokens not set properly')

      await expectRevert.unspecified(
        gp.staking.finalizeLogout(subgraphIdBytes, indexingStaker)
      )
      expectEvent.inLogs(logout.logs, 'IndexingNodeBeginLogout', {
        staker: indexingStaker,
        subgraphID: subgraphIdHex0x,
        unstakedAmount: stakingAmount,
        fees: new BN(0)
      })
    })

    it('...should finalize logout after cooling period', async () => {
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
      assert.isObject(deployedStaking, 'Deploy Staking contract tx failed.')

      // TODO - should reduce subgraph.totalStakers by 1, should delete indexingNodes(user), should decrease thawing tokens, should increase standby tokens, should check for event
      // finalize logout
      const finalizedLogout = await deployedStaking.finalizeLogout(
        subgraphIdBytes, // subgraphId
        { from: indexingStaker }
      )
      assert.isObject(finalizedLogout, 'Finalized Logout process.')
    })
  })

  describe('Graph Network indexers array', () => {
    it('...should allow setting of Graph Network subgraph ID, and the array of initial indexers, ' +
      'and allow the length of the indexers to be returned', async () => {
      const indexers = accounts.slice(0, 3)
      const subgraphID = subgraphIdHex0x

      const tx = await deployedStaking.setGraphSubgraphID(
        subgraphID,
        indexers,
        { from: daoContract },
      )
      assert(tx, 'Tx was not successful')

      const setSubgraphID = await deployedStaking.graphSubgraphID()
      assert(setSubgraphID === subgraphID, 'Graph Network subgraph ID was not set properly.')

      const indexersSetLength = await deployedStaking.numberOfGraphIndexingNodeAddresses()
      assert(indexersSetLength.toNumber() === indexers.length, 'The amount of indexers are not matching.')

      for (let i = 0; i < 3; i++) {
        let indexer = await deployedStaking.graphIndexingNodeAddresses(i)
        assert(indexer === indexers[i], `Indexer address ${i} does not match.`)
      }

    })
    it('...should delete the indexer from graph network indexing nodes', async () => {
      // TODO!!!!
    })
  })

})