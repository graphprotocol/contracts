// Export all TypeChain generated types
export * from './types'

// Export runtime values
export const addressBookDir: string
export const configDir: string
export const artifactsDir: string

// Keep the original IPFS declaration
declare module 'ipfs-http-client'
