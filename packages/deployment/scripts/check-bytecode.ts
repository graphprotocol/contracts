import { createPublicClient, http } from 'viem'

import { loadSubgraphServiceArtifact } from '../lib/artifact-loaders.js'
import { computeBytecodeHash } from '../lib/bytecode-utils.js'
import { graph } from '../rocketh/deploy.js'

async function main() {
  const chainId = 421614 // arbitrumSepolia

  // Get address book
  const addressBook = graph.getSubgraphServiceAddressBook(chainId)
  const entry = addressBook.getEntry('SubgraphService')
  const deploymentMetadata = addressBook.getDeploymentMetadata('SubgraphService')

  console.log('\n📋 SubgraphService Bytecode Analysis\n')
  console.log('Proxy address:', entry.address)
  console.log('Current implementation:', entry.implementation)
  console.log('Pending implementation:', entry.pendingImplementation?.address ?? 'none')

  // Get local artifact
  const artifact = loadSubgraphServiceArtifact('SubgraphService')
  const localHash = computeBytecodeHash(artifact.deployedBytecode ?? '0x')
  console.log('\nLocal artifact bytecode hash:', localHash)

  // Get address book stored hash
  console.log('Address book stored hash:', deploymentMetadata?.bytecodeHash ?? '(none)')

  // Get on-chain bytecode
  const client = createPublicClient({
    transport: http('https://sepolia-rollup.arbitrum.io/rpc'),
  })

  const onChainBytecode = await client.getCode({
    address: entry.implementation as `0x${string}`,
  })

  if (onChainBytecode && onChainBytecode !== '0x') {
    const onChainHash = computeBytecodeHash(onChainBytecode)
    console.log('On-chain implementation hash:', onChainHash)

    console.log('\n🔍 Comparison:')
    console.log(
      'Local vs Address Book:',
      localHash === (deploymentMetadata?.bytecodeHash ?? '') ? '✓ MATCH' : '✗ DIFFERENT',
    )
    console.log('Local vs On-chain:', localHash === onChainHash ? '✓ MATCH' : '✗ DIFFERENT')
    console.log(
      'Address Book vs On-chain:',
      (deploymentMetadata?.bytecodeHash ?? '') === onChainHash ? '✓ MATCH' : '✗ DIFFERENT (or missing)',
    )
  }
}

main().catch(console.error)
