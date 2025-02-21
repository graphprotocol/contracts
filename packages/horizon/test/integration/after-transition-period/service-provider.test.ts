import hre from 'hardhat'
import { ethers } from 'hardhat'
import { expect } from 'chai'
import { HorizonStaking, IGraphToken } from '../../../typechain-types'
import { SignerWithAddress } from '@nomicfoundation/hardhat-ethers/signers'

import {
  addToProvision,
  createProvision,
  deprovision,
  reprovision,
  stake,
  stakeToProvision,
  thaw,
  unstake,
} from '../shared/staking'
import { PaymentTypes } from '../utils/types'

describe('HorizonStaking Integration Tests', () => {
  let horizonStaking: HorizonStaking
  let graphToken: IGraphToken
  let verifier: string
  let serviceProvider: SignerWithAddress
  const thawingPeriod = 2419200

  before(async () => {
    const graph = hre.graph()

    horizonStaking = graph.horizon!.contracts.HorizonStaking
    graphToken = graph.horizon!.contracts.L2GraphToken as unknown as IGraphToken

    verifier = await ethers.Wallet.createRandom().getAddress();

    [serviceProvider] = await ethers.getSigners()
  })

  describe('Service provider', () => {
    const stakeAmount = ethers.parseEther('1000')

    it('should allow staking tokens and unstake right after', async () => {
      const serviceProviderBalanceBefore = await graphToken.balanceOf(serviceProvider.address)
      await stake({ horizonStaking, graphToken, serviceProvider, tokens: stakeAmount })
      await unstake({ horizonStaking, serviceProvider, tokens: stakeAmount })
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

      const tx = await horizonStaking.connect(serviceProvider).setDelegationFeeCut(
        serviceProvider.address,
        verifier,
        paymentType,
        delegationFeeCut,
      )
      await tx.wait()

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
      let maxVerifierCut: number

      before(async () => {
        const tokensToStake = ethers.parseEther('100000')
        maxVerifierCut = 50_000 // 50%
        const createProvisionTokens = ethers.parseEther('10000')

        // Add idle stake
        await stake({ horizonStaking, graphToken, serviceProvider, tokens: tokensToStake })

        // Create provision
        await createProvision({
          horizonStaking,
          serviceProvider,
          verifier,
          tokens: createProvisionTokens,
          maxVerifierCut,
          thawingPeriod,
        })
      })

      it('should be able to stake to provision directly', async () => {
        let provision = await horizonStaking.getProvision(serviceProvider.address, verifier)
        const provisionTokensBefore = provision.tokens

        // Add stake and provision on the same transaction
        const stakeToProvisionTokens = ethers.parseEther('100')
        await stakeToProvision({
          horizonStaking,
          graphToken,
          serviceProvider,
          verifier,
          tokens: stakeToProvisionTokens,
        })

        // Verify provision tokens were updated
        provision = await horizonStaking.getProvision(serviceProvider.address, verifier)
        expect(provision.tokens).to.equal(provisionTokensBefore + stakeToProvisionTokens, 'Provision tokens were not updated')
      })

      it('should be able to add idle stake to provision', async () => {
        let provision = await horizonStaking.getProvision(serviceProvider.address, verifier)
        const provisionTokensBefore = provision.tokens

        // Add to provision using idle stake
        const addToProvisionTokens = ethers.parseEther('100')
        await addToProvision({ horizonStaking, serviceProvider, verifier, tokens: addToProvisionTokens })

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
            await thaw({ horizonStaking, serviceProvider, verifier, tokens: tokensToThaw })

            // Wait for thawing period
            await ethers.provider.send('evm_increaseTime', [thawingPeriod])
            await ethers.provider.send('evm_mine', [])

            // Deprovision the single thaw request
            await deprovision({ horizonStaking, serviceProvider, verifier, nThawRequests: 1n })

            // Unstake
            await unstake({ horizonStaking, serviceProvider, tokens: tokensToThaw })

            // Verify service provider balance increased by the unstake tokens
            const serviceProviderBalanceAfter = await graphToken.balanceOf(serviceProvider.address)
            expect(serviceProviderBalanceAfter).to.equal(serviceProviderBalanceBefore + tokensToThaw, 'Service provider balance should increase by the thawed tokens')
          })

          it('should be able to create multiple thaw requests and deprovision all at once', async () => {
            const serviceProviderIdleStakeBefore = await horizonStaking.getIdleStake(serviceProvider.address)
            const tokensToThaw = ethers.parseEther('100')
            // Create 10 thaw requests for 100 GRT each
            for (let i = 0; i < 10; i++) {
              await thaw({ horizonStaking, serviceProvider, verifier, tokens: tokensToThaw })
            }

            // Wait for thawing period
            await ethers.provider.send('evm_increaseTime', [thawingPeriod])
            await ethers.provider.send('evm_mine', [])

            // Deprovision all thaw requests
            await deprovision({ horizonStaking, serviceProvider, verifier, nThawRequests: 10n })

            // Verify service provider idle stake increased by the deprovisioned tokens
            const serviceProviderIdleStakeAfter = await horizonStaking.getIdleStake(serviceProvider.address)
            expect(serviceProviderIdleStakeAfter).to.equal(serviceProviderIdleStakeBefore + tokensToThaw * 10n, 'Service provider idle stake should increase by the deprovisioned tokens')
          })

          it('should be able to create multiple thaw requests and deprovision one by one', async () => {
            const serviceProviderIdleStakeBefore = await horizonStaking.getIdleStake(serviceProvider.address)
            const tokensToThaw = ethers.parseEther('100')
            // Create 3 thaw requests for 100 GRT each
            for (let i = 0; i < 3; i++) {
              await thaw({ horizonStaking, serviceProvider, verifier, tokens: tokensToThaw })
            }

            // Wait for thawing period
            await ethers.provider.send('evm_increaseTime', [thawingPeriod])
            await ethers.provider.send('evm_mine', [])

            // Deprovision one by one
            for (let i = 0; i < 3; i++) {
              await deprovision({ horizonStaking, serviceProvider, verifier, nThawRequests: 1n })
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
            await createProvision({
              horizonStaking,
              serviceProvider,
              verifier: newVerifier,
              tokens: ethers.parseEther('100'),
              maxVerifierCut,
              thawingPeriod,
            })
          })

          it('should be able to thaw tokens, wait for thawing period and reprovision', async () => {
            const serviceProviderNewProvisionSizeBefore = (await horizonStaking.getProvision(serviceProvider.address, newVerifier)).tokens
            const serviceProviderOldProvisionSizeBefore = (await horizonStaking.getProvision(serviceProvider.address, verifier)).tokens
            const tokensToThaw = ethers.parseEther('100')

            // Thaw tokens
            await thaw({ horizonStaking, serviceProvider, verifier, tokens: tokensToThaw })

            // Wait for thawing period
            await ethers.provider.send('evm_increaseTime', [thawingPeriod])
            await ethers.provider.send('evm_mine', [])

            // Reprovision
            await reprovision({
              horizonStaking,
              serviceProvider,
              verifier,
              newVerifier,
              nThawRequests: 1n,
            })

            // Verify new provision size increased by the reprovisioned tokens
            const serviceProviderNewProvisionSizeAfter = (await horizonStaking.getProvision(serviceProvider.address, newVerifier)).tokens
            expect(serviceProviderNewProvisionSizeAfter).to.equal(serviceProviderNewProvisionSizeBefore + tokensToThaw, 'New provision size should increase by the reprovisioned tokens')

            // Verify old provision size decreased by the reprovisioned tokens
            const serviceProviderOldProvisionSizeAfter = (await horizonStaking.getProvision(serviceProvider.address, verifier)).tokens
            expect(serviceProviderOldProvisionSizeAfter).to.equal(serviceProviderOldProvisionSizeBefore - tokensToThaw, 'Old provision size should decrease by the reprovisioned tokens')
          })

          it('should revert if thawing period is not over', async () => {
            const tokensToThaw = ethers.parseEther('100')
            await thaw({ horizonStaking, serviceProvider, verifier, tokens: tokensToThaw })

            await expect(reprovision({
              horizonStaking,
              serviceProvider,
              verifier,
              newVerifier,
              nThawRequests: 1n,
            })).to.be.revertedWithCustomError(horizonStaking, 'HorizonStakingInvalidZeroTokens')
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
})
