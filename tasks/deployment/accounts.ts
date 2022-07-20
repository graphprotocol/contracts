import { task } from 'hardhat/config'

import { cliOpts } from '../../cli/defaults'
import { updateItem, writeConfig } from '../../cli/config'

task('migrate:accounts', '[localhost] Creates protocol accounts and saves them in graph config')
  .addParam('graphConfig', cliOpts.graphConfig.description, cliOpts.graphConfig.default)
  .setAction(async (taskArgs, hre) => {
    if (hre.network.name !== 'localhost') {
      throw new Error('This task can only be run on localhost network')
    }

    const { graphConfig } = hre.graph({ graphConfig: taskArgs.graphConfig })

    console.log('> Generating addresses')

    const [
      deployer,
      arbitrator,
      governor,
      authority,
      availabilityOracle,
      pauseGuardian,
      edgeAndNode,
    ] = await hre.ethers.getSigners()

    console.log(`- Deployer: ${deployer.address}`)
    console.log(`- Arbitrator: ${arbitrator.address}`)
    console.log(`- Governor: ${governor.address}`)
    console.log(`- Authority: ${authority.address}`)
    console.log(`- Availability Oracle: ${availabilityOracle.address}`)
    console.log(`- Pause Guardian: ${pauseGuardian.address}`)
    console.log(`- Edge & Node: ${edgeAndNode.address}`)

    updateItem(graphConfig, 'general/arbitrator', arbitrator.address)
    updateItem(graphConfig, 'general/governor', governor.address)
    updateItem(graphConfig, 'general/authority', authority.address)
    updateItem(graphConfig, 'general/availabilityOracle', availabilityOracle.address)
    updateItem(graphConfig, 'general/pauseGuardian', pauseGuardian.address)
    updateItem(graphConfig, 'general/edgeAndNode', edgeAndNode.address)

    writeConfig(taskArgs.graphConfig, graphConfig.toString())
  })
