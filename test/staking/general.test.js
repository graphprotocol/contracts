const { constants } = require('openzeppelin-test-helpers')
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
  /* scoped test variables */
  let deployedStaking,
    deployedGraphToken,
    gp

  before(async () => {
    // deploy GraphToken contract
    deployedGraphToken = await GraphToken.new(
      daoContract, // governor
      1000000, // initial supply
      { from: deploymentAddress }
    )
    assert.isObject(deployedGraphToken, "Deploy GraphToken contract.")

    // deploy Staking contract
    deployedStaking = await Staking.new(
      daoContract, // governor
      deployedGraphToken.address, // token
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

  describe('state variables set in construction', () => {
    it('...should set `governor` during construction', async function () {
      assert((await gp.staking.governor()) === daoContract, "Set `governor` in constructor.")
    })

    it('...should set `maximumIndexers` during construction', async function () {
      assert((await gp.staking.maximumIndexers()) > 0, "Set `maximumIndexers` in constructor.")
    })

    it('...should set `minimumCurationStakingAmount` during construction', async function () {
      assert((await gp.staking.minimumCurationStakingAmount()) > 0, "Set `minimumCurationStakingAmount` in constructor.")
    })

    it('...should set `minimumIndexingStakingAmount` during construction', async function () {
      assert((await gp.staking.minimumIndexingStakingAmount()) > 0, "Set `minimumIndexingStakingAmount` in constructor.")
    })

    it('...should set `token` during construction', async function () {
      /** @todo Find a better way to identify a valid `address` */
      assert((await gp.staking.token()).length === 42, "Set `token` in constructor.")
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
      assert(await gp.staking.arbitrator() === ZERO_ADDRESS, "No `arbitrator` is set.")
    })
  })

  describe('public functions', () => {
    it('...should return `issuedShares` from `stakeToShares`', async () => {
      (await gp.staking.stakeToShares(
        1000, // added stake
        1000 // total stake
      )).should.be.bignumber.equal('1')
    })
  })
})
