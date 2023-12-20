// Valid allocation states for
// - chain: Ethereum Mainnet
// - block number: 17324022
// Allocation ids obtained from network subgraph

import { AllocationState } from '@graphprotocol/sdk'

export default [
  { id: '0x00b7a526e1e42ba1f14e69f487aad31350164a9e', state: AllocationState.Null },
  { id: '0x00b7a526e1e42ba1f14e69f487aad31350164a9f', state: AllocationState.Null },
  { id: '0x00b7a526e1e42ba1f14e69f487aad31350164a90', state: AllocationState.Null },
  { id: '0x00b7a526e1e42ba1f14e69f487aad31350164a9d', state: AllocationState.Active },
  { id: '0x02a5e2312af00aa85a24cf4c43a8c0a6fd9a6c2d', state: AllocationState.Active },
  { id: '0x0a272f72c14a226525fb4e2114f8a0052dc7dd38', state: AllocationState.Active },
  { id: '0x016ad691b2572ed3192e366584d12e94699e12b2', state: AllocationState.Closed },
  { id: '0x060df24858f3aa6d445645b73d0d2eeb117ae8a3', state: AllocationState.Closed },
  { id: '0x08ee64a4505e9cd77f0cae15c56e795dca7384e3', state: AllocationState.Closed },
  { id: '0x03f9e610fea2f8eab7321038997a50fe4ecc6aa5', state: AllocationState.Finalized },
  { id: '0x0989e792c6ca9eb0a0f2f63d92e407cdc1e64c29', state: AllocationState.Finalized },
  { id: '0x0d62657d6b75f462b28c000f6f6e41d56cc60069', state: AllocationState.Finalized },
  { id: '0x0da397c2887632e7250a5f1a8a7ed56e437780f5', state: AllocationState.Claimed },
  { id: '0x0d819c0e05782f41a4ab22fe9b5d439235093706', state: AllocationState.Claimed },
  { id: '0x0afef3ebeb9f85ce60c89ecaa7d98e41335ce5a4', state: AllocationState.Claimed },
]
