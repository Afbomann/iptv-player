import {test} from 'node:test';
import assert from 'node:assert/strict';
import {resolveVersion} from './release-version.mjs';

const automatic = {event: 'push', run: 2, pubspec: 'version: 0.1.0+1\n'};
test('pushes receive unique versions and builds without dispatch inputs', () => {
  assert.deepEqual(resolveVersion(automatic), {version: '0.1.2', build: 3});
  assert.deepEqual(resolveVersion({...automatic, run: 3}), {version: '0.1.3', build: 4});
});
test('automatic numbering advances beyond a prior manual release', () => {
  assert.deepEqual(resolveVersion({...automatic, previous: {version: '1.2.30', build: 800}}), {version: '1.2.31', build: 801});
});
test('manual versions stay explicit and invalid inputs fail', () => {
  assert.deepEqual(resolveVersion({event: 'workflow_dispatch', version: '2.0.1', build: '900'}), {version: '2.0.1', build: 900});
  assert.throws(() => resolveVersion({...automatic, run: 0}));
  assert.throws(() => resolveVersion({event: 'pull_request'}));
  assert.throws(() => resolveVersion({event: 'workflow_dispatch', version: '1.0.1\ninjected', build: '1'}));
  assert.throws(() => resolveVersion({...automatic, previous: {version: '1.0.65535', build: 900}}));
});
