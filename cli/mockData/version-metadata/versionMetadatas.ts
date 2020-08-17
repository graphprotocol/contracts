import { jsonToVersionMetadata } from '../../metadataHelpers'

import first from './firstVersion.json'
import second from './secondVersion.json'

const firstVersion = jsonToVersionMetadata(first)
const secondVersion = jsonToVersionMetadata(second)

export default {
  firstVersion,
  secondVersion,
}
