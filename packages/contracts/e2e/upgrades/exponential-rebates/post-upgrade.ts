import hre from 'hardhat'
import { getGREOptsFromArgv } from '@graphprotocol/sdk/gre'

async function main() {
  const graphOpts = getGREOptsFromArgv()
  const graph = hre.graph(graphOpts)
  console.log('Hello from the post-upgrade script!')

  // TODO: remove this hack
  // mainnet does not have staking extension as of now
  // We set it to a random contract, otherwise it uses 0x00
  // which does not revert when called with calldata
  const { governor } = await graph.getNamedAccounts()
  await graph.contracts.Staking.connect(governor).setExtensionImpl(
    '0xc944E90C64B2c07662A292be6244BDf05Cda44a7',
  )
}

// We recommend this pattern to be able to use async/await everywhere
// and properly handle errors.
main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error)
    process.exitCode = 1
  })
