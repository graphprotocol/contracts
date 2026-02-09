import { type AddressBookJson, runTenderlyUpload } from '@graphprotocol/toolshed/hardhat'
import { task } from 'hardhat/config'
import { HardhatRuntimeEnvironment } from 'hardhat/types'
import path from 'path'

import addresses from '../addresses.json'

task('tenderly:upload', 'Upload and verify contracts on Tenderly')
  .addFlag('noVerify', 'Skip contract verification')
  .addFlag('skipAdd', 'Skip adding contracts (only verify)')
  .setAction(async (taskArgs: { noVerify: boolean; skipAdd: boolean }, hre: HardhatRuntimeEnvironment) => {
    // Dynamically import tenderly plugin only when this task runs
    // This avoids triggering provider initialization for other hardhat commands
    const { Tenderly } = require('@tenderly/hardhat-integration')
    const { configExists, getAccessToken } = require('@tenderly/api-client/utils/config')

    if (!configExists()) {
      throw new Error(
        'Tenderly config not found. Run `tenderly login` to authenticate, or create ~/.tenderly/config.yaml manually.',
      )
    }

    const tenderly = new Tenderly(hre)
    const accessToken = getAccessToken()
    const packageDir = path.join(__dirname, '..')

    await runTenderlyUpload(hre, tenderly, packageDir, addresses as AddressBookJson, accessToken, taskArgs)
  })
