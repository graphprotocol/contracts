import { expect } from 'chai'
import hre from 'hardhat'
import { IgnitionHelper } from 'hardhat-graph-protocol/sdk'

import type { GraphRuntimeEnvironment } from 'hardhat-graph-protocol'

import type { GraphPayments } from '../../typechain-types'

let graph: GraphRuntimeEnvironment
// eslint-disable-next-line @typescript-eslint/no-explicit-any
let config: any

let GraphPayments: GraphPayments

describe('GraphPayments', function () {
  before(function () {
    graph = hre.graph()
    config = IgnitionHelper.loadConfig('./ignition/configs/', 'migrate', hre.network.name).config

    GraphPayments = graph.horizon!.contracts.GraphPayments
  })

  it('Should set the right protocolPaymentCut', async function () {
    const protocolPaymentCut = await GraphPayments.PROTOCOL_PAYMENT_CUT()
    expect(protocolPaymentCut).to.equal(config.GraphPayments.protocolPaymentCut)
  })
})
