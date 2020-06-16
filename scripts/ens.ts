#!/usr/bin/env ts-node

import { utils } from 'ethers'
import * as path from 'path'
import * as minimist from 'minimist'

import { contracts, executeTransaction, overrides, checkFuncInputs } from './helpers'

///////////////////////
// Set up the script //
///////////////////////

const { func, name, node } = minimist.default(process.argv.slice(2), {
  string: ['func', 'name', 'node'],
})

if (!func) {
  console.error(
    `
Usage: ${path.basename(process.argv[1])}
    --func <string> - options: setRecord, setText, checkOwner

Function arguments:
    setRecord
      --name <string>   - name being registered on ens

    setText
      --node <bytes32>  - node having the graph text field set

    checkOwner
      --name <string>   - name being checked for ownership
`,
  )
  process.exit(1)
}

///////////////////////
// functions //////////
///////////////////////

// NOT IN USE, SEE setTestRecord. Will be in use when we are on Rinkeby
// const setSubnodeRecord = async (nodeName: string, labelName: string) => {
//   checkFuncInputs([nodeName, labelName], ['nodeName', 'labelName'], 'setSubnodeRecord')
//   const node = utils.namehash(nodeName)
//   const labelNameFull = `${labelName}.${nodeName}`
//   const label = utils.namehash(labelNameFull)
//   const ttl = 31536000 // time to live = 1 year
//   const resolverAddress = contracts.publicResolver.address
//   const signerAddress = await contracts.ens.signer.getAddress()
//   console.log(signerAddress)
//   const ensOverrides = overrides('ens', 'setSubnodeRecord')
//   console.log('Namehash node: ', node)
//   console.log('Namehash labelNameFull: ', labelNameFull)
//   console.log('Namehash label: ', label)

//   await executeTransaction(
//     contracts.ens.setSubnodeRecord(node, label, signerAddress, resolverAddress, ttl, ensOverrides),
//   )
// }

const setTestRecord = async (labelName: string) => {
  checkFuncInputs([labelName], ['labelName'], 'setTestRecord')
  const node = utils.namehash('test')
  const labelNameFull = `${labelName}.${'test'}`
  const label = utils.keccak256(utils.toUtf8Bytes(labelName))
  console.log(label)
  const labelHashFull = utils.namehash(labelNameFull)
  const signerAddress = await contracts.ens.signer.getAddress()
  const ensOverrides = overrides('ens', 'register')
  console.log('Namehash node for "test": ', node)
  console.log(`Hash of label ${labelName}: `, label)
  console.log(`Namehash for ${labelNameFull}: ${labelHashFull}`)

  await executeTransaction(contracts.testRegistrar.register(label, signerAddress, ensOverrides))
}

const setText = async () => {
  checkFuncInputs([node], ['node'], 'setText')
  const key = 'GRAPH NAME SERVICE'
  const ensOverrides = overrides('ens', 'setText')
  const signerAddress = await contracts.publicResolver.signer.getAddress()
  await executeTransaction(contracts.publicResolver.setText(node, key, signerAddress, ensOverrides))
}

const checkOwner = async () => {
  checkFuncInputs([name], ['name'], 'checkOwner')
  try {
    const node = utils.namehash(`${name}.test`)
    console.log(`Node: ${node}`)
    const res = await contracts.ens.owner(node)
    console.log(`Owner of ${name}.test is: ${res}`)
  } catch (e) {
    console.log(`  ..failed on checkOwner: ${e.message}`)
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
