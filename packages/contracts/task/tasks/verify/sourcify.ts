import axios, { AxiosError } from 'axios'
import FormData from 'form-data'
import { HardhatRuntimeEnvironment } from 'hardhat/types'
import { Readable } from 'stream'

// Helper function to safely extract error information
function getErrorMessage(error: unknown): string {
  if (error instanceof AxiosError) {
    if (error.response?.data) {
      return JSON.stringify(error.response.data)
    }
    return error.message
  }
  if (error instanceof Error) {
    return error.message
  }
  return String(error)
}

// Inspired by:
// - https://github.com/wighawag/hardhat-deploy/blob/9c8cd433a37188e793181b727222e2d22aef34b0/src/sourcify.ts
// - https://github.com/zoey-t/hardhat-sourcify/blob/26f10a08eb6cf97700c78989bf42b009c9cb3275/src/sourcify.ts
export async function submitSourcesToSourcify(
  hre: HardhatRuntimeEnvironment,
  contract: {
    source: string
    name: string
    address: string
    fqn: string
  },
): Promise<void> {
  const chainId = hre.network.config.chainId
  const sourcifyUrl = 'https://sourcify.dev/server/'

  // Get contract metadata
  const contractBuildInfo = await hre.artifacts.getBuildInfo(contract.fqn)
  if (!contractBuildInfo) {
    throw new Error(`Build info not found for contract ${contract.fqn}`)
  }
  const contractOutput = contractBuildInfo.output.contracts[contract.source]?.[contract.name]
  if (!contractOutput) {
    throw new Error(`Contract output not found for ${contract.name}`)
  }
  const contractMetadata = (contractOutput as { metadata?: string }).metadata

  if (contractMetadata === undefined) {
    console.error(
      `Contract ${contract.name} was deployed without saving metadata. Cannot submit to sourcify, skipping.`,
    )
    return
  }

  // Check if contract already verified
  try {
    const checkResponse = await axios.get(
      `${sourcifyUrl}checkByAddresses?addresses=${contract.address.toLowerCase()}&chainIds=${chainId}`,
    )
    const { data: checkData } = checkResponse
    if (checkData[0].status === 'perfect') {
      console.log(`already verified: ${contract.name} (${contract.address}), skipping.`)
      return
    }
  } catch (e) {
    console.error(getErrorMessage(e))
  }

  console.log(`verifying ${contract.name} (${contract.address} on chain ${chainId}) ...`)

  // Build form data
  const formData = new FormData()
  formData.append('address', contract.address)
  formData.append('chain', chainId)

  const fileStream = new Readable()
  fileStream.push(contractMetadata)
  fileStream.push(null)
  formData.append('files', fileStream)

  // Verify contract
  try {
    const submissionResponse = await axios.post(sourcifyUrl, formData, {
      headers: formData.getHeaders(),
    })
    const { status } = submissionResponse.data.result[0]
    if (status === 'perfect') {
      console.log(` => contract ${contract.name} is now verified`)
    } else if (status === 'partial') {
      console.log(` => contract ${contract.name} is partially verified`)
    } else {
      console.error(` => contract ${contract.name} is not verified`)
    }
  } catch (e) {
    console.error(getErrorMessage(e))
  }
}
