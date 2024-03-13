import { subtask, task } from 'hardhat/config'
import fs from 'fs'
import { execSync } from 'child_process'
import { greTask } from '@graphprotocol/sdk/gre'
import { helpers } from '@graphprotocol/sdk'

greTask(
  'migrate:nitro:fund-accounts',
  'Funds protocol accounts on Arbitrum Nitro testnodes',
).setAction(async (taskArgs, hre) => {
  const graph = hre.graph(taskArgs)
  await helpers.fundLocalAccounts(
    [await graph.getDeployer(), ...(await graph.getAllAccounts())],
    graph.provider,
  )
})

// Arbitrum SDK does not support Nitro testnodes out of the box
// This adds the testnodes to the SDK configuration
subtask('migrate:nitro:register', 'Adds nitro testnodes to SDK config')
  .addParam('deploymentFile', 'The testnode deployment file to use', 'localNetwork.json')
  // eslint-disable-next-line @typescript-eslint/require-await
  .setAction(async (taskArgs): Promise<void> => {
    helpers.addLocalNetwork(taskArgs.deploymentFile)
  })

subtask('migrate:nitro:deployment-file', 'Fetches nitro deployment file from a local testnode')
  .addParam(
    'deploymentFile',
    'Path to the file where to deployment file will be saved',
    'localNetwork.json',
  )
  // eslint-disable-next-line @typescript-eslint/require-await
  .setAction(async (taskArgs) => {
    console.log(`Attempting to fetch deployment file from testnode...`)

    const command = `docker container cp $(docker ps -alqf "name=tokenbridge" --format "{{.ID}}"):/workspace/localNetwork.json .`
    const stdOut = execSync(command)
    console.log(stdOut.toString())

    if (!fs.existsSync(taskArgs.deploymentFile)) {
      throw new Error(`Unable to fetch deployment file: ${taskArgs.deploymentFile}`)
    }
    console.log(`Deployment file saved to ${taskArgs.deploymentFile}`)
  })

// Read arbitrum contract addresses from deployment file and write them to the address book
task('migrate:nitro:address-book', 'Write arbitrum addresses to address book')
  .addParam('deploymentFile', 'The testnode deployment file to use')
  .addParam('arbitrumAddressBook', 'Arbitrum address book file')
  .setAction(async (taskArgs, hre) => {
    if (!fs.existsSync(taskArgs.deploymentFile)) {
      await hre.run('migrate:nitro:deployment-file', taskArgs)
    }
    const deployment = JSON.parse(fs.readFileSync(taskArgs.deploymentFile, 'utf-8'))

    const addressBook = {
      1337: {
        L1GatewayRouter: {
          address: deployment.l2Network.tokenBridge.l1GatewayRouter,
        },
        IInbox: {
          address: deployment.l2Network.ethBridge.inbox,
        },
      },
      412346: {
        L2GatewayRouter: {
          address: deployment.l2Network.tokenBridge.l2GatewayRouter,
        },
      },
    }

    fs.writeFileSync(taskArgs.arbitrumAddressBook, JSON.stringify(addressBook))
  })
