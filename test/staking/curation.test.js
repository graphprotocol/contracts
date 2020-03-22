const { expectEvent } = require('@openzeppelin/test-helpers')
const BN = web3.utils.BN

// contracts
const GraphToken = artifacts.require('./GraphToken.sol')
const Staking = artifacts.require('./Staking.sol')

// helpers
const GraphProtocol = require('../../graphProtocol.js')
const helpers = require('../lib/testHelpers')

contract(
  'Staking (Curation)',
  ([deploymentAddress, daoContract, curationStaker, ...accounts]) => {
    /**
     * testing constants & variables
     */
    const minimumCurationStakingAmount =
      helpers.stakingConstants.minimumCurationStakingAmount
    const minimumIndexingStakingAmount =
      helpers.stakingConstants.minimumIndexingStakingAmount
    const defaultReserveRatio = helpers.stakingConstants.defaultReserveRatio
    const maximumIndexers = helpers.stakingConstants.maximumIndexers
    const simpleThawingPeriod = helpers.stakingConstants.thawingPeriodSimple
    const initialTokenSupply = helpers.graphTokenConstants.initialTokenSupply
    const stakingAmount = helpers.graphTokenConstants.stakingAmount
    const shareAmountFor10000 = helpers.graphTokenConstants.shareAmountFor10000
    const tokensMintedForStaker =
      helpers.graphTokenConstants.tokensMintedForStaker
    let deployedStaking
    let deployedGraphToken
    const subgraphIdHex0x = helpers.randomSubgraphIdHex0x()
    const subgraphIdHex = helpers.randomSubgraphIdHex(subgraphIdHex0x)
    let gp

    beforeEach(async () => {
      // deploy GraphToken contract
      deployedGraphToken = await GraphToken.new(
        daoContract, // governor
        initialTokenSupply, // initial supply
        { from: deploymentAddress },
      )

      // send some tokens to the staking account
      const tokensForCurator = await deployedGraphToken.mint(
        curationStaker, // to
        tokensMintedForStaker, // value
        { from: daoContract },
      )
      assert(tokensForCurator, 'Mints Graph Tokens for Curator.')

      // deploy Staking contract
      deployedStaking = await Staking.new(
        daoContract, // <address> governor
        minimumCurationStakingAmount, // <uint256> minimumCurationStakingAmount
        defaultReserveRatio, // <uint256> defaultReserveRatio
        minimumIndexingStakingAmount, // <uint256> minimumIndexingStakingAmount
        maximumIndexers, // <uint256> maximumIndexers
        simpleThawingPeriod, // <uint256> thawingPeriod
        deployedGraphToken.address, // <address> token
        { from: deploymentAddress },
      )

      // init Graph Protocol JS library with deployed staking contract
      gp = GraphProtocol({
        Staking: deployedStaking,
        GraphToken: deployedGraphToken,
      })
    })

    it('...should allow signaling directly', async () => {
      let totalBalance = await deployedGraphToken.balanceOf(
        deployedStaking.address,
      )
      let curatorBalance = await deployedGraphToken.balanceOf(curationStaker)
      assert(
        curatorBalance.toString() === tokensMintedForStaker.toString() &&
          totalBalance.toString() === new BN(0).toString(),
        'Balances before transfer are incorrect.',
      )

      const data = '0x01' + subgraphIdHex
      const tx = await deployedGraphToken.transferToTokenReceiver(
        deployedStaking.address, // to
        stakingAmount, // value
        data, // data
        { from: curationStaker },
      )

      const subgraphShares = await gp.staking.curators(
        subgraphIdHex0x,
        curationStaker,
      )

      expectEvent.inTransaction(tx.tx, Staking, 'CuratorStaked', {
        staker: curationStaker,
        subgraphID: subgraphIdHex0x,
        curatorShares: subgraphShares,
        subgraphTotalCurationShares: subgraphShares,
        subgraphTotalCurationStake: stakingAmount,
      })

      totalBalance = await deployedGraphToken.balanceOf(deployedStaking.address)
      curatorBalance = await deployedGraphToken.balanceOf(curationStaker)
      assert(
        curatorBalance.toString() === shareAmountFor10000.toString() &&
          totalBalance.toString() === stakingAmount.toString(),
        'Balances after transfer is incorrect.',
      )
    })

    it('...should allow curation signaling and emit CuratorStaked', async () => {
      // We abstract this functionality into a function so we can use it in other tests
      await stakeForCuration()
    })

    it('...should allow Curator to partially logout and fully logout', async () => {
      const subgraphShares = await stakeForCuration()
      const halfSharesInt = Math.floor(subgraphShares / 2)

      await deployedStaking.curatorLogout(
        subgraphIdHex0x, // Subgraph ID the Curator is returning shares for
        halfSharesInt, // Amount of shares to return
        { from: curationStaker },
      )

      const halfShares = await gp.staking.curators(
        subgraphIdHex0x,
        curationStaker,
      )

      assert(
        halfShares.toNumber() === subgraphShares - halfSharesInt,
        'Shares were not reduced by half',
      )

      const fullLogout = await deployedStaking.curatorLogout(
        subgraphIdHex0x, // Subgraph ID the Curator is returning shares for
        subgraphShares - halfSharesInt, // Amount of shares to return
        { from: curationStaker },
      )

      expectEvent.inLogs(fullLogout.logs, 'CuratorLogout', {
        staker: curationStaker,
        subgraphID: subgraphIdHex0x,
        subgraphTotalCurationShares: new BN(0),
        subgraphTotalCurationStake: new BN(0),
      })
    })

    async function stakeForCuration() {
      let totalBalance = await deployedGraphToken.balanceOf(
        deployedStaking.address,
      )
      let curatorBalance = await deployedGraphToken.balanceOf(curationStaker)
      assert(
        curatorBalance.toString() === tokensMintedForStaker.toString() &&
          totalBalance.toNumber() === 0,
        'Balances before transfer are incorrect.',
      )

      const curationStake = await gp.staking.stakeForCuration(
        subgraphIdHex, // subgraphId
        curationStaker, // from
        stakingAmount, // value
      )

      const subgraphShares = await gp.staking.curators(
        subgraphIdHex0x,
        curationStaker,
      )

      totalBalance = await deployedGraphToken.balanceOf(deployedStaking.address)
      curatorBalance = await deployedGraphToken.balanceOf(curationStaker)
      assert(
        curatorBalance.toString() === shareAmountFor10000.toString() &&
          totalBalance.toString() === stakingAmount.toString(),
        'Balances after transfer is incorrect.',
      )

      expectEvent.inTransaction(curationStake.tx, Staking, 'CuratorStaked', {
        staker: curationStaker,
        subgraphID: subgraphIdHex0x,
        curatorShares: subgraphShares,
        subgraphTotalCurationShares: subgraphShares,
        subgraphTotalCurationStake: stakingAmount,
      })

      return subgraphShares.toNumber()
    }
  },
)
