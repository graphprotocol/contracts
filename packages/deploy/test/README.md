# Deploy Package Tests

Integration and fork-based tests for cross-package orchestration.

## Test Categories

### Integration Tests

Test orchestration logic without forking:
- TX batch generation
- Module coordination
- Parameter validation

### Fork-Based Tests

Test complete governance workflow on Arbitrum fork:
- Deploy components
- Generate governance TX
- Simulate governance execution
- Verify with checkpoint modules

## Planned Tests

- `reo-governance-workflow.test.ts` - REO deployment and integration
- `ia-governance-workflow.test.ts` - IA deployment and integration
- `tx-builder.test.ts` - Safe TX generation

## Running Tests

```bash
# All tests
pnpm test

# Specific test
pnpm test test/reo-governance-workflow.test.ts

# Fork tests only
pnpm test:fork
```
