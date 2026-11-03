# Legacy mainnet implementations

A frozen archive of the source of seven implementations running on Ethereum mainnet, as verified on [Sourcify](https://sourcify.dev). Each contract has its own bundle under `verified/<Contract>/`, holding the verified sources and the compiler version and settings.

This package is private and is not published. It holds no Solidity imports from the workspace and no tests of contract behaviour.

When this package was created (commit `4cbcd066`), each bundle was compiled with its exact solc version and shown to reproduce the bytecode on mainnet. That check has since been removed. [Sourcify](https://sourcify.dev) and [Etherscan](https://etherscan.io) are the authority for what is deployed; the files here are a copy.

GraphToken and L1Staking are Sourcify partial matches (`sourcifyMatch: "match"`), so their sources may differ from the deployed ones outside the code.

## Bundles

### GraphToken

- Implementation: `0xc944E90C64B2c07662A292be6244BDf05Cda44a7`
- Proxy: none
- Compiler: solc 0.7.4
- Links: [Etherscan](https://etherscan.io/address/0xc944E90C64B2c07662A292be6244BDf05Cda44a7#code), [Sourcify](https://sourcify.dev/#/lookup/0xc944E90C64B2c07662A292be6244BDf05Cda44a7)

### L1GraphTokenGateway

- Implementation: `0xD41ca6A1d034D178c196DFa916f22f7D1a1B8222`
- Proxy: `0x01cDC91B0A9bA741903aA3699BF4CE31d6C5cC06`
- Compiler: solc 0.7.6
- Links: [Etherscan](https://etherscan.io/address/0xD41ca6A1d034D178c196DFa916f22f7D1a1B8222#code), [Sourcify](https://sourcify.dev/#/lookup/0xD41ca6A1d034D178c196DFa916f22f7D1a1B8222)

### BridgeEscrow

- Implementation: `0xBcD54513aa593646d72aEA31406c633C235Ad6EA`
- Proxy: `0x36aFF7001294daE4C2ED4fDEfC478a00De77F090`
- Compiler: solc 0.7.6
- Links: [Etherscan](https://etherscan.io/address/0xBcD54513aa593646d72aEA31406c633C235Ad6EA#code), [Sourcify](https://sourcify.dev/#/lookup/0xBcD54513aa593646d72aEA31406c633C235Ad6EA)

### L1GNS

- Implementation: `0x83A5B6C542aB20436087Fc79724bdF06ea80f836`
- Proxy: `0xaDcA0dd4729c8BA3aCf3E99F3A9f471EF37b6825`
- Compiler: solc 0.7.6
- Links: [Etherscan](https://etherscan.io/address/0x83A5B6C542aB20436087Fc79724bdF06ea80f836#code), [Sourcify](https://sourcify.dev/#/lookup/0x83A5B6C542aB20436087Fc79724bdF06ea80f836)

### Curation

- Implementation: `0xDeb46851907fd85DD475780CcE2eE0D67c969825`
- Proxy: `0x8FE00a685Bcb3B2cc296ff6FfEaB10acA4CE1538`
- Compiler: solc 0.7.6
- Links: [Etherscan](https://etherscan.io/address/0xDeb46851907fd85DD475780CcE2eE0D67c969825#code), [Sourcify](https://sourcify.dev/#/lookup/0xDeb46851907fd85DD475780CcE2eE0D67c969825)

### L1Staking

- Implementation: `0x20a14D78848BC8B3F3d4B77239F2adC3C0259A10`
- Proxy: `0xF55041E37E12cD407ad00CE2910B8269B01263b9`
- Compiler: solc 0.7.6
- Links: [Etherscan](https://etherscan.io/address/0x20a14D78848BC8B3F3d4B77239F2adC3C0259A10#code), [Sourcify](https://sourcify.dev/#/lookup/0x20a14D78848BC8B3F3d4B77239F2adC3C0259A10)

### StakingExtension

- Implementation: `0xA479c00cDa8C07bce458D7a826C7b091672EB92C`
- Proxy: none
- Compiler: solc 0.7.6
- Links: [Etherscan](https://etherscan.io/address/0xA479c00cDa8C07bce458D7a826C7b091672EB92C#code), [Sourcify](https://sourcify.dev/#/lookup/0xA479c00cDa8C07bce458D7a826C7b091672EB92C)

## Addresses and audits

`addresses.json` is the L1 deployment record: the Ethereum mainnet (1) and Sepolia (11155111) entries, including contracts whose source isn't in this package. It is copied to `@graphprotocol/address-book` as `legacy/addresses.json`; keep `packages/address-book/src/legacy/addresses.json` identical to it.

`audits/` holds the historical audit reports of the original protocol contracts.

## Checks

`pnpm test:self` needs no network access. It compares every source file with `sourceHashes` in the bundle's `compiler.json` and fails naming any file that changed, was added or is missing.

## Sources must stay unformatted

Never edit or format anything under `verified/`. The source-hash check catches any edit, including formatting. `.prettierignore`, `.solhintignore`, `scripts/lint-staged-run.sh` and `.gitattributes` keep tools and git from rewriting these files, and `GraphToken.sol` keeps its CRLF line endings. Don't add a `.solhint.json` to this package.
