# Hardhat-Deploy Migration Status

## ✅ Completed

### Core Infrastructure

- [x] Split monolithic deployment into numbered hardhat-deploy scripts
- [x] Added comprehensive deployment test suite
- [x] Fixed toolshed TypeScript build issue (ProxyAdmin type import)
- [x] Configured external OpenZeppelin contract artifacts
- [x] Added address book export script with all 4 required contracts
- [x] Updated package.json with proper build/test scripts

### Deployment Scripts Created

- [x] `00_proxy_admin.ts` - Deploy GraphIssuanceProxyAdmin
- [x] `01_issuance_allocator.ts` - Deploy IssuanceAllocator with proxy
- [x] `02_pilot_allocation.ts` - Deploy PilotAllocation with proxy (DirectAllocation impl)
- [x] `03_rewards_eligibility_oracle.ts` - Deploy RewardsEligibilityOracle with proxy
- [x] `04_accept_ownership.ts` - Accept ownership via governor (idempotent)
- [x] `00_rewards_manager.ts` - Legacy RewardsManager upgrade support

### Test Infrastructure

- [x] Deployment test suite with proxy architecture verification
- [x] Tests for atomic initialization
- [x] Tests for two-step ownership
- [x] Tests for address book export completeness

## 🚧 Remaining Tasks

### Code Cleanup

- [ ] Remove `deploy/lib/params.ts` (unused, causes circular import)
- [ ] Remove `config/` directory (unused)
- [ ] Re-enable `tasks/upgrade-rewards-manager.ts` import after params.ts removal
- [ ] Remove or move `ignition/` directory after validation

### Documentation

- [ ] Update main README to reference hardhat-deploy workflow (remove Ignition refs)
- [ ] Document deployment process in deploy/README_DEPLOYMENT.md
- [ ] Add network configuration examples (arbitrum-sepolia, arbitrum-one)

### Testing & Validation

- [ ] Test full deployment on arbitrum-sepolia fork
- [ ] Test full deployment on arbitrum-one fork
- [ ] Verify address book integration with horizon/subgraph-service packages
- [ ] Create example deployment for new networks

## 📊 Key Improvements

### Before (Ignition)

- Single monolithic module
- Complex dependency management
- Harder to debug deployment failures
- Non-standard for Graph Protocol monorepo

### After (hardhat-deploy)

- Clean numbered scripts with clear dependencies
- Tag-based selective deployment
- Native deployments JSON per network
- Aligns with token-distribution package patterns
- First-class hardhat task integration

## 🎯 Next Steps

1. **Clean up unused code** - Remove params.ts, config/, and potentially Ignition
2. **Documentation** - Update README with hardhat-deploy workflows
3. **Testing** - Validate on testnet forks
4. **Integration** - Ensure address book works with other packages

## 📝 Notes

- All deployment scripts follow atomic initialization pattern
- Two-step ownership (Ownable2Step) enforced across all contracts
- GraphIssuanceProxyAdmin manages all issuance contract proxies
- Scripts are idempotent and resumable via hardhat-deploy
- External OpenZeppelin artifacts configured in hardhat.config.ts
