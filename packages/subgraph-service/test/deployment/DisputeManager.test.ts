import { expect } from 'chai'
import hre from 'hardhat'
import { IgnitionHelper } from 'hardhat-graph-protocol/sdk'
import { transparentUpgradeableProxyTests } from '../../../horizon/test/deployment/lib/TransparentUpgradeableProxy.tests'

const config = IgnitionHelper.loadConfig('./ignition/configs/', 'migrate', hre.network.name).config
const graph = hre.graph()

const addressBookEntry = graph.subgraphService!.addressBook.getEntry('DisputeManager')
const DisputeManager = graph.subgraphService!.contracts.DisputeManager

describe('DisputeManager', function () {
  it('should be owned by the governor', async function () {
    const owner = await DisputeManager.owner()
    expect(owner).to.equal(config.$global.governor)
  })

  it('should set the right arbitrator', async function () {
    const arbitrator = await DisputeManager.arbitrator()
    expect(arbitrator).to.equal(config.$global.arbitrator)
  })

  it('should set the right dispute period', async function () {
    const disputePeriod = await DisputeManager.disputePeriod()
    expect(disputePeriod).to.equal(config.DisputeManager.disputePeriod)
  })

  it('should set the right dispute deposit', async function () {
    const disputeDeposit = await DisputeManager.disputeDeposit()
    expect(disputeDeposit).to.equal(config.DisputeManager.disputeDeposit)
  })

  it('should set the right fisherman reward cut', async function () {
    const fishermanRewardCut = await DisputeManager.fishermanRewardCut()
    expect(fishermanRewardCut).to.equal(config.DisputeManager.fishermanRewardCut)
  })

  it('should set the right max slashing cut', async function () {
    const maxSlashingCut = await DisputeManager.maxSlashingCut()
    expect(maxSlashingCut).to.equal(config.DisputeManager.maxSlashingCut)
  })

  it('should set the right subgraph service address', async function () {
    const subgraphService = await DisputeManager.subgraphService()
    expect(subgraphService).to.equal(config.$global.subgraphServiceProxyAddress)
  })
})

transparentUpgradeableProxyTests('DisputeManager', addressBookEntry, config.$global.governor)
