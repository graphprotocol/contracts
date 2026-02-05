import { createPublicClient, http } from 'viem'
import { computeBytecodeHash } from '../lib/bytecode-utils.js'
import { loadSubgraphServiceArtifact } from '../lib/artifact-loaders.js'

async function main() {
  console.log('\n📋 Investigating Deploy "Unchanged" Message\n')

  // The deploy script checks env.getOrNull('SubgraphService_Implementation')
  // But rocketh state is in-memory during deploy runs
  // We can't easily check that without running deploy

  // What we CAN check is:
  // 1. If sync step would have synced the implementation
  // 2. The actual bytecode hashes

  const artifact = loadSubgraphServiceArtifact('SubgraphService')
  const localHash = computeBytecodeHash(artifact.deployedBytecode ?? '0x')

  console.log('Local artifact bytecode hash:', localHash)
  console.log('\n⚠️  The issue:')
  console.log('1. Sync shows "code changed" because address book has different/missing hash')
  console.log('2. Deploy says "unchanged" - this suggests rocketh has the implementation')
  console.log('3. But local bytecode IS different from on-chain')
  console.log('\nThis means deploy will NOT deploy the new implementation!')
  console.log('The local changes will be ignored.\n')
}

main().catch(console.error)
