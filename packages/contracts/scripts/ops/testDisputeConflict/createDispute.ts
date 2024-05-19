import {
  GraphChainId,
  buildAttestation,
  encodeAttestation,
  randomHexBytes,
} from '@graphprotocol/sdk'
import hre from 'hardhat'

async function main() {
  const graph = hre.graph()
  const deployer = await graph.getDeployer()
  const [indexer] = await graph.getTestAccounts()
  const indexerChannelPrivKey = '0x82226c70efbe0d9525a5f9dc85c29b11fed1f46798a416b7626e21fdd6518d08'

  console.log('Deployer:', deployer.address)
  console.log('Indexer:', indexer.address)

  const receipt = {
    requestCID: '0x8bec406793c8e1c5d4bd4e059833e95b7a9aeed6a118cbe335a79735836f9ff7',
    responseCID: '0xbdfc41643b5ff8d55f6cdb50f05575e1fdf177fa54d98cae1b9c76d8b360ff57',
    subgraphDeploymentID: '0xa3bfbfc6f53fd8a61b78e0b9a90c7fbe9ff290cba87b045bc476137fb2963cf9',
  }
  const receipt2 = { ...receipt, responseCID: randomHexBytes() }

  const attestation1 = await buildAttestation(
    receipt,
    indexerChannelPrivKey,
    graph.contracts.DisputeManager.address,
    graph.chainId as GraphChainId,
  )
  const attestation2 = await buildAttestation(
    receipt2,
    indexerChannelPrivKey,
    graph.contracts.DisputeManager.address,
    graph.chainId as GraphChainId,
  )

  console.log('Attestation 1:', attestation1)
  console.log('Attestation 2:', attestation2)

  // Create dispute
  await graph.contracts.DisputeManager.connect(deployer).createQueryDisputeConflict(
    encodeAttestation(attestation1),
    encodeAttestation(attestation2),
  )
}

main().catch((error) => {
  console.error(error)
  process.exitCode = 1
})
