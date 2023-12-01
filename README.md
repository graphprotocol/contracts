<p align="center">
  <a href="https://thegraph.com/"><img src="https://storage.thegraph.com/logos/grt.png" alt="The Graph" width="200"></a> 
</p>

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
  <a href="#setup">Setup</a> •
  <a href="#documentation">Docs</a> •
  <a href="#contributing">Contributing</a> •
  <a href="#security">Security</a> •
  <a href="#license">License</a>
</p>

---

[The Graph](https://thegraph.com/) is an indexing protocol for querying networks like Ethereum, IPFS, Polygon, and other blockchains. Anyone can build and Publish open APIs, called subgraphs, making data easily accessible.

## Packages

This repository is a Yarn workspaces monorepo containing the following packages:

- [contracts](./packages/contracts): Contracts enabling the open and permissionless decentralized network known as The Graph protocol.
- [sdk](./packages/sdk): TypeScript based SDK to interact with the protocol contracts

## Setup

To set up this project you'll need [git](https://git-scm.com) and [yarn](https://yarnpkg.com/) installed.
From your command line:

```bash
# Clone this repository
$ git clone https://github.com/graphprotocol/contracts

# Go into the repository
$ cd contracts

# Install dependencies
$ yarn

# Build projects
$ yarn build
```

## Documentation

> Coming soon

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
