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
]
