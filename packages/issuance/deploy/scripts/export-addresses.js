const fs = require('fs').promises
const path = require('path')
const hre = require('hardhat')

// Export a minimal address-book JSON from hardhat-deploy deployments.
// Usage:
//   pnpm --filter @graphprotocol/issuance-deploy hardhat run scripts/export-addresses.js --network <network>

async function main() {
  const { deployments, network } = hre
  const chainId = network.config.chainId
  if (!chainId) throw new Error('Missing chainId')

  const out = {}

  const pa = await deployments.getOrNull('GraphIssuanceProxyAdmin')
  const ia = await deployments.getOrNull('IssuanceAllocator')
  const iaImpl = await deployments.getOrNull('IssuanceAllocator_Implementation')
  const reo = await deployments.getOrNull('RewardsEligibilityOracle')
  const reoImpl = await deployments.getOrNull('RewardsEligibilityOracle_Implementation')

  const chainMap = {}

  if (ia) {
    chainMap['IssuanceAllocator'] = {
      address: ia.address,
      implementation: iaImpl?.address,
      proxyAdmin: pa?.address,
      proxy: 'transparent',
    }
  }

  if (reo) {
    chainMap['RewardsEligibilityOracle'] = {
      address: reo.address,
      implementation: reoImpl?.address,
      proxyAdmin: pa?.address,
      proxy: 'transparent',
    }
  }

  out[String(chainId)] = chainMap

  const target = path.resolve(process.cwd(), 'addresses.json')
  await fs.writeFile(target, JSON.stringify(out, null, 2))
  console.log(`Wrote ${target}`)
}

main().catch((err) => {
  console.error(err)
  process.exit(1)
})
