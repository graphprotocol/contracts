require('json5/lib/register')

import { ignition } from 'hardhat'

import MigrateModule from '../ignition/modules/migrate'

async function main() {
  const HorizonConfig = removeNFromBigInts(require('../ignition/configs/horizon-migrate.hardhat.json5'))

  // Deploy Horizon
  await ignition.deploy(MigrateModule, {
    displayUi: true,
    parameters: HorizonConfig,
  })
}
main().catch((error) => {
  console.error(error)
  process.exit(1)
})

// eslint-disable-next-line @typescript-eslint/no-explicit-any
function removeNFromBigInts(obj: any): any {
  // Ignition requires "n" suffix for bigints, but not here
  if (typeof obj === 'string') {
    return obj.replace(/(\d+)n/g, '$1')
  } else if (Array.isArray(obj)) {
    return obj.map(removeNFromBigInts)
  } else if (typeof obj === 'object' && obj !== null) {
    for (const key in obj) {
      obj[key] = removeNFromBigInts(obj[key])
    }
  }
  return obj
}