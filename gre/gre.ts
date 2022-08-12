import { HardhatRuntimeEnvironment } from 'hardhat/types'
import { extendEnvironment } from 'hardhat/config'
import { lazyFunction, lazyObject } from 'hardhat/plugins'

import { getAddressBook } from '../cli/address-book'
import { loadContracts } from '../cli/contracts'
import { readConfig } from '../cli/config'
import {
  GraphNetworkEnvironment,
  GraphRuntimeEnvironment,
  GraphRuntimeEnvironmentOptions,
} from './type-extensions'
import { providers } from 'ethers'
import { getChains, getProviders, getAddressBookPath, getGraphConfigPaths } from './config'
import { getDeployer, getNamedAccounts, getTestAccounts } from './accounts'

// Graph Runtime Environment (GRE) extensions for the HRE
extendEnvironment((hre: HardhatRuntimeEnvironment) => {
  hre.graph = (opts: GraphRuntimeEnvironmentOptions = {}) => {
    const { l1ChainId, l2ChainId, isHHL1 } = getChains(hre.network.config.chainId)
    const { l1Provider, l2Provider } = getProviders(hre, l1ChainId, l2ChainId)
    const addressBookPath = getAddressBookPath(hre, opts)
    const { l1GraphConfigPath, l2GraphConfigPath } = getGraphConfigPaths(
      hre,
      opts,
      l1ChainId,
      l2ChainId,
    )

    const l1Graph: GraphNetworkEnvironment = buildGraphNetworkEnvironment(
      l1ChainId,
      l1Provider,
      l1GraphConfigPath,
      addressBookPath,
    )

    const l2Graph: GraphNetworkEnvironment = buildGraphNetworkEnvironment(
      l2ChainId,
      l2Provider,
      l2GraphConfigPath,
      addressBookPath,
    )

    const gre: GraphRuntimeEnvironment = {
      ...(isHHL1 ? l1Graph : l2Graph),
      l1: l1Graph,
      l2: l2Graph,
    }

    return gre
  }
})

function buildGraphNetworkEnvironment(
  chainId: number,
  provider: providers.JsonRpcProvider,
  graphConfigPath: string,
  addressBookPath: string,
): GraphNetworkEnvironment {
  return {
    addressBook: lazyObject(() => getAddressBook(addressBookPath, chainId.toString())),
    graphConfig: lazyObject(() => readConfig(graphConfigPath, true)),
    contracts: lazyObject(() =>
      loadContracts(getAddressBook(addressBookPath, chainId.toString()), provider),
    ),
    getDeployer: lazyFunction(() => () => getDeployer(provider)),
    getNamedAccounts: lazyFunction(() => () => getNamedAccounts(provider, graphConfigPath)),
    getTestAccounts: lazyFunction(() => () => getTestAccounts(provider, graphConfigPath)),
  }
}
