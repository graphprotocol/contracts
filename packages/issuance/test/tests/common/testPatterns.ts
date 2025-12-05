/**
 * Common test patterns shared by both allocate and eligibility tests
 */

import { expect } from 'chai'

/**
 * Comprehensive interface compliance test suite
 * Replaces multiple individual interface support tests
 *
 * @param contractGetter - Function that returns the contract instance to test
 * @param interfaces - Array of Typechain factory classes with interfaceId and interfaceName
 *
 * @example
 * import { IPausableControl__factory, IAccessControl__factory } from '@graphprotocol/interfaces/types'
 *
 * shouldSupportInterfaces(
 *   () => contract,
 *   [
 *     IPausableControl__factory,
 *     IAccessControl__factory,
 *   ]
 * )
 */
export function shouldSupportInterfaces<T>(
  contractGetter: () => T,
  interfaces: Array<{
    interfaceId: string
    interfaceName: string
  }>,
) {
  return function () {
    describe('Interface Compliance', () => {
      it('should support ERC-165 interface', async function () {
        const contract = contractGetter()
        expect(await (contract as any).supportsInterface('0x01ffc9a7')).to.be.true
      })

      interfaces.forEach((iface) => {
        it(`should support ${iface.interfaceName} interface`, async function () {
          const contract = contractGetter()
          expect(await (contract as any).supportsInterface(iface.interfaceId)).to.be.true
        })
      })

      it('should not support random interface', async function () {
        const contract = contractGetter()
        expect(await (contract as any).supportsInterface('0x12345678')).to.be.false
      })
    })
  }
}
