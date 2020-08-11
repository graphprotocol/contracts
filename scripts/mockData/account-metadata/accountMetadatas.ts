import { jsonToAccountMetadata } from '../metadataHelpers'

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

const compoundAccountMetadata = jsonToAccountMetadata(compound)
const decentralandAccountMetadata = jsonToAccountMetadata(decentraland)
const ensAccountMetadata = jsonToAccountMetadata(ens)
const livepeerAccountMetadata = jsonToAccountMetadata(livepeer)
const makerAccountMetadata = jsonToAccountMetadata(maker)
const melonAccountMetadata = jsonToAccountMetadata(melon)
const molochAccountMetadata = jsonToAccountMetadata(moloch)
const originAccountMetadata = jsonToAccountMetadata(origin)
const thegraphAccountMetadata = jsonToAccountMetadata(thegraph)
const uniswapAccountMetadata = jsonToAccountMetadata(uniswap)

export default {
  compoundAccountMetadata,
  decentralandAccountMetadata,
  ensAccountMetadata,
  livepeerAccountMetadata,
  makerAccountMetadata,
  melonAccountMetadata,
  molochAccountMetadata,
  originAccountMetadata,
  thegraphAccountMetadata,
  uniswapAccountMetadata,
}
