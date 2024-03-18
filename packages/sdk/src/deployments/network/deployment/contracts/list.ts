// List of contract names for the Graph Network

export const GraphNetworkSharedContractNameList = [
  'GraphProxyAdmin',
  'BancorFormula',
  'Controller',
  'EpochManager',
  'GraphCurationToken',
  'ServiceRegistry',
  'SubgraphNFTDescriptor',
  'SubgraphNFT',
  'StakingExtension',
  'RewardsManager',
  'DisputeManager',
  'AllocationExchange',
] as const
export const GraphNetworkOptionalContractNameList = [
  'IENS',
  'ENS',
  'IEthereumDIDRegistry',
  'EthereumDIDRegistry',
] as const
export const GraphNetworkL1ContractNameList = [
  'GraphToken',
  'Curation',
  'L1GNS',
  'L1Staking',
  'L1GraphTokenGateway',
  'BridgeEscrow',
] as const
export const GraphNetworkL2ContractNameList = [
  'L2GraphToken',
  'L2Curation',
  'L2GNS',
  'L2Staking',
  'L2GraphTokenGateway',
] as const

export const GraphNetworkContractNameList = [
  ...GraphNetworkSharedContractNameList,
  ...GraphNetworkOptionalContractNameList,
  ...GraphNetworkL1ContractNameList,
  ...GraphNetworkL2ContractNameList,
] as const

export type GraphNetworkContractName = (typeof GraphNetworkContractNameList)[number]

export function isGraphNetworkContractName(name: unknown): name is GraphNetworkContractName {
  return (
    typeof name === 'string' &&
    GraphNetworkContractNameList.includes(name as GraphNetworkContractName)
  )
}

export const GraphNetworkGovernedContractNameList: GraphNetworkContractName[] = [
  'GraphToken',
  'Controller',
  'GraphProxyAdmin',
  'SubgraphNFT',
]
