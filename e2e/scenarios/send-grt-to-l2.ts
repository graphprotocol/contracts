// ### Scenario description ###
// Bridge action > Bridge GRT tokens from L1 to L2
// This scenario will bridge GRT tokens from L1 to L2. See fixtures for details.
// Run with:
//    npx hardhat e2e:scenario send-grt-to-l2 --network <network> --graph-config config/graph.<network>.yml

import hre from 'hardhat'
import { TASK_BRIDGE_TO_L2 } from '../../tasks/bridge/to-l2'
import { getGraphOptsFromArgv } from './lib/helpers'
import { getBridgeFixture } from './fixtures/bridge'

async function main() {
  const graphOpts = getGraphOptsFromArgv()
  const graph = hre.graph(graphOpts)

  const l1Deployer = await graph.l1.getDeployer()
  const l2Deployer = await graph.l2.getDeployer()

  const bridgeFixture = getBridgeFixture([l1Deployer, l2Deployer])

  // == Send GRT to L2 accounts
  for (const account of bridgeFixture.accountsToFund) {
    await hre.run(TASK_BRIDGE_TO_L2, {
      ...graphOpts,
      amount: account.amount.toString(),
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
