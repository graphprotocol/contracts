import 'hardhat-deploy'
import { deployments } from 'hardhat'
import { expect } from 'chai'
import { GraphTokenDistributor } from '../build/typechain/contracts/GraphTokenDistributor'
import { GraphTokenMock } from '../build/typechain/contracts/GraphTokenMock'

import { Account, getAccounts, getContract, toGRT } from './network'
import { DeployOptions } from 'hardhat-deploy/types'

// Fixture
const setupTest = deployments.createFixture(async ({ deployments }) => {
  const deploy = (name: string, options: DeployOptions) => deployments.deploy(name, options)
  const [deployer] = await getAccounts()

  // Start from a fresh snapshot
  await deployments.fixture([])

  // Deploy token
  await deploy('GraphTokenMock', {
    from: deployer.address,
    args: [toGRT('400000000'), deployer.address],
  })
  const grt = await getContract('GraphTokenMock')

  // Deploy distributor
  await deploy('GraphTokenDistributor', {
    from: deployer.address,
    args: [grt.address],
  })
  const distributor = await getContract('GraphTokenDistributor')

  return {
    grt: grt as GraphTokenMock,
    distributor: distributor as GraphTokenDistributor,
  }
})

describe('GraphTokenDistributor', () => {
  let deployer: Account
  let beneficiary1: Account
  let beneficiary2: Account

  let grt: GraphTokenMock
  let distributor: GraphTokenDistributor

  before(async function () {
    [deployer, beneficiary1, beneficiary2] = await getAccounts()
  })

  beforeEach(async () => {
    ({ grt, distributor } = await setupTest())
  })

  describe('init', function () {
    it('should deploy locked', async function () {
      const isLocked = await distributor.locked()
      expect(isLocked).eq(true)
    })
  })

  describe('setup beneficiary', function () {
    const amount = toGRT('100')

    describe('add', function () {
      it('should add tokens to beneficiary', async function () {
        const tx = distributor.connect(deployer.signer).addBeneficiaryTokens(beneficiary1.address, amount)
        await expect(tx).emit(distributor, 'BeneficiaryUpdated').withArgs(beneficiary1.address, amount)
      })

      it('reject add tokens to beneficiary if not allowed', async function () {
        const tx = distributor.connect(beneficiary1.signer).addBeneficiaryTokens(beneficiary1.address, amount)
        await expect(tx).revertedWith('Ownable: caller is not the owner')
      })

      it('should add tokens to multiple beneficiaries', async function () {
        const accounts = [beneficiary1.address, beneficiary2.address]
        const amounts = [amount, amount]

        await distributor.connect(deployer.signer).addBeneficiaryTokensMulti(accounts, amounts)
      })

      it('reject add token to multiple beneficiaries if not allowed', async function () {
        const accounts = [beneficiary1.address, beneficiary2.address]
        const amounts = [amount, amount]

        const tx = distributor.connect(beneficiary1.signer).addBeneficiaryTokensMulti(accounts, amounts)
        await expect(tx).revertedWith('Ownable: caller is not the owner')
      })
    })

    describe('sub', function () {
      it('should remove tokens from beneficiary', async function () {
        await distributor.addBeneficiaryTokens(beneficiary1.address, amount)

        const tx = distributor.subBeneficiaryTokens(beneficiary1.address, amount)
        await expect(tx).emit(distributor, 'BeneficiaryUpdated').withArgs(beneficiary1.address, toGRT('0'))
      })

      it('reject remove more tokens than available ', async function () {
        const tx = distributor.subBeneficiaryTokens(beneficiary1.address, toGRT('1000'))
        await expect(tx).revertedWith('SafeMath: subtraction overflow')
      })
    })
  })

  describe('unlocking', function () {
    it('should lock', async function () {
      const tx = distributor.connect(deployer.signer).setLocked(true)
      await expect(tx).emit(distributor, 'LockUpdated').withArgs(true)
      expect(await distributor.locked()).eq(true)
    })

    it('should unlock', async function () {
      const tx = distributor.connect(deployer.signer).setLocked(false)
      await expect(tx).emit(distributor, 'LockUpdated').withArgs(false)
      expect(await distributor.locked()).eq(false)
    })

    it('reject unlock if not allowed', async function () {
      const tx = distributor.connect(beneficiary1.signer).setLocked(false)
      await expect(tx).revertedWith('Ownable: caller is not the owner')
    })
  })

  describe('claim', function () {
    const totalAmount = toGRT('1000000')
    const amount = toGRT('10000')

    beforeEach(async function () {
      // Setup
      await grt.transfer(distributor.address, totalAmount)
      await distributor.connect(deployer.signer).addBeneficiaryTokens(beneficiary1.address, amount)
    })

    it('should claim outstanding token amount', async function () {
      await distributor.connect(deployer.signer).setLocked(false)

      const tx = distributor.connect(beneficiary1.signer).claim()
      await expect(tx).emit(distributor, 'TokensClaimed').withArgs(beneficiary1.address, beneficiary1.address, amount)
    })

    it('reject claim if locked', async function () {
      const tx = distributor.connect(beneficiary1.signer).claim()
      await expect(tx).revertedWith('Distributor: Claim is locked')
    })

    it('reject claim if no available tokens', async function () {
      await distributor.connect(deployer.signer).setLocked(false)

      const tx = distributor.connect(beneficiary2.signer).claim()
      await expect(tx).revertedWith('Distributor: Unavailable funds')
    })

    it('reject claim if beneficiary already claimed all tokens', async function () {
      await distributor.connect(deployer.signer).setLocked(false)

      await distributor.connect(beneficiary1.signer).claim()
      const tx = distributor.connect(beneficiary1.signer).claim()
      await expect(tx).revertedWith('Distributor: Unavailable funds')
    })
  })

  describe('deposit & withdraw', function () {
    it('should deposit funds into the distributor', async function () {
      const beforeBalance = await grt.balanceOf(distributor.address)

      const amount = toGRT('1000')
      await grt.approve(distributor.address, amount)
      const tx = distributor.connect(distributor.signer).deposit(amount)
      await expect(tx).emit(distributor, 'TokensDeposited').withArgs(deployer.address, amount)

      const afterBalance = await grt.balanceOf(distributor.address)
      expect(afterBalance).eq(beforeBalance.add(amount))
    })

    it('should withdraw tokens from the contract if owner', async function () {
      // Setup
      const amount = toGRT('1000')
      await grt.approve(distributor.address, amount)
      await distributor.connect(distributor.signer).deposit(amount)

      const tx = distributor.connect(deployer.signer).withdraw(amount)
      await expect(tx).emit(distributor, 'TokensWithdrawn').withArgs(deployer.address, amount)

      const afterBalance = await grt.balanceOf(distributor.address)
      expect(afterBalance).eq(0)
    })

    it('reject withdraw tokens from the contract if no balance', async function () {
      const amount = toGRT('1000')
      const tx = distributor.connect(deployer.signer).withdraw(amount)
      await expect(tx).revertedWith('ERC20: transfer amount exceeds balance')
    })

    it('reject withdraw tokens from the contract if not allowed', async function () {
      const amount = toGRT('1000')
      const tx = distributor.connect(beneficiary1.signer).withdraw(amount)
      await expect(tx).revertedWith('Ownable: caller is not the owner')
    })
  })
})
