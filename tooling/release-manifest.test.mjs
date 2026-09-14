import {test} from 'node:test';
import assert from 'node:assert/strict';
import {generateKeyPairSync, verify, createHash} from 'node:crypto';
import {mkdtemp, writeFile, rm} from 'node:fs/promises';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import {createManifest} from './release-manifest.mjs';

test('Signed manifest binds build, URLs and file hashes; rejects unsafe config', async () => {
  const dir = await mkdtemp(join(tmpdir(),'lumen-release-test-'));
  const {privateKey,publicKey} = generateKeyPairSync('ed25519');
  const pem = privateKey.export({type:'pkcs8',format:'pem'});
  try {
    await writeFile(join(dir,'lumen.apk'),'fixture');
    const config = {version:'1.2.3',build:42,baseUrl:'https://example.com/v1.2.3/',assets:{android:'lumen.apk'}};
    const signed = await createManifest(config,dir,pem);
    assert(verify(null,Buffer.from(signed.payload,'base64'),publicKey,Buffer.from(signed.signature,'base64')));
    const payload = JSON.parse(Buffer.from(signed.payload,'base64'));
    assert.equal(payload.build,42);
    assert.equal(payload.assets.android.sha256,createHash('sha256').update('fixture').digest('hex'));
    const tampered = Buffer.from(signed.payload,'base64');
    tampered[0] ^= 1;
    assert(!verify(null,tampered,publicKey,Buffer.from(signed.signature,'base64')));
    await assert.rejects(createManifest({...config,baseUrl:'http://example.com/'},dir,pem));
    await assert.rejects(createManifest({...config,assets:{android:'../secret'}},dir,pem));
    await assert.rejects(createManifest({...config,build:0},dir,pem));
  } finally { await rm(dir,{recursive:true,force:true}); }
});
