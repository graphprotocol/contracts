const BN = web3.utils.BN

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
    daoContract, // Note - this is not an actual multisig, it is just account[1]
    curationStaker,
    indexingStaker,
    subgraph1,
    ...accounts
  ]) => {
    /**
     * testing constants
     */
    const minimumCurationStakingAmount =
      helpers.stakingConstants.minimumCurationStakingAmount
    const minimumIndexingStakingAmount =
      helpers.stakingConstants.minimumIndexingStakingAmount
    const defaultReserveRatio = helpers.stakingConstants.defaultReserveRatio
    const maximumIndexers = helpers.stakingConstants.maximumIndexers
    const simpleThawingPeriod = helpers.stakingConstants.thawingPeriodSimple
    const initialTokenSupply = helpers.graphTokenConstants.initialTokenSupply
    let deployedStaking
    let deployedGraphToken
    let gp

    before(async () => {
      // deploy GraphToken contract
      deployedGraphToken = await GraphToken.new(
        daoContract, // governor
        initialTokenSupply, // initial supply
        { from: deploymentAddress },
      )

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
      assert(
        web3.utils.isAddress(deployedStaking.address),
        'Staking address is address.',
      )

      // init Graph Protocol JS library with deployed staking contract
      gp = GraphProtocol({
        Staking: deployedStaking,
        GraphToken: deployedGraphToken,
      })
    })

    describe('state variables set in construction', () => {
      it('...should set `minimumCurationStakingAmount` to a new value', async function() {
        const newMin = new BN('200000000000000000000')
        await deployedStaking.setMinimumCurationStakingAmount(newMin, {
          from: daoContract,
        })
        assert(
          (await gp.staking.minimumCurationStakingAmount()).toString() ===
            newMin.toString(),
          'Set `minimumCurationStakingAmount` does not work.',
        )
      })

      it('...should set `updateDefaultReserveRatio` to a new value', async function() {
        const newDRR = 100000
        await deployedStaking.updateDefaultReserveRatio(newDRR, {
          from: daoContract,
        })
        assert(
          (await gp.staking.defaultReserveRatio()).toNumber() === newDRR,
          'Set `defaultReserveRatio` does not work.',
        )
      })

      it('...should set `minimumIndexingStakingAmount` during construction', async function() {
        const newMin = new BN('200000000000000000000')
        await deployedStaking.setMinimumIndexingStakingAmount(newMin, {
          from: daoContract,
        })
        assert(
          (await gp.staking.minimumIndexingStakingAmount()).toString() ===
            newMin.toString(),
          'Set `minimumIndexingStakingAmount` does not work.',
        )
      })

      it('...should set `maximumIndexers` to a new value', async function() {
        const newMaxIndexers = 20
        await deployedStaking.setMaximumIndexers(newMaxIndexers, {
          from: daoContract,
        })
        assert(
          (await gp.staking.maximumIndexers()).toNumber() === newMaxIndexers,
          'Set `maximumIndexers` does not work.',
        )
      })

      it('...should set `thawingPeriod` to a new value', async function() {
        const thawingPeriod = 60 * 60 * 24 * 7 * 3 // 3 weeks
        await deployedStaking.updateThawingPeriod(thawingPeriod, {
          from: daoContract,
        })
        assert(
          (await gp.staking.thawingPeriod()).toNumber() === thawingPeriod,
          'Set `thawingPeriod` does not work.',
        )
      })

      it('...should set `token` during construction', async function() {
        assert(
          web3.utils.isAddress(await gp.staking.token()),
          'Set `token` in constructor.',
        )
      })

      it('...should set `governor` during construction', async function() {
        // No need to test transferGovernance(), it is tested in governance.test.js
        assert(
          (await gp.staking.governor()) === daoContract,
          'Set `governor` in constructor.',
        )
      })
    })
  },
)
