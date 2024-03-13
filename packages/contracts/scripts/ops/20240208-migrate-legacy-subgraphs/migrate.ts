import hre from 'hardhat'
import data from './data.json'
import { confirm, subgraphIdToHex } from '@graphprotocol/sdk'
import { BigNumber, ethers } from 'ethers'

async function main() {
  const graph = hre.graph()
  const deployer = await graph.getDeployer()

  // First estimate cost
  const gasEstimate = await data.data.subgraphs.reduce(async (acc, subgraph) => {
    return (await acc).add(
      await graph.contracts.L1GNS.connect(deployer).estimateGas.migrateLegacySubgraph(
        subgraph.owner.id,
        subgraph.subgraphNumber,
        subgraph.metadataHash,
      ),
    )
  }, Promise.resolve(BigNumber.from(0)))
  const gasPrice = await graph.provider.getGasPrice()
  const cost = ethers.utils.formatEther(gasEstimate.mul(gasPrice))

  // Ask for confirmation
  if (
    !(await confirm(
      `This script will migrate ${data.data.subgraphs.length} legacy subgraphs, with an approximate cost of ${cost} Ξ. Are you sure you want to continue?`,
      false,
    ))
  )
    return

  // do it
  for (const subgraph of data.data.subgraphs) {
    console.log(`Migrating legacy subgraph ${subgraph.owner.id}/${subgraph.subgraphNumber}...`)

    const legacyKey = await graph.contracts.L1GNS.legacySubgraphKeys(subgraphIdToHex(subgraph.id))
    if (legacyKey.account !== ethers.constants.AddressZero) {
      console.log(`  - Already migrated, skipping`)
      continue
    }
    try {
      const tx = await graph.contracts.L1GNS.connect(deployer).migrateLegacySubgraph(
        subgraph.owner.id,
        subgraph.subgraphNumber,
        subgraph.metadataHash,
      )
      const receipt = await tx.wait()
      if (receipt.status == 1) {
        console.log(`   ✔ Migration succeeded!`)
      } else {
        console.log(`   ✖ Migration failed!`)
        console.log(receipt)
      }
    } catch (error) {
      console.log(error)
    }
  }
}

main().catch((error) => {
  console.error(error)
  process.exitCode = 1
})
