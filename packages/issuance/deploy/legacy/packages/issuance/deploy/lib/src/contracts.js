'use strict'
var __createBinding =
  (this && this.__createBinding) ||
  (Object.create
    ? function (o, m, k, k2) {
        if (k2 === undefined) k2 = k
        var desc = Object.getOwnPropertyDescriptor(m, k)
        if (!desc || ('get' in desc ? !m.__esModule : desc.writable || desc.configurable)) {
          desc = {
            enumerable: true,
            get: function () {
              return m[k]
            },
          }
        }
        Object.defineProperty(o, k2, desc)
      }
    : function (o, m, k, k2) {
        if (k2 === undefined) k2 = k
        o[k2] = m[k]
      })
var __setModuleDefault =
  (this && this.__setModuleDefault) ||
  (Object.create
    ? function (o, v) {
        Object.defineProperty(o, 'default', { enumerable: true, value: v })
      }
    : function (o, v) {
        o['default'] = v
      })
var __importStar =
  (this && this.__importStar) ||
  (function () {
    var ownKeys = function (o) {
      ownKeys =
        Object.getOwnPropertyNames ||
        function (o) {
          var ar = []
          for (var k in o) if (Object.prototype.hasOwnProperty.call(o, k)) ar[ar.length] = k
          return ar
        }
      return ownKeys(o)
    }
    return function (mod) {
      if (mod && mod.__esModule) return mod
      var result = {}
      if (mod != null)
        for (var k = ownKeys(mod), i = 0; i < k.length; i++) if (k[i] !== 'default') __createBinding(result, mod, k[i])
      __setModuleDefault(result, mod)
      return result
    }
  })()
Object.defineProperty(exports, '__esModule', { value: true })
exports.IssuanceArtifactsMap =
  exports.OPENZEPPELIN_ARTIFACTS_PATH =
  exports.ISSUANCE_ARTIFACTS_PATH =
  exports.IssuanceContractNameList =
    void 0
exports.isIssuanceContractName = isIssuanceContractName
exports.getArtifactPath = getArtifactPath
const path = __importStar(require('path'))
/**
 * IssuanceAllocator system contract names
 *
 * This includes all contracts that are part of the IssuanceAllocator deployment:
 * - IssuanceAllocator: Main contract (proxy)
 * - ProxyAdmin: Manages proxy upgrades
 * - TransparentUpgradeableProxy: The actual proxy contract
 */
exports.IssuanceContractNameList = [
  'IssuanceAllocator',
  'IssuanceAllocatorImplementation',
  'GraphProxyAdmin2',
  'IssuanceAllocatorProxy',
]
/**
 * Artifact paths for issuance contracts
 * Points to the compiled contract artifacts
 */
exports.ISSUANCE_ARTIFACTS_PATH = path.resolve(
  __dirname,
  '../../node_modules/@graphprotocol/contracts/artifacts/contracts',
)
exports.OPENZEPPELIN_ARTIFACTS_PATH = path.resolve(
  __dirname,
  '../../node_modules/@openzeppelin/contracts/build/contracts',
)
/**
 * Mapping of contract names to their artifact paths
 */
exports.IssuanceArtifactsMap = {
  IssuanceAllocator: exports.ISSUANCE_ARTIFACTS_PATH,
  IssuanceAllocatorImplementation: exports.ISSUANCE_ARTIFACTS_PATH,
  GraphProxyAdmin2: exports.OPENZEPPELIN_ARTIFACTS_PATH,
  IssuanceAllocatorProxy: exports.OPENZEPPELIN_ARTIFACTS_PATH,
}
/**
 * Type guard to check if a string is a valid IssuanceContractName
 *
 * @param name - String to check
 * @returns True if the name is a valid contract name
 */
function isIssuanceContractName(name) {
  return typeof name === 'string' && exports.IssuanceContractNameList.includes(name)
}
/**
 * Get the artifact path for a given contract name
 *
 * @param contractName - Name of the contract
 * @returns Path to the contract's artifacts
 */
function getArtifactPath(contractName) {
  return exports.IssuanceArtifactsMap[contractName]
}
//# sourceMappingURL=contracts.js.map
