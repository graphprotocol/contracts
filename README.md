<p align="center">
  <a href="https://thegraph.com/"><img src="https://storage.thegraph.com/logos/grt.png" alt="The Graph" width="200"></a> 
</p>

<h3 align="center">The Graph Protocol</h3>
<h4 align="center">A decentralized network for querying and indexing blockchain data.</h4>

<p align="center">
  <a href="https://github.com/graphprotocol/contracts/actions/workflows/build.yml">
    <img src="https://github.com/graphprotocol/contracts/actions/workflows/build.yml/badge.svg" alt="Build">
  </a>
  <a href="https://github.com/graphprotocol/contracts/actions/workflows/ci.yml">
    <img src="https://github.com/graphprotocol/contracts/actions/workflows/ci.yml/badge.svg" alt="CI">
  </a>
  <a href="https://github.com/graphprotocol/contracts/actions/workflows/e2e.yml">
    <img src="https://github.com/graphprotocol/contracts/actions/workflows/e2e.yml/badge.svg" alt="E2E">
  </a>
</p>

<p align="center">
  <a href="#packages">Packages</a> •
  <a href="#development">Development</a> •
  <a href="#documentation">Docs</a> •
  <a href="#contributing">Contributing</a> •
  <a href="#security">Security</a> •
  <a href="#license">License</a>
</p>

---

[The Graph](https://thegraph.com/) is an indexing protocol for querying networks like Ethereum, IPFS, Polygon, and other blockchains. Anyone can build and Publish open APIs, called subgraphs, making data easily accessible.

## Packages

This repository is a Yarn workspaces monorepo containing the following packages:

| Package | Latest version | Description |
| --- | --- | --- |
| [contracts](./packages/contracts) | [![npm version](https://badge.fury.io/js/@graphprotocol%2Fcontracts.svg)](https://badge.fury.io/js/@graphprotocol%2Fcontracts) | Contracts enabling the open and permissionless decentralized network known as The Graph protocol. |
| [sdk](./packages/sdk) | [![npm version](https://badge.fury.io/js/@graphprotocol%2Fsdk.svg)](https://badge.fury.io/js/@graphprotocol%2Fsdk) | TypeScript based SDK to interact with the protocol contracts |


## Development

### Setup
To set up this project you'll need [git](https://git-scm.com) and [yarn](https://yarnpkg.com/) installed. Note that Yarn v4 is required to install the dependencies and build the project. 

From your command line:

```bash
# Enable Yarn v4
corepack enable
yarn set version stable

# Clone this repository
$ git clone https://github.com/graphprotocol/contracts

# Go into the repository
$ cd contracts

# Install dependencies
$ yarn

# Build projects
$ yarn build
```

### Versioning a package 

To version a package, run the following command from the root of the repository:

```bash
# Change directory to the package you want to version
$ cd packages/<package-name>

# Bump the version
$ yarn version <major|minor|patch>
```

__Note on cross referenced packages__: Bumping the version of a package that is cross referenced by another package will automatically bump the dependency version in the other package. For example, if you bump the version of `sdk` from `0.0.1` to `0.0.2`, the required version of `sdk` in the `contracts` package will automatically be bumped to `0.0.2`. Depending on the nature of the change you might need to bump (and publish) a new version of the `contracts` package as well.

### Publishing a package

Packages are published and distributed via NPM. To publish a package, run the following command from the root of the repository:

```bash
# Publish the package
$ yarn npm publish --access public --tag <tag>
```

Alternatively, there is a GitHub action that can be manually triggered to publish a package.

## Documentation

> Coming soon

For now, each package has its own README with more specific documentation you can check out.

## Contributing

Contributions are welcomed and encouraged! You can do so by:

- Creating an issue
- Opening a PR

If you are opening a PR, it is a good idea to first go to [The Graph Discord](https://discord.com/invite/vtvv7FP) or [The Graph Forum](https://forum.thegraph.com/) and discuss your idea! Discussions on the forum or Discord are another great way to contribute.

## Security

If you find a bug or security issue please go through the official channel, [The Graph Security Bounties on Immunefi](https://immunefi.com/bounty/thegraph/). Responsible disclosure procedures must be followed to receive bounties.

## License

Copyright &copy; 2021 The Graph Foundation

Licensed under [GPL license](LICENSE).
