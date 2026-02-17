import { deployImplementation, upgradeTransparentUpgradeableProxy } from '@graphprotocol/horizon/ignition'
import { buildModule } from '@nomicfoundation/hardhat-ignition/modules'
import ProxyAdminArtifact from '@openzeppelin/contracts/build/contracts/ProxyAdmin.json'
import TransparentUpgradeableProxyArtifact from '@openzeppelin/contracts/build/contracts/TransparentUpgradeableProxy.json'

import AllocationHandlerArtifact from '../../build/contracts/contracts/libraries/AllocationHandler.sol/AllocationHandler.json'
import IndexingAgreementArtifact from '../../build/contracts/contracts/libraries/IndexingAgreement.sol/IndexingAgreement.json'
import IndexingAgreementDecoderArtifact from '../../build/contracts/contracts/libraries/IndexingAgreementDecoder.sol/IndexingAgreementDecoder.json'
import IndexingAgreementDecoderRawArtifact from '../../build/contracts/contracts/libraries/IndexingAgreementDecoderRaw.sol/IndexingAgreementDecoderRaw.json'
import StakeClaimsArtifact from '../../build/contracts/@graphprotocol/horizon/contracts/data-service/libraries/StakeClaims.sol/StakeClaims.json'
import SubgraphServiceArtifact from '../../build/contracts/contracts/SubgraphService.sol/SubgraphService.json'

export default buildModule('SubgraphService', (m) => {
  const deployer = m.getAccount(0)
  const governor = m.getParameter('governor')
  const pauseGuardian = m.getParameter('pauseGuardian')
  const controllerAddress = m.getParameter('controllerAddress')
  const subgraphServiceProxyAddress = m.getParameter('subgraphServiceProxyAddress')
  const subgraphServiceProxyAdminAddress = m.getParameter('subgraphServiceProxyAdminAddress')
  const disputeManagerProxyAddress = m.getParameter('disputeManagerProxyAddress')
  const graphTallyCollectorAddress = m.getParameter('graphTallyCollectorAddress')
  const curationProxyAddress = m.getParameter('curationProxyAddress')
  const recurringCollectorAddress = m.getParameter('recurringCollectorAddress')
  const minimumProvisionTokens = m.getParameter('minimumProvisionTokens')
  const maximumDelegationRatio = m.getParameter('maximumDelegationRatio')
  const stakeToFeesRatio = m.getParameter('stakeToFeesRatio')
  const maxPOIStaleness = m.getParameter('maxPOIStaleness')
  const curationCut = m.getParameter('curationCut')
  const indexingFeesCut = m.getParameter('indexingFeesCut')

  const SubgraphServiceProxyAdmin = m.contractAt('ProxyAdmin', ProxyAdminArtifact, subgraphServiceProxyAdminAddress)
  const SubgraphServiceProxy = m.contractAt(
    'SubgraphServiceProxy',
    TransparentUpgradeableProxyArtifact,
    subgraphServiceProxyAddress,
  )

  // Deploy libraries
  const StakeClaims = m.library('StakeClaims', StakeClaimsArtifact)
  const AllocationHandler = m.library('AllocationHandler', AllocationHandlerArtifact)
  const IndexingAgreementDecoderRaw = m.library('IndexingAgreementDecoderRaw', IndexingAgreementDecoderRawArtifact)
  const IndexingAgreementDecoder = m.library('IndexingAgreementDecoder', IndexingAgreementDecoderArtifact, {
    libraries: {
      IndexingAgreementDecoderRaw: IndexingAgreementDecoderRaw,
    },
  })
  const IndexingAgreement = m.library('IndexingAgreement', IndexingAgreementArtifact, {
    libraries: {
      IndexingAgreementDecoder: IndexingAgreementDecoder,
    },
  })

  // Deploy implementation
  const SubgraphServiceImplementation = deployImplementation(m, {
    name: 'SubgraphService',
    constructorArgs: [controllerAddress, disputeManagerProxyAddress, graphTallyCollectorAddress, curationProxyAddress, recurringCollectorAddress],
  }, {
    libraries: {
      StakeClaims: StakeClaims,
      AllocationHandler: AllocationHandler,
      IndexingAgreementDecoder: IndexingAgreementDecoder,
      IndexingAgreement: IndexingAgreement,
    },
  })

  // Upgrade implementation
  const SubgraphService = upgradeTransparentUpgradeableProxy(
    m,
    SubgraphServiceProxyAdmin,
    SubgraphServiceProxy,
    SubgraphServiceImplementation,
    {
      name: 'SubgraphService',
      artifact: SubgraphServiceArtifact,
      initArgs: [deployer, minimumProvisionTokens, maximumDelegationRatio, stakeToFeesRatio],
    },
  )

  const callSetPauseGuardianGovernor = m.call(SubgraphService, 'setPauseGuardian', [governor, true], {
    id: 'setPauseGuardianGovernor',
  })
  const callSetPauseGuardianPauseGuardian = m.call(SubgraphService, 'setPauseGuardian', [pauseGuardian, true], {
    id: 'setPauseGuardianPauseGuardian',
  })
  const callSetMaxPOIStaleness = m.call(SubgraphService, 'setMaxPOIStaleness', [maxPOIStaleness])
  const callSetCurationCut = m.call(SubgraphService, 'setCurationCut', [curationCut])
  const callSetIndexingFeesCut = m.call(SubgraphService, 'setIndexingFeesCut', [indexingFeesCut])

  m.call(SubgraphService, 'transferOwnership', [governor], {
    after: [
      callSetPauseGuardianGovernor,
      callSetPauseGuardianPauseGuardian,
      callSetMaxPOIStaleness,
      callSetCurationCut,
      callSetIndexingFeesCut,
    ],
  })
  m.call(SubgraphServiceProxyAdmin, 'transferOwnership', [governor], {
    after: [
      callSetPauseGuardianGovernor,
      callSetPauseGuardianPauseGuardian,
      callSetMaxPOIStaleness,
      callSetCurationCut,
      callSetIndexingFeesCut,
    ],
  })

  return {
    SubgraphService,
    SubgraphServiceImplementation,
  }
})
