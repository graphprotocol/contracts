import hre from 'hardhat'
import data from './data.json'
import { ethers } from 'ethers'
import { confirm } from '@graphprotocol/sdk'

async function main() {
  const graph = hre.graph()
  const deployer = await graph.getDeployer()

  // Get the staking and token contracts
  const stakingContract = graph.l2.contracts.L2Staking
  const tokenContract = graph.l2.contracts.L2GraphToken

  // Calculate the total amount of tokens to approve
  const totalTokensToCollect = data.allocations.reduce(
    (acc, allocation) => acc.add(ethers.BigNumber.from(allocation.amount.toString())),
    ethers.BigNumber.from(0),
  )

  // Output transaction details
  console.log(`This script will execute ${data.allocations.length} transactions.`)
  console.log(`Total tokens to collect: ${ethers.utils.formatEther(totalTokensToCollect)} tokens`)

  // Ask for confirmation before continuing
  if (!(await confirm(
    `Are you sure you want to proceed with ${data.allocations.length} transactions, collecting ${ethers.utils.formatEther(totalTokensToCollect)} tokens?`,
    false,
  ))) {
    console.log('Transaction cancelled.')
    return
  }

  // Approve tokens for the staking contract
  console.log(`Approving ${ethers.utils.formatEther(totalTokensToCollect)} tokens for staking contract...`)
  try {
    const approveTx = await tokenContract.connect(deployer).approve(
      stakingContract.address,
      totalTokensToCollect,
    )
    const approveReceipt = await approveTx.wait()

    if (approveReceipt.status === 1) {
      console.log(`✔ Approval succeeded! Transaction hash: ${approveTx.hash}`)
    } else {
      console.log(`✖ Approval failed!`)
      return
    }
  } catch (error) {
    console.log(`✖ Error during approval:`, error)
    return
  }

  // Execute the collect transactions
  for (const allocation of data.allocations) {
    console.log(`Collecting for allocation ${allocation.allocation_id}...`)

    try {
      const tx = await stakingContract.connect(deployer).collect(
        allocation.amount.toString(),
        allocation.allocation_id,
      )
      const receipt = await tx.wait()

      if (receipt.status === 1) {
        console.log(`   ✔ Collection succeeded for ${allocation.allocation_id}! Transaction hash: ${tx.hash}`)
      } else {
        console.log(`   ✖ Collection failed for ${allocation.allocation_id}`)
      }
    } catch (error) {
      console.log(`   ✖ Error collecting for ${allocation.allocation_id}:`, error)
    }
  }
}

main().catch((error) => {
  console.error(error)
  process.exitCode = 1
})
