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
      isHHL1,
    )

    const l1Graph: GraphNetworkEnvironment | null = buildGraphNetworkEnvironment(
      l1ChainId,
      l1Provider,
      l1GraphConfigPath,
      addressBookPath,
      isHHL1,
    )

    const l2Graph: GraphNetworkEnvironment | null = buildGraphNetworkEnvironment(
      l2ChainId,
      l2Provider,
      l2GraphConfigPath,
      addressBookPath,
      isHHL1,
    )

    const gre: GraphRuntimeEnvironment = {
      ...(isHHL1 ? (l1Graph as GraphNetworkEnvironment) : (l2Graph as GraphNetworkEnvironment)),
      l1: l1Graph,
      l2: l2Graph,
    }

    return gre
  }
})

function buildGraphNetworkEnvironment(
  chainId: number,
  provider: providers.JsonRpcProvider,
  graphConfigPath: string | undefined,
  addressBookPath: string,
  isHHL1: boolean,
): GraphNetworkEnvironment | null {
  if (graphConfigPath === undefined) {
    console.warn(
      `No graph config file provided for chain: ${chainId}. L${
        isHHL1 ? '2' : '1'
      } graph object will not be initialized.`,
    )
    return null
  }

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
