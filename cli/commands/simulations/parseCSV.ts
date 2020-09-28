import fs from 'fs'
// import { utils } from 'ethers'

import { SubgraphMetadata } from '../../metadata'

export interface CurateSimulationTransaction {
  subgraphID: string
  signal: string
  subgraph: SubgraphMetadata
}

// Parses a CSV where the titles are ordered like so:
//  displayName,description,subgraphID,signal,codeRepository,image,website
export function parseCreateSubgraphsCSV(path: string): Array<CurateSimulationTransaction> {
  const data = fs.readFileSync(path, 'utf8')
  const subgraphs = data.split('\n').map((e) => e.trim())
  const txData: Array<CurateSimulationTransaction> = []
  for (let i = 1; i < subgraphs.length; i++) {
    // skip the csv title line by starting at 1
    const csvSubgraph = subgraphs[i]

    const [
      displayName,
      description,
      subgraphID,
      signal,
      codeRepository,
      image,
      website,
    ] = csvSubgraph.split(',').map((e) => e.trim())
    const subgraph: SubgraphMetadata = {
      description: description,
      displayName: displayName,
      image: image,
      codeRepository: codeRepository,
      website: website,
    }

    const curateData: CurateSimulationTransaction = {
      subgraphID: subgraphID,
      signal: signal,
      subgraph: subgraph,
    }
    txData.push(curateData)
  }
  return txData
}

export interface UnsignalTransaction {
  account: string
  subgraphNumber: string
  amount: string
}

// Parses a CSV for unsignalling
export function parseUnsignalCSV(path: string): Array<UnsignalTransaction> {
  const data = fs.readFileSync(path, 'utf8')
  const subgraphs = data.split('\n').map((e) => e.trim())
  const txData: Array<UnsignalTransaction> = []
  for (let i = 1; i < subgraphs.length; i++) {
    // skip the csv title line by starting at 1
    const csvData = subgraphs[i]
    const [account, subgraphNumber, amount] = csvData.split(',').map((e) => e.trim())
    const data: UnsignalTransaction = {
      account: account,
      subgraphNumber: subgraphNumber,
      amount: amount,
    }
    txData.push(data)
  }
  return txData
}
