import hre from 'hardhat'
import '@nomiclabs/hardhat-ethers'
import { providers } from 'ethers'
import { getActiveAllocations, getSignaledSubgraphs } from './queries'
import { deployContract, waitTransaction, toGRT } from '../../cli/network'
import { deriveChannelKey, randomAddress } from '../../test/lib/testHelpers'

const { ethers } = hre

// TODO: add notes about the why of certain things and caveats

// global values
const INITIAL_ETH_BALANCE = hre.ethers.utils.parseEther('1000').toHexString()
const L1_DEPLOYER_ADDRESS = '0xE04FcE05E9B8d21521bd1B0f069982c03BD31F76'
const L1_COUNCIL_ADDRESS = '0x48301Fe520f72994d32eAd72E2B6A8447873CF50'
const RPC_CONCURRENCY = 10
const MULTICALL_BATCH_SIZE = 5
const NETWORK_SUBGRAPH = 'graphprotocol/graph-network-mainnet'

async function setAccountBalance(
  provider: providers.JsonRpcProvider,
  address: string,
  balance: string,
) {
  return provider.send('anvil_setBalance', [address, balance])
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
  const newL1GNSImpl = await deployContract('L1GNS', [], deployer)
  const newL1CurationImpl = await deployContract('Curation', [], deployer)

  // provider node config
  await provider.send('evm_setAutomine', [false])

  // ### batch 2
  // deploy new implementations and upgrade
  {
    console.log('[*] Executing batch 2 (L1 GNS Transfer Tools)...')

    // upgrade implementations
    const tx1 = await contracts.GraphProxyAdmin.connect(council).upgrade(
      contracts.GNS.address,
      newL1GNSImpl.contract.address,
    )
    const tx2 = await contracts.GraphProxyAdmin.connect(council).upgrade(
      contracts.Curation.address,
      newL1CurationImpl.contract.address,
    )
    const tx3 = await contracts.GraphProxyAdmin.connect(council).acceptProxy(
      newL1GNSImpl.contract.address,
      contracts.GNS.address,
    )
    const tx4 = await contracts.GraphProxyAdmin.connect(council).acceptProxy(
      newL1CurationImpl.contract.address,
      contracts.Curation.address,
    )

    // set L2 counterparty
    const l2GNSAddress = randomAddress() // TODO: works as long as we only care about testing L1 side
    const tx5 = await contracts.GNS.setCounterpartGNSAddress(l2GNSAddress)

    // set bridge allowlist
    const tx6 = await contracts.L1GraphTokenGateway.addToCallhookAllowlist(contracts.GNS.address)

    // mine block and wait
    await provider.send('evm_mine', [])
    await Promise.all([tx1, tx2, tx3, tx4, tx5, tx6].map((tx) => waitTransaction(council, tx)))
  }

  // ### tests
  // migrate one subgraph
  {
    const subgraphID = '' // TODO:  fetch from network subgraph
    const subgraphOwnerAddress = '' // TODO: get subgraph owner from above
    const curatorAddress = '' // TODO: get owner from above
    const curator = await ethers.getImpersonatedSigner(curatorAddress)
    await contracts.L1GNS.connect(subgraphOwnerAddress).sendSubgraphToL2(
      subgraphID,
      subgraphOwnerAddress,
      0,
      0,
      0,
    ) // TODO: fill gas values

    await contracts.L1GNS.connect(curator).sendCuratorBalanceToBeneficiaryOnL2(
      subgraphID,
      curatorAddress,
      0,
      0,
      0,
    ) // TODO: fill gas values
  }
}

main().catch((error) => {
  console.error(error)
  process.exitCode = 1
})
