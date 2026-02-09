// scripts/compare-creation.ts
import fs from 'node:fs'

import { Interface } from 'ethers'
import { ethers } from 'hardhat'

async function main() {
  const fqn = process.env.FQN // "contracts/payments/GraphPayments.sol:GraphPayments";
  const txHash = process.env.TX! // deployment tx hash
  const args = process.env.ARGS ? JSON.parse(process.env.ARGS) : [] // '[arg1,arg2,...]'

  if (!fqn || !txHash) {
    console.error('❌ FQN or TX is not set')
    process.exit(1)
  }

  const artifactPath = `build/contracts/${fqn.replace(/:/g, '/')}.json`
  const artifact = JSON.parse(fs.readFileSync(artifactPath, 'utf8'))

  // Creation (init) code is artifact.bytecode with libraries linked + encoded ctor args appended.
  if (artifact.bytecode.includes('__$')) {
    console.error('Unlinked libraries in creation bytecode.')
    process.exit(1)
  }

  const iface = new Interface(artifact.abi)
  const encodedArgs = iface.encodeDeploy(args)
  const compiledInit = (artifact.bytecode + encodedArgs.slice(2)).toLowerCase()

  const tx = await ethers.provider.getTransaction(txHash)
  if (!tx) {
    console.error('❌ Transaction not found')
    process.exit(1)
  }
  const deployedInit = (tx.data || '').toLowerCase()

  console.log('compiled init len:', compiledInit.length, ' deployed init len:', deployedInit.length)
  console.log(
    compiledInit === deployedInit
      ? '✅ Creation bytecode matches.'
      : '❌ Creation bytecode mismatch (ctor args / linking / settings).',
  )
}
main().catch((e) => {
  console.error(e)
  process.exit(1)
})
