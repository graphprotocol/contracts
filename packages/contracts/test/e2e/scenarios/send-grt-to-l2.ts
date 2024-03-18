// ### Scenario description ###
// Bridge action > Bridge GRT tokens from L1 to L2
// This scenario will bridge GRT tokens from L1 to L2. See fixtures for details.
// Run with:
//    npx hardhat e2e:scenario send-grt-to-l2 --network <network> --graph-config config/graph.<network>.yml

import hre from 'hardhat'
import { getBridgeFixture } from './fixtures/bridge'
import { getGREOptsFromArgv } from '@graphprotocol/sdk/gre'
import { ethers } from 'ethers'

async function main() {
  const graphOpts = getGREOptsFromArgv()
  const graph = hre.graph(graphOpts)

  const l1Deployer = await graph.l1.getDeployer()
  const l2Deployer = await graph.l2.getDeployer()

  const bridgeFixture = getBridgeFixture([l1Deployer, l2Deployer])

  // == Send GRT to L2 accounts
  for (const account of bridgeFixture.accountsToFund) {
    await hre.run('bridge:send-to-l2', {
      ...graphOpts,
      amount: ethers.utils.formatEther(account.amount),
      sender: bridgeFixture.funder.address,
      recipient: account.signer.address,
      deploymentFile: bridgeFixture.deploymentFile,
    })
  }
}

// We recommend this pattern to be able to use async/await everywhere
// and properly handle errors.
main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error)
    process.exitCode = 1
  })
