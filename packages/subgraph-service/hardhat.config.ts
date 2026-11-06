// Hardhat plugins
import '@nomicfoundation/hardhat-foundry'
import '@nomicfoundation/hardhat-toolbox'
import '@nomicfoundation/hardhat-ignition-ethers'
import 'hardhat-contract-sizer'
import 'hardhat-secure-accounts'
import 'solidity-docgen'
import 'hardhat-graph-protocol'

import { hardhatBaseConfig, isProjectBuilt, loadTasks } from '@graphprotocol/toolshed/hardhat'
import { HardhatUserConfig } from 'hardhat/config'
import type { SolcUserConfig } from 'hardhat/types'

// Some tasks need compiled artifacts to run so we avoid loading them when building the project
if (isProjectBuilt(__dirname)) {
  loadTasks(__dirname)
}

const baseConfig = hardhatBaseConfig(require)

// L2GNS, L2Curation and their dependencies were ported from 0.7.6 and keep the legacy pipeline (no viaIR)
const portedSolidityConfig = {
  version: '0.8.35',
  settings: {
    optimizer: {
      enabled: true,
      runs: 200,
    },
    evmVersion: 'cancun',
  },
}

const overrides = Object.fromEntries(
  [
    'contracts/base/Multicall.sol',
    'contracts/curation/CurationStorage.sol',
    'contracts/discovery/GNS.sol',
    'contracts/discovery/GNSStorage.sol',
    'contracts/l2/curation/L2Curation.sol',
    'contracts/l2/discovery/L2GNS.sol',
    'contracts/l2/discovery/L2GNSStorage.sol',
    'contracts/upgrades/InitializableV3.sol',
    // Dependencies that only the ported files import. Without an override, Hardhat would add them to the
    // default viaIR job, which changes that job's solc input and SubgraphService's bytecode.
    // `pnpm check:bytecode` (SubgraphService in the migration manifest) catches a missing entry.
    '@graphprotocol/graph-core/contracts/governance/Managed.sol',
    '@graphprotocol/graph-core/contracts/upgrades/GraphUpgradeable.sol',
    '@graphprotocol/interfaces/contracts/contracts/base/IMulticall.sol',
    '@graphprotocol/interfaces/contracts/contracts/curation/IGraphCurationToken.sol',
    '@graphprotocol/interfaces/contracts/contracts/discovery/erc1056/IEthereumDIDRegistry.sol',
    '@graphprotocol/interfaces/contracts/contracts/discovery/IGNS.sol',
    '@graphprotocol/interfaces/contracts/contracts/discovery/ISubgraphNFT.sol',
    '@graphprotocol/interfaces/contracts/contracts/gateway/ICallhookReceiver.sol',
    '@graphprotocol/interfaces/contracts/contracts/governance/IManaged.sol',
    '@graphprotocol/interfaces/contracts/contracts/l2/curation/IL2Curation.sol',
    '@graphprotocol/interfaces/contracts/contracts/l2/discovery/IL2GNS.sol',
    '@graphprotocol/interfaces/contracts/contracts/staking/IStaking.sol',
    '@graphprotocol/interfaces/contracts/contracts/staking/IStakingBase.sol',
    '@graphprotocol/interfaces/contracts/contracts/staking/IStakingData.sol',
    '@graphprotocol/interfaces/contracts/contracts/staking/IStakingExtension.sol',
    '@graphprotocol/interfaces/contracts/contracts/staking/libs/IStakes.sol',
    '@openzeppelin/contracts/proxy/Clones.sol',
    '@openzeppelin/contracts/token/ERC721/IERC721.sol',
    '@openzeppelin/contracts/utils/Create2.sol',
    '@openzeppelin/contracts/utils/introspection/IERC165.sol',
  ].map((file) => [file, portedSolidityConfig]),
)

const config: HardhatUserConfig = {
  ...baseConfig,
  solidity: { compilers: [baseConfig.solidity as SolcUserConfig], overrides },
  sourcify: {
    enabled: false,
  },
}

export default config
