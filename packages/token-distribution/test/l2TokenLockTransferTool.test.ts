import { deployments, ethers, upgrades } from 'hardhat'
import { constants } from 'ethers'
import { expect } from 'chai'

import '@nomiclabs/hardhat-ethers'
import 'hardhat-deploy'

import { GraphTokenMock } from '../build/typechain/contracts/GraphTokenMock'
import { L2GraphTokenLockManager } from '../build/typechain/contracts/L2GraphTokenLockManager'
import { L2GraphTokenLockTransferTool } from '../build/typechain/contracts/L2GraphTokenLockTransferTool'
import { L2GraphTokenLockTransferTool__factory } from '../build/typechain/contracts/factories/L2GraphTokenLockTransferTool__factory'
import { L2GraphTokenLockWallet } from '../build/typechain/contracts/L2GraphTokenLockWallet'
import { L2TokenGatewayMock } from '../build/typechain/contracts/L2TokenGatewayMock'

import { Account, getAccounts, getContract, toBN, toGRT } from './network'
import { defaultAbiCoder, keccak256 } from 'ethers/lib/utils'
import { defaultInitArgs, TokenLockParameters } from './config'
import { DeployOptions } from 'hardhat-deploy/types'

const { AddressZero } = constants

// Fixture
const setupTest = deployments.createFixture(async ({ deployments }) => {
  const deploy = (name: string, options: DeployOptions) => deployments.deploy(name, options)
  const [deployer, , l1TransferToolMock, l1GRTMock] = await getAccounts()

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

  // Deploy the gateway mock
  await deploy('L2TokenGatewayMock', {
    from: deployer.address,
    args: [l1GRTMock.address, grt.address],
  })
  const gateway = await getContract('L2TokenGatewayMock')

  // Deploy token lock manager
  await deploy('L2GraphTokenLockManager', {
    from: deployer.address,
    args: [grt.address, tokenLockWallet.address, gateway.address, l1TransferToolMock.address],
  })
  const tokenLockManager = await getContract('L2GraphTokenLockManager')

  // Deploy the L2GraphTokenLockTransferTool using a proxy

  // Deploy transfer tool using a proxy
  const transferToolFactory = await ethers.getContractFactory('L2GraphTokenLockTransferTool')
  const tokenLockTransferTool = (await upgrades.deployProxy(transferToolFactory, [], {
    kind: 'transparent',
    unsafeAllow: ['state-variable-immutable', 'constructor'],
    constructorArgs: [grt.address, gateway.address, l1GRTMock.address],
  })) as L2GraphTokenLockTransferTool

  // Fund the manager contract
  await grt.connect(deployer.signer).transfer(tokenLockManager.address, toGRT('100000000'))

  return {
    grt: grt as GraphTokenMock,
    gateway: gateway as L2TokenGatewayMock,
    tokenLockTransferTool: tokenLockTransferTool,
    tokenLockImplementation: tokenLockWallet as L2GraphTokenLockWallet,
    tokenLockManager: tokenLockManager as L2GraphTokenLockManager,
  }
})

async function authProtocolFunctions(tokenLockManager: L2GraphTokenLockManager, tokenLockTransferToolAddress: string) {
  await tokenLockManager.setAuthFunctionCall('withdrawToL1Locked(uint256)', tokenLockTransferToolAddress)
}

describe('L2GraphTokenLockTransferTool', () => {
  let deployer: Account
  let beneficiary: Account
  let l1TransferToolMock: Account
  let l1GRTMock: Account
  let l1TokenLock: Account

  let grt: GraphTokenMock
  let tokenLock: L2GraphTokenLockWallet
  let tokenLockImplementation: L2GraphTokenLockWallet
  let tokenLockManager: L2GraphTokenLockManager
  let tokenLockTransferTool: L2GraphTokenLockTransferTool
  let gateway: L2TokenGatewayMock
  let lockAsTransferTool: L2GraphTokenLockTransferTool

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

  const initFromL1 = async (): Promise<L2GraphTokenLockWallet> => {
    // First we mock creating a token lock wallet through the gateway
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

    // Mock the gateway call
    const tx = gateway.finalizeInboundTransfer(
      l1GRTMock.address,
      l1TransferToolMock.address,
      tokenLockManager.address,
      toGRT('35000000'),
      data,
    )

    await expect(tx).emit(tokenLockManager, 'TokenLockCreatedFromL1')

    const expectedL2Address = await tokenLockManager['getDeploymentAddress(bytes32,address,address)'](
      keccak256(data),
      tokenLockImplementation.address,
      tokenLockManager.address,
    )

    return ethers.getContractAt('L2GraphTokenLockWallet', expectedL2Address) as Promise<L2GraphTokenLockWallet>
  }

  before(async function () {
    [deployer, beneficiary, l1TransferToolMock, l1GRTMock, l1TokenLock] = await getAccounts()
  })

  beforeEach(async () => {
    ({ grt, gateway, tokenLockTransferTool, tokenLockImplementation, tokenLockManager } = await setupTest())

    // Setup authorized functions in Manager
    await authProtocolFunctions(tokenLockManager, tokenLockTransferTool.address)

    // Add the transfer tool contract as token destination
    await tokenLockManager.addTokenDestination(tokenLockTransferTool.address)
  })

  describe('Upgrades', function () {
    it('should be upgradeable', async function () {
      const transferToolFactory = await ethers.getContractFactory('L2GraphTokenLockTransferTool')
      tokenLockTransferTool = (await upgrades.upgradeProxy(tokenLockTransferTool.address, transferToolFactory, {
        kind: 'transparent',
        unsafeAllow: ['state-variable-immutable', 'constructor'],
        constructorArgs: [beneficiary.address, gateway.address, l1GRTMock.address],
      })) as L2GraphTokenLockTransferTool
      expect(await tokenLockTransferTool.graphToken()).to.eq(beneficiary.address)
      tokenLockTransferTool = (await upgrades.upgradeProxy(tokenLockTransferTool.address, transferToolFactory, {
        kind: 'transparent',
        unsafeAllow: ['state-variable-immutable', 'constructor'],
        constructorArgs: [grt.address, gateway.address, l1GRTMock.address],
      })) as L2GraphTokenLockTransferTool
      expect(await tokenLockTransferTool.graphToken()).to.eq(grt.address)
    })
  })
  describe('withdrawToL1Locked', function () {
    it('allows a token lock wallet to send GRT to L1 through the gateway', async function () {
      tokenLock = await initFromL1()
      // Approve contracts to pull tokens from the token lock
      await tokenLock.connect(beneficiary.signer).approveProtocol()

      lockAsTransferTool = L2GraphTokenLockTransferTool__factory.connect(tokenLock.address, deployer.signer)

      const amountToSend = toGRT('1000000')
      const tx = await lockAsTransferTool.connect(beneficiary.signer).withdrawToL1Locked(amountToSend)

      await expect(tx).emit(gateway, 'WithdrawalInitiated').withArgs(
        l1GRTMock.address,
        tokenLockTransferTool.address,
        l1TokenLock.address,
        toBN('0'), // sequence number
        amountToSend,
      )
      await expect(tx)
        .emit(tokenLockTransferTool, 'LockedFundsSentToL1')
        .withArgs(l1TokenLock.address, tokenLock.address, tokenLockManager.address, amountToSend)
    })
    it('rejects calls from a lock that was not transferred from L1', async function () {
      tokenLock = await initWithArgs(defaultInitArgs(deployer, beneficiary, grt, toGRT('35000000')))
      // Approve contracts to pull tokens from the token lock
      await tokenLock.connect(beneficiary.signer).approveProtocol()

      lockAsTransferTool = L2GraphTokenLockTransferTool__factory.connect(tokenLock.address, deployer.signer)

      const amountToSend = toGRT('1000000')
      const tx = lockAsTransferTool.connect(beneficiary.signer).withdrawToL1Locked(amountToSend)

      await expect(tx).to.be.revertedWith('NOT_L1_WALLET')
    })
    it('rejects calls from an address that is not a lock (has no manager)', async function () {
      const tx = tokenLockTransferTool.connect(beneficiary.signer).withdrawToL1Locked(toGRT('1000000'))
      await expect(tx).to.be.reverted // Function call to a non-contract account
    })
    it('rejects calls from an address that has a manager() function that returns zero', async function () {
      // Use WalletMock to simulate an invalid wallet with no manager
      // WalletMock constructor args are: target, token, manager, isInitialized, isAccepted
      await deployments.deploy('WalletMock', {
        from: deployer.address,
        args: [tokenLockTransferTool.address, grt.address, AddressZero, true, true],
      })
      const invalidWallet = await getContract('WalletMock')
      const walletAsTransferTool = L2GraphTokenLockTransferTool__factory.connect(invalidWallet.address, deployer.signer)

      const tx = walletAsTransferTool.connect(beneficiary.signer).withdrawToL1Locked(toGRT('1000000'))
      await expect(tx).to.be.revertedWith('INVALID_SENDER')
    })
    it('rejects calls from a lock that has insufficient GRT balance', async function () {
      tokenLock = await initFromL1()
      // Approve contracts to pull tokens from the token lock
      await tokenLock.connect(beneficiary.signer).approveProtocol()

      lockAsTransferTool = L2GraphTokenLockTransferTool__factory.connect(tokenLock.address, deployer.signer)

      const amountToSend = toGRT('35000001')
      const tx = lockAsTransferTool.connect(beneficiary.signer).withdrawToL1Locked(amountToSend)

      await expect(tx).to.be.revertedWith('INSUFFICIENT_BALANCE')
    })
    it('rejects calls trying to send a zero amount', async function () {
      tokenLock = await initFromL1()
      // Approve contracts to pull tokens from the token lock
      await tokenLock.connect(beneficiary.signer).approveProtocol()

      lockAsTransferTool = L2GraphTokenLockTransferTool__factory.connect(tokenLock.address, deployer.signer)

      const amountToSend = toGRT('0')
      const tx = lockAsTransferTool.connect(beneficiary.signer).withdrawToL1Locked(amountToSend)

      await expect(tx).to.be.revertedWith('ZERO_AMOUNT')
    })
  })
})
