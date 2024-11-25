require('json5/lib/register')

import { ignition } from 'hardhat'

import HorizonModule from '../ignition/modules/horizon'

async function main() {
  // const HorizonConfig = removeNFromBigInts(require('../ignition/configs/horizon.hardhat.json5'))
  // Deploy Horizon
  await ignition.deploy(HorizonModule, {
    parameters: {
      $global: {
        governor: '0xFFcf8FDEE72ac11b5c542428B35EEF5769C409f0',
        pauseGuardian: '0x95cED938F7991cd0dFcb48F0a06a40FA1aF46EBC',
        subgraphAvailabilityOracle: '0xd03ea8624C8C5987235048901fB614fDcA89b117',
        subgraphServiceAddress: '0x0000000000000000000000000000000000000000',
      },
      RewardsManager: { issuancePerBlock: '114155251141552511415' },
      EpochManager: { epochLength: 60 },
      Curation: { curationTaxPercentage: 10000, minimumCurationDeposit: 1 },
      GraphToken: { initialSupply: '10000000000000000000000000000' },
      HorizonStaking: { maxThawingPeriod: 2419200 },
      GraphPayments: { protocolPaymentCut: 10000 },
      PaymentsEscrow: {
        revokeCollectorThawingPeriod: 10000,
        withdrawEscrowThawingPeriod: 10000,
      },
      TAPCollector: {
        eip712Name: 'TAPCollector',
        eip712Version: '1',
        revokeSignerThawingPeriod: 10000,
      },
    },
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
