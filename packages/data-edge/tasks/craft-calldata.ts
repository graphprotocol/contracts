import '@nomiclabs/hardhat-ethers'
import { Contract } from 'ethers'
import { task } from 'hardhat/config'

const baseABI = [
  {
    inputs: [
      {
        internalType: 'bytes',
        name: '_payload',
        type: 'bytes',
      },
    ],
    name: '',
    outputs: [],
    stateMutability: 'nonpayable',
    type: 'function',
  },
]

const getContract = (contractAddress: string, abi, provider) => {
  return new Contract(contractAddress, abi, provider)
}

const getAbiForSelector = (selector: string) => {
  return baseABI.map((item) => {
    item.name = selector
    return item
  })
}

task('data:craft', 'Build calldata')
  .addParam('edge', 'Address of the data edge contract')
  .addParam('selector', 'Selector name')
  .addParam('data', 'Call data to post')
  .setAction(async (taskArgs, hre) => {
    // parse input
    const edgeAddress = taskArgs.edge
    const calldata = taskArgs.data
    const selector = taskArgs.selector

    // build data
    const abi = getAbiForSelector(selector)
    const contract = getContract(edgeAddress, abi, hre.ethers.provider)
    const tx = await contract.populateTransaction[selector](calldata)
    const txData = tx.data
    console.log(txData)
  })
