import { buildModule } from '@nomicfoundation/hardhat-ignition/modules'
import GraphTokenArtifact from '@graphprotocol/contracts/build/contracts/contracts/token/GraphToken.sol/GraphToken.json'

export default buildModule('GraphHorizon_Core', (m) => {
  // GraphToken contract
  const initialSupply = m.getParameter('GraphToken_initialSupply')
  const graphToken = m.contract('GraphToken', GraphTokenArtifact, [initialSupply])

  return { graphToken }
})
