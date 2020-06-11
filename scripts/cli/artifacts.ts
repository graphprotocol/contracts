import fs from 'fs'
import { utils } from 'ethers'

type Abi = Array<string | utils.FunctionFragment | utils.EventFragment | utils.ParamType>

type Artifact = {
  contractName: string
  abi: Abi
  bytecode: string
  deployedBytecode: string
}

type Artifacts = { [contractName: string]: Artifact }

const ARTIFACTS_PATH = './build/contracts/'

export const loadArtifact = (name: string): Artifact => {
  const path = `${ARTIFACTS_PATH}${name}.json`
  return JSON.parse(fs.readFileSync(path, 'utf8') || '{}') as Artifact
}
