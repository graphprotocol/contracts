import { ContractFactory } from 'ethers'
import { loadArtifact } from './artifacts'

import type { Artifact } from 'hardhat/types'
import type { Libraries } from '../types/artifacts'

/**
 * Gets a contract factory for a given contract name
 *
 * @param name Name of the contract
 * @param libraries Libraries to link
 * @returns the contract factory
 */
export const getContractFactory = (name: string, libraries?: Libraries): ContractFactory => {
  const artifact = loadArtifact(name)
  // Fixup libraries
  if (libraries && Object.keys(libraries).length > 0) {
    artifact.bytecode = linkLibraries(artifact, libraries)
  }
  return new ContractFactory(artifact.abi, artifact.bytecode)
}

const linkLibraries = (artifact: Artifact, libraries?: Libraries): string => {
  let bytecode = artifact.bytecode

  if (libraries) {
    if (artifact.linkReferences) {
      for (const fileReferences of Object.values(artifact.linkReferences)) {
        for (const [libName, fixups] of Object.entries(fileReferences)) {
          const addr = libraries[libName]
          if (addr === undefined) {
            continue
          }

          for (const fixup of fixups) {
            bytecode =
              bytecode.substr(0, 2 + fixup.start * 2) +
              addr.substr(2) +
              bytecode.substr(2 + (fixup.start + fixup.length) * 2)
          }
        }
      }
    }
  }
  return bytecode
}
