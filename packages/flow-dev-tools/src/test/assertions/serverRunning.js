/**
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 *
 * @flow
 * @format
 */

const {default: simpleDiffAssertion} = require('./simpleDiffAssertion');

import type {AssertionLocation, ErrorAssertion} from './assertionTypes';

function serverRunning(
  expected: 'stopped' | 'running',
  assertLoc: ?AssertionLocation,
): ErrorAssertion {
  return (reason: ?string, env) => {
    const actual = env.getServerRunning();
    const suggestion = {method: 'verifyServerStatus', args: [actual]};
    return simpleDiffAssertion(
      String(expected),
      String(actual),
      assertLoc,
      reason,
      "'server is running'",
      suggestion,
    );
  };
}

module.exports = {
  default: serverRunning,
};
