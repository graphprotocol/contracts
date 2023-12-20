/**
 * Master chain list for all the chain pairs supported by the Graph Protocol
 * See {@link GraphChainPair} for details on the structure of a chain pair
 * @enum
 */
export const GraphChainList = [
  {
    l1: {
      id: 1,
      name: 'mainnet',
    },
    l2: {
      id: 42161,
      name: 'arbitrum-one',
    },
  },
  {
    l1: {
      id: 4,
      name: 'rinkeby',
    },
    l2: {
      id: 421611,
      name: 'arbitrum-rinkeby',
    },
  },
  {
    l1: {
      id: 11155111,
      name: 'sepolia',
    },
    l2: {
      id: 421614,
      name: 'arbitrum-sepolia',
    },
  },
  {
    l1: {
      id: 5,
      name: 'goerli',
    },
    l2: {
      id: 421613,
      name: 'arbitrum-goerli',
    },
  },
  {
    l1: {
      id: 1337,
      name: 'localnitrol1',
    },
    l2: {
      id: 412346,
      name: 'localnitrol2',
    },
  },
] as const
