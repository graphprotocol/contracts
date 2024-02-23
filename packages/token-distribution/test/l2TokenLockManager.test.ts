import { constants, Wallet } from 'ethers'
import { deployments, ethers } from 'hardhat'
import { expect } from 'chai'

import '@nomiclabs/hardhat-ethers'
import 'hardhat-deploy'

import { GraphTokenMock } from '../build/typechain/contracts/GraphTokenMock'
import { L2GraphTokenLockManager } from '../build/typechain/contracts/L2GraphTokenLockManager'
import { L2GraphTokenLockWallet } from '../build/typechain/contracts/L2GraphTokenLockWallet'
import { Staking__factory } from '@graphprotocol/contracts/dist/types/factories/Staking__factory'
import { StakingMock } from '../build/typechain/contracts/StakingMock'

import { Account, advanceTimeAndBlock, getAccounts, getContract, toGRT } from './network'
import { defaultAbiCoder, keccak256 } from 'ethers/lib/utils'
import { defaultInitArgs, Revocability, TokenLockParameters } from './config'
import { DeployOptions } from 'hardhat-deploy/types'
import { Staking } from '@graphprotocol/contracts'

const { AddressZero } = constants

// Fixture
const setupTest = deployments.createFixture(async ({ deployments }) => {
  const deploy = (name: string, options: DeployOptions) => deployments.deploy(name, options)
  const [deployer, , l1TransferToolMock, gateway] = await getAccounts()

  // Start from a fresh snapshot
  await deployments.fixture([])

  // Deploy token
  await deploy('GraphTokenMock', {
    from: deployer.address,
    args: [toGRT('1000000000'), deployer.address],
  })
  const grt = await getContract('GraphTokenMock')

  // Deploy token lock masterCopy
  await deploy('L2GraphTokenLockWallet', {
    from: deployer.address,
  })
  const tokenLockWallet = await getContract('L2GraphTokenLockWallet')

  // Deploy token lock manager
  await deploy('L2GraphTokenLockManager', {
    from: deployer.address,
    args: [grt.address, tokenLockWallet.address, gateway.address, l1TransferToolMock.address],
  })
  const tokenLockManager = await getContract('L2GraphTokenLockManager')

  // Protocol contracts
  await deploy('StakingMock', { from: deployer.address, args: [grt.address] })
  const staking = await getContract('StakingMock')

  // Fund the manager contract
  await grt.connect(deployer.signer).transfer(tokenLockManager.address, toGRT('100000000'))

  return {
    grt: grt as GraphTokenMock,
    staking: staking as StakingMock,
    tokenLockImplementation: tokenLockWallet as L2GraphTokenLockWallet,
    tokenLockManager: tokenLockManager as L2GraphTokenLockManager,
  }
})

async function authProtocolFunctions(tokenLockManager: L2GraphTokenLockManager, stakingAddress: string) {
  await tokenLockManager.setAuthFunctionCall('stake(uint256)', stakingAddress)
  await tokenLockManager.setAuthFunctionCall('unstake(uint256)', stakingAddress)
  await tokenLockManager.setAuthFunctionCall('withdraw()', stakingAddress)
}

describe('L2GraphTokenLockManager', () => {
  let deployer: Account
  let beneficiary: Account
  let l1TransferToolMock: Account
  let gateway: Account
  let l1TokenLock: Account

  let grt: GraphTokenMock
  let tokenLock: L2GraphTokenLockWallet
  let tokenLockImplementation: L2GraphTokenLockWallet
  let tokenLockManager: L2GraphTokenLockManager
  let staking: StakingMock
  let lockAsStaking: Staking

  let initArgs: TokenLockParameters

  const initWithArgs = async (args: TokenLockParameters): Promise<L2GraphTokenLockWallet> => {
    const tx = await tokenLockManager.createTokenLockWallet(
      args.owner,
      args.beneficiary,
      args.managedAmount,
      args.startTime,
      args.endTime,
      args.periods,
      args.releaseStartTime,
      args.vestingCliffTime,
      args.revocable,
    )
    const receipt = await tx.wait()
    const contractAddress = receipt.events[0].args['proxy']
    return ethers.getContractAt('L2GraphTokenLockWallet', contractAddress) as Promise<L2GraphTokenLockWallet>
  }

  before(async function () {
    [deployer, beneficiary, l1TransferToolMock, gateway, l1TokenLock] = await getAccounts()
  })

  beforeEach(async () => {
    ({ grt, tokenLockManager, staking, tokenLockImplementation } = await setupTest())

    // Setup authorized functions in Manager
    await authProtocolFunctions(tokenLockManager, staking.address)

    // Add the staking contract as token destination
    await tokenLockManager.addTokenDestination(staking.address)
  })

  describe('TokenLockManager standard behavior', function () {
    it('reverts if initialized with empty token', async function () {
      const deploy = (name: string, options: DeployOptions) => deployments.deploy(name, options)

      const d = deploy('L2GraphTokenLockManager', {
        from: deployer.address,
        args: [
          AddressZero,
          Wallet.createRandom().address,
          Wallet.createRandom().address,
          Wallet.createRandom().address,
        ],
      })
      await expect(d).revertedWith('Token cannot be zero')
    })

    it('should set the master copy', async function () {
      const address = Wallet.createRandom().address
      const tx = tokenLockManager.setMasterCopy(address)
      await expect(tx).emit(tokenLockManager, 'MasterCopyUpdated').withArgs(address)
    })

    it('reverts if setting the master copy to zero address', async function () {
      const tx = tokenLockManager.setMasterCopy(AddressZero)
      await expect(tx).revertedWith('MasterCopy cannot be zero')
    })

    it('should add a token destination', async function () {
      const address = Wallet.createRandom().address

      expect(await tokenLockManager.isTokenDestination(address)).eq(false)
      const tx = tokenLockManager.addTokenDestination(address)
      await expect(tx).emit(tokenLockManager, 'TokenDestinationAllowed').withArgs(address, true)
      expect(await tokenLockManager.isTokenDestination(address)).eq(true)
    })

    it('reverts when adding a token destination with zero address', async function () {
      const tx = tokenLockManager.addTokenDestination(AddressZero)
      await expect(tx).revertedWith('Destination cannot be zero')
    })

    it('creates a token lock wallet that can participate in the protocol', async function () {
      initArgs = defaultInitArgs(deployer, beneficiary, grt, toGRT('35000000'))
      tokenLock = await initWithArgs(initArgs)

      // Approve contracts to pull tokens from the token lock
      await tokenLock.connect(beneficiary.signer).approveProtocol()

      // Check that the token lock wallet was created with the correct parameters
      expect(await tokenLock.owner()).eq(initArgs.owner)
      expect(await tokenLock.beneficiary()).eq(initArgs.beneficiary)
      expect(await tokenLock.managedAmount()).eq(initArgs.managedAmount)
      expect(await tokenLock.startTime()).eq(initArgs.startTime)
      expect(await tokenLock.endTime()).eq(initArgs.endTime)
      expect(await tokenLock.periods()).eq(initArgs.periods)
      expect(await tokenLock.releaseStartTime()).eq(initArgs.releaseStartTime)
      expect(await tokenLock.vestingCliffTime()).eq(initArgs.vestingCliffTime)
      expect(await tokenLock.revocable()).eq(initArgs.revocable)
      expect(await tokenLock.isAccepted()).eq(false)

      expect(await grt.balanceOf(tokenLock.address)).eq(initArgs.managedAmount)

      // Stake in the protocol using the lock as a Staking contract
      const amount = toGRT('10000000')

      lockAsStaking = Staking__factory.connect(tokenLock.address, deployer.signer)
      await lockAsStaking.connect(beneficiary.signer).stake(amount)

      // Check that the staking contract received the tokens
      expect(await grt.balanceOf(staking.address)).eq(amount)
      // Check the token lock wallet balance
      expect(await grt.balanceOf(tokenLock.address)).eq(initArgs.managedAmount.sub(amount))
    })
  })
  describe('onTokenTransfer', function () {
    it('receives tokens and creates a new token lock with the received parameters', async function () {
      // ABI-encoded callhook data
      initArgs = defaultInitArgs(deployer, beneficiary, grt, toGRT('35000000'))
      const walletDataType = 'tuple(address,address,address,uint256,uint256,uint256)'
      const data = defaultAbiCoder.encode(
        [walletDataType],
        [
          [
            l1TokenLock.address,
            initArgs.owner,
            initArgs.beneficiary,
            initArgs.managedAmount,
            initArgs.startTime,
            initArgs.endTime,
          ],
        ],
      )
      const walletData = {
        l1Address: l1TokenLock.address,
        owner: initArgs.owner,
        beneficiary: initArgs.beneficiary,
        managedAmount: initArgs.managedAmount,
        startTime: initArgs.startTime,
        endTime: initArgs.endTime,
      }

      const expectedL2Address = await tokenLockManager['getDeploymentAddress(bytes32,address,address)'](
        keccak256(data),
        tokenLockImplementation.address,
        tokenLockManager.address,
      )

      // Assume part of the managed amount were used in L1, so we don't get all of it
      const transferredAmount = initArgs.managedAmount.sub(toGRT('100000'))

      const expectedInitData = tokenLockImplementation.interface.encodeFunctionData('initializeFromL1', [
        tokenLockManager.address,
        grt.address,
        walletData,
      ])
      const expectedInitHash = keccak256(expectedInitData)

      // Call onTokenTransfer from the gateway:
      const tx = tokenLockManager
        .connect(gateway.signer)
        .onTokenTransfer(l1TransferToolMock.address, transferredAmount, data)

      await expect(tx)
        .emit(tokenLockManager, 'TokenLockCreatedFromL1')
        .withArgs(
          expectedL2Address,
          expectedInitHash,
          walletData.beneficiary,
          walletData.managedAmount,
          walletData.startTime,
          walletData.endTime,
          walletData.l1Address,
        )

      // Check that the token lock wallet was created with the correct parameters
      const tokenLock = (await ethers.getContractAt(
        'L2GraphTokenLockWallet',
        expectedL2Address,
        deployer.signer,
      )) as L2GraphTokenLockWallet
      expect(await tokenLock.owner()).eq(initArgs.owner)
      expect(await tokenLock.beneficiary()).eq(initArgs.beneficiary)
      expect(await tokenLock.managedAmount()).eq(initArgs.managedAmount)
      expect(await tokenLock.startTime()).eq(initArgs.startTime)
      expect(await tokenLock.endTime()).eq(initArgs.endTime)
      expect(await tokenLock.periods()).eq(1)
      expect(await tokenLock.releaseStartTime()).eq(initArgs.endTime)
      expect(await tokenLock.vestingCliffTime()).eq(0)
      expect(await tokenLock.revocable()).eq(Revocability.Disabled)
      expect(await grt.balanceOf(tokenLock.address)).eq(transferredAmount)
      expect(await tokenLock.isAccepted()).eq(true)

      // The mapping for L1 address to L2 address should be set correctly
      expect(await tokenLockManager.l1WalletToL2Wallet(l1TokenLock.address)).eq(expectedL2Address)
      // And same for L2 address to L1 address
      expect(await tokenLockManager.l2WalletToL1Wallet(expectedL2Address)).eq(l1TokenLock.address)
    })
    it('sends the tokens to an already created wallet', async function () {
      // ABI-encoded callhook data
      initArgs = defaultInitArgs(deployer, beneficiary, grt, toGRT('35000000'))
      const walletDataType = 'tuple(address,address,address,uint256,uint256,uint256)'
      const data = defaultAbiCoder.encode(
        [walletDataType],
        [
          [
            l1TokenLock.address,
            initArgs.owner,
            initArgs.beneficiary,
            initArgs.managedAmount,
            initArgs.startTime,
            initArgs.endTime,
          ],
        ],
      )
      const walletData = {
        l1Address: l1TokenLock.address,
        owner: initArgs.owner,
        beneficiary: initArgs.beneficiary,
        managedAmount: initArgs.managedAmount,
        startTime: initArgs.startTime,
        endTime: initArgs.endTime,
      }

      const expectedL2Address = await tokenLockManager['getDeploymentAddress(bytes32,address,address)'](
        keccak256(data),
        tokenLockImplementation.address,
        tokenLockManager.address,
      )

      // Assume part of the managed amount were used in L1, so we don't get all of it
      const transferredAmount = initArgs.managedAmount.sub(toGRT('100000'))

      const expectedInitData = tokenLockImplementation.interface.encodeFunctionData('initializeFromL1', [
        tokenLockManager.address,
        grt.address,
        walletData,
      ])
      const expectedInitHash = keccak256(expectedInitData)

      // Call onTokenTransfer from the gateway:
      const tx = tokenLockManager
        .connect(gateway.signer)
        .onTokenTransfer(l1TransferToolMock.address, transferredAmount, data)

      await expect(tx)
        .emit(tokenLockManager, 'TokenLockCreatedFromL1')
        .withArgs(
          expectedL2Address,
          expectedInitHash,
          walletData.beneficiary,
          walletData.managedAmount,
          walletData.startTime,
          walletData.endTime,
          walletData.l1Address,
        )

      // Check that the token lock wallet was created with the correct parameters
      const tokenLock = (await ethers.getContractAt(
        'L2GraphTokenLockWallet',
        expectedL2Address,
        deployer.signer,
      )) as L2GraphTokenLockWallet
      expect(await grt.balanceOf(tokenLock.address)).eq(transferredAmount)

      // Call onTokenTransfer from the gateway again:
      const tx2 = tokenLockManager
        .connect(gateway.signer)
        .onTokenTransfer(l1TransferToolMock.address, transferredAmount, data)
      // This tx should not emit a TokenLockCreatedFromL1 event
      await expect(tx2).to.not.emit(tokenLockManager, 'TokenLockCreatedFromL1')
      // But it should transfer the tokens to the token lock wallet
      expect(await grt.balanceOf(tokenLock.address)).eq(transferredAmount.mul(2))
    })
    it('creates a wallet that can participate in the protocol', async function () {
      // ABI-encoded callhook data
      initArgs = defaultInitArgs(deployer, beneficiary, grt, toGRT('35000000'))
      const walletDataType = 'tuple(address,address,address,uint256,uint256,uint256)'
      const data = defaultAbiCoder.encode(
        [walletDataType],
        [
          [
            l1TokenLock.address,
            initArgs.owner,
            initArgs.beneficiary,
            initArgs.managedAmount,
            initArgs.startTime,
            initArgs.endTime,
          ],
        ],
      )

      const expectedL2Address = await tokenLockManager['getDeploymentAddress(bytes32,address,address)'](
        keccak256(data),
        tokenLockImplementation.address,
        tokenLockManager.address,
      )

      // Assume part of the managed amount were used in L1, so we don't get all of it
      const transferredAmount = initArgs.managedAmount.sub(toGRT('100000'))

      // Call onTokenTransfer from the gateway:
      await tokenLockManager
        .connect(gateway.signer)
        .onTokenTransfer(l1TransferToolMock.address, transferredAmount, data)

      // Check that the token lock wallet was created with the correct parameters
      const tokenLock = (await ethers.getContractAt(
        'L2GraphTokenLockWallet',
        expectedL2Address,
        deployer.signer,
      )) as L2GraphTokenLockWallet

      // Approve the protocol
      await tokenLock.connect(beneficiary.signer).approveProtocol()

      // And the created wallet should be able to participate in the protocol
      // Stake in the protocol using the lock as a Staking contract
      const amount = toGRT('100000')

      const lockAsStaking = Staking__factory.connect(tokenLock.address, deployer.signer)
      await lockAsStaking.connect(beneficiary.signer).stake(amount)

      // Check that the staking contract received the tokens
      expect(await grt.balanceOf(staking.address)).eq(amount)
      // Check the token lock wallet balance
      expect(await grt.balanceOf(tokenLock.address)).eq(transferredAmount.sub(amount))
    })
    it('creates a wallet that has zero releasable amount until the end of the vesting period', async function () {
      // ABI-encoded callhook data
      initArgs = defaultInitArgs(deployer, beneficiary, grt, toGRT('35000000'))
      const walletDataType = 'tuple(address,address,address,uint256,uint256,uint256)'
      const data = defaultAbiCoder.encode(
        [walletDataType],
        [
          [
            l1TokenLock.address,
            initArgs.owner,
            initArgs.beneficiary,
            initArgs.managedAmount,
            initArgs.startTime,
            initArgs.endTime,
          ],
        ],
      )

      const expectedL2Address = await tokenLockManager['getDeploymentAddress(bytes32,address,address)'](
        keccak256(data),
        tokenLockImplementation.address,
        tokenLockManager.address,
      )

      // Assume part of the managed amount were used in L1, so we don't get all of it
      const transferredAmount = initArgs.managedAmount.sub(toGRT('100000'))

      // Call onTokenTransfer from the gateway:
      await tokenLockManager
        .connect(gateway.signer)
        .onTokenTransfer(l1TransferToolMock.address, transferredAmount, data)

      // Check that the token lock wallet was created with the correct parameters
      const tokenLock = (await ethers.getContractAt(
        'L2GraphTokenLockWallet',
        expectedL2Address,
        deployer.signer,
      )) as L2GraphTokenLockWallet

      // Check that the releasable amount is zero
      expect(await tokenLock.releasableAmount()).eq(0)
      // After a few blocks, check that the releasable amount is still zero
      await advanceTimeAndBlock(3600 * 24 * 90)
      expect(await tokenLock.releasableAmount()).eq(0)
      // And available amount should also be zero
      expect(await tokenLock.availableAmount()).eq(0)

      // Advance time to the end of the vesting period
      await advanceTimeAndBlock(3600 * 24 * 181)
      // Check that the releasable amount is the full amount transferred
      expect(await tokenLock.releasableAmount()).eq(transferredAmount)
      // And available amount should also be the full managed amount
      expect(await tokenLock.availableAmount()).eq(initArgs.managedAmount)
    })
  })
})
