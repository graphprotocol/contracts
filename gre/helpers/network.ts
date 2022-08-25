import { NetworkConfig, NetworksConfig } from 'hardhat/types/config'
import { logWarn } from './logger'
import { GREPluginError } from './error'

export function getNetworkConfig(
  networks: NetworksConfig,
  chainId: number,
  mainNetworkName: string,
): (NetworkConfig & { name: string }) | undefined {
  let candidateNetworks = Object.keys(networks)
    .map((n) => ({ ...networks[n], name: n }))
    .filter((n) => n.chainId === chainId)

  if (candidateNetworks.length > 1) {
    logWarn(
      `Found multiple networks with chainId ${chainId}, trying to use main network name to desambiguate`,
    )

    candidateNetworks = candidateNetworks.filter((n) => n.name === mainNetworkName)

    if (candidateNetworks.length === 1) {
      return candidateNetworks[0]
    } else {
      throw new GREPluginError(
        `Found multiple networks with chainID ${chainId}. This is not supported!`,
      )
    }
  } else if (candidateNetworks.length === 1) {
    return candidateNetworks[0]
  } else {
    return undefined
  }
}

export function getNetworkName(
  networks: NetworksConfig,
  chainId: number,
  mainNetworkName: string,
): string | undefined {
  const network = getNetworkConfig(networks, chainId, mainNetworkName)
  return network?.name
}
