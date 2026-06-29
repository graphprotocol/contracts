# Layer Analysis: Future Work

## Current State

**Layer 1 (AddressBookOps)**: ✅ Complete - pure local storage operations.

## Potential Future Layers

### Layer 2: Network-Linked Operations

Combine on-chain queries with address book updates. Currently scattered in `sync-utils.ts`.

```typescript
class NetworkAddressBookOps {
  constructor(
    private ops: AddressBookOps,
    private client: PublicClient,
  ) {}

  async syncImplementationFromChain(name, proxyAddress, proxyType): Promise<void> {
    const impl = await getOnChainImplementation(this.client, proxyAddress, proxyType)
    this.ops.setImplementationAndClearIfMatches(name, impl)
  }
}
```

`getOnChainImplementation` already exists in `deploy-implementation.ts`. A
matching on-chain proxy-admin reader would need to be added to wrap
`ops.setProxyAdmin` the same way.

### Layer 3+: Higher-Level Abstractions

| Layer   | Purpose                       | Status                                 |
| ------- | ----------------------------- | -------------------------------------- |
| Layer 3 | Rocketh state sync            | Exists in `sync-utils.ts`              |
| Layer 4 | Deploy + address book update  | Scattered in deploy scripts            |
| Layer 5 | Integrated deploy-and-sync    | Does not exist                         |
| Layer 6 | State assessment + governance | Partial in `upgrade-implementation.ts` |

## Design Rationale

Layer 1 is pure local storage because:

- **Testability**: No mocked RPC clients needed
- **Flexibility**: Callers choose when/how to fetch on-chain data
- **Composability**: Higher layers can wrap Layer 1
