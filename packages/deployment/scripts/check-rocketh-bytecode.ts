import { readFileSync } from 'fs'
import { computeBytecodeHash } from '../lib/bytecode-utils.js'
import { loadSubgraphServiceArtifact } from '../lib/artifact-loaders.js'

async function main() {
  console.log('\n📋 Rocketh vs Local Artifact Comparison\n')

  // Get local artifact
  const artifact = loadSubgraphServiceArtifact('SubgraphService')
  const localHash = computeBytecodeHash(artifact.deployedBytecode ?? '0x')
  console.log('Local artifact hash:', localHash)

  // Check rocketh stored bytecode
  try {
    const rockethPath = '.rocketh/deployments/arbitrumSepolia/SubgraphService_Implementation.json'
    const rockethData = JSON.parse(readFileSync(rockethPath, 'utf-8'))

    if (rockethData.deployedBytecode) {
      const rockethHash = computeBytecodeHash(rockethData.deployedBytecode)
      console.log('Rocketh stored hash:', rockethHash)
      console.log('\nComparison:', localHash === rockethHash ? '✓ MATCH (deploy will skip)' : '✗ DIFFERENT (deploy will redeploy)')
    } else {
      console.log('Rocketh stored hash: (no deployedBytecode)')
    }
  } catch (err) {
    console.log('Rocketh record:', 'not found')
  }
}

main().catch(console.error)
