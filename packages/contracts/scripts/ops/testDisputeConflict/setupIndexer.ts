import { allocateFrom, deriveChannelKey, randomHexBytes, stake, toGRT } from '@graphprotocol/sdk'
import hre, { ethers } from 'hardhat'

async function main() {
  const graph = hre.graph()
  const deployer = await graph.getDeployer()
  const [indexer] = await graph.getTestAccounts()

  console.log('Deployer:', deployer.address)
  console.log('Indexer:', indexer.address)

  const receipt = {
    requestCID: '0x8bec406793c8e1c5d4bd4e059833e95b7a9aeed6a118cbe335a79735836f9ff7',
    responseCID: '0xbdfc41643b5ff8d55f6cdb50f05575e1fdf177fa54d98cae1b9c76d8b360ff57',
    subgraphDeploymentID: '0xa3bfbfc6f53fd8a61b78e0b9a90c7fbe9ff290cba87b045bc476137fb2963cf9',
  }

  console.log('Receipt requestCID:', receipt.requestCID)
  console.log('Receipt response CID:', receipt.responseCID)
  console.log('Receipt subgraphDeploymentID:', receipt.subgraphDeploymentID)

  const indexerChannelKey = deriveChannelKey()
  console.log('Indexer channel key:', indexerChannelKey.address)
  console.log('Indexer channel key privKey:', indexerChannelKey.privKey)

  // Set up indexer
  await deployer.sendTransaction({ value: toGRT('0.05'), to: indexer.address })
  await graph.contracts.GraphToken.connect(deployer).transfer(indexer.address, toGRT('100000'))
  await stake(graph.contracts, indexer, { amount: toGRT('100000') })
  await allocateFrom(graph.contracts, indexer, {
    channelKey: indexerChannelKey,
    amount: toGRT('100000'),
    subgraphDeploymentID: receipt.subgraphDeploymentID,
  })
}

main().catch((error) => {
  console.error(error)
  process.exitCode = 1
})
