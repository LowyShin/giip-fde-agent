#!/usr/bin/env node

'use strict';

const path = require('path');
const { run } = require('../lib/windows-hook-doctor');

function parseArgs(argv) {
  const args = new Set(argv);
  return {
    repair: args.has('--repair'),
    quiet: args.has('--quiet'),
    json: args.has('--json'),
  };
}

function summary(result) {
  const codes = [...new Set(result.issues.map((issue) => issue.code))];
  return [
    `status=${result.status}`,
    `hooks=${result.inspectedHooks}`,
    `changed=${result.changedFiles.length}`,
    `issues=${codes.length ? codes.join(',') : 'none'}`,
  ].join(' ');
}

function main(argv = process.argv.slice(2)) {
  const options = parseArgs(argv);
  const result = run({
    root: path.join(__dirname, '..'),
    repair: options.repair,
  });

  if (options.json) {
    console.log(JSON.stringify(result));
  } else if (!options.quiet || result.status === 'blocked') {
    const output = `[giip hook doctor] ${summary(result)}`;
    if (result.status === 'blocked') console.error(output);
    else console.log(output);
  }

  return result.status === 'blocked' ? 2 : 0;
}

if (require.main === module) {
  try {
    process.exitCode = main();
  } catch (error) {
    console.error(`[giip hook doctor] status=blocked error=${error.message}`);
    process.exitCode = 2;
  }
}

module.exports = { main, parseArgs, summary };

