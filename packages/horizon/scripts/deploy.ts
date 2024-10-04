import { ignition } from 'hardhat'

import Parameters from '../ignition/graph.hardhat.json'
import PeripheryModule from '../ignition/modules/periphery'

async function main() {
  await ignition.deploy(PeripheryModule, {
    parameters: Parameters,
  })
}

main()
  .catch((error) => {
    console.error(error)
    process.exit(1)
  })
