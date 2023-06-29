import hre from 'hardhat'
import { getGraphOptsFromArgv } from '../../lib/helpers'

async function main() {
  const graphOpts = getGraphOptsFromArgv()
  const graph = hre.graph(graphOpts)
  console.log('Hello from the pre-upgrade script!')
}

// We recommend this pattern to be able to use async/await everywhere
// and properly handle errors.
main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error)
    process.exitCode = 1
  })
