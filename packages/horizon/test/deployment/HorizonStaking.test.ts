import { loadConfig } from '@graphprotocol/toolshed/hardhat'
import { assert, expect } from 'chai'
import hre from 'hardhat'

import { graphProxyTests } from './lib/GraphProxy.test'
import { testIf } from './lib/testIf'

const config = loadConfig(
  './ignition/configs/',
  'migrate',
  String(process.env.TEST_DEPLOYMENT_CONFIG ?? hre.network.name),
).config
const graph = hre.graph()

const horizonStakingAddressBookEntry = graph.horizon.addressBook.getEntry('HorizonStaking')
const HorizonStaking = graph.horizon.contracts.HorizonStaking
const graphProxyAdminAddressBookEntry = graph.horizon.addressBook.getEntry('GraphProxyAdmin')

describe('HorizonStaking', function () {
  testIf(4)('should set the right maxThawingPeriod', async function () {
    const maxThawingPeriod = await HorizonStaking.getMaxThawingPeriod()
    expect(maxThawingPeriod).to.equal(config.$global.maxThawingPeriod)
  })

  testIf(4)('should set delegationSlashingEnabled to false', async function () {
    const delegationSlashingEnabled = await HorizonStaking.isDelegationSlashingEnabled()
    expect(delegationSlashingEnabled).to.equal(false)
  })

  testIf(4)('should set a non zero thawing period', async function () {
    if (process.env.IGNITION_DEPLOYMENT_TYPE === 'protocol') {
      assert.fail('Deployment type "protocol": no historical state available')
    }
    const thawingPeriod = await HorizonStaking.__DEPRECATED_getThawingPeriod()
    expect(thawingPeriod).to.not.equal(0)
  })

  it.skip('should set the right staking extension address')

  testIf(4)('should set the right subgraph data service address', async function () {
    const subgraphDataServiceAddress = await HorizonStaking.getSubgraphService()
    expect(subgraphDataServiceAddress).to.equal(config.$global.subgraphServiceAddress)
  })

  it.skip('should set the right allowed lock verifiers')
})

graphProxyTests('HorizonStaking', horizonStakingAddressBookEntry, graphProxyAdminAddressBookEntry.address)
