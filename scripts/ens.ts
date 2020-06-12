#!/usr/bin/env ts-node

import { utils } from 'ethers'
import * as path from 'path'
import * as minimist from 'minimist'

import { contracts, executeTransaction, overrides, checkUserInputs } from './helpers'

///////////////////////
// Set up the script //
///////////////////////

let { func, name, node } = minimist.default(process.argv.slice(2), {
  string: ['func', 'name', 'node'],
})

if (!func) {
  console.error(
    `
Usage: ${path.basename(process.argv[1])}
    --func <string> - options: setRecord, setText

Function arguments:
    setRecord
      --name <string>   - name being registered on ens

    setText
      --node <bytes32>  - node having the graph text field set
`,
  )
  process.exit(1)
}

///////////////////////
// functions //////////
///////////////////////

const setRecord = async () => {
  checkUserInputs([name], ['name'], 'setRecord')
  const node = utils.namehash(name)
  const ttl = 31536000 // time to live = 1 year
  const resolverAddress = contracts.publicResolver.address
  const signeraddress = await contracts.ens.signer.getAddress()
  console.log(signeraddress)
  const ensOverrides = await overrides('ens', 'setRecord')
  console.log('Namehash node: ', node)
  await executeTransaction(
    contracts.ens.setRecord(node, signeraddress, resolverAddress, ttl, ensOverrides),
  )
}

// NOT IN USE, SEE setTestRecord
// const setSubnodeRecord = async (nodeName: string, labelName: string) => {
//   checkUserInputs([nodeName, labelName], ['nodeName', 'labelName'], 'setSubnodeRecord')
//   const node = utils.namehash(nodeName)
//   const labelNameFull = `${labelName}.${nodeName}`
//   const label = utils.namehash(labelNameFull)
//   const ttl = 31536000 // time to live = 1 year
//   const resolverAddress = contracts.publicResolver.address
//   const signeraddress = await contracts.ens.signer.getAddress()
//   console.log(signeraddress)
//   const ensOverrides = await overrides('ens', 'setSubnodeRecord')
//   console.log('Namehash node: ', node)
//   console.log('Namehash labelNameFull: ', labelNameFull)
//   console.log('Namehash label: ', label)

//   await executeTransaction(
//     contracts.ens.setSubnodeRecord(node, label, signeraddress, resolverAddress, ttl, ensOverrides),
//   )
// }

const setTestRecord = async (labelName: string) => {
    checkUserInputs([labelName], ['labelName'], 'setTestRecord')
    const node = utils.namehash('test')
    const labelNameFull = `${labelName}.${'test'}`
    const label = utils.keccak256(utils.toUtf8Bytes(labelName))
    console.log(label)
    const labelHashFull = utils.namehash(labelNameFull)
    const signeraddress = await contracts.ens.signer.getAddress()
    const ensOverrides = await overrides('ens', 'register')
    console.log('Namehash node for "test": ', node)
    console.log(`Hash of label ${labelName}: `, label)
    console.log(`Namehash for ${labelNameFull}: ${labelHashFull}`)
  
    await executeTransaction(
      contracts.testRegistrar.register(label, signeraddress, ensOverrides),
    )
  }

  const setText = async () => {
    checkUserInputs([node], ['node'], 'setText')
    const key = 'GRAPH NAME SERVICE'
    const ensOverrides = await overrides('ens', 'setText')
    const signeraddress = await contracts.publicResolver.signer.getAddress()
    await executeTransaction(contracts.publicResolver.setText(node, key, '0x93606b27cB5e4c780883eC4F6b7Bed5f6572d1dd', ensOverrides))
  }

const checkOwner = async () => {
  checkUserInputs([name], ['name'], 'checkOwner')
  try {
    const node = utils.namehash('thegraph')
    console.log(node)
    const res = await contracts.ens.owner(node)
    console.log(`Owner of ${name} is ${res}`)
  } catch (e) {
    console.log(`  ..failed within main: ${e.message}`)
  }
}

///////////////////////
// main ///////////////
///////////////////////

const main = async () => {
  try {
    if (func == 'setTestRecord') {
      console.log(`Setting owner for ${name} ...`)
      setTestRecord(name)
    } else if (func == 'setText') {
      console.log(`Setting text record of 'GRAPH NAME SERVICE' for caller ...`)
      setText()
    // } else if (func == 'setEthDomain') { NOT IN USE
    //   console.log(`Setting '.eth' domain ...`)
    //   setSubnodeRecord('', 'eth')
    } else if (func == 'checkOwner') {
      console.log(`Checking owner of ${name} ...`)
      checkOwner()
    } else if (func == 'namehash') {
        console.log(`Namehash of ${name}: ${utils.namehash(name)}`)
    } else {
      console.log(`Wrong func name provided`)
      process.exit(1)
    }
  } catch (e) {
    console.log(`  ..failed within main: ${e.message}`)
    process.exit(1)
  }
}

main()
