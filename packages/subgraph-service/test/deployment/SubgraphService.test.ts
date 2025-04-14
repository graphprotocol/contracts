import hre from 'hardhat'

import { expect } from 'chai'
import { loadConfig } from '@graphprotocol/toolshed/hardhat'
import { transparentUpgradeableProxyTests } from '../../../horizon/test/deployment/lib/TransparentUpgradeableProxy.tests'

const config = loadConfig('./ignition/configs/', 'migrate', hre.network.name).config
const graph = hre.graph()

const addressBookEntry = graph.subgraphService.addressBook.getEntry('SubgraphService')
const SubgraphService = graph.subgraphService.contracts.SubgraphService

describe('SubgraphService', function () {
  it('should be owned by the governor', async function () {
    const owner = await SubgraphService.owner()
    expect(owner).to.equal(config.$global.governor)
  })

  it('should set the right minimum provision tokens', async function () {
    const [minimumProvisionTokens] = await SubgraphService.getProvisionTokensRange()
    expect(minimumProvisionTokens).to.equal(config.SubgraphService.minimumProvisionTokens)
  })

  it('should set the right delegation ratio', async function () {
    const delegationRatio = await SubgraphService.getDelegationRatio()
    expect(delegationRatio).to.equal(config.SubgraphService.maximumDelegationRatio)
  })

  it('should set the right stake to fees ratio', async function () {
    const stakeToFeesRatio = await SubgraphService.stakeToFeesRatio()
    expect(stakeToFeesRatio).to.equal(config.SubgraphService.stakeToFeesRatio)
  })

  it('should set the right dispute manager address', async function () {
    const disputeManagerAddress = await SubgraphService.getDisputeManager()
    expect(disputeManagerAddress).to.equal(config.$global.disputeManagerProxyAddress)
  })

  it('should set the right graph tally address', async function () {
    const graphTallyAddress = await SubgraphService.getGraphTallyCollector()
    expect(graphTallyAddress).to.equal(config.$global.graphTallyCollectorAddress)
  })

  it('should set the right curation address', async function () {
    const curationAddress = await SubgraphService.getCuration()
    expect(curationAddress).to.equal(config.$global.curationProxyAddress)
  })

  it('should set the right pause guardian')

  it('should set the right maxPOIStaleness', async function () {
    const maxPOIStaleness = await SubgraphService.maxPOIStaleness()
    expect(maxPOIStaleness).to.equal(config.SubgraphService.maxPOIStaleness)
  })

  it('should set the right curationCut', async function () {
    const curationCut = await SubgraphService.curationFeesCut()
    expect(curationCut).to.equal(config.SubgraphService.curationCut)
  })
})

transparentUpgradeableProxyTests('SubgraphService', addressBookEntry, config.$global.governor as string)
