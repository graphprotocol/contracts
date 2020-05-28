const BN = web3.utils.BN
const { MultisigOperation, CommitmentTarget } = require('@connext/types')
const { getRandomPrivateKey, ChannelSigner } = require('@connext/utils')
const WithdrawInterpreter = require('../../build/IndexerWithdrawInterpreter.json')
const Multisig = require('../../build/MinimumViableMultisig.json')

async function getRandomFundedChannelSigners(
  numSigners,
  ethProviderUrl,
  fundedAccount,
  graphContract = undefined,
) {
  // Create signer array
  const signers = []

  // Fund all signers with eth + tokens
  for (const _ of Array(numSigners).fill(0)) {
    // Create random signer
    const privKey = getRandomPrivateKey()
    const signer = new ChannelSigner(privKey, ethProviderUrl)
    const addr = await signer.getAddress()

    // Add signer to array
    signers.push(signer)

    // Add signer as a web3 accounts
    web3.eth.accounts.wallet.add(privKey)

    // Send eth
    const ETH_DEPOSIT = web3.utils.toWei('0.1')
    await new Promise((resolve, reject) => {
      web3.eth
        .sendTransaction({
          from: fundedAccount,
          to: addr,
          value: ETH_DEPOSIT,
        })
        .on('error', reject)
        .on('receipt', resolve)
    })

    if (!graphContract) {
      continue
    }

    // Send tokens
    const GRT_DEPOSIT = web3.utils.toWei(new BN('100'))
    await new Promise((resolve, reject) => {
      graphContract
        .mint(addr, GRT_DEPOSIT, { from: fundedAccount })
        .on('error', reject)
        .on('receipt', resolve)
    })
  }

  return signers
}

function fundMultisig(amount, multisigAddr, funder, tokenContract = undefined) {
  if (tokenContract) {
    return new Promise((resolve, reject) => {
      tokenContract
        .mint(multisigAddr, amount, { from: funder })
        .on('error', reject)
        .on('receipt', resolve)
    })
  }
  return new Promise((resolve, reject) => {
    web3.eth
      .sendTransaction({
        from: funder,
        to: multisigAddr,
        value: amount,
        gas: 80000,
      })
      .on('error', reject)
      .on('receipt', resolve)
  })
}

class MiniCommitment {
  constructor(
    multisigAddr, // Address
    owners, // ChannelSigner[]
  ) {
    this.owners = owners
    this.multisigAddress = multisigAddr
  }

  getTransactionDetails(commitmentType, params) {
    switch (commitmentType) {
      case 'withdraw': {
        // Destructure withdrawal commitment params
        const { withdrawInterpreter, amount, assetId, recipient } = params

        // Return properly encoded transaction values
        const interpreter = new web3.eth.Contract(WithdrawInterpreter.abi, withdrawInterpreter)
        return {
          to: withdrawInterpreter,
          value: 0,
          data: interpreter.methods.multisigTransfer(recipient, assetId, amount).encodeABI(),
          operation: MultisigOperation.DelegateCall,
        }
      }
      default: {
        throw new Error(`Invalid commitment type: ${commitmentType}`)
      }
    }
  }

  // Returns the hash to sign from generated transaction details
  getDigestFromDetails(details) {
    // Parse tx details
    const { to, value, data, operation } = details

    // Generate properly hashed digest from tx details
    const dataHash = web3.utils.soliditySha3({ type: 'bytes', value: data })
    const digest = web3.utils.keccak256(
      web3.utils.soliditySha3(
        { type: 'uint8', value: CommitmentTarget.MULTISIG },
        { type: 'address', value: this.multisigAddress },
        { type: 'address', value: to },
        { type: 'uint256', value },
        { type: 'bytes32', value: dataHash },
        { type: 'uint8', value: operation },
      ),
    )
    return digest
  }

  async getSignedTransaction(commitmentType, params) {
    // Generate transaction details
    const details = this.getTransactionDetails(commitmentType, params)

    // Generate owner signatures
    const digest = this.getDigestFromDetails(details)
    console.log('owners are signing', digest)
    const signatures = await Promise.all(this.owners.map(owner => owner.signMessage(digest)))

    // Encode call to execute transaction
    const multisig = new web3.eth.Contract(Multisig.abi, this.multisigAddress)
    const txData = multisig.methods
      .execTransaction(details.to, details.value, details.data, details.operation, signatures)
      .encodeABI()

    return { to: this.multisigAddress, value: 0, data: txData }
  }
}

module.exports = {
  getRandomFundedChannelSigners,
  fundMultisig,
  MiniCommitment,
}
