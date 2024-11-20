import path from 'path'
import { resetHardhatContext } from 'hardhat/plugins-testing'

import type { HardhatRuntimeEnvironment } from 'hardhat/types'

declare module 'mocha' {
  interface Context {
    hre: HardhatRuntimeEnvironment
  }
}

export function useEnvironment(fixtureProjectName: string, network?: string): void {
  beforeEach('Loading hardhat environment', function () {
    process.chdir(path.join(__dirname, 'fixtures', fixtureProjectName))

    if (network !== undefined) {
      process.env.HARDHAT_NETWORK = network
    }
    this.hre = require('hardhat')
  })

  afterEach('Resetting hardhat', function () {
    resetHardhatContext()
    delete process.env.HARDHAT_NETWORK
  })
}
