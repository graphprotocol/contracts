import { ethers } from 'hardhat'
import { HardhatEthersSigner } from '@nomicfoundation/hardhat-ethers/signers'
import { SignerWithAddress } from '@nomicfoundation/hardhat-ethers/signers'
import {
  BaseUpgradeable,
  DirectAllocation,
  IssuanceAllocator,
  ServiceQualityOracle,
  ExpiringServiceQualityOracle,
  TestProxy,
  MockGraphToken
} from '../../build/types'

/**
 * Standard test accounts
 */
export interface TestAccounts {
  governor: SignerWithAddress
  nonGovernor: SignerWithAddress
  operator: SignerWithAddress
  user: SignerWithAddress
  indexer1: SignerWithAddress
  indexer2: SignerWithAddress
  selfMintingTarget: SignerWithAddress
}

/**
 * Get standard test accounts
 */
export async function getTestAccounts(): Promise<TestAccounts> {
  const [
    governor,
    nonGovernor,
    operator,
    user,
    indexer1,
    indexer2,
    selfMintingTarget
  ] = await ethers.getSigners()

  return {
    governor,
    nonGovernor,
    operator,
    user,
    indexer1,
    indexer2,
    selfMintingTarget
  }
}

/**
 * Common constants used in tests
 */
export const Constants = {
  PPM: 1_000_000, // Parts per million (100%)
  DEFAULT_ISSUANCE_PER_BLOCK: ethers.parseEther('100') // 100 GRT per block
}

/**
 * Deploy a test GraphToken for testing
 * This uses MockGraphToken for now, but could be replaced with a more accurate implementation later
 */
export async function deployTestGraphToken(): Promise<MockGraphToken> {
  // For testing purposes, we'll use MockGraphToken
  const GraphTokenFactory = await ethers.getContractFactory('MockGraphToken')
  return await GraphTokenFactory.deploy() as unknown as MockGraphToken
}

/**
 * Deploy a proxy contract pointing to an implementation
 */
export async function deployProxy(
  implementation: string,
  admin: string,
  initData: string
): Promise<TestProxy> {
  const ProxyFactory = await ethers.getContractFactory('TestProxy')
  return await ProxyFactory.deploy(
    implementation,
    admin,
    initData
  ) as unknown as TestProxy
}

/**
 * Deploy the IssuanceAllocator contract with proxy
 */
export async function deployIssuanceAllocator(
  graphToken: string,
  governor: HardhatEthersSigner,
  issuancePerBlock: bigint
): Promise<IssuanceAllocator> {
  // Deploy implementation
  const IssuanceAllocatorFactory = await ethers.getContractFactory('IssuanceAllocator')
  const issuanceAllocatorImpl = await IssuanceAllocatorFactory.deploy(graphToken)

  // Create initialization data
  const initData = IssuanceAllocatorFactory.interface.encodeFunctionData('initialize', [governor.address])

  // Deploy proxy
  const proxy = await deployProxy(
    await issuanceAllocatorImpl.getAddress(),
    governor.address,
    initData
  )

  // Get contract at proxy address
  const issuanceAllocator = IssuanceAllocatorFactory.attach(
    await proxy.getAddress()
  ) as unknown as IssuanceAllocator

  // Set issuance per block
  await issuanceAllocator.connect(governor).setIssuancePerBlock(issuancePerBlock)

  return issuanceAllocator
}

/**
 * Deploy a complete issuance system with production contracts
 */
export async function deployIssuanceSystem(
  accounts: TestAccounts,
  issuancePerBlock: bigint = Constants.DEFAULT_ISSUANCE_PER_BLOCK
) {
  const { governor } = accounts

  // Deploy test GraphToken
  const graphToken = await deployTestGraphToken()
  const graphTokenAddress = await graphToken.getAddress()

  // Deploy IssuanceAllocator
  const issuanceAllocator = await deployIssuanceAllocator(
    graphTokenAddress,
    governor,
    issuancePerBlock
  )

  // Deploy DirectAllocation targets
  const target1 = await deployDirectAllocation(
    graphTokenAddress,
    governor
  )

  const target2 = await deployDirectAllocation(
    graphTokenAddress,
    governor
  )

  // Deploy ServiceQualityOracle
  const serviceQualityOracle = await deployServiceQualityOracle(
    graphTokenAddress,
    governor
  )

  // Deploy ExpiringServiceQualityOracle
  const expiringServiceQualityOracle = await deployExpiringServiceQualityOracle(
    graphTokenAddress,
    governor
  )

  return {
    graphToken,
    issuanceAllocator,
    target1,
    target2,
    serviceQualityOracle,
    expiringServiceQualityOracle
  }
}

/**
 * Deploy the DirectAllocation contract with proxy
 */
export async function deployDirectAllocation(
  graphToken: string,
  governor: HardhatEthersSigner
): Promise<DirectAllocation> {
  // Deploy implementation
  const DirectAllocationFactory = await ethers.getContractFactory('DirectAllocation')
  const directAllocationImpl = await DirectAllocationFactory.deploy(graphToken)

  // Create initialization data
  const initData = DirectAllocationFactory.interface.encodeFunctionData('initialize', [governor.address])

  // Deploy proxy
  const proxy = await deployProxy(
    await directAllocationImpl.getAddress(),
    governor.address,
    initData
  )

  // Get contract at proxy address
  return DirectAllocationFactory.attach(
    await proxy.getAddress()
  ) as unknown as DirectAllocation
}

/**
 * Deploy the ServiceQualityOracle contract with proxy
 */
export async function deployServiceQualityOracle(
  graphToken: string,
  governor: HardhatEthersSigner
): Promise<ServiceQualityOracle> {
  // Deploy implementation
  const ServiceQualityOracleFactory = await ethers.getContractFactory('ServiceQualityOracle')
  const serviceQualityOracleImpl = await ServiceQualityOracleFactory.deploy(graphToken)

  // Create initialization data
  const initData = ServiceQualityOracleFactory.interface.encodeFunctionData('initialize', [governor.address])

  // Deploy proxy
  const proxy = await deployProxy(
    await serviceQualityOracleImpl.getAddress(),
    governor.address,
    initData
  )

  // Get contract at proxy address
  return ServiceQualityOracleFactory.attach(
    await proxy.getAddress()
  ) as unknown as ServiceQualityOracle
}

/**
 * Deploy the BaseUpgradeable contract with proxy
 */
export async function deployBaseUpgradeable(
  graphToken: string,
  governor: HardhatEthersSigner
): Promise<BaseUpgradeable> {
  // Deploy implementation
  const BaseUpgradeableFactory = await ethers.getContractFactory('BaseUpgradeable')
  const baseUpgradeableImpl = await BaseUpgradeableFactory.deploy(graphToken)

  // Create initialization data
  const initData = BaseUpgradeableFactory.interface.encodeFunctionData('initialize', [governor.address])

  // Deploy proxy
  const proxy = await deployProxy(
    await baseUpgradeableImpl.getAddress(),
    governor.address,
    initData
  )

  // Get contract at proxy address
  return BaseUpgradeableFactory.attach(
    await proxy.getAddress()
  ) as unknown as BaseUpgradeable
}

/**
 * Deploy the ExpiringServiceQualityOracle contract with proxy
 * @param validityPeriod The validity period in seconds (default: 7 days)
 */
export async function deployExpiringServiceQualityOracle(
  graphToken: string,
  governor: HardhatEthersSigner,
  validityPeriod: number = 7 * 24 * 60 * 60 // 7 days in seconds
): Promise<ExpiringServiceQualityOracle> {
  // Deploy implementation
  const ExpiringServiceQualityOracleFactory = await ethers.getContractFactory('ExpiringServiceQualityOracle')
  const expiringServiceQualityOracleImpl = await ExpiringServiceQualityOracleFactory.deploy(graphToken)

  // Create initialization data for the base contract
  const initData = ExpiringServiceQualityOracleFactory.interface.encodeFunctionData(
    'initialize(address)',
    [governor.address]
  )

  // Deploy proxy
  const proxy = await deployProxy(
    await expiringServiceQualityOracleImpl.getAddress(),
    governor.address,
    initData
  )

  // Get contract at proxy address
  const expiringServiceQualityOracle = ExpiringServiceQualityOracleFactory.attach(
    await proxy.getAddress()
  ) as unknown as ExpiringServiceQualityOracle

  // Set the validity period after initialization
  // First grant operator role to governor so they can set the validity period
  await expiringServiceQualityOracle.connect(governor).grantOperatorRole(governor.address)
  await expiringServiceQualityOracle.connect(governor).setValidityPeriod(validityPeriod)
  // Now revoke the operator role from governor to ensure tests start with clean state
  await expiringServiceQualityOracle.connect(governor).revokeOperatorRole(governor.address)

  return expiringServiceQualityOracle
}
