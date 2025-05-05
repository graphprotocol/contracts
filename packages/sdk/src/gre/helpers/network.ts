import { NetworkConfig, NetworksConfig } from 'hardhat/types/config'
import { logDebug, logWarn } from './logger'
import { GREPluginError } from './error'
import { counterpartName } from '../..'

export function getNetworkConfig(
  networks: NetworksConfig,
  chainId: number,
  mainNetworkName: string,
): (NetworkConfig & { name: string }) | undefined {
  const candidateNetworks = Object.keys(networks)
    .map((n) => ({ ...networks[n], name: n }))
    .filter((n) => n.chainId === chainId)

  if (candidateNetworks.length > 1) {
    logWarn(
      `Found multiple networks with chainId ${chainId}, trying to use main network name to desambiguate`,
    )

    const filteredByMainNetworkName = candidateNetworks.filter((n) => n.name === mainNetworkName)

    if (filteredByMainNetworkName.length === 1) {
      logDebug(`Found network with chainId ${chainId} and name ${mainNetworkName}`)
      return filteredByMainNetworkName[0]
    } else {
      logWarn(`Could not desambiguate with main network name, trying secondary network name`)
      const secondaryNetworkName = counterpartName(mainNetworkName)
      const filteredBySecondaryNetworkName = candidateNetworks.filter(
        (n) => n.name === secondaryNetworkName,
      )

      if (filteredBySecondaryNetworkName.length === 1) {
        logDebug(`Found network with chainId ${chainId} and name ${mainNetworkName}`)
        return filteredBySecondaryNetworkName[0]
      } else {
        throw new GREPluginError(
          `Could not desambiguate network with chainID ${chainId}. Use case not supported!`,
        )
      }
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
