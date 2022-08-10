import { HardhatRuntimeEnvironment } from 'hardhat/types'

// Set signers on fixture with hh signers
export const setFixtureSigners = async (
  hre: HardhatRuntimeEnvironment,
  fixture: any,
): Promise<any> => {
  const graph = hre.graph()
  const [
    indexer1,
    indexer2,
    subgraphOwner,
    curator1,
    curator2,
    curator3,
    allocation1,
    allocation2,
    allocation3,
    allocation4,
    allocation5,
    allocation6,
    allocation7,
  ] = await graph.getTestAccounts()

  fixture.indexers[0].signer = indexer1
  fixture.indexers[0].allocations[0].signer = allocation1
  fixture.indexers[0].allocations[1].signer = allocation2
  fixture.indexers[0].allocations[2].signer = allocation3

  fixture.indexers[1].signer = indexer2
  fixture.indexers[1].allocations[0].signer = allocation4
  fixture.indexers[1].allocations[1].signer = allocation5
  fixture.indexers[1].allocations[2].signer = allocation6
  fixture.indexers[1].allocations[3].signer = allocation7

  fixture.curators[0].signer = curator1
  fixture.curators[1].signer = curator2
  fixture.curators[2].signer = curator3

  fixture.subgraphOwner = subgraphOwner

  return fixture
}
