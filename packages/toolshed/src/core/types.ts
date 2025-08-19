import type { BytesLike } from 'ethers'

export enum PaymentTypes {
  QueryFee = 0,
  IndexingFee = 1,
  IndexingRewards = 2,
}

export enum ThawRequestType {
  Provision = 0,
  Delegation = 1,
}

export type RAV = {
  collectionId: string
  payer: string
  serviceProvider: string
  dataService: string
  timestampNs: number
  valueAggregate: bigint
  metadata: BytesLike
}

export type Receipt = {
  collection_id: string
  payer: string
  data_service: string
  service_provider: string
  timestamp_ns: bigint
  nonce: bigint
  value: bigint
}
