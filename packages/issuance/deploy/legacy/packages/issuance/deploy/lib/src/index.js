'use strict'
/**
 * IssuanceAllocator Deployment Utilities
 *
 * This module provides TypeScript utilities for deploying and managing
 * IssuanceAllocator system contracts with type safety and toolshed integration.
 */
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
var __exportStar =
  (this && this.__exportStar) ||
  function (m, exports) {
    for (var p in m)
      if (p !== 'default' && !Object.prototype.hasOwnProperty.call(exports, p)) __createBinding(exports, m, p)
  }
Object.defineProperty(exports, '__esModule', { value: true })
// Contract type definitions and utilities
__exportStar(require('./contracts'), exports)
// Address book for contract management
__exportStar(require('./address-book'), exports)
//# sourceMappingURL=index.js.map
