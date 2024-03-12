import hre, { ethers } from 'hardhat'
import { getGREOptsFromArgv } from '@graphprotocol/sdk/gre'

async function main() {
  const graphOpts = getGREOptsFromArgv()
  const graph = hre.graph(graphOpts)
  const { GraphToken, Staking } = graph.contracts

  console.log('Hello from the pre-upgrade script!')

  // Make the deployer an asset holder
  const deployer = await graph.getDeployer()
  const { governor } = await graph.getNamedAccounts()
  // @ts-expect-error asset holder existed back then
  await Staking.connect(governor).setAssetHolder(deployer.address, true)

  // Get some funds on the deployer
  await GraphToken.connect(governor).transfer(deployer.address, ethers.utils.parseEther('100000'))
  await graph.provider.send('hardhat_setBalance', [deployer.address, '0x56BC75E2D63100000']) // 100 Eth

  // Approve Staking contract to pull GRT from new asset holder
  await GraphToken.connect(deployer).approve(Staking.address, ethers.utils.parseEther('100000'))
}

// We recommend this pattern to be able to use async/await everywhere
// and properly handle errors.
main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error)
    process.exitCode = 1
  })
