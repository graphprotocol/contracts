import fs from 'fs'
import { task } from 'hardhat/config'
import '@nomiclabs/hardhat-ethers'
import { solidityKeccak256 } from 'ethers/lib/utils'
import { BigNumber } from 'ethers'

import { toGRT } from '../../cli/network'

const log = (s, ...params) => console.log(s, ...params)

const buildSubgraphID = (account: string, seqID: BigNumber): string =>
  solidityKeccak256(['address', 'uint256'], [account, seqID])

interface SubgraphConfig {
  ownerAddress: string
  subgraphMetadata: string
  versionMetadata: string
  deploymentId: string
}

// Example:
// {
//   ownerAddress: '0x0e2897efECC61c7B6A3f1B13e34308Cb366B3671',
//   subgraphMetadata: '0xe829843dd866a9abaeb9046ac83679a357109cd90dd00ecb26561565e85ee69f',
//   versionMetadata: '0x4cd9c67bc4d056782e8bad8b1f6642010ef519bbf8e57d4278431ce4a3db65f6',
//   deploymentId: '0xcb7af9cee6e3c7a85c999a39a3a2fca9106736e348251e3ba74151b4463664da'
// }
const loadSubgraphParams = (filename): SubgraphConfig => {
  const data = fs.readFileSync(filename, 'utf8')
  return JSON.parse(data)
}

task('action:subgraph:new', 'New subgraph')
  .addParam('subgraphConfigFile', 'A subgraph config file')
  .addParam('signalAmount', 'Amount to signal in GRT')
  .setAction(async ({ subgraphConfigFile, signalAmount }, hre) => {
    const { contracts } = hre
    const { GNS, GraphToken } = contracts

    // Load config
    const subgraphConfig = loadSubgraphParams(subgraphConfigFile)
    const signalAmountWei = toGRT(signalAmount)

    log(`# Parameters\n`)
    log(`Signal: ${signalAmount} GRT (${signalAmountWei} wei)`)
    log('Subgraph config:')
    log(subgraphConfig)

    log(`\n# Calls`)

    // Approval
    const allowance = await GraphToken.allowance(subgraphConfig.ownerAddress, GNS.address)
    if (allowance.lt(signalAmountWei)) {
      const tx0 = await GraphToken.populateTransaction.approve(GNS.address, signalAmountWei)
      log(`\nApproval Payload ->`, tx0)
    }

    const multicall = []

    // Create a subgraph
    const tx1 = await GNS.populateTransaction.publishNewSubgraph(
      subgraphConfig.deploymentId,
      subgraphConfig.versionMetadata,
      subgraphConfig.subgraphMetadata,
    )
    multicall.push(tx1.data)

    // Curate on the subgraph
    if (signalAmountWei.gt(0)) {
      const nextSeqID = await GNS.nextAccountSeqID(subgraphConfig.ownerAddress)
      const subgraphID = buildSubgraphID(subgraphConfig.ownerAddress, nextSeqID)
      const tx2 = await GNS.populateTransaction.mintSignal(subgraphID, signalAmountWei, 0)
      multicall.push(tx2.data)
      log(
        `Add Signal tx to multicall : (Account: ${subgraphConfig.ownerAddress} SeqID: ${nextSeqID}) -> SubgraphID: ${subgraphID}`,
      )
    }

    // Multicall
    const tx = await GNS.populateTransaction.multicall(multicall)
    log(`\nMulticall Payload ->`, tx)
  })
