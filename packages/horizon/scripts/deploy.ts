import hre, { ignition } from 'hardhat'
import { IgnitionHelper } from 'hardhat-graph-protocol/sdk'

import DeployModule from '../ignition/modules/deploy'

async function main() {
  const HorizonConfig = IgnitionHelper.loadConfig('./ignition/configs/', 'horizon', hre.network.name)

  // Deploy Horizon
  const deployment = await ignition.deploy(DeployModule, {
    displayUi: true,
    parameters: HorizonConfig,
  })

  IgnitionHelper.saveAddressBook(deployment, hre.network.config.chainId)
}

main().catch((error) => {
  console.error(error)
  process.exit(1)
})
