import { task } from 'hardhat/config'

task('data:post', 'Post calldata')
  .addParam('edge', 'Address of the data edge contract')
  .addParam('data', 'Call data to post')
  .setAction(async (taskArgs, hre) => {
    const edgeAddress = taskArgs.edge
    const txData = taskArgs.data
    const [signer] = await hre.ethers.getSigners()
    const contract = await hre.ethers.getContractAt('DataEdge', edgeAddress)
    const contractAddress = await contract.getAddress()
    const txRequest = {
      data: txData,
      to: contractAddress,
    }

    console.log(`Sending data...`)
    console.log(`> edge: ${contractAddress}`)
    console.log(`> sender: ${await signer.getAddress()}`)
    console.log(`> payload: ${txData}`)
    const tx = await signer.sendTransaction(txRequest)
    console.log(
      `> tx: ${tx.hash} nonce:${tx.nonce} limit: ${tx.gasLimit.toString()} gas: ${Number(tx.gasPrice) / 1e9} (gwei)`,
    )
    const rx = await tx.wait()
    console.log('> rx: ', rx!.status == 1 ? 'success' : 'failed')
    console.log(`Done!`)
  })
