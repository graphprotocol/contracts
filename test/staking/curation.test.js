const { expectEvent } = require('openzeppelin-test-helpers')

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
    const minimumCurationStakingAmount = 100,
      defaultReserveRatio = 500000,
      minimumIndexingStakingAmount = 100,
      maximumIndexers = 10,
      slashingPercent = 10,
      thawingPeriod = 60 * 60 * 24 * 7 // seconds
    let deployedStaking,
      deployedGraphToken,
      initialTokenSupply = 1000000,
      stakingAmount = 1000,
      tokensMintedForStaker = stakingAmount * 10,
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
      assert.isObject(deployedGraphToken, 'Deploy GraphToken contract.')

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
        slashingPercent, // <uint256> slashingPercent
        thawingPeriod, // <uint256> thawingPeriod
        deployedGraphToken.address, // <address> token
        { from: deploymentAddress },
      )
      assert.isObject(deployedStaking, 'Deploy Staking contract.')

      // init Graph Protocol JS library with deployed staking contract
      gp = GraphProtocol({
        Staking: deployedStaking,
        GraphToken: deployedGraphToken,
      })
      assert.isObject(gp, 'Initialize the Graph Protocol library.')
    })

    it('...should allow staking directly', async () => {
      let totalBalance = await deployedGraphToken.balanceOf(
        deployedStaking.address,
      )
      let curatorBalance = await deployedGraphToken.balanceOf(curationStaker)
      assert(
        curatorBalance.toNumber() === tokensMintedForStaker &&
          totalBalance.toNumber() === 0,
        'Balances before transfer are incorrect.',
      )

      const data = web3.utils.hexToBytes('0x01' + subgraphIdHex)
      const curationStake = await deployedGraphToken.transferWithData(
        deployedStaking.address, // to
        stakingAmount, // value
        data, // data
        { from: curationStaker },
      )
      assert(curationStake, 'Stake Graph Tokens for curation directly.')

      const { amountStaked, subgraphShares } = await gp.staking.curators(
        web3.utils.hexToBytes('0x' + subgraphIdHex),
        curationStaker,
      )
      assert(
        amountStaked.toNumber() === stakingAmount &&
          subgraphShares.toNumber() > 0,
        'Staked curation amount is not correect.',
      )

      totalBalance = await deployedGraphToken.balanceOf(deployedStaking.address)
      curatorBalance = await deployedGraphToken.balanceOf(curationStaker)
      assert(
        curatorBalance.toNumber() === tokensMintedForStaker - stakingAmount &&
          totalBalance.toNumber() === stakingAmount,
        'Balances after transfer is incorrect.',
      )
    })

    /* TODO need to introduce this back in, but because of dependency issues,
        this is being commented out until we merge two branches with
        updated open zepplin test helpers, which will change all the tests anyways */
    it('...should allow Curator to log out', async () => {
      // const subgraphShares = await stakeForCuration()
      //
      // /** @dev Log out Curator */
      // const logOut = await deployedStaking.curatorLogout(
      //   subgraphIdBytes, // Subgraph ID the Curator is returning shares for
      //   subgraphShares, // Amount of shares to return
      //   { from: curationStaker }
      // )
      // expectEvent.inLogs(logOut.logs, 'CuratorLogout',
      //   { staker: curationStaker }
      // )
    })

    async function stakeForCuration() {
      /** @dev Verify that balances are what we expect */
      let totalBalance = await deployedGraphToken.balanceOf(
        deployedStaking.address,
      )
      let curatorBalance = await deployedGraphToken.balanceOf(curationStaker)
      assert(
        curatorBalance.toNumber() === tokensMintedForStaker &&
          totalBalance.toNumber() === 0,
        'Balances before transfer are incorrect.',
      )

      /** @dev Stake some tokens for curation */
      const curationsStake = await gp.staking.stakeForCuration(
        subgraphIdHex, // subgraphId
        curationStaker, // from
        stakingAmount, // value
      )
      assert(curationsStake, 'Stake Graph Tokens for curation through module.')

      /** @dev Verify that balances are what we expect */
      const { amountStaked, subgraphShares } = await gp.staking.curators(
        subgraphIdBytes,
        curationStaker,
      )
      assert(
        amountStaked.toNumber() === stakingAmount &&
          subgraphShares.toNumber() > 0,
        'Staked curation amount is not confirmed.',
      )
      totalBalance = await deployedGraphToken.balanceOf(deployedStaking.address)
      curatorBalance = await deployedGraphToken.balanceOf(curationStaker)
      assert(
        curatorBalance.toNumber() === tokensMintedForStaker - stakingAmount &&
          totalBalance.toNumber() === stakingAmount,
        'Balances after transfer is incorrect.',
      )

      return subgraphShares.toNumber()
    }
  },
)
