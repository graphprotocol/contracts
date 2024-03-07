# solhint-graph-config

This repository contains shared linting and formatting rules for Solidity projects.

## Code linting

### Installation

⚠️ Unfortunately there isn't a way to install peer dependencies using Yarn v4, so we need to install them manually.


```bash
# Install with peer packages
yarn add --dev solhint solhint-graph-config

# For projects on this monorepo
yarn add --dev solhint solhint-graph-config@workspace:^x.y.z
```

### Configuration

Run `solhint` with `node_modules/solhint-graph-config/index.js` as the configuration file. We suggest creating an npm script to make it easier to run:

```json

{
  "scripts": {
    "lint": "solhint --fix --noPrompt contracts/**/*.sol --config node_modules/solhint-graph-config/index.js"
  }
}

```

## Code formatting

### Installation

⚠️ Unfortunately there isn't a way to install peer dependencies using Yarn v4, so we need to install them manually.


```bash
# Install with peer packages
yarn add --dev solhint-graph-config prettier prettier-plugin-solidity

# For projects on this monorepo
yarn add --dev solhint-graph-config@workspace:^x.y.z prettier prettier-plugin-solidity
```


### Configuration: formatting

Create a configuration file for prettier at `prettier.config.js`:

```javascript
const prettierGraphConfig = require('solhint-graph-config/prettier')
module.exports = prettierGraphConfig
```

Running `prettier` will automatically pick up the configuration file. We suggest creating an npm script to make it easier to run:

```json
{
  "scripts": {
    "format": "prettier --write 'contracts/**/*.sol'"
  }
}
```

## Tooling

This package uses the following tools:
- [solhint](https://protofire.github.io/solhint/) as the base linting tool
- [prettier](https://prettier.io/) as the base formatting tool
- [prettier-plugin-solidity](https://github.com/prettier-solidity/prettier-plugin-solidity) to format Solidity code


## VSCode support

If you are using VSCode you can install the [Solidity extension by Nomic Foundation](https://marketplace.visualstudio.com/items?itemName=NomicFoundation.hardhat-solidity). Unfortunately there is currently no way of getting real-time linting output from solhint, but this extension will provide formatting support using our prettier config and will also provide inline code validation using solc compiler output.

For formatting, the following settings should be added to your `settings.json` file:
```json
  "[solidity]": {
    "editor.defaultFormatter": "NomicFoundation.hardhat-solidity"
  },
```

Additionally you can configure the `Format document` keyboard shortcut to run `prettier --write` on demand.