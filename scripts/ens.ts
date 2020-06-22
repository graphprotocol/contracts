#!/usr/bin/env ts-node

import { utils } from 'ethers'
import * as path from 'path'
import * as minimist from 'minimist'

import { contracts, executeTransaction, overrides, checkFuncInputs } from './helpers'

///////////////////////
// Set up the script //
///////////////////////

const { func, name } = minimist.default(process.argv.slice(2), {
  string: ['func', 'name'],
})

if (!func || !name) {
  console.error(
    `
Usage: ${path.basename(process.argv[1])}
    --func <string> - options: registerName, setRecord, setText, checkOwner, nameHash

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

// Must normalize name to lower case to get script to work with ethers namehash
// This is because in setTestRecord() - label uses the normal keccak
// TODO - follow UTS46 in scripts https://docs.ens.domains/contract-api-reference/name-processing
const normalizedName = name.toLowerCase()

const setTestRecord = async () => {
  // const node = utils.namehash('test')
  // console.log('Namehash node for "test": ', node)
  const labelNameFull = `${normalizedName}.${'test'}`
  const labelHashFull = utils.namehash(labelNameFull)
  console.log(`Namehash for ${labelNameFull}: ${labelHashFull}`)

  const signerAddress = await contracts.ens.signer.getAddress()
  const ensOverrides = overrides('ens', 'register')
  const label = utils.keccak256(utils.toUtf8Bytes(normalizedName))
  // console.log(`Hash of label being registered on ens ${name}: `, label)
  await executeTransaction(contracts.testRegistrar.register(label, signerAddress, ensOverrides))
}

const setText = async () => {
  const labelNameFull = `${normalizedName}.${'test'}`
  const labelHashFull = utils.namehash(labelNameFull)
  console.log(`Setting text name: ${labelNameFull} with node: ${labelHashFull}`)

  const key = 'GRAPH NAME SERVICE'
  const ensOverrides = overrides('ens', 'setText')
  const signerAddress = await contracts.publicResolver.signer.getAddress()
  await executeTransaction(
    contracts.publicResolver.setText(labelHashFull, key, signerAddress, ensOverrides),
  )
}

// does everything in one func call
const registerName = async () => {
  await setTestRecord()
  await setText()
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
    if (func == 'registerName') {
      console.log(`Registering ownership and text record for ${name} ...`)
      registerName()
    } else if (func == 'setTestRecord') {
      console.log(`Setting owner for ${name} ...`)
      setTestRecord()
    } else if (func == 'setText') {
      console.log(`Setting text record of 'GRAPH NAME SERVICE' for caller ...`)
      setText()
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
