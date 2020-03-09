const { expectEvent, expectRevert, time } = require('openzeppelin-test-helpers')
const BN = web3.utils.BN

// contracts
const GraphToken = artifacts.require('./GraphToken.sol')
const Staking = artifacts.require('./Staking.sol')

// helpers
const GraphProtocol = require('../../graphProtocol.js')
const helpers = require('../lib/testHelpers')

contract(
  'Staking (Indexing)',
  ([deploymentAddress, daoContract, indexingStaker, ...accounts]) => {
    const minimumCurationStakingAmount =
        helpers.stakingConstants.minimumCurationStakingAmount,
      minimumIndexingStakingAmount =
        helpers.stakingConstants.minimumIndexingStakingAmount,
      defaultReserveRatio = helpers.stakingConstants.defaultReserveRatio,
      maximumIndexers = helpers.stakingConstants.maximumIndexers,
      slashingPercent = helpers.stakingConstants.slashingPercent,
      thawingPeriod = helpers.stakingConstants.thawingPeriod,
      initialTokenSupply = helpers.graphTokenConstants.initialTokenSupply,
      stakingAmount = helpers.graphTokenConstants.stakingAmount,
      tokensMintedForStaker = helpers.graphTokenConstants.tokensMintedForStaker
    let deployedStaking,
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
        { from: deploymentAddress },
      )

      // send some tokens to the staking account
      const tokensForIndexer = await deployedGraphToken.mint(
        indexingStaker, // to
        tokensMintedForStaker, // value
        { from: daoContract },
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
        { from: deploymentAddress },
      )

      // init Graph Protocol JS library with deployed staking contract
      gp = GraphProtocol({
        Staking: deployedStaking,
        GraphToken: deployedGraphToken,
      })
    })

    describe('staking', () => {
      it('...should allow staking directly', async () => {
        let totalBalance = await deployedGraphToken.balanceOf(
          deployedStaking.address,
        )
        let stakerBalance = await deployedGraphToken.balanceOf(indexingStaker)
        assert(
          stakerBalance.toString() === tokensMintedForStaker.toString() &&
            totalBalance.toNumber() === 0,
          'Balances before transfer are incorrect.',
        )
        const data = '0x00' + subgraphIdHex
        const tx = await deployedGraphToken.transferToTokenReceiver(
          deployedStaking.address, // to
          stakingAmount, // value
          data, // data
          { from: indexingStaker },
        )

        const subgraph = await deployedStaking.subgraphs(subgraphIdHex0x)
        assert(
          subgraph.totalIndexingStake.toString() === stakingAmount.toString(),
          'Subgraph did not increase its total stake',
        )

        expectEvent.inTransaction(tx.tx, Staking, 'IndexingNodeStaked', {
          staker: indexingStaker,
          amountStaked: stakingAmount,
          subgraphID: subgraphIdHex0x,
          subgraphTotalIndexingStake: subgraph.totalIndexingStake,
        })

        const { amountStaked, logoutStarted } = await gp.staking.indexingNodes(
          subgraphIdHex0x,
          indexingStaker,
        )
        assert(
          amountStaked.toString() === stakingAmount.toString() &&
            logoutStarted.toNumber() === 0,
          'Staked indexing amount incorrect.',
        )

        totalBalance = await deployedGraphToken.balanceOf(
          deployedStaking.address,
        )
        stakerBalance = await deployedGraphToken.balanceOf(indexingStaker)

        assert(
          stakerBalance.toString() ===
            tokensMintedForStaker.sub(stakingAmount).toString() &&
            totalBalance.toString() === stakingAmount.toString(),
          'Balances after transfer are incorrect.',
        )
      })

      it('...should allow staking through JS module', async () => {
        await stakeForIndexing()
      })
    })

    describe('logout', () => {
      it('...should begin logout and fail finalize logout', async () => {
        await stakeForIndexing()
        await beginLogout()
        await expectRevert.unspecified(
          gp.staking.finalizeLogout(subgraphIdHex0x, indexingStaker),
        )
      })

      it('...should finalize logout and withdrawal after cooling period', async () => {
        await stakeForIndexing()
        await beginLogout()
        const subgraphBeforeFinalize = await deployedStaking.subgraphs(
          subgraphIdHex0x,
        )
        const indexerCount = subgraphBeforeFinalize.totalIndexers

        // Note - be careful moving this function around. It may
        // screw up time dependancies of other functions.
        await time.increase(thawingPeriod + 1)

        // finalize logout
        const finalizedLogout = await deployedStaking.finalizeLogout(
          subgraphIdHex0x, // subgraphId
          { from: indexingStaker },
        )

        const subgraph = await deployedStaking.subgraphs(subgraphIdHex0x)
        assert(
          subgraph.totalIndexers.toNumber() === indexerCount.toNumber() - 1,
          'Total indexers of subgraph did not decrease by 1.',
        )

        const indexingNode = await gp.staking.indexingNodes(
          subgraphIdHex0x,
          indexingStaker,
        )

        assert(
          indexingNode.amountStaked.toNumber() === 0 &&
            indexingNode.feesAccrued.toNumber() === 0 &&
            indexingNode.logoutStarted.toNumber() === 0,
          'Index node was not deleted.',
        )

        assert(
          indexingNode.lockedTokens.toString() === '0',
          'Locked tokens not set properly',
        )

        expectEvent.inLogs(finalizedLogout.logs, 'IndexingNodeFinalizeLogout', {
          staker: indexingStaker,
          subgraphID: subgraphIdHex0x,
        })
      })
    })

    describe('Graph Network indexers array', () => {
      it(
        '...should allow setting of Graph Network subgraph ID, and the array of initial indexers, ' +
          'and allow the length of the indexers to be returned',
        async () => {
          await setGraphSubgraphID()
        },
      )
      it('...should add an indexer to the graphIndexingNodeAddresses(), and delete the user', async () => {
        await setGraphSubgraphID()
        const indexersSetLength = (
          await deployedStaking.numberOfGraphIndexingNodeAddresses()
        ).toNumber()

        await stakeForIndexing()

        const newLength = (
          await deployedStaking.numberOfGraphIndexingNodeAddresses()
        ).toNumber()
        assert(
          newLength === indexersSetLength + 1,
          `Indexers length does not match.`,
        )

        let indexer = await deployedStaking.graphIndexingNodeAddresses(
          newLength - 1,
        )
        assert(indexer === indexingStaker, `Indexer address does not match.`)

        await beginLogout()

        // Note - index isn't deleted on the array, the entry is just zeroed
        let blankIndexer = await deployedStaking.graphIndexingNodeAddresses(
          newLength - 1,
        )
        assert(
          blankIndexer === helpers.zeroAddress(),
          `Indexer was not deleted.`,
        )
      })
    })

    async function stakeForIndexing() {
      let totalBalance = await deployedGraphToken.balanceOf(
        deployedStaking.address,
      )
      let stakerBalance = await deployedGraphToken.balanceOf(indexingStaker)
      assert(
        stakerBalance.toString() === tokensMintedForStaker.toString() &&
          totalBalance.toNumber() === 0,
        'Balances before transfer are incorrect.',
      )

      const indexingStake = await gp.staking.stakeForIndexing(
        subgraphIdHex, // subgraphId
        indexingStaker, // from
        stakingAmount, // value
      )
      assert(
        indexingStake,
        'Stake Graph Tokens tx through graph module failed.',
      )

      const { amountStaked, logoutStarted } = await gp.staking.indexingNodes(
        subgraphIdHex0x,
        indexingStaker,
      )
      assert(
        amountStaked.toString() === stakingAmount.toString() &&
          logoutStarted.toNumber() === 0,
        'Staked indexing amount is not correct.',
      )

      totalBalance = await deployedGraphToken.balanceOf(deployedStaking.address)
      stakerBalance = await deployedGraphToken.balanceOf(indexingStaker)
      assert(
        stakerBalance.toString() ===
          tokensMintedForStaker.sub(stakingAmount).toString() &&
          totalBalance.toString() === stakingAmount.toString(),
        'Balances after transfer are incorrect.',
      )
      return indexingStake
    }

    // begin log out after staking (must call stakeForIndexing() first)
    async function beginLogout() {
      const subgraphWithStake = await deployedStaking.subgraphs(subgraphIdHex0x)
      const previousTotalIndexingStake = subgraphWithStake.totalIndexingStake

      const logout = await gp.staking.beginLogout(
        subgraphIdHex0x,
        indexingStaker,
      )

      const blockNumber = logout.receipt.blockNumber
      const block = await web3.eth.getBlock(blockNumber)

      const indexNode = await gp.staking.indexingNodes(
        subgraphIdHex0x,
        indexingStaker,
      )

      assert(
        indexNode.amountStaked.toNumber() === 0,
        'Amount staked was not reduced to 0.',
      )
      assert(
        indexNode.feesAccrued.toNumber() === 0,
        'Fees accrued was not reduced to 0.',
      )

      assert(
        indexNode.logoutStarted.toNumber() === block.timestamp,
        'Logout start is not equal to block timestamp',
      )

      const subgraph = await deployedStaking.subgraphs(subgraphIdHex0x)
      assert(
        previousTotalIndexingStake.sub(stakingAmount).toString() ===
          subgraph.totalIndexingStake.toString(),
        'Subgraph did not decrease its total stake',
      )

      assert(
        indexNode.lockedTokens.toString() === stakingAmount.toString(),
        'Locked tokens not set properly',
      )

      expectEvent.inLogs(logout.logs, 'IndexingNodeBeginLogout', {
        staker: indexingStaker,
        subgraphID: subgraphIdHex0x,
        unstakedAmount: stakingAmount,
        fees: new BN(0),
      })
      return logout
    }

    async function setGraphSubgraphID() {
      const indexers = accounts.slice(0, 3)
      const subgraphID = subgraphIdHex0x

      const tx = await deployedStaking.setGraphSubgraphID(
        subgraphID,
        indexers,
        { from: daoContract },
      )
      assert(tx, 'Tx was not successful')

      const setSubgraphID = await deployedStaking.graphSubgraphID()
      assert(
        setSubgraphID === subgraphID,
        'Graph Network subgraph ID was not set properly.',
      )

      const indexersSetLength = await deployedStaking.numberOfGraphIndexingNodeAddresses()
      assert(
        indexersSetLength.toNumber() === indexers.length,
        'The amount of indexers are not matching.',
      )

      for (let i = 0; i < 3; i++) {
        let indexer = await deployedStaking.graphIndexingNodeAddresses(i)
        assert(indexer === indexers[i], `Indexer address ${i} does not match.`)
      }
    }
  },
)
