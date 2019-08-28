const { expect } = require('chai')

// contracts
const GraphToken = artifacts.require('./GraphToken.sol')
const Staking = artifacts.require('./Staking.sol')

// helpers
const GraphProtocol = require('../../graphProtocol.js')
const helpers = require('../lib/testHelpers')

contract(
  'Staking (General)',
  ([
     deploymentAddress,
     daoContract,
     curationStaker,
     indexingStaker,
     subgraph1,
     ...accounts
   ]) => {
    /**
     * testing constants
     */
    const
      minimumCurationStakingAmount = helpers.stakingConstants.minimumCurationStakingAmount,
      minimumIndexingStakingAmount = helpers.stakingConstants.minimumIndexingStakingAmount,
      defaultReserveRatio = helpers.stakingConstants.defaultReserveRatio,
      maximumIndexers = helpers.stakingConstants.maximumIndexers,
      slashingPercent = helpers.stakingConstants.slashingPercent,
      simpleThawingPeriod = helpers.stakingConstants.thawingPeriodSimple,
      initialTokenSupply = helpers.graphTokenConstants.initialTokenSupply
    let
      deployedStaking,
      deployedGraphToken,
      gp

    before(async () => {
      // deploy GraphToken contract
      deployedGraphToken = await GraphToken.new(
        daoContract, // governor
        initialTokenSupply, // initial supply
        { from: deploymentAddress },
      )
      assert.isObject(deployedGraphToken, 'Deploy GraphToken contract.')

      // deploy Staking contract
      deployedStaking = await Staking.new(
        daoContract, // <address> governor
        minimumCurationStakingAmount, // <uint256> minimumCurationStakingAmount
        defaultReserveRatio, // <uint256> defaultReserveRatio
        minimumIndexingStakingAmount, // <uint256> minimumIndexingStakingAmount
        maximumIndexers, // <uint256> maximumIndexers
        slashingPercent, // <uint256> slashingPercent
        simpleThawingPeriod, // <uint256> thawingPeriod
        deployedGraphToken.address, // <address> token
        { from: deploymentAddress },
      )
      assert.isObject(deployedStaking, 'Deploy Staking contract.')
      assert(
        web3.utils.isAddress(deployedStaking.address),
        'Staking address is address.',
      )

      // init Graph Protocol JS library with deployed staking contract
      gp = GraphProtocol({
        Staking: deployedStaking,
        GraphToken: deployedGraphToken,
      })
      assert.isObject(gp, 'Initialize the Graph Protocol library.')
    })

    describe('state variables set in construction', () => {
      it('...should set `governor` during construction', async function () {
        assert(
          (await gp.staking.governor()) === daoContract,
          'Set `governor` in constructor.',
        )
      })

      it('...should set `maximumIndexers` during construction', async function () {
        assert(
          (await gp.staking.maximumIndexers()).toNumber() === maximumIndexers,
          'Set `maximumIndexers` in constructor.',
        )
      })

      it('...should set `minimumCurationStakingAmount` during construction', async function () {
        assert(
          (await gp.staking.minimumCurationStakingAmount()).toString() ===
          minimumCurationStakingAmount.toString(),
          'Set `minimumCurationStakingAmount` in constructor.',
        )
      })

      it('...should set `minimumIndexingStakingAmount` during construction', async function () {
        assert(
          (await gp.staking.minimumIndexingStakingAmount()).toString() ===
          minimumIndexingStakingAmount.toString(),
          'Set `minimumIndexingStakingAmount` in constructor.',
        )
      })

      it('...should set `token` during construction', async function () {
        assert(
          web3.utils.isAddress(await gp.staking.token()),
          'Set `token` in constructor.',
        )
      })
    })

    describe('public variables are readable', () => {
      it('...should return `curators`', async () => {
        const curators = await gp.staking.curators(
          curationStaker, // staker address
          subgraph1, // subgraphId
        )
        assert(curators.toString() === '0')
      })

      it('...should return `indexingNodes`', async () => {
        const indexingNodes = await gp.staking.indexingNodes(
          indexingStaker, // staker address
          subgraph1, // subgraphId
        )
        assert(indexingNodes.amountStaked.toString() === '0')
        assert(indexingNodes.logoutStarted.toString() === '0')
      })

      it('...should return `arbitrator` address', async () => {
        assert(
          (await gp.staking.arbitrator()) === daoContract,
          'Arbitrator set to governor.',
        )
      })
    })
  },
)
