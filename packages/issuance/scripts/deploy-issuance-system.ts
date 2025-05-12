import { ethers } from 'hardhat'
import { HardhatEthersSigner } from '@nomicfoundation/hardhat-ethers/signers'
import { Contract } from 'ethers'
import * as fs from 'fs/promises'

// Constants
const DEFAULT_ISSUANCE_PER_BLOCK = ethers.parseEther('120.73') // 120.73 GRT per block
const DEFAULT_VALIDITY_PERIOD = 7 * 24 * 60 * 60 // 7 days in seconds
const PPM = 1_000_000 // Parts per million (100%)

// Contract addresses - these will be populated during deployment
const addresses: Record<string, string> = {
  graphToken: '',
  governor: '',
  proxyAdmin: '',
  issuanceAllocator: '',
  serviceQualityOracle: '',
  expiringServiceQualityOracle: '',
  innovationAllocation: '',
  pilotAllocation: '',
  rewardsManager: ''
}

/**
 * Deploy a proxy contract
 */
async function deployProxy(
  implementation: string,
  admin: string,
  initData: string
): Promise<Contract> {
  // Use the actual GraphProxy contract used in production
  const ProxyFactory = await ethers.getContractFactory('GraphProxy')
  const proxy = await ProxyFactory.deploy(implementation, admin)
  await proxy.waitForDeployment()

  // Get the proxy admin
  const proxyAdminFactory = await ethers.getContractFactory('GraphProxyAdmin')
  const proxyAdmin = proxyAdminFactory.attach(admin)

  // If we have initialization data, use acceptProxyAndCall
  if (initData && initData.length > 0) {
    await proxyAdmin.acceptProxyAndCall(implementation, await proxy.getAddress(), initData)
  } else {
    // Otherwise just accept the upgrade
    await proxyAdmin.acceptProxy(implementation, await proxy.getAddress())
  }

  return proxy
}

/**
 * Deploy the IssuanceAllocator contract
 */
async function deployIssuanceAllocator(
  graphToken: string,
  governor: HardhatEthersSigner,
  issuancePerBlock: bigint = DEFAULT_ISSUANCE_PER_BLOCK
): Promise<Contract> {
  console.log('Deploying IssuanceAllocator...')

  // Deploy implementation
  const IssuanceAllocatorFactory = await ethers.getContractFactory('IssuanceAllocator')
  const issuanceAllocatorImpl = await IssuanceAllocatorFactory.deploy(graphToken)
  await issuanceAllocatorImpl.waitForDeployment()

  console.log(`IssuanceAllocator implementation deployed at: ${await issuanceAllocatorImpl.getAddress()}`)

  // Create initialization data
  const initData = IssuanceAllocatorFactory.interface.encodeFunctionData('initialize', [governor.address])

  // Deploy proxy
  const proxy = await deployProxy(
    await issuanceAllocatorImpl.getAddress(),
    governor.address,
    initData
  )
  await proxy.waitForDeployment()

  console.log(`IssuanceAllocator proxy deployed at: ${await proxy.getAddress()}`)

  // Get contract instance with the proxy address
  const issuanceAllocator = IssuanceAllocatorFactory.attach(await proxy.getAddress())

  // Set issuance per block
  const tx = await issuanceAllocator.connect(governor).setIssuancePerBlock(issuancePerBlock)
  await tx.wait()

  console.log(`IssuanceAllocator issuance per block set to: ${issuancePerBlock}`)

  return issuanceAllocator
}

/**
 * Deploy the ServiceQualityOracle contract
 */
async function deployServiceQualityOracle(
  graphToken: string,
  governor: HardhatEthersSigner
): Promise<Contract> {
  console.log('Deploying ServiceQualityOracle...')

  // Deploy implementation
  const ServiceQualityOracleFactory = await ethers.getContractFactory('ServiceQualityOracle')
  const serviceQualityOracleImpl = await ServiceQualityOracleFactory.deploy(graphToken)
  await serviceQualityOracleImpl.waitForDeployment()

  console.log(`ServiceQualityOracle implementation deployed at: ${await serviceQualityOracleImpl.getAddress()}`)

  // Create initialization data
  const initData = ServiceQualityOracleFactory.interface.encodeFunctionData('initialize', [governor.address])

  // Deploy proxy
  const proxy = await deployProxy(
    await serviceQualityOracleImpl.getAddress(),
    governor.address,
    initData
  )
  await proxy.waitForDeployment()

  console.log(`ServiceQualityOracle proxy deployed at: ${await proxy.getAddress()}`)

  // Get contract instance with the proxy address
  return ServiceQualityOracleFactory.attach(await proxy.getAddress())
}

/**
 * Deploy the ExpiringServiceQualityOracle contract
 */
async function deployExpiringServiceQualityOracle(
  graphToken: string,
  governor: HardhatEthersSigner,
  validityPeriod: number = DEFAULT_VALIDITY_PERIOD
): Promise<Contract> {
  console.log('Deploying ExpiringServiceQualityOracle...')

  // Deploy implementation
  const ExpiringServiceQualityOracleFactory = await ethers.getContractFactory('ExpiringServiceQualityOracle')
  const expiringServiceQualityOracleImpl = await ExpiringServiceQualityOracleFactory.deploy(graphToken)
  await expiringServiceQualityOracleImpl.waitForDeployment()

  console.log(`ExpiringServiceQualityOracle implementation deployed at: ${await expiringServiceQualityOracleImpl.getAddress()}`)

  // Create initialization data
  const initData = ExpiringServiceQualityOracleFactory.interface.encodeFunctionData('initialize', [governor.address])

  // Deploy proxy
  const proxy = await deployProxy(
    await expiringServiceQualityOracleImpl.getAddress(),
    governor.address,
    initData
  )
  await proxy.waitForDeployment()

  console.log(`ExpiringServiceQualityOracle proxy deployed at: ${await proxy.getAddress()}`)

  // Get contract instance with the proxy address
  const expiringServiceQualityOracle = ExpiringServiceQualityOracleFactory.attach(await proxy.getAddress())

  // Set validity period
  const tx = await expiringServiceQualityOracle.connect(governor).setValidityPeriod(validityPeriod)
  await tx.wait()

  console.log(`ExpiringServiceQualityOracle validity period set to: ${validityPeriod} seconds`)

  return expiringServiceQualityOracle
}

/**
 * Deploy a DirectAllocation contract
 */
async function deployDirectAllocation(
  graphToken: string,
  governor: HardhatEthersSigner,
  name: string
): Promise<Contract> {
  console.log(`Deploying DirectAllocation (${name})...`)

  // Deploy implementation
  const DirectAllocationFactory = await ethers.getContractFactory('DirectAllocation')
  const directAllocationImpl = await DirectAllocationFactory.deploy(graphToken)
  await directAllocationImpl.waitForDeployment()

  console.log(`DirectAllocation (${name}) implementation deployed at: ${await directAllocationImpl.getAddress()}`)

  // Create initialization data
  const initData = DirectAllocationFactory.interface.encodeFunctionData('initialize', [governor.address])

  // Deploy proxy
  const proxy = await deployProxy(
    await directAllocationImpl.getAddress(),
    governor.address,
    initData
  )
  await proxy.waitForDeployment()

  console.log(`DirectAllocation (${name}) proxy deployed at: ${await proxy.getAddress()}`)

  // Get contract instance with the proxy address
  return DirectAllocationFactory.attach(await proxy.getAddress())
}

/**
 * Get the existing GraphProxyAdmin contract
 */
async function getGraphProxyAdmin(): Promise<Contract> {
  console.log('Getting existing GraphProxyAdmin...')

  // Get the address book to find the GraphProxyAdmin address
  const addressBookPath = process.env.ADDRESS_BOOK || 'addresses.json'
  const addressBook = JSON.parse(await fs.readFile(addressBookPath, 'utf8'))

  // Get the chain ID
  const chainId = (await ethers.provider.getNetwork()).chainId.toString()

  // Get the GraphProxyAdmin address
  const proxyAdminAddress = addressBook[chainId]?.GraphProxyAdmin?.address

  if (!proxyAdminAddress) {
    throw new Error(`GraphProxyAdmin not found in address book for chain ID ${chainId}`)
  }

  console.log(`Using existing GraphProxyAdmin at: ${proxyAdminAddress}`)

  // Get the GraphProxyAdmin contract
  const GraphProxyAdminFactory = await ethers.getContractFactory('GraphProxyAdmin')
  return GraphProxyAdminFactory.attach(proxyAdminAddress)
}

/**
 * Main deployment function
 */
async function main() {
  const [deployer] = await ethers.getSigners()
  console.log(`Deploying contracts with account: ${deployer.address}`)

  // Get GraphToken address from environment or use a default for testing
  const graphTokenAddress = process.env.GRAPH_TOKEN_ADDRESS || '0xc944E90C64B2c07662A292be6244BDf05Cda44a7'
  addresses.graphToken = graphTokenAddress
  addresses.governor = deployer.address

  console.log(`Using GraphToken address: ${graphTokenAddress}`)

  // Get the existing GraphProxyAdmin
  const proxyAdmin = await getGraphProxyAdmin()
  addresses.proxyAdmin = await proxyAdmin.getAddress()

  // Deploy IssuanceAllocator
  const issuanceAllocator = await deployIssuanceAllocator(graphTokenAddress, deployer)
  addresses.issuanceAllocator = await issuanceAllocator.getAddress()

  // Deploy ServiceQualityOracle
  const serviceQualityOracle = await deployServiceQualityOracle(graphTokenAddress, deployer)
  addresses.serviceQualityOracle = await serviceQualityOracle.getAddress()

  // Deploy ExpiringServiceQualityOracle
  const expiringServiceQualityOracle = await deployExpiringServiceQualityOracle(graphTokenAddress, deployer)
  addresses.expiringServiceQualityOracle = await expiringServiceQualityOracle.getAddress()

  // Deploy DirectAllocation for Innovation
  const innovationAllocation = await deployDirectAllocation(graphTokenAddress, deployer, 'Innovation')
  addresses.innovationAllocation = await innovationAllocation.getAddress()

  // Deploy DirectAllocation for Pilot
  const pilotAllocation = await deployDirectAllocation(graphTokenAddress, deployer, 'Pilot')
  addresses.pilotAllocation = await pilotAllocation.getAddress()

  console.log('Deployment completed successfully!')
  console.log('Contract addresses:', addresses)

  return addresses
}

// Execute the script
if (require.main === module) {
  main()
    .then(() => process.exit(0))
    .catch((error) => {
      console.error(error)
      process.exit(1)
    })
}

export default main
