// Valid for
// - chain: Ethereum Mainnet
// - block number: 17324022
// Query to obtain data:
// allocations (
//   block: { number: 17324022 },
//   where: {
//     indexer_: { id: "0x87eba079059b75504c734820d6cf828476754b83" },
//     status: Active
//   },
//   first:10
// ){
//  id
//  status
// }

export default [
  {
    signer: null,
    address: '0x87Eba079059B75504c734820d6cf828476754B83',
    allocationsBatch1: [
      {
        id: '0x0074115940dee3ecb0c1d524c94b169cc5ea28ac',
        status: 'Active',
      },
      {
        id: '0x0419959df8ecfaeb98f273ad7e037bea2dac58b8',
        status: 'Active',
      },
      {
        id: '0x04d40e25064297f1548ffbca867edbc26f4e85bb',
        status: 'Active',
      },
      {
        id: '0x0607ae1824a834c44004eeee58f5513911fedc18',
        status: 'Active',
      },
      {
        id: '0x08abad5b5fbc5436e043d680b6721fda5c3ea370',
        status: 'Active',
      },
    ],
    allocationsBatch2: [
      {
        id: '0x10ffbcdf3f294c029621b85dca22651f819530e2',
        status: 'Active',
      },
      {
        id: '0x160c431e8c94e06164f44ed9deaeb3ff9972d4ec',
        status: 'Active',
      },
      {
        id: '0x23df5d592c149eb62c7f4caa22642d3e353009a3',
        status: 'Active',
      },
      {
        id: '0x2ddef43b8328a9e6e5c6e8ec4cea01d6aca514ec',
        status: 'Active',
      },
      {
        id: '0x30310400346f6384040afdc8d57a78b67907efb6',
        status: 'Active',
      },
    ],
  },
]
