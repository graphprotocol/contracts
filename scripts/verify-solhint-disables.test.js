#!/usr/bin/env node

/**
 * Unit tests for verify-solhint-disables.js
 *
 * Tests the extractDisabledRulesFromContent function with various file structures
 */

const { extractDisabledRulesFromContent, fixDisabledRulesInContent } = require('./verify-solhint-disables.js')

// Test helper
function assertArrayEquals(actual, expected, testName) {
  const actualStr = JSON.stringify(actual)
  const expectedStr = JSON.stringify(expected)
  if (actualStr === expectedStr) {
    console.log(`✅ ${testName}`)
    return true
  } else {
    console.log(`❌ ${testName}`)
    console.log(`   Expected: ${expectedStr}`)
    console.log(`   Actual:   ${actualStr}`)
    return false
  }
}

// Test cases
let passedTests = 0
let failedTests = 0

// Test 1: File with only pre-TODO disables
const test1 = `// SPDX-License-Identifier: GPL-2.0-or-later
// solhint-disable one-contract-per-file

pragma solidity ^0.7.6;

contract Foo {}`

const result1 = extractDisabledRulesFromContent(test1)
if (assertArrayEquals(result1.preTodoRules, ['one-contract-per-file'], 'Test 1: Pre-TODO only')) {
  passedTests++
} else {
  failedTests++
}
if (assertArrayEquals(result1.todoRules, [], 'Test 1: No TODO rules')) {
  passedTests++
} else {
  failedTests++
}
if (assertArrayEquals(result1.allRules, ['one-contract-per-file'], 'Test 1: All rules')) {
  passedTests++
} else {
  failedTests++
}

// Test 2: File with only TODO section disables
const test2 = `// SPDX-License-Identifier: GPL-2.0-or-later

pragma solidity ^0.7.6;

// TODO: Re-enable and fix issues when publishing a new version
// solhint-disable gas-indexed-events

contract Foo {}`

const result2 = extractDisabledRulesFromContent(test2)
if (assertArrayEquals(result2.preTodoRules, [], 'Test 2: No pre-TODO rules')) {
  passedTests++
} else {
  failedTests++
}
if (assertArrayEquals(result2.todoRules, ['gas-indexed-events'], 'Test 2: TODO section rules')) {
  passedTests++
} else {
  failedTests++
}
if (assertArrayEquals(result2.allRules, ['gas-indexed-events'], 'Test 2: All rules')) {
  passedTests++
} else {
  failedTests++
}

// Test 3: File with both pre-TODO and TODO section disables
const test3 = `// SPDX-License-Identifier: GPL-2.0-or-later
// solhint-disable one-contract-per-file

pragma solidity ^0.7.6;

// TODO: Re-enable and fix issues when publishing a new version
// solhint-disable gas-indexed-events
// solhint-disable named-parameters-mapping

import { Foo } from "./Foo.sol";

contract Bar {}`

const result3 = extractDisabledRulesFromContent(test3)
if (assertArrayEquals(result3.preTodoRules, ['one-contract-per-file'], 'Test 3: Pre-TODO rules')) {
  passedTests++
} else {
  failedTests++
}
if (
  assertArrayEquals(result3.todoRules, ['gas-indexed-events', 'named-parameters-mapping'], 'Test 3: TODO section rules')
) {
  passedTests++
} else {
  failedTests++
}
if (
  assertArrayEquals(
    result3.allRules,
    ['gas-indexed-events', 'named-parameters-mapping', 'one-contract-per-file'],
    'Test 3: All rules',
  )
) {
  passedTests++
} else {
  failedTests++
}

// Test 4: Multiple pre-TODO disables on separate lines
const test4 = `// SPDX-License-Identifier: GPL-2.0-or-later
// solhint-disable one-contract-per-file
// solhint-disable gas-custom-errors

pragma solidity ^0.7.6;

contract Foo {}`

const result4 = extractDisabledRulesFromContent(test4)
if (
  assertArrayEquals(
    result4.preTodoRules,
    ['gas-custom-errors', 'one-contract-per-file'],
    'Test 4: Multiple pre-TODO rules',
  )
) {
  passedTests++
} else {
  failedTests++
}

// Test 5: Multiple rules on same line (comma-separated)
const test5 = `// SPDX-License-Identifier: GPL-2.0-or-later

pragma solidity ^0.7.6;

// TODO: Re-enable and fix issues when publishing a new version
// solhint-disable gas-indexed-events, named-parameters-mapping, gas-small-strings

contract Foo {}`

const result5 = extractDisabledRulesFromContent(test5)
if (
  assertArrayEquals(
    result5.todoRules,
    ['gas-indexed-events', 'gas-small-strings', 'named-parameters-mapping'],
    'Test 5: Comma-separated rules',
  )
) {
  passedTests++
} else {
  failedTests++
}

// Test 6: File with no disables at all
const test6 = `// SPDX-License-Identifier: GPL-2.0-or-later

pragma solidity ^0.7.6;

contract Foo {}`

const result6 = extractDisabledRulesFromContent(test6)
if (assertArrayEquals(result6.allRules, [], 'Test 6: No disables')) {
  passedTests++
} else {
  failedTests++
}

// Test 7: Real-world example (CurationStorage.sol pattern)
const test7 = `// SPDX-License-Identifier: GPL-2.0-or-later
// solhint-disable one-contract-per-file

pragma solidity ^0.7.6;

// TODO: Re-enable and fix issues when publishing a new version
// solhint-disable named-parameters-mapping

import { Initializable } from "@openzeppelin/contracts-upgradeable/proxy/Initializable.sol";

contract CurationStorage {}`

const result7 = extractDisabledRulesFromContent(test7)
if (assertArrayEquals(result7.preTodoRules, ['one-contract-per-file'], 'Test 7 (Real): Pre-TODO rules')) {
  passedTests++
} else {
  failedTests++
}
if (assertArrayEquals(result7.todoRules, ['named-parameters-mapping'], 'Test 7 (Real): TODO rules')) {
  passedTests++
} else {
  failedTests++
}
if (
  assertArrayEquals(result7.allRules, ['named-parameters-mapping', 'one-contract-per-file'], 'Test 7 (Real): All rules')
) {
  passedTests++
} else {
  failedTests++
}

// Test 8: File with disables after TODO section (edge case)
const test8 = `// SPDX-License-Identifier: GPL-2.0-or-later

pragma solidity ^0.7.6;

// TODO: Re-enable and fix issues when publishing a new version
// solhint-disable gas-indexed-events

import { Foo } from "./Foo.sol";

// solhint-disable named-parameters-mapping

contract Bar {}`

const result8 = extractDisabledRulesFromContent(test8)
if (
  assertArrayEquals(
    result8.todoRules,
    ['gas-indexed-events', 'named-parameters-mapping'],
    'Test 8: Disables after TODO section collected',
  )
) {
  passedTests++
} else {
  failedTests++
}

// ========== FIX FUNCTION TESTS ==========
console.log('\n' + '='.repeat(50))
console.log('Testing fixDisabledRulesInContent function')
console.log('='.repeat(50) + '\n')

// Fix Test 1: Remove unnecessary rule from pre-TODO disable
const fixTest1Input = `// SPDX-License-Identifier: GPL-2.0-or-later

// solhint-disable one-contract-per-file, gas-small-strings

pragma solidity ^0.7.6;

contract Foo {}`

const fixTest1Expected = `// SPDX-License-Identifier: GPL-2.0-or-later

// solhint-disable one-contract-per-file

pragma solidity ^0.7.6;

contract Foo {}`

const fixTest1Result = fixDisabledRulesInContent(
  fixTest1Input,
  ['one-contract-per-file'],
  ['one-contract-per-file', 'gas-small-strings'],
)
if (fixTest1Result === fixTest1Expected) {
  console.log('✅ Fix Test 1: Remove unnecessary pre-TODO rule')
  passedTests++
} else {
  console.log('❌ Fix Test 1: Remove unnecessary pre-TODO rule')
  console.log('Expected:', fixTest1Expected)
  console.log('Actual:', fixTest1Result)
  failedTests++
}

// Fix Test 2: Remove all pre-TODO disables when none needed
const fixTest2Input = `// SPDX-License-Identifier: GPL-2.0-or-later

// solhint-disable one-contract-per-file

pragma solidity ^0.7.6;

contract Foo {}`

const fixTest2Expected = `// SPDX-License-Identifier: GPL-2.0-or-later

pragma solidity ^0.7.6;

contract Foo {}`

const fixTest2Result = fixDisabledRulesInContent(fixTest2Input, [], ['one-contract-per-file'])
if (fixTest2Result === fixTest2Expected) {
  console.log('✅ Fix Test 2: Remove all pre-TODO disables when none needed')
  passedTests++
} else {
  console.log('❌ Fix Test 2: Remove all pre-TODO disables when none needed')
  failedTests++
}

// Fix Test 3: Add TODO section when new rules needed
const fixTest3Input = `// SPDX-License-Identifier: GPL-2.0-or-later

pragma solidity ^0.7.6;

contract Foo {}`

const fixTest3Expected = `// SPDX-License-Identifier: GPL-2.0-or-later

pragma solidity ^0.7.6;

// TODO: Re-enable and fix issues when publishing a new version
// solhint-disable gas-indexed-events

contract Foo {}`

const fixTest3Result = fixDisabledRulesInContent(fixTest3Input, ['gas-indexed-events'], [])
if (fixTest3Result === fixTest3Expected) {
  console.log('✅ Fix Test 3: Add TODO section when new rules needed')
  passedTests++
} else {
  console.log('❌ Fix Test 3: Add TODO section when new rules needed')
  console.log('Expected:', fixTest3Expected)
  console.log('Actual:', fixTest3Result)
  failedTests++
}

// Fix Test 4: Keep pre-TODO, add TODO section for additional rules
const fixTest4Input = `// SPDX-License-Identifier: GPL-2.0-or-later

// solhint-disable one-contract-per-file

pragma solidity ^0.7.6;

contract Foo {}
contract Bar {}`

const fixTest4Expected = `// SPDX-License-Identifier: GPL-2.0-or-later

// solhint-disable one-contract-per-file

pragma solidity ^0.7.6;

// TODO: Re-enable and fix issues when publishing a new version
// solhint-disable gas-indexed-events

contract Foo {}
contract Bar {}`

const fixTest4Result = fixDisabledRulesInContent(
  fixTest4Input,
  ['one-contract-per-file', 'gas-indexed-events'],
  ['one-contract-per-file'],
)
if (fixTest4Result === fixTest4Expected) {
  console.log('✅ Fix Test 4: Keep pre-TODO, add TODO for additional rules')
  passedTests++
} else {
  console.log('❌ Fix Test 4: Keep pre-TODO, add TODO for additional rules')
  console.log('Expected:', fixTest4Expected)
  console.log('Actual:', fixTest4Result)
  failedTests++
}

// Fix Test 5: Remove unnecessary TODO section
const fixTest5Input = `// SPDX-License-Identifier: GPL-2.0-or-later

pragma solidity ^0.7.6;

// TODO: Re-enable and fix issues when publishing a new version
// solhint-disable gas-indexed-events

contract Foo {}`

const fixTest5Expected = `// SPDX-License-Identifier: GPL-2.0-or-later

pragma solidity ^0.7.6;

contract Foo {}`

const fixTest5Result = fixDisabledRulesInContent(fixTest5Input, [], [])
if (fixTest5Result === fixTest5Expected) {
  console.log('✅ Fix Test 5: Remove unnecessary TODO section')
  passedTests++
} else {
  console.log('❌ Fix Test 5: Remove unnecessary TODO section')
  failedTests++
}

// Summary
console.log(`\n${'='.repeat(50)}`)
console.log(`Test Summary: ${passedTests} passed, ${failedTests} failed`)
console.log(`${'='.repeat(50)}`)

if (failedTests > 0) {
  process.exit(1)
}
