import '@nomiclabs/hardhat-ethers'
import { task } from 'hardhat/config'

import addresses from '../addresses.json'

import { promises as fs } from 'fs'

enum Contract {
  DataEdge,
  EventfulDataEdge
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
    const tx = contract.deployTransaction

    // The address the Contract WILL have once mined
    console.log(`> deployer: ${await contract.signer.getAddress()}`)
    console.log(`> contract: ${contract.address}`)
    console.log(`> tx: ${tx.hash} nonce:${tx.nonce} limit: ${tx.gasLimit.toString()} gas: ${tx.gasPrice.toNumber() / 1e9} (gwei)`)

    // The contract is NOT deployed yet; we must wait until it is mined
    await contract.deployed()
    console.log(`Done!`)

    // Update addresses.json
    const chainId = (hre.network.config.chainId).toString()
    if (!addresses[chainId]) {
      addresses[chainId] = {}
    }
    let deployName = `${taskArgs.deployName}${taskArgs.contract}`
    addresses[chainId][deployName] = contract.address
    return fs.writeFile('addresses.json', JSON.stringify(addresses, null, 2))
  })
