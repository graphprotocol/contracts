import { Wallet } from 'ethers'
import hre from 'hardhat'

async function main() {
  const graph = hre.graph()
  const arbitratorPrivateKey = process.env.ARBITRATOR_PRIVATE_KEY
  const arbitrator = new Wallet(arbitratorPrivateKey, graph.provider)
  console.log('Arbitrator:', arbitrator.address)

  const disputeId = '0x35e6e68aa71ee59cb710d8005563d63d644f11f2eee879eca9bc22f523c9fade'
  console.log('Dispute ID:', disputeId)

  // Accept dispute
  await graph.contracts.DisputeManager.connect(arbitrator).acceptDispute(disputeId)
}

main().catch((error) => {
  console.error(error)
  process.exitCode = 1
})
