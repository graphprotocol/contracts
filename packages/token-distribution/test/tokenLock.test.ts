import 'hardhat-deploy'
import { BigNumber, constants } from 'ethers'
import { deployments } from 'hardhat'
import { expect } from 'chai'

import { GraphTokenLockSimple } from '../build/typechain/contracts/GraphTokenLockSimple'
import { GraphTokenMock } from '../build/typechain/contracts/GraphTokenMock'

import { Account, advanceTimeAndBlock, getAccounts, getContract, toBN, toGRT } from './network'
import { createScheduleScenarios, defaultInitArgs, Revocability, TokenLockParameters } from './config'
import { DeployOptions } from 'hardhat-deploy/types'

const { AddressZero } = constants

// Fixture
const setupTest = deployments.createFixture(async ({ deployments }) => {
  const deploy = (name: string, options: DeployOptions) => deployments.deploy(name, options)
  const [deployer] = await getAccounts()

  // Start from a fresh snapshot
  await deployments.fixture([])

  // Deploy token
  await deploy('GraphTokenMock', {
    from: deployer.address,
    args: [toGRT('1000000000'), deployer.address],
  })
  const grt = await getContract('GraphTokenMock')

  // Deploy token lock
  await deploy('GraphTokenLockSimple', {
    from: deployer.address,
    args: [],
  })
  const tokenLock = await getContract('GraphTokenLockSimple')

  return {
    grt: grt as GraphTokenMock,
    tokenLock: tokenLock as GraphTokenLockSimple,
  }
})

// -- Time utils --

const advancePeriods = async (tokenLock: GraphTokenLockSimple, n = 1) => {
  const periodDuration = await tokenLock.periodDuration()
  return advanceTimeAndBlock(periodDuration.mul(n).toNumber()) // advance N period
}

const moveToTime = async (tokenLock: GraphTokenLockSimple, target: BigNumber, buffer: number) => {
  const ts = await tokenLock.currentTime()
  const delta = target.sub(ts).add(buffer)
  return advanceTimeAndBlock(delta.toNumber())
}

const advanceToStart = async (tokenLock: GraphTokenLockSimple) => moveToTime(tokenLock, await tokenLock.startTime(), 60)
const advanceToEnd = async (tokenLock: GraphTokenLockSimple) => moveToTime(tokenLock, await tokenLock.endTime(), 60)
const advanceToAboutStart = async (tokenLock: GraphTokenLockSimple) =>
  moveToTime(tokenLock, await tokenLock.startTime(), -60)
const advanceToReleasable = async (tokenLock: GraphTokenLockSimple) => {
  const values = await Promise.all([
    tokenLock.vestingCliffTime(),
    tokenLock.releaseStartTime(),
    tokenLock.startTime(),
  ]).then(values => values.map(e => e.toNumber()))
  const time = Math.max(...values)
  await moveToTime(tokenLock, BigNumber.from(time), 60)
}

const forEachPeriod = async (tokenLock: GraphTokenLockSimple, fn) => {
  const periods = (await tokenLock.periods()).toNumber()
  for (let currentPeriod = 1; currentPeriod <= periods + 1; currentPeriod++) {
    const currentPeriod = await tokenLock.currentPeriod()
    // console.log('\t  ✓ period ->', currentPeriod.toString())
    await fn(currentPeriod.sub(1), currentPeriod)
    await advancePeriods(tokenLock, 1)
  }
}

const shouldMatchSchedule = async (tokenLock: GraphTokenLockSimple, fnName: string, initArgs: TokenLockParameters) => {
  await forEachPeriod(tokenLock, async function (passedPeriods: BigNumber) {
    const amount = (await tokenLock.functions[fnName]())[0]
    const amountPerPeriod = await tokenLock.amountPerPeriod()
    const managedAmount = await tokenLock.managedAmount()

    // console.log(`\t    - amount: ${formatGRT(amount)}/${formatGRT(managedAmount)}`)

    // After last period we expect to have all managed tokens available
    const expectedAmount = passedPeriods.lt(initArgs.periods) ? passedPeriods.mul(amountPerPeriod) : managedAmount
    expect(amount).eq(expectedAmount)
  })
}

// -- Tests --

describe('GraphTokenLockSimple', () => {
  let deployer: Account
  let beneficiary1: Account
  let beneficiary2: Account

  let grt: GraphTokenMock
  let tokenLock: GraphTokenLockSimple

  let initArgs: TokenLockParameters

  const initWithArgs = (args: TokenLockParameters) => {
    return tokenLock
      .connect(deployer.signer)
      .initialize(
        args.owner,
        args.beneficiary,
        args.token,
        args.managedAmount,
        args.startTime,
        args.endTime,
        args.periods,
        args.releaseStartTime,
        args.vestingCliffTime,
        args.revocable,
      )
  }

  const fundContract = async (contract: GraphTokenLockSimple) => {
    const managedAmount = await contract.managedAmount()
    await grt.connect(deployer.signer).transfer(contract.address, managedAmount)
  }

  before(async function () {
    [deployer, beneficiary1, beneficiary2] = await getAccounts()
  })

  describe('Init', function () {
    it('Reject initialize with non-set revocability option', async function () {
      ({ grt, tokenLock } = await setupTest())

      const args = defaultInitArgs(deployer, beneficiary1, grt, toGRT('1000'))
      const tx = tokenLock
        .connect(deployer.signer)
        .initialize(
          args.owner,
          args.beneficiary,
          args.token,
          args.managedAmount,
          args.startTime,
          args.endTime,
          args.periods,
          0,
          0,
          Revocability.NotSet,
        )
      await expect(tx).revertedWith('Must set a revocability option')
    })
  })

  createScheduleScenarios().forEach(function (schedule) {
    describe('> Test scenario', function () {
      beforeEach(async function () {
        ({ grt, tokenLock } = await setupTest())

        const staticArgs = {
          owner: deployer.address,
          beneficiary: beneficiary1.address,
          token: grt.address,
          managedAmount: toGRT('35000000'),
        }
        initArgs = { ...staticArgs, ...schedule }
        await initWithArgs(initArgs)

        // Move time to just before the contract starts
        await advanceToAboutStart(tokenLock)
      })

      describe('Init', function () {
        it('reject re-initialization', async function () {
          const tx = initWithArgs(initArgs)
          await expect(tx).revertedWith('Already initialized')
        })

        it('should be each parameter initialized properly', async function () {
          console.log('\t>> Scenario ', JSON.stringify(schedule))

          expect(await tokenLock.beneficiary()).eq(initArgs.beneficiary)
          expect(await tokenLock.managedAmount()).eq(initArgs.managedAmount)
          expect(await tokenLock.startTime()).eq(initArgs.startTime)
          expect(await tokenLock.endTime()).eq(initArgs.endTime)
          expect(await tokenLock.periods()).eq(initArgs.periods)
          expect(await tokenLock.token()).eq(initArgs.token)
          expect(await tokenLock.releaseStartTime()).eq(initArgs.releaseStartTime)
          expect(await tokenLock.vestingCliffTime()).eq(initArgs.vestingCliffTime)
          expect(await tokenLock.revocable()).eq(initArgs.revocable)
        })
      })

      describe('Balance', function () {
        describe('currentBalance()', function () {
          it('should match to deposited balance', async function () {
            // Before
            expect(await tokenLock.currentBalance()).eq(0)

            // Transfer
            const totalAmount = toGRT('100')
            await grt.connect(deployer.signer).transfer(tokenLock.address, totalAmount)

            // After
            expect(await tokenLock.currentBalance()).eq(totalAmount)
          })
        })
      })

      describe('Time & periods', function () {
        // describe('currentTime()', function () {
        //   it('should return current block time', async function () {
        //     expect(await tokenLock.currentTime()).eq(await latestBlockTime())
        //   })
        // })

        describe('duration()', function () {
          it('should match init parameters', async function () {
            const duration = initArgs.endTime - initArgs.startTime
            expect(await tokenLock.duration()).eq(toBN(duration))
          })
        })

        describe('sinceStartTime()', function () {
          it('should be zero if currentTime < startTime', async function () {
            const now = +new Date() / 1000
            if (now < initArgs.startTime) {
              expect(await tokenLock.sinceStartTime()).eq(0)
            }
          })

          it('should be right amount of time elapsed', async function () {
            await advanceTimeAndBlock(initArgs.startTime + 60)

            const elapsedTime = (await tokenLock.currentTime()).sub(initArgs.startTime)
            expect(await tokenLock.sinceStartTime()).eq(elapsedTime)
          })
        })

        describe('amountPerPeriod()', function () {
          it('should match init parameters', async function () {
            const amountPerPeriod = initArgs.managedAmount.div(initArgs.periods)
            expect(await tokenLock.amountPerPeriod()).eq(amountPerPeriod)
          })
        })

        describe('periodDuration()', function () {
          it('should match init parameters', async function () {
            const periodDuration = toBN(initArgs.endTime - initArgs.startTime).div(initArgs.periods)
            expect(await tokenLock.periodDuration()).eq(periodDuration)
          })
        })

        describe('currentPeriod()', function () {
          it('should be one (1) before start time', async function () {
            expect(await tokenLock.currentPeriod()).eq(1)
          })

          it('should return correct amount for each period', async function () {
            await advanceToStart(tokenLock)

            for (let currentPeriod = 1; currentPeriod <= initArgs.periods; currentPeriod++) {
              expect(await tokenLock.currentPeriod()).eq(currentPeriod)
              // console.log('\t  ✓ period ->', currentPeriod)
              await advancePeriods(tokenLock, 1)
            }
          })
        })

        describe('passedPeriods()', function () {
          it('should return correct amount for each period', async function () {
            await advanceToStart(tokenLock)

            for (let currentPeriod = 1; currentPeriod <= initArgs.periods; currentPeriod++) {
              expect(await tokenLock.passedPeriods()).eq(currentPeriod - 1)
              // console.log('\t  ✓ period ->', currentPeriod)
              await advancePeriods(tokenLock, 1)
            }
          })
        })
      })

      describe('Locking & release', function () {
        describe('availableAmount()', function () {
          it('should return zero before start time', async function () {
            expect(await tokenLock.availableAmount()).eq(0)
          })

          it('should return correct amount for each period', async function () {
            await advanceToStart(tokenLock)
            await shouldMatchSchedule(tokenLock, 'availableAmount', initArgs)
          })

          it('should return full managed amount after end time', async function () {
            await advanceToEnd(tokenLock)

            const managedAmount = await tokenLock.managedAmount()
            expect(await tokenLock.availableAmount()).eq(managedAmount)
          })
        })

        describe('vestedAmount()', function () {
          it('should be fully vested if non-revocable', async function () {
            const revocable: Revocability = await tokenLock.revocable()
            const vestedAmount = await tokenLock.vestedAmount()
            if (revocable === Revocability.Disabled) {
              expect(vestedAmount).eq(await tokenLock.managedAmount())
            }
          })

          it('should match the vesting schedule if revocable', async function () {
            if (initArgs.revocable === Revocability.Disabled) return

            const cliffTime = await tokenLock.vestingCliffTime()

            await forEachPeriod(tokenLock, async function (passedPeriods: BigNumber) {
              const amount = (await tokenLock.functions['vestedAmount']())[0]
              const amountPerPeriod = await tokenLock.amountPerPeriod()
              const managedAmount = await tokenLock.managedAmount()
              const currentTime = await tokenLock.currentTime()

              // console.log(`\t    - amount: ${formatGRT(amount)}/${formatGRT(managedAmount)}`)

              let expectedAmount = managedAmount
              // Before cliff no vested tokens
              if (cliffTime.gt(0) && currentTime.lt(cliffTime)) {
                expectedAmount = BigNumber.from(0)
              } else {
                // After last period we expect to have all managed tokens available
                if (passedPeriods.lt(initArgs.periods)) {
                  expectedAmount = passedPeriods.mul(amountPerPeriod)
                }
              }
              expect(amount).eq(expectedAmount)
            })
          })
        })

        describe('releasableAmount()', function () {
          it('should always return zero if there is no balance in the contract', async function () {
            await forEachPeriod(tokenLock, async function () {
              const releasableAmount = await tokenLock.releasableAmount()
              expect(releasableAmount).eq(0)
            })
          })

          context('> when funded', function () {
            beforeEach(async function () {
              await fundContract(tokenLock)
            })

            it('should match the release schedule', async function () {
              await advanceToReleasable(tokenLock)
              await shouldMatchSchedule(tokenLock, 'releasableAmount', initArgs)
            })

            it('should subtract already released amount', async function () {
              await advanceToReleasable(tokenLock)

              // After one period release
              await advancePeriods(tokenLock, 1)
              const releasableAmountPeriod1 = await tokenLock.releasableAmount()
              await tokenLock.connect(beneficiary1.signer).release()

              // Next periods test that we are not counting released amount on previous period
              await advancePeriods(tokenLock, 2)
              const availableAmount = await tokenLock.availableAmount()
              const releasableAmountPeriod2 = await tokenLock.releasableAmount()
              expect(releasableAmountPeriod2).eq(availableAmount.sub(releasableAmountPeriod1))
            })
          })
        })

        describe('totalOutstandingAmount()', function () {
          it('should be the total managed amount when have not released yet', async function () {
            const managedAmount = await tokenLock.managedAmount()
            const totalOutstandingAmount = await tokenLock.totalOutstandingAmount()
            expect(totalOutstandingAmount).eq(managedAmount)
          })

          context('when funded', function () {
            beforeEach(async function () {
              await fundContract(tokenLock)
            })

            it('should be the total managed when have not started', async function () {
              const managedAmount = await tokenLock.managedAmount()
              const totalOutstandingAmount = await tokenLock.totalOutstandingAmount()
              expect(totalOutstandingAmount).eq(managedAmount)
            })

            it('should be the total managed less the already released amount', async function () {
              // Setup
              await advanceToReleasable(tokenLock)
              await advancePeriods(tokenLock, 1)

              // Release
              const amountToRelease = await tokenLock.releasableAmount()
              await tokenLock.connect(beneficiary1.signer).release()

              const managedAmount = await tokenLock.managedAmount()
              const totalOutstandingAmount = await tokenLock.totalOutstandingAmount()
              expect(totalOutstandingAmount).eq(managedAmount.sub(amountToRelease))
            })

            it('should be zero when all funds have been released', async function () {
              // Setup
              await advanceToEnd(tokenLock)

              // Release
              await tokenLock.connect(beneficiary1.signer).release()

              // Test
              const totalOutstandingAmount = await tokenLock.totalOutstandingAmount()
              expect(totalOutstandingAmount).eq(0)
            })
          })
        })

        describe('surplusAmount()', function () {
          it('should be zero when balance under outstanding amount', async function () {
            // Setup
            await fundContract(tokenLock)
            await advanceToStart(tokenLock)

            // Test
            const surplusAmount = await tokenLock.surplusAmount()
            expect(surplusAmount).eq(0)
          })

          it('should return any balance over outstanding amount', async function () {
            // Setup
            await fundContract(tokenLock)
            await advanceToReleasable(tokenLock)
            await advancePeriods(tokenLock, 1)
            await tokenLock.connect(beneficiary1.signer).release()

            // Send extra amount
            await grt.connect(deployer.signer).transfer(tokenLock.address, toGRT('1000'))

            // Test
            const surplusAmount = await tokenLock.surplusAmount()
            expect(surplusAmount).eq(toGRT('1000'))
          })
        })
      })

      describe('Beneficiary admin', function () {
        describe('changeBeneficiary()', function () {
          it('should change beneficiary', async function () {
            const tx = tokenLock.connect(beneficiary1.signer).changeBeneficiary(beneficiary2.address)
            await expect(tx).emit(tokenLock, 'BeneficiaryChanged').withArgs(beneficiary2.address)

            const afterBeneficiary = await tokenLock.beneficiary()
            expect(afterBeneficiary).eq(beneficiary2.address)
          })

          it('reject if beneficiary is zero', async function () {
            const tx = tokenLock.connect(beneficiary1.signer).changeBeneficiary(AddressZero)
            await expect(tx).revertedWith('Empty beneficiary')
          })

          it('reject if not authorized', async function () {
            const tx = tokenLock.connect(deployer.signer).changeBeneficiary(beneficiary2.address)
            await expect(tx).revertedWith('!auth')
          })
        })
      })

      describe('Recovery', function () {
        beforeEach(async function () {
          await fundContract(tokenLock)
        })

        it('should cancel lock and return funds to owner', async function () {
          const beforeBalance = await grt.balanceOf(deployer.address)
          const contractBalance = await grt.balanceOf(tokenLock.address)
          const tx = tokenLock.connect(deployer.signer).cancelLock()
          await expect(tx).emit(tokenLock, 'LockCanceled')

          const afterBalance = await grt.balanceOf(deployer.address)
          const diff = afterBalance.sub(beforeBalance)
          expect(diff).eq(contractBalance)
        })

        it('reject cancel lock from non-owner', async function () {
          const tx = tokenLock.connect(beneficiary1.signer).cancelLock()
          await expect(tx).revertedWith('Ownable: caller is not the owner')
        })

        it('should accept lock', async function () {
          expect(await tokenLock.isAccepted()).eq(false)
          const tx = tokenLock.connect(beneficiary1.signer).acceptLock()
          await expect(tx).emit(tokenLock, 'LockAccepted')
          expect(await tokenLock.isAccepted()).eq(true)
        })

        it('reject accept lock from non-beneficiary', async function () {
          expect(await tokenLock.isAccepted()).eq(false)
          const tx = tokenLock.connect(deployer.signer).acceptLock()
          await expect(tx).revertedWith('!auth')
        })

        it('reject cancel after contract accepted', async function () {
          await tokenLock.connect(beneficiary1.signer).acceptLock()

          const tx = tokenLock.connect(deployer.signer).cancelLock()
          await expect(tx).revertedWith('Cannot cancel accepted contract')
        })
      })

      describe('Value transfer', function () {
        async function getState(tokenLock: GraphTokenLockSimple) {
          const beneficiaryAddress = await tokenLock.beneficiary()
          const ownerAddress = await tokenLock.owner()
          return {
            beneficiaryBalance: await grt.balanceOf(beneficiaryAddress),
            contractBalance: await grt.balanceOf(tokenLock.address),
            ownerBalance: await grt.balanceOf(ownerAddress),
          }
        }

        describe('release()', function () {
          it('should release the scheduled amount', async function () {
            // Setup
            await fundContract(tokenLock)
            await advanceToReleasable(tokenLock)
            await advancePeriods(tokenLock, 1)

            // Before state
            const before = await getState(tokenLock)

            // Release
            const amountToRelease = await tokenLock.releasableAmount()
            const tx = tokenLock.connect(beneficiary1.signer).release()
            await expect(tx).emit(tokenLock, 'TokensReleased').withArgs(beneficiary1.address, amountToRelease)

            // After state
            const after = await getState(tokenLock)
            expect(after.beneficiaryBalance).eq(before.beneficiaryBalance.add(amountToRelease))
            expect(after.contractBalance).eq(before.contractBalance.sub(amountToRelease))
            expect(await tokenLock.releasableAmount()).eq(0)
          })

          it('should release only vested amount after being revoked', async function () {
            if (initArgs.revocable === Revocability.Disabled) return

            // Setup
            await fundContract(tokenLock)
            await advanceToStart(tokenLock)

            // Move to cliff if any
            if (initArgs.vestingCliffTime) {
              await moveToTime(tokenLock, await tokenLock.vestingCliffTime(), 60)
            }

            // Vest some amount
            await advancePeriods(tokenLock, 2) // fwd two periods

            // Owner revokes the contract
            await tokenLock.connect(deployer.signer).revoke()
            const vestedAmount = await tokenLock.vestedAmount()

            // Some more periods passed
            await advancePeriods(tokenLock, 2) // fwd two periods

            // Release
            const tx = tokenLock.connect(beneficiary1.signer).release()
            await expect(tx).emit(tokenLock, 'TokensReleased').withArgs(beneficiary1.address, vestedAmount)
          })

          it('reject release vested amount before cliff', async function () {
            if (initArgs.revocable === Revocability.Disabled) return
            if (!initArgs.vestingCliffTime) return

            // Setup
            await fundContract(tokenLock)
            await advanceToStart(tokenLock)
            await advancePeriods(tokenLock, 2) // fwd two periods

            // Release before cliff
            const tx1 = tokenLock.connect(beneficiary1.signer).release()
            await expect(tx1).revertedWith('No available releasable amount')

            // Release after cliff
            await moveToTime(tokenLock, await tokenLock.vestingCliffTime(), 60)
            await tokenLock.connect(beneficiary1.signer).release()
          })

          it('reject release if no funds available', async function () {
            // Setup
            await fundContract(tokenLock)

            // Release
            const tx = tokenLock.connect(beneficiary1.signer).release()
            await expect(tx).revertedWith('No available releasable amount')
          })

          it('reject release if not the beneficiary', async function () {
            const tx = tokenLock.connect(beneficiary2.signer).release()
            await expect(tx).revertedWith('!auth')
          })
        })

        describe('withdrawSurplus()', function () {
          it('should withdraw surplus balance that is over managed amount', async function () {
            // Setup
            const managedAmount = await tokenLock.managedAmount()
            const amountToWithdraw = toGRT('100')
            const totalAmount = managedAmount.add(amountToWithdraw)
            await grt.connect(deployer.signer).transfer(tokenLock.address, totalAmount)

            // Revert if trying to withdraw more than managed amount
            const tx1 = tokenLock.connect(beneficiary1.signer).withdrawSurplus(amountToWithdraw.add(1))
            await expect(tx1).revertedWith('Amount requested > surplus available')

            // Before state
            const before = await getState(tokenLock)

            // Should withdraw
            const tx2 = tokenLock.connect(beneficiary1.signer).withdrawSurplus(amountToWithdraw)
            await expect(tx2).emit(tokenLock, 'TokensWithdrawn').withArgs(beneficiary1.address, amountToWithdraw)

            // After state
            const after = await getState(tokenLock)
            expect(after.beneficiaryBalance).eq(before.beneficiaryBalance.add(amountToWithdraw))
            expect(after.contractBalance).eq(before.contractBalance.sub(amountToWithdraw))
          })

          it('should withdraw surplus balance that is over managed amount (less than total available)', async function () {
            // Setup
            const managedAmount = await tokenLock.managedAmount()
            const surplusAmount = toGRT('100')
            const totalAmount = managedAmount.add(surplusAmount)
            await grt.connect(deployer.signer).transfer(tokenLock.address, totalAmount)

            // Should withdraw
            const tx2 = tokenLock.connect(beneficiary1.signer).withdrawSurplus(surplusAmount.sub(1))
            await expect(tx2).emit(tokenLock, 'TokensWithdrawn').withArgs(beneficiary1.address, surplusAmount.sub(1))
          })

          it('should withdraw surplus balance even after the contract was released->revoked', async function () {
            if (initArgs.revocable === Revocability.Enabled) {
              // Setup
              const managedAmount = await tokenLock.managedAmount()
              const surplusAmount = toGRT('100')
              const totalAmount = managedAmount.add(surplusAmount)
              await grt.connect(deployer.signer).transfer(tokenLock.address, totalAmount)

              // Vest some amount
              await advanceToReleasable(tokenLock)
              await advancePeriods(tokenLock, 2) // fwd two periods

              // Release / Revoke
              await tokenLock.connect(beneficiary1.signer).release()
              await tokenLock.connect(deployer.signer).revoke()

              // Should withdraw
              const tx2 = tokenLock.connect(beneficiary1.signer).withdrawSurplus(surplusAmount)
              await expect(tx2).emit(tokenLock, 'TokensWithdrawn').withArgs(beneficiary1.address, surplusAmount)

              // Contract must have no balance after all actions
              const balance = await grt.balanceOf(tokenLock.address)
              expect(balance).eq(0)
            }
          })

          it('should withdraw surplus balance even after the contract was revoked->released', async function () {
            if (initArgs.revocable === Revocability.Enabled) {
              // Setup
              const managedAmount = await tokenLock.managedAmount()
              const surplusAmount = toGRT('100')
              const totalAmount = managedAmount.add(surplusAmount)
              await grt.connect(deployer.signer).transfer(tokenLock.address, totalAmount)

              // Vest some amount
              await advanceToReleasable(tokenLock)
              await advancePeriods(tokenLock, 2) // fwd two periods

              // Release / Revoke
              await tokenLock.connect(deployer.signer).revoke()
              await tokenLock.connect(beneficiary1.signer).release()

              // Should withdraw
              const tx2 = tokenLock.connect(beneficiary1.signer).withdrawSurplus(surplusAmount)
              await expect(tx2).emit(tokenLock, 'TokensWithdrawn').withArgs(beneficiary1.address, surplusAmount)

              // Contract must have no balance after all actions
              const balance = await grt.balanceOf(tokenLock.address)
              expect(balance).eq(0)
            }
          })

          it('reject withdraw if not the beneficiary', async function () {
            await grt.connect(deployer.signer).transfer(tokenLock.address, toGRT('100'))

            const tx = tokenLock.connect(beneficiary2.signer).withdrawSurplus(toGRT('100'))
            await expect(tx).revertedWith('!auth')
          })

          it('reject withdraw zero tokens', async function () {
            const tx = tokenLock.connect(beneficiary1.signer).withdrawSurplus(toGRT('0'))
            await expect(tx).revertedWith('Amount cannot be zero')
          })

          it('reject withdraw more than available funds', async function () {
            const tx = tokenLock.connect(beneficiary1.signer).withdrawSurplus(toGRT('100'))
            await expect(tx).revertedWith('Amount requested > surplus available')
          })
        })

        describe('revoke()', function () {
          beforeEach(async function () {
            await fundContract(tokenLock)
            await advanceToStart(tokenLock)
          })

          it('should revoke and get funds back to owner', async function () {
            if (initArgs.revocable === Revocability.Enabled) {
              // Before state
              const before = await getState(tokenLock)

              // Revoke
              const beneficiaryAddress = await tokenLock.beneficiary()
              const vestedAmount = await tokenLock.vestedAmount()
              const managedAmount = await tokenLock.managedAmount()
              const unvestedAmount = managedAmount.sub(vestedAmount)
              const tx = tokenLock.connect(deployer.signer).revoke()
              await expect(tx).emit(tokenLock, 'TokensRevoked').withArgs(beneficiaryAddress, unvestedAmount)

              // After state
              const after = await getState(tokenLock)
              expect(after.ownerBalance).eq(before.ownerBalance.add(unvestedAmount))
            }
          })

          it('reject revoke multiple times', async function () {
            if (initArgs.revocable === Revocability.Enabled) {
              await tokenLock.connect(deployer.signer).revoke()
              const tx = tokenLock.connect(deployer.signer).revoke()
              await expect(tx).revertedWith('Already revoked')
            }
          })

          it('reject revoke if not authorized', async function () {
            const tx = tokenLock.connect(beneficiary1.signer).revoke()
            await expect(tx).revertedWith('Ownable: caller is not the owner')
          })

          it('reject revoke if not revocable', async function () {
            if (initArgs.revocable === Revocability.Disabled) {
              const tx = tokenLock.connect(deployer.signer).revoke()
              await expect(tx).revertedWith('Contract is non-revocable')
            }
          })

          it('reject revoke if no available unvested amount', async function () {
            if (initArgs.revocable === Revocability.Enabled) {
              // Setup
              await advanceToEnd(tokenLock)

              // Try to revoke after all tokens have been vested
              const tx = tokenLock.connect(deployer.signer).revoke()
              await expect(tx).revertedWith('No available unvested amount')
            }
          })
        })
      })
    })
  })
})
