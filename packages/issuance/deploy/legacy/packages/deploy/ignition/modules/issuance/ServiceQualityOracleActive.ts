import { buildModule } from '@nomicfoundation/hardhat-ignition/modules'

import RewardsManagerRef from './_refs/RewardsManager'

export default buildModule('ServiceQualityOracleActive', (m) => {
  const { rewardsManager } = m.useModule(RewardsManagerRef)
  const serviceQualityOracle = m.contractAt('ServiceQualityOracle', m.getParameter('serviceQualityOracle'))

  const verifier = m.contractAt('IssuanceStateVerifier', '0x0000000000000000000000000000000000000000')
  m.call(verifier, 'assertServiceQualityOracleSet', [rewardsManager, serviceQualityOracle], {
    id: 'AssertSQOIntegration',
  })

  return { rewardsManager, serviceQualityOracle }
})
