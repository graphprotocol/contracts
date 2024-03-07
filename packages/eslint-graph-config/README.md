# eslint-graph-config

This repository contains shared linting and formatting rules for TypeScript projects.

## Installation

```bash
yarn add --dev eslint eslint-graph-config
```

For projects on this monorepo, you can use the following command to install the package:

```bash
yarn add --dev eslint eslint-graph-config@workspace:^x.y.z
```

To enable the rules, you need to create an `eslint.config.js` file in the root of your project with the following content:

```javascript
const config = require('eslint-graph-config')
module.exports = config.default
  ```

**Recommended config for existing projects**
The default configuration is quite strict specially with the usage of `any` and it's derivatives. For existing projects with a codebase that was developed with more lenient guidelines migrating to this configuration can be a bit overwhelming. 

You can customize your `eslint.config.js` file to disable some rules and make the transition easier. For example, you can create a `eslint.config.js` file with the following content:

```javascript
const config = require('eslint-graph-config')

module.exports = [
  ...config.default,
  {
    rules: {
      '@typescript-eslint/no-unsafe-assignment': 'off',
      '@typescript-eslint/no-var-requires': 'off',
      '@typescript-eslint/no-unsafe-call': 'off',
      '@typescript-eslint/no-unsafe-member-access': 'off',
      '@typescript-eslint/no-unsafe-argument': 'off',
    },
  },
  {
    ignores: [
      'library/*',                // ignore its contents
      '!node_modules/mylibrary/'  // unignore `node_modules/mylibrary` directory
    ]
  }
]
```

## Tooling

This package uses the following tools:
- [ESLint](https://eslint.org/) as the base linting tool
- [typescript-eslint](https://typescript-eslint.io/) for TypeScript support
- [ESLint Stylistic](https://eslint.style/) as the formatting tool

**Why no prettier?**
Instead of prettier we use ESLint Stylistic which is a set of ESLint rules focused on formatting and styling code. As opposed to prettier, ESLint Stylistic runs entirely within ESLint and does not require a separate tool to be run (e.g. `prettier`, `eslint-plugin-prettier` and `eslint-config-prettier`). Additionally it's supposed to be [more efficient](https://eslint.style/guide/why#linters-vs-formatters) and [less opinionated](https://antfu.me/posts/why-not-prettier).

## VSCode support

If you are using VSCode you can install the [ESLint extension](https://marketplace.visualstudio.com/items?itemName=dbaeumer.vscode-eslint) to get real-time linting and formatting support.

The following settings should be added to your `settings.json` file:
```json
{
  "editor.defaultFormatter": "dbaeumer.vscode-eslint",
  "eslint.format.enable": true,
  "eslint.experimental.useFlatConfig": true,
  "eslint.workingDirectories": [{ "pattern": "./packages/*/" }]
}
```

Additionally you can configure the `Format document` keyboard shortcut to run `eslint --fix` on demand.