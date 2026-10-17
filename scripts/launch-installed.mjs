import {verify} from './deployment.mjs';
import fs from 'node:fs';import path from 'node:path';import {pathToFileURL} from 'node:url';
const profile=process.argv[2];if(!profile)throw Error('Deployment profile path required');
const c=JSON.parse(fs.readFileSync(profile,'utf8').replace(/^\uFEFF/,''));
verify(c);await import(pathToFileURL(path.join(c.bridgeRoot,'dist/index.js')).href);
