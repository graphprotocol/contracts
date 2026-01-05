import { promises as fs } from 'fs'
import hre from 'hardhat'
import path from 'path'

// Export a minimal address-book JSON from hardhat-deploy deployments.
// This is a compatibility layer for any consumers expecting an addresses.json file.
//
// Usage:
//   pnpm --filter @graphprotocol/issuance-deploy hardhat run scripts/export-addresses.ts --network <network>

async function main() {
  const { deployments, network } = hre as any
  const chainId = network.config.chainId
  if (!chainId) throw new Error('Missing chainId')

  const out: Record<string, unknown> = {}

  const pa = await deployments.getOrNull('GraphIssuanceProxyAdmin')
  const ia = await deployments.getOrNull('IssuanceAllocator')
  const iaImpl = await deployments.getOrNull('IssuanceAllocator_Implementation')
  const pilot = await deployments.getOrNull('PilotAllocation')
  const pilotImpl = await deployments.getOrNull('PilotAllocation_Implementation')
  const reo = await deployments.getOrNull('RewardsEligibilityOracle')
  const reoImpl = await deployments.getOrNull('RewardsEligibilityOracle_Implementation')

  const chainMap: Record<string, unknown> = {}

  if (pa) {
    chainMap['GraphIssuanceProxyAdmin'] = {
      address: pa.address,
    }
  }

  if (ia) {
    chainMap['IssuanceAllocator'] = {
      address: ia.address,
      implementation: iaImpl?.address,
      proxyAdmin: pa?.address,
      proxy: 'transparent',
    }
  }

  if (pilot) {
    chainMap['PilotAllocation'] = {
      address: pilot.address,
      implementation: pilotImpl?.address,
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
