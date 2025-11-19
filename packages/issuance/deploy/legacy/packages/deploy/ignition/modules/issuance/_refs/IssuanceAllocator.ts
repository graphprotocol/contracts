import { buildModule } from '@nomicfoundation/hardhat-ignition/modules'

export default buildModule('IssuanceAllocatorRef', (m) => {
  const issuanceAllocator = m.contractAt('IssuanceAllocator', m.getParameter('issuanceAllocator'))
  return { issuanceAllocator }
})
