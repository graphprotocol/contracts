import path from 'path'

import { resetHardhatContext as _resetHardhatContext } from 'hardhat/plugins-testing'
import type { HardhatRuntimeEnvironment } from 'hardhat/types'

declare module 'mocha' {
  interface Context {
    hre: HardhatRuntimeEnvironment
  }
}

export function useHardhatProject(fixtureProjectName: string, network?: string): void {
  beforeEach('Loading hardhat environment', function () {
    this.hre = loadHardhatContext(fixtureProjectName, network)
  })

  afterEach('Resetting hardhat', function () {
    resetHardhatContext()
  })
}

export function loadHardhatContext(fixtureProjectName: string, network?: string): HardhatRuntimeEnvironment {
  resetHardhatContext()
  delete process.env.HARDHAT_NETWORK

  process.chdir(path.join(__dirname, 'fixtures', fixtureProjectName))

  if (network !== undefined) {
    process.env.HARDHAT_NETWORK = network
  }
  // eslint-disable-next-line @typescript-eslint/no-unsafe-return
  return require('hardhat')
}

export function resetHardhatContext(): void {
  _resetHardhatContext()
  delete process.env.HARDHAT_NETWORK
}
