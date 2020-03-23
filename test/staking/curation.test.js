const { expect } = require('chai')
const {
  constants,
  expectRevert,
  expectEvent,
} = require('@openzeppelin/test-helpers')
const BN = web3.utils.BN

// helpers
const deployment = require('../lib/deployment')
const helpers = require('../lib/testHelpers')
const { defaults } = require('../lib/testHelpers')

const MAX_PPM = 1000000

contract(
  'Staking (Curation)',
  ([me, other, governor, curator, distributor]) => {
    beforeEach(async function() {
      // Deploy graph token
      this.graphToken = await deployment.deployGraphToken(governor, {
        from: me,
      })

      // Deploy curation contract
      this.curation = await deployment.deployCurationContract(
        governor,
        this.graphToken.address,
        distributor,
        { from: me },
      )
    })

    describe('state variables functions', function() {
      it('should set `governor`', async function() {
        // Set right in the constructor
        expect(await this.curation.governor()).to.equal(governor)

        // Can set if allowed
        await this.curation.transferGovernance(other, { from: governor })
        expect(await this.curation.governor()).to.equal(other)
      })

      it('should set `graphToken`', async function() {
        // Set right in the constructor
        expect(await this.curation.token()).to.equal(this.graphToken.address)
      })

      it('should set `distributor`', async function() {
        // Set right in the constructor
        expect(await this.curation.distributor()).to.equal(distributor)

        // Can set if allowed
        await this.curation.setDistributor(other, { from: governor })
        expect(await this.curation.distributor()).to.equal(other)
      })

      it('reject set `distributor` if empty address', async function() {
        await expectRevert(
          this.curation.setDistributor(constants.ZERO_ADDRESS, {
            from: governor,
          }),
          'Distributor must be set',
        )
      })

      it('reject set `distributor` if not allowed', async function() {
        await expectRevert(
          this.curation.setDistributor(distributor, { from: other }),
          'Only Governor can call',
        )
      })

      it('reject set `setDefaultReserveRatio` if out of bounds', async function() {
        await expectRevert(
          this.curation.setDefaultReserveRatio(0, { from: governor }),
          'Default reserve ratio must be > 0',
        )
        await expectRevert(
          this.curation.setDefaultReserveRatio(MAX_PPM + 1, {
            from: governor,
          }),
          'Default reserve ratio cannot be higher than MAX_PPM',
        )
      })

      it('reject set `setDefaultReserveRatio` if not allowed', async function() {
        await expectRevert(
          this.curation.setDefaultReserveRatio(defaults.curation.reserveRatio, {
            from: other,
          }),
          'Only Governor can call',
        )
      })
    })

    it('should allow staking on a subgraph', async function() {
      // Give some funds to the curator
      const curatorTokens = web3.utils.toWei(new BN('1000'))
      await this.graphToken.mint(curator, curatorTokens, {
        from: governor,
      })

      // Before balances
      const totalBalanceBefore = await this.graphToken.balanceOf(
        this.curation.address,
      )
      const curatorBalanceBefore = await this.graphToken.balanceOf(curator)

      // Curate a subgraph
      const subgraphId = helpers.randomSubgraphIdHex0x()
      const curatorStake = defaults.curation.minimumCurationStake
      const { tx } = await this.graphToken.transferToTokenReceiver(
        this.curation.address,
        curatorStake,
        subgraphId,
        { from: curator },
      )

      // After balances
      const totalBalanceAfter = await this.graphToken.balanceOf(
        this.curation.address,
      )
      const curatorBalanceAfter = await this.graphToken.balanceOf(curator)

      // Tokens transferred properly
      expect(totalBalanceAfter).to.be.bignumber.equal(
        totalBalanceBefore.add(curatorStake),
      )
      expect(curatorBalanceAfter).to.be.bignumber.equal(
        curatorBalanceBefore.sub(curatorStake),
      )

      // State properly updated
      const subgraph = await this.curation.subgraphs(subgraphId)
      expect(subgraph.reserveRatio).to.be.bignumber.equal(
        defaults.curation.reserveRatio,
      )
      expect(subgraph.totalStake).to.be.bignumber.equal(curatorStake)
      expect(subgraph.totalShares).to.be.bignumber.equal(web3.utils.toBN(1))

      const subgraphCurator = await this.curation.subgraphCurators(
        subgraphId,
        curator,
      )
      expect(subgraphCurator).to.be.bignumber.equal(web3.utils.toBN(1))

      // Event emitted
      expectEvent.inTransaction(
        tx,
        this.curation.constructor,
        'CuratorStakeUpdated',
        {
          curator: curator,
          subgraphID: subgraphId,
          totalShares: '1',
        },
      )

      expectEvent.inTransaction(
        tx,
        this.curation.constructor,
        'SubgraphStakeUpdated',
        {
          subgraphID: subgraphId,
          totalShares: '1',
          totalStake: curatorStake,
        },
      )
    })

    // it('...should allow Curator to partially logout and fully logout', async () => {
    //   const subgraphShares = await stakeForCuration()
    //   const halfSharesInt = Math.floor(subgraphShares / 2)

    //   await deployedStaking.curatorLogout(
    //     subgraphIdHex0x, // Subgraph ID the Curator is returning shares for
    //     halfSharesInt, // Amount of shares to return
    //     { from: curationStaker },
    //   )

    //   const halfShares = await gp.staking.curators(
    //     subgraphIdHex0x,
    //     curationStaker,
    //   )

    //   assert(
    //     halfShares.toNumber() === subgraphShares - halfSharesInt,
    //     'Shares were not reduced by half',
    //   )

    //   const fullLogout = await deployedStaking.curatorLogout(
    //     subgraphIdHex0x, // Subgraph ID the Curator is returning shares for
    //     subgraphShares - halfSharesInt, // Amount of shares to return
    //     { from: curationStaker },
    //   )

    //   expectEvent.inLogs(fullLogout.logs, 'CuratorLogout', {
    //     staker: curationStaker,
    //     subgraphID: subgraphIdHex0x,
    //     subgraphTotalCurationShares: new BN(0),
    //     subgraphTotalCurationStake: new BN(0),
    //   })
    // })

    // async function stakeForCuration() {
    //   let totalBalance = await deployedGraphToken.balanceOf(
    //     deployedStaking.address,
    //   )
    //   let curatorBalance = await deployedGraphToken.balanceOf(curationStaker)
    //   assert(
    //     curatorBalance.toString() === tokensMintedForStaker.toString() &&
    //       totalBalance.toNumber() === 0,
    //     'Balances before transfer are incorrect.',
    //   )

    //   const curationStake = await gp.staking.stakeForCuration(
    //     subgraphIdHex, // subgraphId
    //     curationStaker, // from
    //     stakingAmount, // value
    //   )

    //   const subgraphShares = await gp.staking.curators(
    //     subgraphIdHex0x,
    //     curationStaker,
    //   )

    //   totalBalance = await deployedGraphToken.balanceOf(deployedStaking.address)
    //   curatorBalance = await deployedGraphToken.balanceOf(curationStaker)
    //   assert(
    //     curatorBalance.toString() === shareAmountFor10000.toString() &&
    //       totalBalance.toString() === stakingAmount.toString(),
    //     'Balances after transfer is incorrect.',
    //   )

    //   expectEvent.inTransaction(curationStake.tx, Staking, 'CuratorStaked', {
    //     staker: curationStaker,
    //     subgraphID: subgraphIdHex0x,
    //     curatorShares: subgraphShares,
    //     subgraphTotalCurationShares: subgraphShares,
    //     subgraphTotalCurationStake: stakingAmount,
    //   })

    //   return subgraphShares.toNumber()
    // }
  },
)
