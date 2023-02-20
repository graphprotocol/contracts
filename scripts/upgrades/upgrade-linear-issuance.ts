import hre from 'hardhat'
import '@nomiclabs/hardhat-ethers'
import { BigNumber, ContractTransaction, PopulatedTransaction } from 'ethers'
import PQueue from 'p-queue'
import { getActiveAllocations } from './queries'
import { deployContract, waitTransaction, toBN } from '../../cli/network'
import { aggregate, bundle, MULTICALL_ADDR } from '../../cli/multicall'
import { chunkify } from '../../cli/helpers'
import { RewardsManager } from '../../build/types/RewardsManager'

const { ethers } = hre

// global values
const INITIAL_ETH_BALANCE = hre.ethers.utils.parseEther('1000').toHexString()
const L1_DEPLOYER_ADDRESS = '0xE04FcE05E9B8d21521bd1B0f069982c03BD31F76'
const L1_COUNCIL_ADDRESS = '0x48301Fe520f72994d32eAd72E2B6A8447873CF50'
const ISSUANCE_PER_BLOCK = 124 // TODO: estimate it better
const RPC_CONCURRENCY = 4
const MULTICALL_BATCH_SIZE = 500
const NETWORK_SUBGRAPH = 'graphprotocol/graph-network-mainnet'

async function getAllocationsPendingRewards(
  rewardsManager: RewardsManager,
  blockNumber: number,
): Promise<BigNumber> {
  console.log(blockNumber)
  // Get active allocations
  const allos = await getActiveAllocations(NETWORK_SUBGRAPH, blockNumber)

  // Aggregate pending rewards
  const queue = new PQueue({ concurrency: RPC_CONCURRENCY })
  let totalPendingIndexingRewards = toBN(0)

  for (const batchOfAllos of chunkify(allos, MULTICALL_BATCH_SIZE)) {
    const calls = []
    for (const allo of batchOfAllos) {
      const target = rewardsManager.address
      const tx = await rewardsManager.populateTransaction.getRewards(allo.id)
      const callData = tx.data
      calls.push({ target, callData })
    }
    queue.add(async () => {
      const [_, results] = await aggregate(calls, rewardsManager.provider, blockNumber)
      console.log(results)
      const chunkPendingRewards = results
        .map((pendingRewards) => toBN(pendingRewards))
        .reduce((a: BigNumber, b: BigNumber) => a.add(b), toBN(0))
      totalPendingIndexingRewards = totalPendingIndexingRewards.add(chunkPendingRewards)
    })
  }
  await queue.onIdle()

  return totalPendingIndexingRewards
}

async function main() {
  // TODO: make read address.json with override chain id
  const { contracts, provider } = hre.graph({
    addressBook: 'addresses.json',
    graphConfig: 'config/graph.mainnet.yml',
  })

  // roles
  const deployer = await ethers.getImpersonatedSigner(L1_DEPLOYER_ADDRESS)
  const council = await ethers.getImpersonatedSigner(L1_COUNCIL_ADDRESS)

  // fund accounts
  // await setBalance(L1_DEPLOYER_ADDRESS, INITIAL_ETH_BALANCE)
  // await setBalance(L1_COUNCIL_ADDRESS, INITIAL_ETH_BALANCE)

  console.log(`Deployer: ${L1_DEPLOYER_ADDRESS}`)
  console.log(`Council:  ${L1_COUNCIL_ADDRESS}`)

  // provider node config
  await provider.send('evm_setAutomine', [false])

  // ### batch 1
  // deploy L1 implementations
  const newRewardsManagerImpl = await deployContract('RewardsManager', [], deployer)
  const newL1GraphTokenGatewayImpl = await deployContract('L1GraphTokenGateway', [], deployer)

  // upgrade L1 implementations
  console.log('Executing batch 1 (start upgrade)...')
  const batch1: ContractTransaction[] = await Promise.all([
    contracts.GraphProxyAdmin.connect(council).upgrade(
      contracts.RewardsManager.address,
      newRewardsManagerImpl.contract.address,
    ),
    contracts.GraphProxyAdmin.connect(council).upgrade(
      contracts.L1GraphTokenGateway.address,
      newL1GraphTokenGatewayImpl.contract.address,
    ),
  ])
  await provider.send('evm_mine', [])
  await Promise.all(batch1.map((tx) => waitTransaction(council, tx)))

  // ### batch 2
  // << FILL WITH L2 actions >>

  const blockNumber1 = await provider.getBlockNumber()
  console.log(`Getting pending rewards at block ${blockNumber1}...`)
  const pendingRewards1 = await getAllocationsPendingRewards(contracts.RewardsManager, blockNumber1)

  // ### batch 3
  // accept L2 implementations
  // accrue all signal and upgrade the rewards function
  // ensures the snapshot for rewards is updated right before the issuance formula changes.
  const batch3: ContractTransaction[] = await Promise.all([
    contracts.GraphProxyAdmin.connect(council).acceptProxy(
      newL1GraphTokenGatewayImpl.contract.address,
      contracts.L1GraphTokenGateway.address,
    ),
    contracts.RewardsManager.connect(council).updateAccRewardsPerSignal(),
    contracts.GraphProxyAdmin.connect(council).acceptProxy(
      newRewardsManagerImpl.contract.address,
      contracts.RewardsManager.address,
    ),
    contracts.RewardsManager.connect(council).setIssuancePerBlock(ISSUANCE_PER_BLOCK),
  ])
  console.log('Executing batch 3 (upgrade implementations)...')
  await provider.send('evm_mine', [])
  await Promise.all(batch3.map((tx) => waitTransaction(council, tx)))

  console.log(await contracts.RewardsManager.issuancePerBlock())

  const blockNumber2 = await provider.getBlockNumber()
  console.log(`Getting pending rewards at block ${blockNumber2}...`)
  const pendingRewards2 = await getAllocationsPendingRewards(contracts.RewardsManager, blockNumber2)

  console.log(`diff is ${pendingRewards2.sub(pendingRewards1)}`)

  // ### batch 4
  // << FILL WITH L2 actions >>

  // test to move time forward and ensure that the inflation rate makes sense
  // one way to test that is to compare the pending rewards calculation before and after the upgrade

  // should be able to close active allocations and collect indexing rewards
}

main().catch((error) => {
  console.error(error)
  process.exitCode = 1
})
