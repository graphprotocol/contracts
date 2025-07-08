import { task } from 'hardhat/config'
import { HardhatRuntimeEnvironment as HRE } from 'hardhat/types'
// Define the VerificationResponse type locally since @openzeppelin/hardhat-defender is deprecated
// and the functionality has been moved to @openzeppelin/hardhat-upgrades
interface VerificationResponse {
  matchType: 'EXACT' | 'PARTIAL' | 'NO_MATCH'
}
import { GraphNetworkContractName } from '@graphprotocol/sdk'

async function main(_args: { referenceUrl?: string; contracts: GraphNetworkContractName[] }, _hre: HRE) {
  // NOTE: This task is currently disabled because @openzeppelin/hardhat-defender has been deprecated
  // and the functionality has been moved to @openzeppelin/hardhat-upgrades, but the API has changed.
  // TODO: Update this task to use the new OpenZeppelin Defender API or remove it entirely.

  console.error('ERROR: The verify-defender task is currently disabled.')
  console.error('The @openzeppelin/hardhat-defender package has been deprecated.')
  console.error('Please use alternative verification methods such as:')
  console.error('- yarn hardhat verifyAll --network <network> --graph-config <config>')
  console.error('- yarn hardhat sourcifyAll --network <network>')

  throw new Error('verify-defender task is disabled due to deprecated dependencies')

  /* DISABLED CODE - kept for reference
  const { referenceUrl, contracts } = args
  const { defender, network, graph } = hre
  const summaryPath = process.env.GITHUB_STEP_SUMMARY
  if (summaryPath) appendFileSync(summaryPath, `# Contracts deployment verification\n\n`)

  const workflowUrl
    = referenceUrl
    || process.env.WORKFLOW_URL
    || execSync(`git config --get remote.origin.url`).toString().trim()
  const addressBook = graph().addressBook
  const errs = []

  for (const contractName of contracts) {
    if (!isGraphNetworkContractName(contractName)) {
      throw new Error(`Invalid contract name: ${contractName as string}`)
    }
    const entry = addressBook.getEntry(contractName)
    if (!entry || entry.address === constants.AddressZero) {
      errs.push([contractName, { message: `Entry not found on address book.` }])
      continue
    }

    const addressToVerify = entry.implementation?.address ?? entry.address
    console.error(`Verifying artifact for ${contractName} at ${addressToVerify}`)

    try {
      const response = await defender.verifyDeployment(addressToVerify, contractName, workflowUrl)
      console.error(`Bytecode match for ${contractName} is ${response.matchType}`)
      if (summaryPath) {
        appendFileSync(
          summaryPath,
          `- ${contractName} at ${etherscanLink(network.name, addressToVerify)} is ${
            response.matchType
          } ${emojiForMatch(response.matchType)}\n`,
        )
      }
      if (response.matchType === 'NO_MATCH') {
        errs.push([contractName, { message: `No bytecode match.` }])
      }
    } catch (err) {
      if (summaryPath) {
        appendFileSync(
          summaryPath,
          `- ${contractName} at ${etherscanLink(
            network.name,
            addressToVerify,
          )} failed to verify :x:\n`,
        )
      }
      console.error(`Error verifying artifact: ${err.message}`)
      errs.push([contractName, err])
    }
  }

  if (errs.length > 0) {
    throw new Error(
      `Some verifications failed:\n${errs
        .map(([name, err]) => ` ${name}: ${err.message}`)
        .join('\n')}`,
    )
  }
  */
}

function _ietherscanLink(network: string, address: string): string {
  switch (network) {
    case 'mainnet':
      return `[\`${address}\`](https://etherscan.io/address/${address})`
    case 'arbitrum-one':
      return `[\`${address}\`](https://arbiscan.io/address/${address})`
    case 'goerli':
      return `[\`${address}\`](https://goerli.etherscan.io/address/${address})`
    case 'arbitrum-goerli':
      return `[\`${address}\`](https://goerli.arbiscan.io/address/${address})`
    default:
      return `\`${address}\``
  }
}

function _iemojiForMatch(matchType: VerificationResponse['matchType']): string {
  switch (matchType) {
    case 'EXACT':
      return ':heavy_check_mark:'
    case 'PARTIAL':
      return ':warning:'
    case 'NO_MATCH':
      return ':x:'
  }
}

task('verify-defender')
  .addVariadicPositionalParam('contracts', 'List of contracts to verify')
  .addOptionalParam(
    'referenceUrl',
    'URL to link to for artifact verification (defaults to $WORKFLOW_URL or the remote.origin.url of the repository)',
  )
  .setDescription('Verifies deployed implementations on Defender')
  .setAction(main)
