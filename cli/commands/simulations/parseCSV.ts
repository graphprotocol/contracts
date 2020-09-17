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
export function parseSubgraphsCSV(path: string) {
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
