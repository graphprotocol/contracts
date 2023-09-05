export default [
  {
    inputs: [],
    name: 'channelDisputeEpochs',
    outputs: [{ internalType: 'uint32', name: '', type: 'uint32' }],
    stateMutability: 'view',
    type: 'function',
  },
  {
    inputs: [{ internalType: 'uint256', name: '', type: 'uint256' }],
    name: 'rebates',
    outputs: [
      { internalType: 'uint256', name: 'fees', type: 'uint256' },
      { internalType: 'uint256', name: 'effectiveAllocatedStake', type: 'uint256' },
      { internalType: 'uint256', name: 'claimedRewards', type: 'uint256' },
      { internalType: 'uint32', name: 'unclaimedAllocationsCount', type: 'uint32' },
      { internalType: 'uint32', name: 'alphaNumerator', type: 'uint32' },
      { internalType: 'uint32', name: 'alphaDenominator', type: 'uint32' },
    ],
    stateMutability: 'view',
    type: 'function',
  },
  {
    inputs: [
      { internalType: 'address', name: '_allocationID', type: 'address' },
      { internalType: 'bool', name: '_restake', type: 'bool' },
    ],
    name: 'claim',
    outputs: [],
    stateMutability: 'nonpayable',
    type: 'function',
  },
  {
    inputs: [
      { internalType: 'address', name: '_allocationID', type: 'address' },
      { internalType: 'bool', name: '_restake', type: 'bool' },
    ],
    name: 'claimo',
    outputs: [],
    stateMutability: 'nonpayable',
    type: 'function',
  },
  {
    anonymous: false,
    inputs: [
      { indexed: true, internalType: 'address', name: 'indexer', type: 'address' },
      { indexed: true, internalType: 'bytes32', name: 'subgraphDeploymentID', type: 'bytes32' },
      { indexed: true, internalType: 'address', name: 'allocationID', type: 'address' },
      { indexed: false, internalType: 'uint256', name: 'epoch', type: 'uint256' },
      { indexed: false, internalType: 'uint256', name: 'forEpoch', type: 'uint256' },
      { indexed: false, internalType: 'uint256', name: 'tokens', type: 'uint256' },
      {
        indexed: false,
        internalType: 'uint256',
        name: 'unclaimedAllocationsCount',
        type: 'uint256',
      },
      { indexed: false, internalType: 'uint256', name: 'delegationFees', type: 'uint256' },
    ],
    name: 'RebateClaimed',
    type: 'event',
  },
]
