import { promises as fs } from 'fs'
import { task } from 'hardhat/config'

import addresses from '../addresses.json'

enum Contract {
  DataEdge,
  EventfulDataEdge,
}

enum DeployName {
  EBODataEdge = 'EBO',
  SAODataEdge = 'SAO',
}

task('data-edge:deploy', 'Deploy a DataEdge contract')
  .addParam('contract', 'Chose DataEdge or EventfulDataEdge')
  .addParam('deployName', 'Chose EBO or SAO')
  .setAction(async (taskArgs, hre) => {
    if (!Object.values(Contract).includes(taskArgs.contract)) {
      throw new Error(`Contract ${taskArgs.contract} not supported`)
    }

    if (!Object.values(DeployName).includes(taskArgs.deployName)) {
      throw new Error(`Deploy name ${taskArgs.deployName} not supported`)
    }

    const factory = await hre.ethers.getContractFactory(taskArgs.contract)

    console.log(`Deploying contract...`)
    const contract = await factory.deploy()
    const tx = contract.deploymentTransaction()!

    const contractAddress = await contract.getAddress()
    const [signer] = await hre.ethers.getSigners()
    console.log(`> deployer: ${await signer.getAddress()}`)
    console.log(`> contract: ${contractAddress}`)
    console.log(
      `> tx: ${tx.hash} nonce:${tx.nonce} limit: ${tx.gasLimit.toString()} gas: ${Number(tx.gasPrice) / 1e9} (gwei)`,
    )

    await contract.waitForDeployment()
    console.log(`Done!`)

    // Update addresses.json
    const chainId = hre.network.config.chainId!.toString()
    if (!addresses[chainId]) {
      addresses[chainId] = {}
    }
    const deployName = `${taskArgs.deployName}${taskArgs.contract}`
    addresses[chainId][deployName] = contractAddress
    return fs.writeFile('addresses.json', JSON.stringify(addresses, null, 2) + '\n')
  })
