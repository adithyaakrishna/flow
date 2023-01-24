/**
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 *
 * @flow
 * @format
 */

const {format} = require('util');
const {basename, join, relative, resolve} = require('path');

const {glob} = require('../utils/async');

type Command = {
  name: string,
  path: string,
};

async function finder(cwd: string): Promise<Map<string, string>> {
  const root = join('.', relative(cwd, join(__dirname, '..')));
  const commands = await glob(format('%s/**/*Command.js', root), {cwd});

  const commandMap = new Map();
  for (const command of commands) {
    const match = basename(command).match(/^(.*)Command.js$/);
    if (match != null) {
      const commandName = match[1];

      if (commandMap.has(commandName)) {
        throw new Error(
          format(
            'Error: Multiple providers for command `%s`:\n`%s` and `%s`\n',
            commandName,
            commandMap.get(commandName),
            command,
          ),
        );
      }
      commandMap.set(commandName, command);
    }
  }
  return commandMap;
}

module.exports = finder;
