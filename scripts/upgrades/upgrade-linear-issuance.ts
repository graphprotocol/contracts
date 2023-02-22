import hre from 'hardhat'
import '@nomiclabs/hardhat-ethers'
import { BigNumber, providers } from 'ethers'
import PQueue from 'p-queue'
import { ActiveAllocation, getActiveAllocations, getSignaledSubgraphs } from './queries'
import { deployContract, waitTransaction, toBN, toGRT } from '../../cli/network'
import { aggregate } from '../../cli/multicall'
import { chunkify } from '../../cli/helpers'
import { RewardsManager } from '../../build/types/RewardsManager'

const { ethers } = hre

// TODO: add notes about the why of certain things and caveats

// global values
const INITIAL_ETH_BALANCE = hre.ethers.utils.parseEther('1000').toHexString()
const L1_DEPLOYER_ADDRESS = '0xE04FcE05E9B8d21521bd1B0f069982c03BD31F76'
const L1_COUNCIL_ADDRESS = '0x48301Fe520f72994d32eAd72E2B6A8447873CF50'
const ISSUANCE_PER_BLOCK = toGRT('100') // '114155251141552511415' // toGRT('124') // TODO: estimate it better
const RPC_CONCURRENCY = 10
const MULTICALL_BATCH_SIZE = 5
const NETWORK_SUBGRAPH = 'graphprotocol/graph-network-mainnet'

async function getAllocationsPendingRewards(
  allos: ActiveAllocation[],
  rewardsManager: RewardsManager,
  blockNumber: number,
): Promise<BigNumber> {
  console.log(`Getting pending rewards at block ${blockNumber}...`)

  // Aggregate pending rewards
  const queue = new PQueue({ concurrency: RPC_CONCURRENCY })
  const batches = chunkify(allos, MULTICALL_BATCH_SIZE)
  let totalPendingIndexingRewards = toBN(0)
  let batchNum = 0

  for (const batchOfAllos of chunkify(allos, MULTICALL_BATCH_SIZE)) {
    const calls = []
    for (const allo of batchOfAllos) {
      const target = rewardsManager.address
      const tx = await rewardsManager.populateTransaction.getRewards(allo.id)
      const callData = tx.data
      calls.push({ target, callData })
    }
    queue.add(async () => {
      batchNum++
      // console.log(
      //   `Aggregate (${calls.length} calls) for block ${blockNumber} and batch ${batchNum}/${batches.length}...`,
      // )
      const [_, results] = await aggregate(calls, rewardsManager.provider, blockNumber)
      const chunkPendingRewards = results
        .map((pendingRewards) => toBN(pendingRewards))
        .reduce((a: BigNumber, b: BigNumber) => a.add(b), toBN(0))
      totalPendingIndexingRewards = totalPendingIndexingRewards.add(chunkPendingRewards)
    })
  }
  await queue.onIdle()

  console.log(`Pending rewards at block ${blockNumber}: ${totalPendingIndexingRewards}`)
  return totalPendingIndexingRewards
}

async function setAccountBalance(
  provider: providers.JsonRpcProvider,
  address: string,
  balance: string,
) {
  return provider.send('anvil_setBalance', [address, balance])
}

function getDarkSubgraphs(items) {
  return items
    .map((item) => {
      return {
        signalledTokens: item.signalledTokens,
        allos: item.indexerAllocations.length,
      }
    })
    .filter((item) => item.signalledTokens != '0' && item.allos === 0)
}

async function main() {
  // TODO: make read address.json with override chain id
  const { contracts, provider } = hre.graph({
    addressBook: 'addresses.json',
    graphConfig: 'config/graph.mainnet.yml',
  })

  // setup roles
  const deployer = await ethers.getImpersonatedSigner(L1_DEPLOYER_ADDRESS)
  const council = await ethers.getImpersonatedSigner(L1_COUNCIL_ADDRESS)

  // fund accounts
  await setAccountBalance(provider, L1_DEPLOYER_ADDRESS, INITIAL_ETH_BALANCE)
  await setAccountBalance(provider, L1_COUNCIL_ADDRESS, INITIAL_ETH_BALANCE)
  console.log(`Deployer: ${L1_DEPLOYER_ADDRESS}`)
  console.log(`Council:  ${L1_COUNCIL_ADDRESS}`)

  // deploy L1 implementations
  const newRewardsManagerImpl = await deployContract('RewardsManager', [], deployer)
  const newL1GraphTokenGatewayImpl = await deployContract('L1GraphTokenGateway', [], deployer)

  // provider node config
  await provider.send('evm_setAutomine', [false])

  // ### batch 1
  // deploy new implementations and start upgrade process
  {
    // upgrade L1 implementations
    console.log('[*] Executing batch 1 (start upgrade)...')
    const tx1 = await contracts.GraphProxyAdmin.connect(council).upgrade(
      contracts.RewardsManager.address,
      newRewardsManagerImpl.contract.address,
    )
    const tx2 = await contracts.GraphProxyAdmin.connect(council).upgrade(
      contracts.L1GraphTokenGateway.address,
      newL1GraphTokenGatewayImpl.contract.address,
    )

    // mine block and wait
    await provider.send('evm_mine', [])
    await Promise.all([tx1, tx2].map((tx) => waitTransaction(council, tx)))
  }

  // ### batch 2
  // accept L2 implementations
  // TODO: L2 actions

  // ### batch 3
  // accrue all signal and upgrade the rewards function
  // ensures the snapshot for rewards is updated right before the issuance formula changes.
  {
    const tx1 = await contracts.GraphProxyAdmin.connect(council).acceptProxy(
      newL1GraphTokenGatewayImpl.contract.address,
      contracts.L1GraphTokenGateway.address,
    )
    console.log(tx1.hash)
    const tx2 = await contracts.RewardsManager.connect(council).updateAccRewardsPerSignal()
    console.log(tx2.hash)
    const tx3 = await contracts.GraphProxyAdmin.connect(council).acceptProxy(
      newRewardsManagerImpl.contract.address,
      contracts.RewardsManager.address,
    )
    console.log(tx3.hash)
    const tx4 = await contracts.RewardsManager.connect(council).setIssuancePerBlock(
      ISSUANCE_PER_BLOCK,
    )
    console.log(tx4.hash)
    console.log('[*] Executing batch 3 (upgrade implementations)...')
    await provider.send('evm_mine', [])
    await Promise.all([tx1, tx2, tx3, tx4].map((tx) => waitTransaction(council, tx)))

    console.log(`Issuance per block is: ${await contracts.RewardsManager.issuancePerBlock()}`)
  }

  // snapshot: get pending rewards before doing ops
  const blockNumber1 = await provider.getBlockNumber()
  console.log(`-> We are at block ${blockNumber1}`)
  console.log('AccRewardsPerSignal:', await contracts.RewardsManager.getAccRewardsPerSignal())

  console.log(`Getting signaled subgraphs in block ${blockNumber1}...`)
  const subgraphs = await getSignaledSubgraphs(NETWORK_SUBGRAPH, blockNumber1)
  console.log(`Found ${subgraphs.length} signaled subgraphs in block ${blockNumber1}`)
  const minimals = getDarkSubgraphs(subgraphs)
  console.log('Subgraphs (len):', minimals.length)
  console.log(
    'Subgraphs (grt):',
    minimals.reduce((a, b) => a + b.signalledTokens / 1e18, 0),
  )
  console.log(
    'Subgraph (grt-total):',
    subgraphs.reduce((a, b) => a + b.signalledTokens / 1e18, 0),
  )

  console.log(`Getting active allocations in block ${blockNumber1}...`)
  const allos = await getActiveAllocations(NETWORK_SUBGRAPH, blockNumber1)
  console.log(`Found ${allos.length} active allocations in block ${blockNumber1}`)

  const pendingRewards1 = await getAllocationsPendingRewards(
    allos,
    contracts.RewardsManager,
    blockNumber1,
  )

  // move forward a few blocks
  for (let i = 0; i < 1; i++) await provider.send('evm_mine', [])

  // snapshot: get pending rewards after doing ops
  const blockNumber2 = await provider.getBlockNumber()
  console.log(`-> We are at block ${blockNumber2}`)
  console.log('AccRewardsPerSignal:', await contracts.RewardsManager.getAccRewardsPerSignal())

  const pendingRewards2 = await getAllocationsPendingRewards(
    allos, // we use same subset of allocations, no new were created during the simulation
    contracts.RewardsManager,
    blockNumber2,
  )

  // get issuance difference
  const issuanceDiff = pendingRewards2.sub(pendingRewards1)
  const blockDiff = blockNumber2 - blockNumber1
  console.log(`diff is ${issuanceDiff} @ ${blockDiff} blocks`)

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
