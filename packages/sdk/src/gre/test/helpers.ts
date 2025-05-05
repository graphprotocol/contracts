import { resetHardhatContext } from 'hardhat/plugins-testing'
import { HardhatRuntimeEnvironment } from 'hardhat/types'
import path from 'path'

declare module 'mocha' {
  interface Context {
    hre: HardhatRuntimeEnvironment
  }
}

export function useEnvironment(fixtureProjectName: string, network?: string): void {
  beforeEach('Loading hardhat environment', function () {
    process.chdir(path.join(__dirname, 'fixture-projects', fixtureProjectName))

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
