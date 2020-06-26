interface AccountMetadata {
  codeRepository: string
  description: string
  image: string
  name: string
  website: string
}

interface SubgraphMetadata {
  subgraphDescription: string
  subgraphDisplayName: string
  subgraphImage: string
  subgraphCodeRepository: string
  subgraphWebsite: string
  versionLabel: string
  versionDescription: string
}

const jsonToSubgraphMetadata = (json): SubgraphMetadata => {
  const subgraphMetadata: SubgraphMetadata = {
    subgraphDescription: checkString(json.subgraphDescription),
    subgraphDisplayName: checkString(json.subgraphDisplayName),
    subgraphImage: checkString(json.subgraphImage),
    subgraphCodeRepository: checkString(json.subgraphCodeRepository),
    subgraphWebsite: checkString(json.subgraphWebsite),
    versionLabel: checkString(json.versionLabel),
    versionDescription: checkString(json.versionDescription),
  }
  return subgraphMetadata
}

const jsonToAccountMetadata = (json): AccountMetadata => {
  const accountMetadata: AccountMetadata = {
    codeRepository: checkString(json.codeRepository),
    description: checkString(json.description),
    image: checkString(json.image),
    name: checkString(json.name),
    website: checkString(json.website),
  }
  return accountMetadata
}

const checkString = (field): string => {
  if (typeof field != 'string') {
    throw Error('Subgraph metadata is incorrect for one or more files')
  }
  return field
}

export { AccountMetadata, SubgraphMetadata, jsonToSubgraphMetadata, jsonToAccountMetadata }
