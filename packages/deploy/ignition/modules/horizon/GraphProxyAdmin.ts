import { buildModule } from '@nomicfoundation/hardhat-ignition/modules'

/**
 * Reference module for existing GraphProxyAdmin deployment
 *
 * This module doesn't deploy anything - it just creates a reference to the
 * already-deployed GraphProxyAdmin contract from the Horizon package.
 */
export default buildModule('GraphProxyAdminRef', (m) => {
  const address = m.getParameter('graphProxyAdminAddress')

  const graphProxyAdmin = m.contractAt('IGraphProxyAdmin', address, {
    id: 'GraphProxyAdmin',
  })

  return { graphProxyAdmin }
})
