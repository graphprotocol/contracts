import { toGRT } from '../../../cli/network'

export const fixture = {
  ethAmount: toGRT(0.1),
  grtAmount: toGRT(100_000),
  indexers: [
    // indexer1
    {
      signer: null,
      stake: toGRT(100_000),
      allocations: [
        {
          signer: null,
          subgraphDeploymentId:
            '0xbbde25a2c85f55b53b7698b9476610c3d1202d88870e66502ab0076b7218f98a',
          amount: toGRT(25_000),
          close: false,
        },
        {
          signer: null,
          subgraphDeploymentId:
            '0x0653445635cc1d06bd2370d2a9a072406a420d86e7fa13ea5cde100e2108b527',
          amount: toGRT(50_000),
          close: true,
        },
        {
          signer: null,
          subgraphDeploymentId:
            '0xbbde25a2c85f55b53b7698b9476610c3d1202d88870e66502ab0076b7218f98a',
          amount: toGRT(10_000),
          close: true,
        },
      ],
    },
    // indexer2
    {
      signer: null,
      stake: toGRT(100_000),
      allocations: [
        {
          signer: null,
          subgraphDeploymentId:
            '0x3093dadafd593b5c2d10c16bf830e96fc41ea7b91d7dabd032b44331fb2a7e51',
          amount: toGRT(25_000),
          close: true,
        },
        {
          signer: null,
          subgraphDeploymentId:
            '0x0653445635cc1d06bd2370d2a9a072406a420d86e7fa13ea5cde100e2108b527',
          amount: toGRT(10_000),
          close: false,
        },
        {
          signer: null,
          subgraphDeploymentId:
            '0x3093dadafd593b5c2d10c16bf830e96fc41ea7b91d7dabd032b44331fb2a7e51',
          amount: toGRT(10_000),
          close: true,
        },
        {
          signer: null,
          subgraphDeploymentId:
            '0xb3fc2abc303c70a16ab9d5fc38d7e8aeae66593a87a3d971b024dd34b97e94b1',
          amount: toGRT(45_000),
          close: true,
        },
      ],
    },
  ],
  curators: [
    // curator1
    {
      signer: null,
      signalled: toGRT(10_400),
      subgraphs: [
        {
          deploymentId: '0x0653445635cc1d06bd2370d2a9a072406a420d86e7fa13ea5cde100e2108b527',
          signal: toGRT(400),
        },
        {
          deploymentId: '0x3093dadafd593b5c2d10c16bf830e96fc41ea7b91d7dabd032b44331fb2a7e51',
          signal: toGRT(4_000),
        },
        {
          deploymentId: '0xb3fc2abc303c70a16ab9d5fc38d7e8aeae66593a87a3d971b024dd34b97e94b1',
          signal: toGRT(6_000),
        },
      ],
    },
    // curator2
    {
      signer: null,
      signalled: toGRT(4_500),
      subgraphs: [
        {
          deploymentId: '0x3093dadafd593b5c2d10c16bf830e96fc41ea7b91d7dabd032b44331fb2a7e51',
          signal: toGRT(2_000),
        },
        {
          deploymentId: '0xb3fc2abc303c70a16ab9d5fc38d7e8aeae66593a87a3d971b024dd34b97e94b1',
          signal: toGRT(2_500),
        },
      ],
    },
    // curator3
    {
      signer: null,
      signalled: toGRT(8_000),
      subgraphs: [
        {
          deploymentId: '0x3093dadafd593b5c2d10c16bf830e96fc41ea7b91d7dabd032b44331fb2a7e51',
          signal: toGRT(4_000),
        },
        {
          deploymentId: '0xb3fc2abc303c70a16ab9d5fc38d7e8aeae66593a87a3d971b024dd34b97e94b1',
          signal: toGRT(4_000),
        },
      ],
    },
  ],
  subgraphOwner: null,
  subgraphs: [
    {
      deploymentId: '0xbbde25a2c85f55b53b7698b9476610c3d1202d88870e66502ab0076b7218f98a',
      subgraphId: null,
    },
    {
      deploymentId: '0x0653445635cc1d06bd2370d2a9a072406a420d86e7fa13ea5cde100e2108b527',
      subgraphId: null,
    },
    {
      deploymentId: '0x3093dadafd593b5c2d10c16bf830e96fc41ea7b91d7dabd032b44331fb2a7e51',
      subgraphId: null,
    },
    {
      deploymentId: '0xb3fc2abc303c70a16ab9d5fc38d7e8aeae66593a87a3d971b024dd34b97e94b1',
      subgraphId: null,
    },
  ],
}
