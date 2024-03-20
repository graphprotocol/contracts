import '@nomiclabs/hardhat-ethers'
import { task } from 'hardhat/config'

task('data:post', 'Post calldata')
  .addParam('edge', 'Address of the data edge contract')
  .addParam('data', 'Call data to post')
  .setAction(async (taskArgs, hre) => {
    // prepare data
    const edgeAddress = taskArgs.edge
    const txData = taskArgs.data
    const contract = await hre.ethers.getContractAt('DataEdge', edgeAddress)
    const txRequest = {
      data: txData,
      to: contract.address,
    }

    // send transaction
    console.log(`Sending data...`)
    console.log(`> edge: ${contract.address}`)
    console.log(`> sender: ${await contract.signer.getAddress()}`)
    console.log(`> payload: ${txData}`)
    const tx = await contract.signer.sendTransaction(txRequest)
    console.log(`> tx: ${tx.hash} nonce:${tx.nonce} limit: ${tx.gasLimit.toString()} gas: ${tx.gasPrice.toNumber() / 1e9} (gwei)`)
    const rx = await tx.wait()
    console.log('> rx: ', rx.status == 1 ? 'success' : 'failed')
    console.log(`Done!`)
  })
