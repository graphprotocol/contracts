import { BytesLike, ethers, keccak256, toUtf8Bytes } from 'ethers'

export function generatePOI(message = 'poi') {
  return ethers.getBytes(keccak256(toUtf8Bytes(message)))
}

export function encodePOIMetadata(
  blockNumber: number,
  publicPOI: BytesLike,
  indexingStatus: number,
  errorCode: number,
  errorBlockNumber: number,
) {
  return ethers.AbiCoder.defaultAbiCoder().encode(
    ['uint256', 'bytes32', 'uint8', 'uint8', 'uint256'],
    [blockNumber, publicPOI, indexingStatus, errorCode, errorBlockNumber],
  )
}
