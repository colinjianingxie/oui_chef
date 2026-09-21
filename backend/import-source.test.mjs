import { execFileSync } from 'node:child_process';
import test from 'node:test';

// Reproduce metadata-only success: it must still reach the public page's Chinese captions.
test('social imports try page captions on missing or empty tracks before downloading audio',()=>{
  execFileSync(process.execPath,['--experimental-test-module-mocks','--input-type=module','-'],{cwd:import.meta.dirname,input:`
import {mock} from 'node:test';
import assert from 'node:assert/strict';
import {EventEmitter} from 'node:events';
let mode, pages;
const transcript=JSON.stringify({events:[{tStartMs:1000,segs:[{utf8:'牛肉切块，冷水下锅，煮开后撇去浮沫。'}]}]});
mock.module('node:dns/promises',{namedExports:{lookup:async()=>[{address:'8.8.8.8'}]}});
mock.module('node:https',{namedExports:{request:(url,options,callback)=>{
  const req=new EventEmitter();req.setTimeout=()=>{};
  req.end=()=>{const res=new EventEmitter();res.statusCode=200;res.headers={'content-type':'text/html'};
    callback(res);
    const body=url.pathname==='/watch'?'page':url.searchParams.get('from')==='page'||mode==='direct'?transcript:'';
    res.emit('data',Buffer.from(body));res.emit('end');};return req;
}}});
mock.module('node:child_process',{namedExports:{execFile:(file,args,options,callback)=>{
  const metadata={title:'红烧牛肉',duration:306,subtitles:mode==='missing'?{}:{'zh-CN':[{ext:'json3',url:'https://www.youtube.com/api/timedtext?from=social'}]}};
  const page={title:'红烧牛肉',text:'Ingredients',captionTracks:[{languageCode:'zh-CN',baseUrl:'https://www.youtube.com/api/timedtext?from=page'}]};
  if(args.includes('yt_dlp'))callback(null,{stdout:JSON.stringify(metadata),stderr:''});
  else {pages++;callback(null,{stdout:JSON.stringify(page),stderr:''});}
}}});
const {readSocial}=await import('./import-source.mjs');
for(mode of ['missing','empty','direct']){
  pages=0;
  const result=await readSocial('https://www.youtube.com/watch?v=d31CCyGSGZA',{captions:true,withMedia:true});
  assert.equal(result.hasTranscript,true,mode);
  assert.equal(result.transcriptLanguage,'zh-CN');
  assert.match(result.transcript,/\\[1s\\].*撇去浮沫/);
  assert.equal(pages,mode==='direct'?0:1);
  assert.equal(result.audio,undefined);
}
`,stdio:'pipe'});
});
