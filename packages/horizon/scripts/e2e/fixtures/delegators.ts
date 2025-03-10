import { parseEther } from 'ethers'
import { indexers } from './indexers'

export interface Delegator {
  address: string
  delegations: {
    indexerAddress: string
    tokens: bigint
  }[]
  undelegate: boolean // Whether this delegator should undelegate at the end
}

export const delegators: Delegator[] = [
  {
    address: '0x610Bb1573d1046FCb8A70Bbbd395754cD57C2b60', // Hardhat account #10
    delegations: [
      {
        indexerAddress: indexers[0].address,
        tokens: parseEther('50000'),
      },
      {
        indexerAddress: indexers[1].address,
        tokens: parseEther('25000'),
      }
    ],
    undelegate: false,
  },
  {
    address: '0x855FA758c77D68a04990E992aA4dcdeF899F654A', // Hardhat account #11
    delegations: [
      {
        indexerAddress: indexers[1].address,
        tokens: parseEther('75000'),
      }
    ],
    undelegate: false,
  },
  {
    address: '0xfA2435Eacf10Ca62ae6787ba2fB044f8733Ee843', // Hardhat account #12
    delegations: [
      {
        indexerAddress: indexers[0].address,
        tokens: parseEther('100000'),
      }
    ],
    undelegate: true, // This delegator will undelegate
  },
  {
    address: '0x64E078A8Aa15A41B85890265648e965De686bAE6', // Hardhat account #13
    delegations: [],
    undelegate: false,
  },
  {
    address: '0x2F560290FEF1B3Ada194b6aA9c40aa71f8e95598', // Hardhat account #14
    delegations: [],
    undelegate: false,
  }
]