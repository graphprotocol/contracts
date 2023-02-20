import hre from 'hardhat'
import '@nomiclabs/hardhat-ethers'
import { PopulatedTransaction } from 'ethers'
import { deployContract, toBN } from '../../cli/network'

const { ethers } = hre

// global values
const L1_DEPLOYER_ADDRESS = '0xE04FcE05E9B8d21521bd1B0f069982c03BD31F76'
const L1_COUNCIL_ADDRESS = '0x48301Fe520f72994d32eAd72E2B6A8447873CF50'

async function main() {
  // TODO: make read address.json with override chain id
  const { contracts, provider } = hre.graph({
    addressBook: 'addresses.json',
    graphConfig: 'config/graph.mainnet.yml',
  })

  // roles
  const deployer = await ethers.getSigner(L1_DEPLOYER_ADDRESS)
  const council = await ethers.getSigner(L1_COUNCIL_ADDRESS)
  console.log(`Deployer: ${L1_DEPLOYER_ADDRESS}`)
  console.log(`Council:  ${L1_COUNCIL_ADDRESS}`)

  // ### batch 1
  // deploy L1 implementations
  const newRewardsManagerImpl = await deployContract('RewardsManager', [], deployer)
  const newL1GraphTokenGatewayImpl = await deployContract('L1GraphTokenGateway', [], deployer)

  // upgrade L1 implementations
  console.log('Executing batch 1 (start upgrade)...')
  const batch1: PopulatedTransaction[] = await Promise.all([
    contracts.GraphProxyAdmin.connect(council).populateTransaction.upgrade(
      contracts.RewardsManager.address,
      newRewardsManagerImpl.contract.address,
    ),
    contracts.GraphProxyAdmin.connect(council).populateTransaction.upgrade(
      contracts.L1GraphTokenGateway.address,
      newL1GraphTokenGatewayImpl.contract.address,
    ),
  ])
  await provider.send('tenderly_simulateBundle', [
    batch1.map((tx) => {
      return {
        from: tx.from,
        to: tx.to,
        data: tx.data,
      }
    }),
  ])
}

main().catch((error) => {
  console.error(error)
  process.exitCode = 1
})
