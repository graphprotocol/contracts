/* eslint-disable no-secrets/no-secrets */
/* eslint-disable @typescript-eslint/no-explicit-any */
import axios from 'axios'
import FormData from 'form-data'
import { HardhatRuntimeEnvironment } from 'hardhat/types'
import { Readable } from 'stream'

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
  const contractMetadata = (
    contractBuildInfo.output.contracts[contract.source][contract.name] as any
  ).metadata

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
    console.error(((e).response && JSON.stringify((e).response.data)) || e)
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
    console.error(((e).response && JSON.stringify((e).response.data)) || e)
  }
}
