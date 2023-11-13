import path from 'path'
import { Artifacts } from 'hardhat/internal/artifacts'
import { LinkReferences } from 'hardhat/types'
import { utils } from 'ethers'

type Abi = Array<string | utils.FunctionFragment | utils.EventFragment | utils.ParamType>

type Artifact = {
  contractName: string
  abi: Abi
  bytecode: string
  deployedBytecode: string
  linkReferences?: LinkReferences
  deployedLinkReferences?: LinkReferences
}

const ARTIFACTS_PATH = path.resolve('build/contracts')

const artifacts = new Artifacts(ARTIFACTS_PATH)

export const loadArtifact = (name: string): Artifact => {
  return artifacts.readArtifactSync(name)
}
