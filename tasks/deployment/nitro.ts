import { BigNumber, ContractTransaction } from 'ethers'
import { subtask, task } from 'hardhat/config'
import { cliOpts } from '../../cli/defaults'
import { addCustomNetwork } from '@arbitrum/sdk/dist/lib/dataEntities/networks'
import fs from 'fs'
import { execSync } from 'child_process'

export const TASK_NITRO_FUND_ACCOUNTS = 'nitro:fund-accounts'
export const TASK_NITRO_SETUP_SDK = 'nitro:sdk-setup'
export const TASK_NITRO_SETUP_ADDRESS_BOOK = 'nitro:address-book-setup'
export const TASK_NITRO_FETCH_DEPLOYMENT_FILE = 'nitro:fetch-deployment-file'

task(TASK_NITRO_FUND_ACCOUNTS, 'Funds protocol accounts on Arbitrum Nitro testnodes')
  .addFlag('disableSecureAccounts', 'Disable secure accounts on GRE')
  .addOptionalParam('graphConfig', cliOpts.graphConfig.description)
  .addOptionalParam('privateKey', 'The private key for Arbitrum testnode genesis account')
  .addOptionalParam('amount', 'The amount to fund each account with')
  .setAction(async (taskArgs, hre) => {
    // Arbitrum Nitro testnodes have a pre-funded genesis account whose private key is hardcoded here:
    // - L1 > https://github.com/OffchainLabs/nitro/blob/01c558c06ad9cbaa083bebe3e51960e195c3fd6b/test-node.bash#L136
    // - L2 > https://github.com/OffchainLabs/nitro/blob/01c558c06ad9cbaa083bebe3e51960e195c3fd6b/testnode-scripts/config.ts#L22
    const genesisAccountPrivateKey =
      taskArgs.privateKey ?? 'e887f7d17d07cc7b8004053fb8826f6657084e88904bb61590e498ca04704cf2'
    const genesisAccount = new hre.ethers.Wallet(genesisAccountPrivateKey)

    // Get protocol accounts
    const { getDeployer, getNamedAccounts, getTestAccounts, provider } = hre.graph(taskArgs)
    const deployer = await getDeployer()
    const testAccounts = await getTestAccounts()
    const namedAccounts = await getNamedAccounts()
    const accounts = [
      deployer,
      ...testAccounts,
      ...Object.keys(namedAccounts).map((k) => namedAccounts[k]),
    ]

    // Amount to fund
    // - If amount is specified, use that
    // - Otherwise, use 95% of genesis account balance with a maximum of 100 Eth
    let amount: BigNumber
    const maxAmount = hre.ethers.utils.parseEther('100')
    const genesisAccountBalance = await provider.getBalance(genesisAccount.address)

    if (taskArgs.amount) {
      amount = hre.ethers.BigNumber.from(taskArgs.amount)
    } else {
      const splitGenesisBalance = genesisAccountBalance.mul(95).div(100).div(accounts.length)
      if (splitGenesisBalance.gt(maxAmount)) {
        amount = maxAmount
      } else {
        amount = splitGenesisBalance
      }
    }

    // Check genesis account balance
    const requiredFunds = amount.mul(accounts.length)
    if (genesisAccountBalance.lt(requiredFunds)) {
      throw new Error('Insufficient funds in genesis account')
    }

    // Fund accounts
    console.log('> Funding protocol addresses')
    console.log(`Genesis account: ${genesisAccount.address}`)
    console.log(`Total accounts: ${accounts.length}`)
    console.log(`Amount per account: ${hre.ethers.utils.formatEther(amount)}`)
    console.log(`Required funds: ${hre.ethers.utils.formatEther(requiredFunds)}`)

    const txs: ContractTransaction[] = []
    for (const account of accounts) {
      const tx = await genesisAccount.connect(provider).sendTransaction({
        value: amount,
        to: account.address,
      })
      txs.push(tx)
    }
    await Promise.all(txs.map((tx) => tx.wait()))
    console.log('Done!')
  })

// Arbitrum SDK does not support Nitro testnodes out of the box
// This adds the testnodes to the SDK configuration
subtask(TASK_NITRO_SETUP_SDK, 'Adds nitro testnodes to SDK config')
  .addParam('deploymentFile', 'The testnode deployment file to use', 'localNetwork.json')
  .setAction(async (taskArgs) => {
    if (!fs.existsSync(taskArgs.deploymentFile)) {
      throw new Error(`Deployment file not found: ${taskArgs.deploymentFile}`)
    }
    const deployment = JSON.parse(fs.readFileSync(taskArgs.deploymentFile, 'utf-8'))
    addCustomNetwork({
      customL1Network: deployment.l1Network,
      customL2Network: deployment.l2Network,
    })
  })

subtask(TASK_NITRO_FETCH_DEPLOYMENT_FILE, 'Fetches nitro deployment file from a local testnode')
  .addParam(
    'deploymentFile',
    'Path to the file where to deployment file will be saved',
    'localNetwork.json',
  )
  .setAction(async (taskArgs) => {
    console.log(`Attempting to fetch deployment file from testnode...`)

    const command = `docker exec $(docker ps -qf "name=sequencer") cat /workspace/localNetwork.json > ${taskArgs.deploymentFile}`
    const stdOut = execSync(command)
    console.log(stdOut.toString())

    if (!fs.existsSync(taskArgs.deploymentFile)) {
      throw new Error(`Unable to fetch deployment file: ${taskArgs.deploymentFile}`)
    }
    console.log(`Deployment file saved to ${taskArgs.deploymentFile}`)
  })

// Read arbitrum contract addresses from deployment file and write them to the address book
task(TASK_NITRO_SETUP_ADDRESS_BOOK, 'Write arbitrum addresses to address book')
  .addParam('deploymentFile', 'The testnode deployment file to use')
  .addParam('arbitrumAddressBook', 'Arbitrum address book file')
  .setAction(async (taskArgs, hre) => {
    if (!fs.existsSync(taskArgs.deploymentFile)) {
      await hre.run(TASK_NITRO_FETCH_DEPLOYMENT_FILE, taskArgs)
    }
    const deployment = JSON.parse(fs.readFileSync(taskArgs.deploymentFile, 'utf-8'))

    const addressBook = {
      '1337': {
        L1GatewayRouter: {
          address: deployment.l2Network.tokenBridge.l1GatewayRouter,
        },
        IInbox: {
          address: deployment.l2Network.ethBridge.inbox,
        },
      },
      '412346': {
        L2GatewayRouter: {
          address: deployment.l2Network.tokenBridge.l2GatewayRouter,
        },
      },
    }

    fs.writeFileSync(taskArgs.arbitrumAddressBook, JSON.stringify(addressBook))
  })
