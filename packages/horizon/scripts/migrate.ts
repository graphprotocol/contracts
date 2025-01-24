import hre, { ignition } from 'hardhat'
import { IgnitionHelper } from 'hardhat-graph-protocol/sdk'

import MigrateModule from '../ignition/modules/migrate'

async function main() {
  console.log(getHorizonBanner())
  const HorizonMigrateConfig = IgnitionHelper.loadConfig('../ignition/configs/', 'horizon-migrate', hre.network.name)

  const signers = await hre.ethers.getSigners()
  const deployer = signers[0]
  const governor = signers[1]

  console.log('Using deployer account:', deployer.address)
  console.log('Using governor account:', governor.address)

  const deployment = await ignition.deploy(MigrateModule, {
    displayUi: true,
    parameters: HorizonMigrateConfig,
    deploymentId: `horizon-${hre.network.name}`,
  })

  IgnitionHelper.saveAddressBook(deployment, hre.network.config.chainId)

  console.log('Migration successful! 🎉')
}

main().catch((error) => {
  console.error(error)
  process.exit(1)
})

function getHorizonBanner(): string {
  return `
██╗  ██╗ ██████╗ ██████╗ ██╗███████╗ ██████╗ ███╗   ██╗
██║  ██║██╔═══██╗██╔══██╗██║╚══███╔╝██╔═══██╗████╗  ██║
███████║██║   ██║██████╔╝██║  ███╔╝ ██║   ██║██╔██╗ ██║
██╔══██║██║   ██║██╔══██╗██║ ███╔╝  ██║   ██║██║╚██╗██║
██║  ██║╚██████╔╝██║  ██║██║███████╗╚██████╔╝██║ ╚████║
╚═╝  ╚═╝ ╚═════╝ ╚═╝  ╚═╝╚═╝╚══════╝ ╚═════╝ ╚═╝  ╚═══╝
                                                        
██╗   ██╗██████╗  ██████╗ ██████╗  █████╗ ██████╗ ███████╗
██║   ██║██╔══██╗██╔════╝ ██╔══██╗██╔══██╗██╔══██╗██╔════╝
██║   ██║██████╔╝██║  ███╗██████╔╝███████║██║  ██║█████╗  
██║   ██║██╔═══╝ ██║   ██║██╔══██╗██╔══██║██║  ██║██╔══╝  
╚██████╔╝██║     ╚██████╔╝██║  ██║██║  ██║██████╔╝███████╗
 ╚═════╝ ╚═╝      ╚═════╝ ╚═╝  ╚═╝╚═╝  ╚═╝╚═════╝ ╚══════╝
`
}
