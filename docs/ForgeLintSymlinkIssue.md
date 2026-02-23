# Foundry Issue Draft: forge lint symlink loop

**Repository:** <https://github.com/foundry-rs/foundry/issues>

---

## Title

`forge lint` fails with "too many levels of symbolic links" in pnpm workspaces

## Component

`forge-lint`

## Describe the bug

`forge lint` fails with OS error 40 ("too many levels of symbolic links") when the project uses pnpm workspaces with circular symlinks. This is a standard pnpm workspace pattern where sub-packages depend on their parent package.

The `[lint] ignore` configuration does not prevent this - forge appears to traverse the entire filesystem tree before applying the ignore filter, hitting the symlink loop in the process.

Note: `forge build` and `forge test` work correctly in the same project, suggesting they use different traversal logic that handles or avoids symlink loops.

## Error message

```
Error: attempting to read `/path/to/project/node_modules/@graphprotocol/contracts/testing/node_modules/@graphprotocol/contracts/testing/node_modules/@graphprotocol/contracts/testing/[...repeating...]/contracts/governance` resulted in an error: Too many levels of symbolic links (os error 40)
```

## To reproduce

1. Create a pnpm workspace with package A
2. Package A has a sub-directory (e.g., `testing/`) with its own `package.json`
3. The sub-package lists package A as a dependency
4. pnpm creates a symlink: `A/testing/node_modules/A` → `../../..` (circular)
5. Run `forge lint`

### Minimal reproduction

```bash
# Create workspace
mkdir -p workspace/packages/parent/child
cd workspace

# Root package.json
cat > package.json << 'EOF'
{
  "name": "workspace",
  "private": true
}
EOF

# pnpm workspace config
cat > pnpm-workspace.yaml << 'EOF'
packages:
  - 'packages/*'
  - 'packages/*/child'
EOF

# Parent package
cat > packages/parent/package.json << 'EOF'
{
  "name": "@example/parent",
  "version": "1.0.0"
}
EOF

# Child package that depends on parent
cat > packages/parent/child/package.json << 'EOF'
{
  "name": "@example/child",
  "version": "1.0.0",
  "dependencies": {
    "@example/parent": "workspace:^"
  }
}
EOF

# Install - pnpm creates circular symlink
pnpm install

# Verify circular symlink exists
ls -la packages/parent/child/node_modules/@example/parent
# Shows: parent -> ../../..

# Create minimal foundry project
cat > packages/parent/foundry.toml << 'EOF'
[profile.default]
src = 'contracts'
libs = ["node_modules"]

[lint]
ignore = ["node_modules/**/*"]
EOF

mkdir -p packages/parent/contracts
cat > packages/parent/contracts/Example.sol << 'EOF'
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;
contract Example {}
EOF

# This fails
cd packages/parent && forge lint
```

## Expected behavior

`forge lint` should either:

1. Apply the `ignore` configuration during traversal (not after), skipping `node_modules` entirely
2. Detect and handle symlink loops gracefully (track visited inodes)
3. Respect the `libs` configuration to avoid deep traversal into library directories

## Environment

- forge version: 1.5.1-stable
- OS: Linux
- Package manager: pnpm 9.x with workspaces

## Root cause hypothesis

The traversal logic appears to recursively walk the entire directory tree before applying `ignore` patterns, rather than pruning during traversal.

Evidence:

- `node_modules/@graphprotocol/contracts/testing/` is not a standard Solidity directory
- It's not in the package exports
- It's not `src`, `test`, `script`, or `lib`
- Yet forge descends into it (and its nested `node_modules`)

The fix should apply ignore patterns during traversal (using something like `filter_entry` in walkdir) to prune directories before descending, not filter results after traversal.

## Additional context

This pattern is common in monorepos where:

- A main package exists (e.g., `@graphprotocol/contracts`)
- Sub-packages for testing/tooling exist within it (e.g., `contracts/testing/`)
- Sub-packages depend on the parent for shared code

pnpm resolves this by creating symlinks back to the parent, which is intentional and works correctly with Node.js module resolution (which has built-in cycle detection).

The workaround of removing these symlinks would break the workspace, so it's not viable.

## Workaround (current)

None that preserves full functionality. Options:

- Skip `forge lint` and use only `solhint`
- Manually delete circular symlinks before linting (breaks workspace)
