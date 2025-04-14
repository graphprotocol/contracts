import hre from 'hardhat'

import { ONE_MILLION, PaymentTypes } from '@graphprotocol/toolshed'
import { ethers } from 'hardhat'
import { expect } from 'chai'
import { indexers } from '../../../tasks/test/fixtures/indexers'
import { setGRTBalance } from '@graphprotocol/toolshed/hardhat'

import type { HardhatEthersSigner } from '@nomicfoundation/hardhat-ethers/signers'

describe('Service provider', () => {
  let verifier: string
  const thawingPeriod = 2419200n

  const graph = hre.graph()
  const { stake, stakeToProvision, addToProvision } = graph.horizon.actions
  const horizonStaking = graph.horizon.contracts.HorizonStaking
  const graphToken = graph.horizon.contracts.L2GraphToken

  before(async () => {
    verifier = await ethers.Wallet.createRandom().getAddress()
  })

  describe('New Protocol Users', () => {
    let serviceProvider: HardhatEthersSigner
    const stakeAmount = ethers.parseEther('1000')

    before(async () => {
      [serviceProvider] = await graph.accounts.getTestAccounts()
      await setGRTBalance(graph.provider, graphToken.target, serviceProvider.address, ONE_MILLION)
    })

    it('should allow staking tokens and unstake right after', async () => {
      const serviceProviderBalanceBefore = await graphToken.balanceOf(serviceProvider.address)
      await stake(serviceProvider, [stakeAmount])
      await horizonStaking.connect(serviceProvider).unstake(stakeAmount)
      const serviceProviderBalanceAfter = await graphToken.balanceOf(serviceProvider.address)
      expect(serviceProviderBalanceAfter).to.equal(serviceProviderBalanceBefore, 'Service provider balance should not change')
    })

    it('should revert if unstaking more than the idle stake', async () => {
      const idleStake = await horizonStaking.getIdleStake(serviceProvider.address)
      await expect(horizonStaking.connect(serviceProvider).unstake(idleStake + 1n))
        .to.be.revertedWithCustomError(horizonStaking, 'HorizonStakingInsufficientIdleStake')
        .withArgs(idleStake + 1n, idleStake)
    })

    it('should be able to set delegation fee cut for payment type', async () => {
      const delegationFeeCut = 10_000 // 10%
      const paymentType = PaymentTypes.QueryFee

      await horizonStaking.connect(serviceProvider).setDelegationFeeCut(
        serviceProvider.address,
        verifier,
        paymentType,
        delegationFeeCut,
      )

      // Verify delegation fee cut was set
      const delegationFeeCutAfterSet = await horizonStaking.getDelegationFeeCut(
        serviceProvider.address,
        verifier,
        paymentType,
      )
      expect(delegationFeeCutAfterSet).to.equal(delegationFeeCut, 'Delegation fee cut was not set')
    })

    it('should be able to set an operator for a verifier', async () => {
      const operator = await ethers.Wallet.createRandom().getAddress()
      await horizonStaking.connect(serviceProvider).setOperator(
        verifier,
        operator,
        true,
      )

      // Verify operator was set
      const isAuthorized = await horizonStaking.isAuthorized(
        serviceProvider.address,
        verifier,
        operator,
      )
      expect(isAuthorized).to.be.true
    })

    describe('Provision', () => {
      let maxVerifierCut: bigint

      before(async () => {
        const tokensToStake = ethers.parseEther('100000')
        maxVerifierCut = 50_000n // 50%
        const createProvisionTokens = ethers.parseEther('10000')

        // Add idle stake
        await stake(serviceProvider, [tokensToStake])
        await horizonStaking.connect(serviceProvider).provision(serviceProvider.address, verifier, createProvisionTokens, maxVerifierCut, thawingPeriod)
      })

      it('should be able to stake to provision directly', async () => {
        let provision = await horizonStaking.getProvision(serviceProvider.address, verifier)
        const provisionTokensBefore = provision.tokens

        // Add stake and provision on the same transaction
        const stakeToProvisionTokens = ethers.parseEther('100')
        await stakeToProvision(serviceProvider, [serviceProvider.address, verifier, stakeToProvisionTokens])

        // Verify provision tokens were updated
        provision = await horizonStaking.getProvision(serviceProvider.address, verifier)
        expect(provision.tokens).to.equal(provisionTokensBefore + stakeToProvisionTokens, 'Provision tokens were not updated')
      })

      it('should be able to add idle stake to provision', async () => {
        let provision = await horizonStaking.getProvision(serviceProvider.address, verifier)
        const provisionTokensBefore = provision.tokens

        // Add to provision using idle stake
        const addToProvisionTokens = ethers.parseEther('100')
        await addToProvision(serviceProvider, [serviceProvider.address, verifier, addToProvisionTokens])

        // Verify provision tokens were updated
        provision = await horizonStaking.getProvision(serviceProvider.address, verifier)
        expect(provision.tokens).to.equal(provisionTokensBefore + addToProvisionTokens, 'Provision tokens were not updated')
      })

      it('should revert if creating a provision with tokens greater than the idle stake', async () => {
        const newVerifier = await ethers.Wallet.createRandom().getAddress()
        const idleStake = await horizonStaking.getIdleStake(serviceProvider.address)
        await expect(horizonStaking.connect(serviceProvider).provision(
          serviceProvider.address, newVerifier, idleStake + 1n, maxVerifierCut, thawingPeriod))
          .to.be.revertedWithCustomError(horizonStaking, 'HorizonStakingInsufficientIdleStake')
          .withArgs(idleStake + 1n, idleStake)
      })

      it('should revert if adding to provision with tokens greater than the idle stake', async () => {
        const idleStake = await horizonStaking.getIdleStake(serviceProvider.address)
        await expect(horizonStaking.connect(serviceProvider).addToProvision(
          serviceProvider.address, verifier, idleStake + 1n))
          .to.be.revertedWithCustomError(horizonStaking, 'HorizonStakingInsufficientIdleStake')
          .withArgs(idleStake + 1n, idleStake)
      })

      describe('Thawing', () => {
        describe('Deprovisioning', () => {
          it('should be able to thaw tokens, wait for thawing period, deprovision and unstake', async () => {
            const serviceProviderBalanceBefore = await graphToken.balanceOf(serviceProvider.address)
            const tokensToThaw = ethers.parseEther('100')
            await horizonStaking.connect(serviceProvider).thaw(serviceProvider.address, verifier, tokensToThaw)

            // Wait for thawing period
            await ethers.provider.send('evm_increaseTime', [Number(thawingPeriod)])
            await ethers.provider.send('evm_mine', [])

            // Deprovision the single thaw request
            await horizonStaking.connect(serviceProvider).deprovision(serviceProvider.address, verifier, 1n)

            // Unstake
            await horizonStaking.connect(serviceProvider).unstake(tokensToThaw)

            // Verify service provider balance increased by the unstake tokens
            const serviceProviderBalanceAfter = await graphToken.balanceOf(serviceProvider.address)
            expect(serviceProviderBalanceAfter).to.equal(serviceProviderBalanceBefore + tokensToThaw, 'Service provider balance should increase by the thawed tokens')
          })

          it('should be able to create multiple thaw requests and deprovision all at once', async () => {
            const serviceProviderIdleStakeBefore = await horizonStaking.getIdleStake(serviceProvider.address)
            const tokensToThaw = ethers.parseEther('100')
            // Create 10 thaw requests for 100 GRT each
            for (let i = 0; i < 10; i++) {
              await horizonStaking.connect(serviceProvider).thaw(serviceProvider.address, verifier, tokensToThaw)
            }

            // Wait for thawing period
            await ethers.provider.send('evm_increaseTime', [Number(thawingPeriod)])
            await ethers.provider.send('evm_mine', [])

            // Deprovision all thaw requests
            await horizonStaking.connect(serviceProvider).deprovision(serviceProvider.address, verifier, 10n)

            // Verify service provider idle stake increased by the deprovisioned tokens
            const serviceProviderIdleStakeAfter = await horizonStaking.getIdleStake(serviceProvider.address)
            expect(serviceProviderIdleStakeAfter).to.equal(serviceProviderIdleStakeBefore + tokensToThaw * 10n, 'Service provider idle stake should increase by the deprovisioned tokens')
          })

          it('should be able to create multiple thaw requests and deprovision one by one', async () => {
            const serviceProviderIdleStakeBefore = await horizonStaking.getIdleStake(serviceProvider.address)
            const tokensToThaw = ethers.parseEther('100')
            // Create 3 thaw requests for 100 GRT each
            for (let i = 0; i < 3; i++) {
              await horizonStaking.connect(serviceProvider).thaw(serviceProvider.address, verifier, tokensToThaw)
            }

            // Wait for thawing period
            await ethers.provider.send('evm_increaseTime', [Number(thawingPeriod)])
            await ethers.provider.send('evm_mine', [])

            // Deprovision one by one
            for (let i = 0; i < 3; i++) {
              await horizonStaking.connect(serviceProvider).deprovision(serviceProvider.address, verifier, 1n)
            }

            // Verify service provider idle stake increased by the deprovisioned tokens
            const serviceProviderIdleStakeAfter = await horizonStaking.getIdleStake(serviceProvider.address)
            expect(serviceProviderIdleStakeAfter).to.equal(serviceProviderIdleStakeBefore + tokensToThaw * 3n, 'Service provider idle stake should increase by the deprovisioned tokens')
          })
        })

        describe('Reprovisioning', () => {
          let newVerifier: string

          before(async () => {
            newVerifier = await ethers.Wallet.createRandom().getAddress()
            await horizonStaking.connect(serviceProvider).provision(serviceProvider.address, newVerifier, ethers.parseEther('100'), maxVerifierCut, thawingPeriod)
          })

          it('should be able to thaw tokens, wait for thawing period and reprovision', async () => {
            const serviceProviderNewProvisionSizeBefore = (await horizonStaking.getProvision(serviceProvider.address, newVerifier)).tokens
            const serviceProviderOldProvisionSizeBefore = (await horizonStaking.getProvision(serviceProvider.address, verifier)).tokens
            const tokensToThaw = ethers.parseEther('100')

            // Thaw tokens
            await horizonStaking.connect(serviceProvider).thaw(serviceProvider.address, verifier, tokensToThaw)

            // Wait for thawing period
            await ethers.provider.send('evm_increaseTime', [Number(thawingPeriod)])
            await ethers.provider.send('evm_mine', [])

            // Reprovision
            await horizonStaking.connect(serviceProvider).reprovision(serviceProvider.address, verifier, newVerifier, 1n)

            // Verify new provision size increased by the reprovisioned tokens
            const serviceProviderNewProvisionSizeAfter = (await horizonStaking.getProvision(serviceProvider.address, newVerifier)).tokens
            expect(serviceProviderNewProvisionSizeAfter).to.equal(serviceProviderNewProvisionSizeBefore + tokensToThaw, 'New provision size should increase by the reprovisioned tokens')

            // Verify old provision size decreased by the reprovisioned tokens
            const serviceProviderOldProvisionSizeAfter = (await horizonStaking.getProvision(serviceProvider.address, verifier)).tokens
            expect(serviceProviderOldProvisionSizeAfter).to.equal(serviceProviderOldProvisionSizeBefore - tokensToThaw, 'Old provision size should decrease by the reprovisioned tokens')
          })

          it('should revert if thawing period is not over', async () => {
            const tokensToThaw = ethers.parseEther('100')
            await horizonStaking.connect(serviceProvider).thaw(serviceProvider.address, verifier, tokensToThaw)

            await expect(horizonStaking.connect(serviceProvider).reprovision(serviceProvider.address, verifier, newVerifier, 1n))
              .to.be.revertedWithCustomError(horizonStaking, 'HorizonStakingInvalidZeroTokens')
          })
        })
      })

      describe('Set parameters', () => {
        it('should be able to set provision parameters', async () => {
          const newMaxVerifierCut = 20_000 // 20%
          const newThawingPeriod = 1000

          // Set parameters
          await horizonStaking.connect(serviceProvider).setProvisionParameters(
            serviceProvider.address,
            verifier,
            newMaxVerifierCut,
            newThawingPeriod,
          )

          // Verify parameters were set as pending
          const provision = await horizonStaking.getProvision(serviceProvider.address, verifier)
          expect(provision.maxVerifierCutPending).to.equal(newMaxVerifierCut, 'Max verifier cut should be set')
          expect(provision.thawingPeriodPending).to.equal(newThawingPeriod, 'Thawing period should be set')
        })
      })
    })
  })

  describe('Existing Protocol Users', () => {
    let indexer: HardhatEthersSigner
    let tokensToUnstake: bigint
    let snapshotId: string

    before(async () => {
      // Get indexer
      const indexerFixture = indexers[0]
      indexer = await ethers.getSigner(indexerFixture.address)
      await setGRTBalance(graph.provider, graphToken.target, indexer.address, ONE_MILLION)
      // Set tokens
      tokensToUnstake = ethers.parseEther('10000')
    })

    beforeEach(async () => {
      // Take a snapshot before each test
      snapshotId = await ethers.provider.send('evm_snapshot', [])
    })

    afterEach(async () => {
      // Revert to the snapshot after each test
      await ethers.provider.send('evm_revert', [snapshotId])
    })

    it('should be able to unstake tokens without thawing', async () => {
      // Get balance before unstaking
      const balanceBefore = await graphToken.balanceOf(indexer.address)

      // Unstake tokens
      await horizonStaking.connect(indexer).unstake(tokensToUnstake)

      // Verify tokens are transferred back to service provider
      const balanceAfter = await graphToken.balanceOf(indexer.address)
      expect(balanceAfter).to.equal(balanceBefore + tokensToUnstake, 'Tokens were not transferred back to service provider')
    })

    it('should be able to withdraw locked tokens after thawing period', async () => {
      const oldThawingPeriod = 6646

      // Mine blocks to complete thawing period
      for (let i = 0; i < oldThawingPeriod + 1; i++) {
        await ethers.provider.send('evm_mine', [])
      }

      // Get balance before withdrawing
      const balanceBefore = await graphToken.balanceOf(indexer.address)

      // Withdraw tokens
      await horizonStaking.connect(indexer).withdraw()

      // Get balance after withdrawing
      const balanceAfter = await graphToken.balanceOf(indexer.address)
      expect(balanceAfter).to.equal(balanceBefore + tokensToUnstake, 'Tokens were not transferred back to service provider')
    })
  })
})
