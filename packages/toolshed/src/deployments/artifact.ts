import { Artifacts } from 'hardhat/internal/artifacts'

import type { Artifact } from 'hardhat/types'

/**
 * Load a contract's artifact from the build output folder
 * If multiple build output folders are provided, they will be searched in order
 * @param name Name of the contract
 * @param buildDir Path to the build output folder(s). Defaults to `build/contracts`.
 * @returns The artifact corresponding to the contract name
 */
export const loadArtifact = (name: string, buildDir?: string[] | string): Artifact => {
  let artifacts: Artifacts
  let artifact: Artifact | undefined
  buildDir = buildDir ?? ['build/contracts']

  if (typeof buildDir === 'string') {
    buildDir = [buildDir]
  }

  for (const dir of buildDir) {
    try {
      artifacts = new Artifacts(dir)
      artifact = artifacts.readArtifactSync(name)
      break
    } catch (error) {
      if (error instanceof Error) {
        throw new Error(`Could not load artifact ${name} from ${dir} - ${error.message}`)
      } else {
        throw new Error(`Could not load artifact ${name} from ${dir}`)
      }
    }
  }

  if (artifact === undefined) {
    throw new Error(`Could not load artifact ${name}`)
  }

  return artifact
}
