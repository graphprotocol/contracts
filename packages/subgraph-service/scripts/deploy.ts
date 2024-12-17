/* eslint-disable no-prototype-builtins */
/* eslint-disable @typescript-eslint/no-unsafe-return */
/* eslint-disable @typescript-eslint/no-unused-vars */
/* eslint-disable @typescript-eslint/no-explicit-any */
require('json5/lib/register')

import { ignition } from 'hardhat'

import DisputeManagerModule from '../ignition/modules/DisputeManager'
import HorizonModule from '@graphprotocol/horizon/ignition/modules/horizon'
import SubgraphServiceModule from '../ignition/modules/SubgraphService'
import SubgraphServiceProxiesModule from '../ignition/modules/Proxies'

// Horizon needs the SubgraphService proxy address before it can be deployed
// But SubgraphService and DisputeManager implementations need Horizon...
// So the deployment order is:
// - Deploy SubgraphService and DisputeManager proxies
// - Deploy Horizon
// - Deploy SubgraphService and DisputeManager implementations
async function main() {
  // TODO: Dynamically load config file based on the hardhat --network value
  const HorizonConfig = removeNFromBigInts(require('@graphprotocol/horizon/ignition/configs/horizon.hardhat.json5'))
  const SubgraphServiceConfig = removeNFromBigInts(require('../ignition/configs/subgraph-service.hardhat.json5'))

  // Deploy proxies
  const { DisputeManagerProxy, DisputeManagerProxyAdmin, SubgraphServiceProxy, SubgraphServiceProxyAdmin } = await ignition.deploy(SubgraphServiceProxiesModule)

  // Deploy Horizon
  const { Controller, TAPCollector, Curation } = await ignition.deploy(HorizonModule, {
    parameters: patchSubgraphServiceAddress(HorizonConfig, SubgraphServiceProxy.target as string),
  })

  // Deploy DisputeManager implementation
  await ignition.deploy(DisputeManagerModule, {
    parameters: deepMerge(SubgraphServiceConfig, {
      DisputeManager: {
        controllerAddress: Controller.target as string,
        disputeManagerProxyAddress: DisputeManagerProxy.target as string,
        disputeManagerProxyAdminAddress: DisputeManagerProxyAdmin.target as string,
      },
    }),
  })

  // Deploy SubgraphService implementation
  await ignition.deploy(SubgraphServiceModule, {
    parameters: deepMerge(SubgraphServiceConfig, {
      SubgraphService: {
        controllerAddress: Controller.target as string,
        subgraphServiceProxyAddress: SubgraphServiceProxy.target as string,
        subgraphServiceProxyAdminAddress: SubgraphServiceProxyAdmin.target as string,
        disputeManagerAddress: DisputeManagerProxy.target as string,
        tapCollectorAddress: TAPCollector.target as string,
        curationAddress: Curation.target as string,
      },
    }),
  })
}
main().catch((error) => {
  console.error(error)
  process.exit(1)
})

// -- Auxiliary functions - by GPT --
function patchSubgraphServiceAddress(jsonData: any, newAddress: string) {
  function recursivePatch(obj: any) {
    if (typeof obj === 'object' && obj !== null) {
      for (const key in obj) {
        if (key === 'subgraphServiceAddress') {
          obj[key] = newAddress
        } else {
          recursivePatch(obj[key])
        }
      }
    }
  }

  recursivePatch(jsonData)
  return jsonData
}

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

function deepMerge(obj1: any, obj2: any) {
  const merged = { ...obj1 }

  for (const key in obj2) {
    if (obj2.hasOwnProperty(key)) {
      if (typeof obj2[key] === 'object' && obj2[key] !== null && obj1[key]) {
        merged[key] = deepMerge(obj1[key], obj2[key])
      } else {
        merged[key] = obj2[key]
      }
    }
  }

  return merged
}
