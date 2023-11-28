import { jsonToSubgraphMetadata } from '../metadataHelpers'

import compound from './compound.json'
import decentraland from './decentraland.json'
import ens from './ens.json'
import livepeer from './livepeer.json'
import maker from './maker.json'
import melon from './melon.json'
import moloch from './moloch.json'
import origin from './origin.json'
import thegraph from './thegraph.json'
import uniswap from './uniswap.json'

const compoundMetadata = jsonToSubgraphMetadata(compound)
const decentralandMetadata = jsonToSubgraphMetadata(decentraland)
const ensMetadata = jsonToSubgraphMetadata(ens)
const livepeerMetadata = jsonToSubgraphMetadata(livepeer)
const makerMetadata = jsonToSubgraphMetadata(maker)
const melonMetadata = jsonToSubgraphMetadata(melon)
const molochMetadata = jsonToSubgraphMetadata(moloch)
const originMetadata = jsonToSubgraphMetadata(origin)
const thegraphMetadata = jsonToSubgraphMetadata(thegraph)
const uniswapMetadata = jsonToSubgraphMetadata(uniswap)

export default {
  compoundMetadata,
  decentralandMetadata,
  ensMetadata,
  livepeerMetadata,
  makerMetadata,
  melonMetadata,
  molochMetadata,
  originMetadata,
  thegraphMetadata,
  uniswapMetadata,
}
