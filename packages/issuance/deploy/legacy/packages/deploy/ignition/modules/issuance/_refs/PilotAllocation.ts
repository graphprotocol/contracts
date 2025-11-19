import { buildModule } from '@nomicfoundation/hardhat-ignition/modules'

export default buildModule('PilotAllocationRef', (m) => {
  const pilotAllocation = m.contractAt('PilotAllocation', m.getParameter('pilotAllocation'))
  return { pilotAllocation }
})
