// scripts/read-immutables-from-event.ts
import { ethers } from 'hardhat'

const ABI = [
  'event GraphDirectoryInitialized(address indexed graphToken,address indexed graphStaking,address graphPayments,address graphEscrow,address indexed graphController,address graphEpochManager,address graphRewardsManager,address graphTokenGateway,address graphProxyAdmin,address graphCuration)',
]

async function main() {
  const address = process.env.ADDRESS! // implementation address
  const txHash = process.env.TX! // deployment tx hash

  const iface = new ethers.Interface(ABI)
  const receipt = await ethers.provider.getTransactionReceipt(txHash)

  if (!receipt) {
    console.error('❌ Transaction receipt not found')
    process.exit(1)
  }

  const ev = receipt.logs
    .map((l) => {
      try {
        return iface.parseLog(l)
      } catch {
        return null
      }
    })
    .find((p) => p && p.name === 'GraphDirectoryInitialized')

  if (!ev) {
    console.error('GraphDirectoryInitialized not found in that tx receipt.')
    process.exit(1)
  }

  const [
    graphToken,
    graphStaking,
    graphPayments,
    graphEscrow,
    graphController,
    graphEpochManager,
    graphRewardsManager,
    graphTokenGateway,
    graphProxyAdmin,
    graphCuration,
  ] = ev.args as any[]

  console.log({
    address,
    graphToken,
    graphStaking,
    graphPayments,
    graphEscrow,
    graphController,
    graphEpochManager,
    graphRewardsManager,
    graphTokenGateway,
    graphProxyAdmin,
    graphCuration,
  })
}

main().catch((e) => {
  console.error(e)
  process.exit(1)
})
