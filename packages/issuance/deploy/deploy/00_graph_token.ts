import type { HardhatRuntimeEnvironment } from 'hardhat/types'
import type { DeployFunction } from 'hardhat-deploy/types'

/**
 * Ensure GraphToken deployment exists for local testing
 *
 * This script only runs on local networks (hardhat, localhost) to provide
 * a GraphToken deployment reference for testing. On real networks, GraphToken
 * must be provided via deployments/<network>/GraphToken.json manually.
 *
 * For test networks, we check if GraphToken already exists in deployments.
 * If not, we create a placeholder deployment record that tests can use.
 */
const func: DeployFunction = async (hre: HardhatRuntimeEnvironment) => {
  const { deployments } = hre
  const { log, getOrNull, save } = deployments

  // Only run on test networks
  const networkName = hre.network.name
  if (networkName !== 'hardhat' && networkName !== 'localhost') {
    log('Skipping GraphToken setup on', networkName)
    log('Ensure deployments/' + networkName + '/GraphToken.json exists with real GraphToken address')
    return
  }

  // Check if GraphToken deployment already exists
  const existing = await getOrNull('GraphToken')
  if (existing) {
    log('GraphToken deployment found at:', existing.address)
    return
  }

  // Create a placeholder deployment record for testing
  // This simulates a pre-existing GraphToken deployment
  const mockAddress = '0x5FbDB2315678afecb367f032d93F642f64180aa3'

  await save('GraphToken', {
    address: mockAddress,
    abi: [],
  })

  log('Created GraphToken deployment record for testing at:', mockAddress)
  log('Note: This is a placeholder address for local testing only')
}

func.tags = ['graph-token', 'issuance']
// This should run first, before any other issuance contracts
func.id = '00_graph_token'

export default func
