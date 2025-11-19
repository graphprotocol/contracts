import { ethers } from 'ethers'

async function main() {
  const rpc = process.env.RPC_URL
  const rewardsManager = process.env.REWARDS_MANAGER
  const serviceQualityOracle = process.env.SERVICE_QUALITY_ORACLE
  const issuanceAllocator = process.env.ISSUANCE_ALLOCATOR
  const graphToken = process.env.GRAPH_TOKEN

  if (!rpc) throw new Error('RPC_URL is required')
  if (!rewardsManager) throw new Error('REWARDS_MANAGER is required')
  if (!serviceQualityOracle) throw new Error('SERVICE_QUALITY_ORACLE is required')
  if (!issuanceAllocator) throw new Error('ISSUANCE_ALLOCATOR is required')
  if (!graphToken) throw new Error('GRAPH_TOKEN is required')

  const provider = new ethers.JsonRpcProvider(rpc)

  const rm = new ethers.Contract(
    rewardsManager,
    ['function serviceQualityOracle() view returns (address)', 'function issuanceAllocator() view returns (address)'],
    provider,
  )

  const gt = new ethers.Contract(graphToken, ['function isMinter(address) view returns (bool)'], provider)

  const [sqoActual, iaActual, iaIsMinter] = await Promise.all([
    rm.serviceQualityOracle(),
    rm.issuanceAllocator(),
    gt.isMinter(issuanceAllocator),
  ])

  const errors: string[] = []
  if (sqoActual.toLowerCase() !== serviceQualityOracle.toLowerCase()) {
    errors.push(`RewardsManager.serviceQualityOracle() = ${sqoActual}, expected ${serviceQualityOracle}`)
  }
  if (iaActual.toLowerCase() !== issuanceAllocator.toLowerCase()) {
    errors.push(`RewardsManager.issuanceAllocator() = ${iaActual}, expected ${issuanceAllocator}`)
  }
  if (!iaIsMinter) {
    errors.push(`GraphToken.isMinter(${issuanceAllocator}) = false, expected true`)
  }

  if (errors.length) {
    console.error('Verification failed:')
    for (const e of errors) console.error(` - ${e}`)
    process.exit(1)
  } else {
    console.log('Verification passed: all governance integrations match expected addresses.')
  }
}

main().catch((e) => {
  console.error(e)
  process.exit(1)
})
