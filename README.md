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
| [eslint-graph-config](./packages/eslint-graph-config) | [![npm version]()]() | Shared linting and formatting rules for TypeScript projects. |
| [token-distribution](./packages/token-distribution) | - | Contracts managing token locks for network participants |
| [sdk](./packages/sdk) | [![npm version](https://badge.fury.io/js/@graphprotocol%2Fsdk.svg)](https://badge.fury.io/js/@graphprotocol%2Fsdk) | TypeScript based SDK to interact with the protocol contracts |
| [solhint-graph-config](./packages/eslint-graph-config) | [![npm version]()]() | Shared linting and formatting rules for Solidity projects. |


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

### Versioning and publishing packages

We use [changesets](https://github.com/changesets/changesets) to manage package versioning, this ensures that all packages are versioned together in a consistent manner and helps with generating changelogs.

#### Step 1: Creating a changeset

A changeset is a file that describes the changes that have been made to the packages in the repository. To create a changeset, run the following command from the root of the repository:

```bash
$ yarn changeset
```

Changeset files are stored in the `.changeset` directory until they are packaged into a release. You can commit these files and even merge them into your main branch without publishing a release.

#### Step 2: Creating a package release

When you are ready to create a new package release, run the following command to package all changesets, this will also bump package versions and dependencies:

```bash
$ yarn changeset version
```

### Step 3: Tagging the release

__Note__: this step is meant to be run on the main branch.

After creating a package release, you will need to tag the release commit with the version number. To do this, run the following command from the root of the repository:

```bash
$ yarn changeset tag
$ git push --follow-tags
```

#### Step 4: Publishing a package release

__Note__: this step is meant to be run on the main branch.

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
