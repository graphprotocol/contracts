import path from 'path'
import { loadGraphNetworkContracts } from '../src'
import type { GraphChainId } from '../src'
import { loadArtifact } from '../src/deployments/lib/deploy/artifacts'

const chains: GraphChainId[] = [1, 5, 42161, 421613]

for (const chain of chains) {
  const contracts = loadGraphNetworkContracts('./addresses.json', chain)

  for (const contract of contracts) {
    try {
      // console.log(contract.address)
    } catch (error) {
      console.log(error)
    }
  }
}

// loadArtifact(
//   'GraphProxyAdmin',
//   path.resolve('node_modules', '@graphprotocol/contracts/build/contracts'),
// )
