/**
 * IssuanceAllocator Deployment Utilities
 *
 * This module provides TypeScript utilities for deploying and managing
 * IssuanceAllocator system contracts with type safety and toolshed integration.
 */

// Contract type definitions and utilities
export * from './contracts'

// Address book for contract management
export * from './address-book'

// Re-export useful toolshed utilities
export type { AddressBookEntry } from '@graphprotocol/toolshed/dist/deployments'
