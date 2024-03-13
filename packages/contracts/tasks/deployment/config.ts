import {
  confirm,
  GraphNetworkConfigContractList,
  GraphNetworkConfigGeneralParams,
  updateContractParams,
  updateGeneralParams,
  writeConfig,
} from '@graphprotocol/sdk'
import { greTask } from '@graphprotocol/sdk/gre'

greTask('update-config', 'Update graph config parameters with onchain data')
  .addFlag('dryRun', 'Only print the changes, don\'t write them to the config file')
  .addFlag('skipConfirmation', 'Skip confirmation prompt on write actions.')
  .setAction(async (taskArgs, hre) => {
    const networkName = hre.network.name
    const configFile = taskArgs.graphConfig
    const dryRun = taskArgs.dryRun
    const skipConfirmation = taskArgs.skipConfirmation

    console.log('## Update graph config ##')
    console.log(`Network: ${networkName}`)
    console.log(`Config file: ${configFile}\n`)

    // Prompt to avoid accidentally overwriting the config file with data from another network
    if (!configFile.includes(networkName)) {
      const sure = await confirm(
        `Config file ${configFile} doesn't match 'graph.<networkName>.yml'. Are you sure you want to continue?`,
        skipConfirmation,
      )
      if (!sure) return
    }

    const { graphConfig, contracts } = hre.graph({ graphConfig: configFile })

    // general parameters
    console.log(`> General`)
    for (const param of GraphNetworkConfigGeneralParams) {
      await updateGeneralParams(contracts, param, graphConfig)
    }

    // contracts parameters
    for (const contract of GraphNetworkConfigContractList) {
      console.log(`> ${contract.name}`)
      await updateContractParams(contracts, contract, graphConfig)
    }

    if (dryRun) {
      console.log('\n Dry run enabled, printing changes to console (no files updated)\n')
      console.log(graphConfig.toString())
    } else {
      writeConfig(configFile, graphConfig.toString())
    }
  })
