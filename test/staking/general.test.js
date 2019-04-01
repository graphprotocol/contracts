const { constants, shouldFail } = require('openzeppelin-test-helpers')
const { ZERO_ADDRESS } = constants

// contracts
const GraphToken = artifacts.require("./GraphToken.sol")
const Staking = artifacts.require("./Staking.sol")

// helpers
const GraphProtocol = require('../../graphProtocol.js')

contract('Staking (General)', ([
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
  const initialSupply = 1000000,
    minimumCurationStakingAmount = 100,
    defaultReserveRatio = 10,
    minimumIndexingStakingAmount = 100,
    maximumIndexers = 10,
    slashingPercent = 10,
    thawingPeriod = 7,
    stakingAmount = 100
  let deployedStaking,
    deployedGraphToken,
    gp

  before(async () => {
    // deploy GraphToken contract
    deployedGraphToken = await GraphToken.new(
      daoContract, // governor
      initialSupply, // initial supply
      { from: deploymentAddress }
    )
    assert.isObject(deployedGraphToken, "Deploy GraphToken contract.")

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
    assert(web3.utils.isAddress(deployedStaking.address), "Staking address is address.")

    // init Graph Protocol JS library with deployed staking contract
    gp = GraphProtocol({
      Staking: deployedStaking,
      GraphToken: deployedGraphToken
    })
    assert.isObject(gp, "Initialize the Graph Protocol library.")
  })

  describe('state variables set in construction', () => {
    it('...should set `governor` during construction', async function () {
      assert((await gp.staking.governor()) === daoContract, "Set `governor` in constructor.")
    })

    it('...should set `maximumIndexers` during construction', async function () {
      assert((await gp.staking.maximumIndexers()).toNumber() === maximumIndexers, "Set `maximumIndexers` in constructor.")
    })

    it('...should set `minimumCurationStakingAmount` during construction', async function () {
      assert((await gp.staking.minimumCurationStakingAmount()).toNumber() === minimumCurationStakingAmount, "Set `minimumCurationStakingAmount` in constructor.")
    })

    it('...should set `minimumIndexingStakingAmount` during construction', async function () {
      assert((await gp.staking.minimumIndexingStakingAmount()).toNumber() === minimumIndexingStakingAmount, "Set `minimumIndexingStakingAmount` in constructor.")
    })

    it('...should set `token` during construction', async function () {
      assert(web3.utils.isAddress(await gp.staking.token()), "Set `token` in constructor.")
    })
  })

  describe('public variables are readable', () => {
    it('...should return `curators`', async () => {
      const curators = await gp.staking.curators(
        curationStaker, // staker address
        subgraph1 // subgraphId
      )
      curators.amountStaked.should.be.bignumber.equal('0')
      curators.subgraphShares.should.be.bignumber.equal('0')
    })

    it('...should return `indexingNodes`', async () => {
      const indexingNodes = await gp.staking.indexingNodes(
        indexingStaker, // staker address
        subgraph1 // subgraphId
      )
      indexingNodes.amountStaked.should.be.bignumber.equal('0')
      indexingNodes.logoutStarted.should.be.bignumber.equal('0')
    })

    it('...should return `arbitrator` address', async () => {
      assert(await gp.staking.arbitrator() === daoContract, "Arbitrator is set to governor.")
    })
  })

  describe('public functions', () => {
    describe('stakeToShares', () => {
      it('...should return `issuedShares` from `stakeToShares`', async () => {
        let stakeToAdd = 1
        let totalStake = 0
        const iterations = 9

        for (let i = 0; i < iterations; i++) {
          stakeToAdd = stakeToAdd * 2
          totalStake += stakeToAdd
          await testBondingCurve(stakeToAdd, totalStake, stakeToAdd)
        }
        
        async function testBondingCurve(addedStake, totalStake, expected) {
          const shares = await gp.staking.stakeToShares(
            addedStake, // purchaseTokens,
            totalStake, // currentTokens,
            0, // currentShares,
            expected, // reserveRatio
          )
          shares.should.be.bignumber.equal(String(expected))
        }
      })  
    })
  })
})
