// Re-export issuance contract types
// Note: Unlike legacy contracts, issuance contracts implement complete interfaces directly,
// so we don't need toolshed wrapper interfaces

import type { IIssuanceAllocationAdministration } from '../../types/contracts/issuance/allocate/IIssuanceAllocationAdministration'
import type { IIssuanceAllocationData } from '../../types/contracts/issuance/allocate/IIssuanceAllocationData'
import type { IIssuanceAllocationDistribution } from '../../types/contracts/issuance/allocate/IIssuanceAllocationDistribution'
import type { IIssuanceAllocationStatus } from '../../types/contracts/issuance/allocate/IIssuanceAllocationStatus'
import type { IIssuanceTarget } from '../../types/contracts/issuance/allocate/IIssuanceTarget'
import type { ISendTokens } from '../../types/contracts/issuance/allocate/ISendTokens'
import type { IRewardsEligibility } from '../../types/contracts/issuance/eligibility/IRewardsEligibility'
import type { IRewardsEligibilityAdministration } from '../../types/contracts/issuance/eligibility/IRewardsEligibilityAdministration'
import type { IRewardsEligibilityReporting } from '../../types/contracts/issuance/eligibility/IRewardsEligibilityReporting'
import type { IRewardsEligibilityStatus } from '../../types/contracts/issuance/eligibility/IRewardsEligibilityStatus'

// Composite types for convenience (combining all interfaces for each contract)
export type IssuanceAllocator = IIssuanceAllocationAdministration &
  IIssuanceAllocationData &
  IIssuanceAllocationDistribution &
  IIssuanceAllocationStatus

export type DirectAllocation = IIssuanceTarget & ISendTokens

export type RewardsEligibilityOracle = IRewardsEligibility &
  IRewardsEligibilityAdministration &
  IRewardsEligibilityReporting &
  IRewardsEligibilityStatus

