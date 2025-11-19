import { buildModule } from '@nomicfoundation/hardhat-ignition/modules'

/**
 * Reference module for existing GraphToken deployment
 *
 * This module doesn't deploy anything - it just creates a reference to the
 * already-deployed GraphToken contract.
 */
export default buildModule('GraphTokenRef', (m) => {
  const address = m.getParameter('graphTokenAddress')

  const graphToken = m.contractAt('IGraphToken', address, {
    id: 'GraphToken',
  })

  return { graphToken }
})
