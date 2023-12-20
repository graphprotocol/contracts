import { Network } from 'hardhat/types/runtime'
import { NetworksConfig, HttpNetworkConfig } from 'hardhat/types/config'
import { EthersProviderWrapper } from '@nomiclabs/hardhat-ethers/internal/ethers-provider-wrapper'
import { HARDHAT_NETWORK_NAME } from 'hardhat/plugins'
import { createProvider } from 'hardhat/internal/core/providers/construction'

import { getNetworkConfig, getNetworkName } from './helpers/network'
import { logDebug } from './helpers/logger'

import { GREPluginError } from './helpers/error'
import { AccountsRuntimeEnvironment } from 'hardhat-secure-accounts/dist/src/type-extensions'

export const getDefaultProvider = (
  networks: NetworksConfig,
  chainId: number,
  network: Network,
  isMainProvider: boolean,
  chainLabel: string,
): EthersProviderWrapper | undefined => {
  // Don't recreate provider if we are on hardhat network. This avoids issues with
  // hardhat node not responding to requests from the recreated provider
  if (network.name === 'hardhat') {
    logDebug(`Hardhat network detected; using default provider for ${chainLabel}(${network.name})`)
    return new EthersProviderWrapper(network.provider)
  }

  const { networkConfig, networkName } = getNetworkData(
    networks,
    chainId,
    network.name,
    isMainProvider,
    chainLabel,
  )

  if (networkConfig === undefined || networkName === undefined) {
    return undefined
  }

  logDebug(`Creating provider for ${chainLabel}(${networkName})`)
  const ethereumProvider = createProvider(networkName, networkConfig)
  const ethersProviderWrapper = new EthersProviderWrapper(ethereumProvider)
  return ethersProviderWrapper
}

export const getSecureAccountsProvider = async (
  accounts: AccountsRuntimeEnvironment,
  networks: NetworksConfig,
  chainId: number,
  mainNetworkName: string,
  isMainProvider: boolean,
  chainLabel: string,
  caller: string,
  accountName?: string,
  accountPassword?: string,
): Promise<EthersProviderWrapper> => {
  const { networkConfig, networkName } = getNetworkData(
    networks,
    chainId,
    mainNetworkName,
    isMainProvider,
    chainLabel,
  )

  if (networkConfig === undefined || networkName === undefined) {
    throw new GREPluginError(
      `Could not get secure accounts provider for ${chainLabel}(${networkName})! - Caller is ${caller}`,
    )
  }

  logDebug(`Using secure accounts provider for ${chainLabel}(${networkName}) - Caller is ${caller}`)
  if (accountName === undefined || accountPassword === undefined) {
    console.log(
      `== Using secure accounts, please unlock an account for ${chainLabel}(${networkName}) - Caller is ${caller}`,
    )
  }

  return await accounts.getProvider(
    { name: networkName, config: networkConfig } as Network,
    accountName,
    accountPassword,
  )
}

const getNetworkData = (
  networks: NetworksConfig,
  chainId: number,
  mainNetworkName: string,
  isMainProvider: boolean,
  chainLabel: string,
): { networkConfig: HttpNetworkConfig | undefined; networkName: string | undefined } => {
  const networkConfig = getNetworkConfig(networks, chainId, mainNetworkName) as HttpNetworkConfig
  const networkName = getNetworkName(networks, chainId, mainNetworkName)

  logDebug(`Provider url for ${chainLabel}(${networkName}): ${networkConfig?.url}`)

  // Ensure at least main provider is configured
  // For Hardhat network we don't need url to create a provider
  if (
    isMainProvider &&
    (networkConfig === undefined || networkConfig.url === undefined) &&
    networkName !== HARDHAT_NETWORK_NAME
  ) {
    throw new GREPluginError(`Must set a provider url for chain: ${chainId}!`)
  }

  return { networkConfig, networkName }
}
