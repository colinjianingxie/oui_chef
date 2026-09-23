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
  assert.equal(pages,1,'missing media formats also need the public player fallback');
  assert.equal(result.audio,undefined);
}
`,stdio:'pipe'});
});

test('separate video and audio survive absent duration, failed audio, and metadata reuse',()=>{
  execFileSync(process.execPath,['--experimental-test-module-mocks','--input-type=module','-'],{cwd:import.meta.dirname,input:`
import {mock} from 'node:test';
import assert from 'node:assert/strict';
import {execFile as execute,execFileSync} from 'node:child_process';
import {EventEmitter} from 'node:events';
const video=execFileSync('ffmpeg',['-v','error','-f','lavfi','-i','color=c=red:s=16x16:d=1','-f','lavfi','-i','anullsrc','-t','1','-c:v','mpeg4','-c:a','aac','-movflags','frag_keyframe+empty_moov','-f','mp4','pipe:1']);
const jpeg=execFileSync('ffmpeg',['-v','error','-f','lavfi','-i','color=c=red:s=16x16','-frames:v','1','-f','image2pipe','-vcodec','mjpeg','pipe:1']);
let metadataCalls=0,rangeCalls=0,failAudio=false,imagesOnly=false;
mock.module('node:dns/promises',{namedExports:{lookup:async()=>[{address:'8.8.8.8'}]}});
mock.module('node:https',{namedExports:{request:(url,options,callback)=>{
  const req=new EventEmitter();req.setTimeout=()=>{};
  req.end=()=>{const res=new EventEmitter();res.statusCode=failAudio&&url.pathname==='/audio'?403:206;
    if(url.pathname==='/image'){res.statusCode=200;res.headers={'content-type':'image/jpeg'};callback(res);res.emit('data',jpeg);res.emit('end');return;}
    const start=Number(options.headers.Range.match(/bytes=(\\d+)/)[1]),end=Math.min(start+511,video.length-1);rangeCalls++;
    res.headers={'content-range':\`bytes \${start}-\${end}/\${video.length}\`};callback(res);res.emit('data',video.subarray(start,end+1));res.emit('end');};return req;
}}});
mock.module('node:child_process',{namedExports:{execFile:(file,args,options,callback)=>{
  if(!args.includes('yt_dlp'))return execute(file,args,options,(error,stdout,stderr)=>callback(error,{stdout,stderr}));
  metadataCalls++;
  const formats=[{url:'https://media.example/video',protocol:'https',vcodec:'mpeg4',acodec:'none',width:360,height:640},{url:'https://media.example/audio',protocol:'https',vcodec:'none',acodec:'aac'}];
  callback(null,{stdout:JSON.stringify({title:'Cooking',formats:imagesOnly?[]:formats,thumbnail:'https://media.example/image'}),stderr:''});
}}});
const {readSocial}=await import('./import-source.mjs');
const original=await readSocial('https://www.instagram.com/reel/example',{captions:true});
assert.equal(metadataCalls,1);
const result=await readSocial('https://www.instagram.com/reel/example',{previous:original,withMedia:true});
assert.equal(metadataCalls,1,'reuse metadata rather than request another expiring source');
assert.equal(result.images.length,4);
assert.ok(result.audio.length>0);assert.ok(result.duration>0);
assert.ok(rangeCalls>2,'download each media stream using validated ranges');
failAudio=true;
const partial=await readSocial('https://www.tiktok.com/@chef/video/123',{withMedia:true});
assert.equal(partial.images.length,4,'failed audio must not discard visual evidence');
assert.equal(partial.audio,undefined);assert.ok(partial.retrievalErrors.some(e=>e.includes('Audio retrieval:')));
imagesOnly=true;
const post=await readSocial('https://www.xiaohongshu.com/explore/example',{withMedia:true});
assert.equal(post.images.length,1);assert.equal(post.images[0].second,null,'a static post image must never pretend to be a video frame');
assert.ok(post.images[0].data.length>0);
`,stdio:'pipe'});
});
