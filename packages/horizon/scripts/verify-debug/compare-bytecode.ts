// scripts/compare-bytecode.ts
import fs from 'node:fs'

import { ethers } from 'hardhat'

function stripCborRuntime(code: string) {
  // Deployed runtime bytecode ends with a CBOR-encoded metadata whose byte length is stored in the final 2 bytes.
  // Remove that trailer so metadataHash differences don't confuse us.
  if (!code || code.length < 4) return code
  const lenHex = code.slice(-4)
  const len = parseInt(lenHex, 16)
  const trailerLen = len * 2 + 4 // hex chars
  if (trailerLen > 0 && trailerLen < code.length) return code.slice(0, code.length - trailerLen)
  return code
}

async function main() {
  const address = process.env.ADDRESS! // target deployed address
  const fqn = process.env.FQN // "contracts/payments/GraphPayments.sol:GraphPayments";

  if (!fqn || !address) {
    console.error('❌ FQN or ADDRESS is not set')
    process.exit(1)
  }

  const artifactPath = `build/contracts/${fqn.replace(/:/g, '/')}.json`
  const artifact = JSON.parse(fs.readFileSync(artifactPath, 'utf8'))

  const onchain = await ethers.provider.getCode(address)
  const onchainStripped = stripCborRuntime(onchain.toLowerCase())

  // Hardhat artifact has both creation bytecode (bytecode) and deployed runtime (deployedBytecode)
  const compiled = artifact.deployedBytecode.toLowerCase()

  // If there are link placeholders like __$abcd$__, the bytecode is not linked:
  if (compiled.includes('__$')) {
    console.error('⚠️ Artifact has unlinked libraries. Link addresses must match deployment.')
    process.exit(1)
  }

  const compiledStripped = stripCborRuntime(compiled)

  console.log('On-chain (stripped) prefix:', onchainStripped.slice(0, 20), '…', onchainStripped.length)
  console.log('Compiled (stripped)   pref:', compiledStripped.slice(0, 20), '…', compiledStripped.length)

  if (onchainStripped === compiledStripped) {
    console.log('✅ Runtime matches (ignoring metadata). Problem likely in constructor args / creation code.')
  } else if (onchainStripped.startsWith(compiledStripped) || compiledStripped.startsWith(onchainStripped)) {
    console.log('✅ Prefix matches. Differences only in metadata. Check metadata.bytecodeHash and solc version.')
  } else {
    console.error('❌ Runtime mismatch. Check solc settings, viaIR, optimizer, libraries, or immutables.')
    process.exit(1)
  }
}
main().catch((e) => {
  console.error(e)
  process.exit(1)
})
