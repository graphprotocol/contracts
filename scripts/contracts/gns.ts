#!/usr/bin/env ts-node

import * as path from 'path'
import * as minimist from 'minimist'

import {
  executeTransaction,
  checkFuncInputs,
  configureGanacheWallet,
  configureWallet,
  buildNetworkEndpoint,
  basicOverrides,
} from './helpers'
import { ConnectedGNS, ConnectedENS, ConnectedGraphToken } from './connectedContracts'
import { connectContracts } from './connectedNetwork'
import { Wallet, utils } from 'ethers'

const {
  network,
  func,
  ipfs,
  graphAccount,
  subgraphDeploymentID,
  name,
  versionPath,
  subgraphPath,
  subgraphNumber,
  tokens,
  nSignal,
} = minimist.default(process.argv.slice(2), {
  string: [
    'network',
    'func',
    'ipfs',
    'graphAccount',
    'subgraphDeploymentID',
    'name',
    'versionPath',
    'subgraphPath',
    'subgraphNumber',
    'tokens',
    'nSignal',
  ],
})

if (!network || !func || !graphAccount) {
  console.error(
    `
Usage: ${path.basename(process.argv[1])}
  --network  <string> - options: ganache, kovan, rinkeby
  --func <text> - options: setDefaultName, publishNewSubgraph, publishVersion, deprecate,
                           updateSubgraphMetadata, mintNSignal, burnNSignal, withdrawGRT

  Function arguments:
  setDefaultName
    --graphAccount <address>        - graph account address
    --nameSystem <number>           - 0 = ENS
    --name <string>                 - name that has been registered and is getting set as default

  publishNewSubgraph
    --ipfs <url>                    - ex. https://api.thegraph.com/ipfs/
    --graphAccount <address>        - graph account address
    --subgraphDeploymentID <base58> - subgraphID in base58
    --versionPath <path>            - filepath to metadata. JSON format:
                                        {
                                          "description": "",
                                          "label": ""
                                        }
    --subgraphPath <path>           - filepath to metadata. JSON format:
                                        {
                                          "description": "",
                                          "displayName": "",
                                          "image": "",
                                          "codeRepository": "",
                                          "website": "",
                                        }

  publishVersion
    --ipfs <url>                    - ex. https://api.thegraph.com/ipfs/
    --graphAccount <address>        - graph account address
    --subgraphDeploymentID <base58> - subgraphID in base58
    --subgraphPath <path>           - filepath to version metadata. Same format as above
    --subgraphNumber <number>       - numbered subgraph for the graph account
    
  deprecate
    --graphAccount <address>        - graph account address
    --subgraphNumber <number>       - numbered subgraph for the graph account

  updateSubgraphMetadata
    --graphAccount <address>        - graph account address
    --subgraphNumber <number>       - numbered subgraph for the graph account
    --subgraphPath <path>           - filepath to subgraph metadata. Same format as above

  mintNSignal
    --graphAccount <address>        - graph account address
    --subgraphNumber <number>       - numbered subgraph for the graph account
    --tokens <number>               - tokens being deposited. Script adds 10^18
  
  burnNSignal
    --graphAccount <address>        - graph account address
    --subgraphNumber <number>       - numbered subgraph for the graph account
    --nSignal <number>              - tokens being burnt. Script adds 10^18

  withdrawGRT
    --graphAccount <address>        - graph account address
    --subgraphNumber <number>       - numbered subgraph for the graph account
  `,
  )
  process.exit(1)
}

const main = async () => {
  let gns: ConnectedGNS
  let connectedGT: ConnectedGraphToken
  let provider
  let mnemonicWallet: Wallet
  const networkContracts = await connectContracts(mnemonicWallet, network)

  if (network == 'ganache') {
    provider = buildNetworkEndpoint(network)
    mnemonicWallet = configureWallet(process.env.MNEMONIC, provider)
    gns = new ConnectedGNS(network, configureGanacheWallet())
    connectedGT = new ConnectedGraphToken(network, configureGanacheWallet())
  } else {
    provider = buildNetworkEndpoint(network, 'infura')
    mnemonicWallet = configureWallet(process.env.MNEMONIC, provider)
    gns = new ConnectedGNS(network, mnemonicWallet)
    connectedGT = new ConnectedGraphToken(network, configureWallet(process.env.MNEMONIC, provider))
  }

  try {
    if (func == 'setDefaultName') {
      checkFuncInputs([name], ['name'], func)
      console.log(`Setting default name for ${name}`)
      const ens = new ConnectedENS(network, mnemonicWallet)
      await executeTransaction(
        networkContracts.gns.setDefaultName(graphAccount, 0, ens.getNode(name), name),
        network,
      )
    }
    if (func == 'publishNewSubgraph') {
      checkFuncInputs(
        [ipfs, subgraphDeploymentID, versionPath, subgraphPath],
        ['ipfs', 'subgraphDeploymentID', 'versionPath', 'subgraphPath'],
        func,
      )
      console.log(`Publishing 1st version of subgraph ${name} ...`)
      await executeTransaction(
        gns.pinIPFSAndNewSubgraph(
          ipfs,
          graphAccount,
          subgraphDeploymentID,
          versionPath,
          subgraphPath,
        ),
        network,
      )
    } else if (func == 'publishNewVersion') {
      checkFuncInputs(
        [ipfs, subgraphDeploymentID, versionPath, subgraphNumber],
        ['ipfs', 'subgraphDeploymentID', 'versionPath', 'subgraphNumber'],
        func,
      )
      console.log(`Publishing a new version for subgraph ${name} ...`)
      await executeTransaction(
        gns.pinIPFSAndNewVersion(
          ipfs,
          graphAccount,
          subgraphDeploymentID,
          versionPath,
          subgraphNumber,
        ),
        network,
      )
    } else if (func == 'deprecate') {
      checkFuncInputs([subgraphNumber], ['subgraphNumber'], func)
      console.log(`Deprecating subgraph ${graphAccount}-${subgraphNumber}`)
      await executeTransaction(gns.gns.deprecateSubgraph(graphAccount, subgraphNumber), network)
    } else if (func == 'updateSubgraphMetadata') {
      checkFuncInputs([subgraphNumber, subgraphPath], ['subgraphNumber', 'subgraphPath'], func)
      console.log(`Updating subgraph metadata for ${graphAccount}-${subgraphNumber}`)
      await executeTransaction(
        gns.gns.updateSubgraphMetadata(graphAccount, subgraphNumber, subgraphPath),
        network,
      )
    } else if (func == 'mintNSignal') {
      checkFuncInputs([subgraphNumber, tokens], ['subgraphNumber', 'tokens'], func)
      console.log(
        '  First calling approve() to ensure curation contract can call transferFrom()...',
      )
      const tokensWithDecimal = utils.parseUnits(tokens as string, 18).toString()
      await executeTransaction(
        connectedGT.approveWithDecimals(networkContracts.gns.address, tokensWithDecimal),
        network,
      )
      console.log(`Minting nSignal with ${tokens} on ${graphAccount}-${subgraphNumber}`)
      await executeTransaction(
        gns.gns.mintNSignal(graphAccount, subgraphNumber, tokensWithDecimal, basicOverrides()),
        network,
      )
    } else if (func == 'burnNSignal') {
      checkFuncInputs([subgraphNumber, nSignal], ['subgraphNumber', nSignal], func)
      console.log(`Burning ${nSignal} nSignal on ${graphAccount}-${subgraphNumber}`)
      const nSignalWithDecimal = utils.parseUnits(nSignal as string, 18).toString()
      await executeTransaction(
        gns.gns.burnNSignal(graphAccount, subgraphNumber, nSignalWithDecimal),
        network,
      )
    } else if (func == 'withdrawGRT') {
      checkFuncInputs([subgraphNumber], ['subgraphNumber'], func)
      console.log(`Withdrawing GRT from deprecated subgraph ${graphAccount}-${subgraphNumber}`)
      await executeTransaction(gns.gns.withdraw(graphAccount, subgraphNumber), network)
    } else {
      console.log(`Wrong func name provided`)
      process.exit(1)
    }
  } catch (e) {
    console.log(`  ..failed within main: ${e.message}`)
    process.exit(1)
  }
}

main()
