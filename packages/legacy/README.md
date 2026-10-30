# Legacy mainnet implementations

A frozen archive of the source of seven implementations running on Ethereum mainnet, as verified on [Sourcify](https://sourcify.dev). Each contract has its own bundle under `verified/<Contract>/`, holding the verified sources and the compiler version and settings.

This package is private and is not published. It holds no Solidity imports from the workspace and no tests of contract behaviour.

| Contract            | Implementation                               | Proxy                                        | solc  |
| ------------------- | -------------------------------------------- | -------------------------------------------- | ----- |
| GraphToken          | `0xc944E90C64B2c07662A292be6244BDf05Cda44a7` | none                                         | 0.7.4 |
| L1GraphTokenGateway | `0xD41ca6A1d034D178c196DFa916f22f7D1a1B8222` | `0x01cDC91B0A9bA741903aA3699BF4CE31d6C5cC06` | 0.7.6 |
| BridgeEscrow        | `0xBcD54513aa593646d72aEA31406c633C235Ad6EA` | `0x36aFF7001294daE4C2ED4fDEfC478a00De77F090` | 0.7.6 |
| L1GNS               | `0x83A5B6C542aB20436087Fc79724bdF06ea80f836` | `0xaDcA0dd4729c8BA3aCf3E99F3A9f471EF37b6825` | 0.7.6 |
| Curation            | `0xDeb46851907fd85DD475780CcE2eE0D67c969825` | `0x8FE00a685Bcb3B2cc296ff6FfEaB10acA4CE1538` | 0.7.6 |
| L1Staking           | `0x20a14D78848BC8B3F3d4B77239F2adC3C0259A10` | `0xF55041E37E12cD407ad00CE2910B8269B01263b9` | 0.7.6 |
| StakingExtension    | `0xA479c00cDa8C07bce458D7a826C7b091672EB92C` | none                                         | 0.7.6 |

When this archive was created, the workspace source reproduced only Curation.

GraphToken and L1Staking are Sourcify partial matches (`sourcifyMatch: "match"`), so their sources may differ from the deployed ones outside the code.

## Checks

`pnpm test:self` needs no network access. It compares every source file with `sourceHashes` in `compiler.json`, compiles every bundle with its exact solc-js version, and compares the result with the hash of the on-chain code in `mainnet.json`. The comparison ignores metadata and immutable values.

## Sources must stay unformatted

Never edit or format anything under `verified/`. Formatting doesn't change bytecode, so only the source hashes catch it. `.prettierignore`, `.solhintignore`, `scripts/lint-staged-run.sh` and `.gitattributes` keep tools and git from rewriting these files, and `GraphToken.sol` keeps its CRLF line endings. Don't add a `.solhint.json` to this package.

## Re-running the scripts

```bash
# Rewrite verified/ from Sourcify, using the addresses in targets.json
node scripts/fetch-verified.mjs

# Check the addresses on-chain at a finalized block and rewrite mainnet.json
MAINNET_RPC_URL=<url> node scripts/record-mainnet.mjs
```

`record-mainnet` exits 1 if a proxy, or L1Staking's `extensionImpl`, no longer points at the listed implementation. Pass the RPC URL only as an inline env var, and never commit it.
