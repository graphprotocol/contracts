import { expect } from 'chai'
import hre from 'hardhat'
import { IgnitionHelper } from 'hardhat-graph-protocol/sdk'
import { transparentUpgradeableProxyTests } from '../../../horizon/test/deployment/lib/TransparentUpgradeableProxy.tests'

const config = IgnitionHelper.loadConfig('./ignition/configs/', 'migrate', hre.network.name).config
const graph = hre.graph()

const addressBookEntry = graph.subgraphService!.addressBook.getEntry('SubgraphService')
const SubgraphService = graph.subgraphService!.contracts.SubgraphService

describe('SubgraphService', function () {
  it('should set the right minimum provision tokens', async function () {
    const minimumProvisionTokens = await SubgraphService.minimumProvisionTokens()
    expect(minimumProvisionTokens).to.equal(config.SubgraphService.minimumProvisionTokens)
  })

  it('should set the right delegation ratio', async function () {
    const delegationRatio = await SubgraphService.getDelegationRatio()
    expect(delegationRatio).to.equal(config.SubgraphService.delegationRatio)
  })

  it('should set the right stake to fees ratio', async function () {
    const stakeToFeesRatio = await SubgraphService.stakeToFeesRatio()
    expect(stakeToFeesRatio).to.equal(config.SubgraphService.stakeToFeesRatio)
  })

  it('should set the right dispute manager address')

  it('should set the right graph tally address')

  it('should set the right curation address')

  it('should set the right pause guardian')

  it('should set the right maxPOIStaleness', async function () {
    const maxPOIStaleness = await SubgraphService.maxPOIStaleness()
    expect(maxPOIStaleness).to.equal(config.SubgraphService.maxPOIStaleness)
  })

  it('should set the right curationCut', async function () {
    const curationCut = await SubgraphService.curationFeesCut()
    expect(curationCut).to.equal(config.SubgraphService.curationFeesCut)
  })
})

transparentUpgradeableProxyTests('SubgraphService', addressBookEntry, config.$global.governor)
