// Public-source diagnostics; --live also calls AI and runs the worker with an in-memory cookbook.
// Never writes to Firebase or consumes the app's shared import-attempt allowance.
import {readPage,readSocial,importInput} from './import-source.mjs';
import {runImport} from './companion.mjs';
const live=process.argv.includes('--live'), urls=process.argv.slice(2).filter(arg=>arg!=='--live');
if(!urls.length || (live && !process.env.XAI_API_KEY)) throw new Error('Usage: node backend/import-smoke.mjs [--live] URL ... (--live requires XAI_API_KEY and incurs provider usage)');
for(const url of urls) {
  const input=importInput({url}),path='users/parser-check/imports/check';
  if(!live) {
    try {
      const source=input.source==='Website'?await readPage(input.url):await readSocial(input.url,{captions:true,withMedia:true,translatedCaptions:false});
      console.log(JSON.stringify({url:input.url,title:source.title,duration:source.duration,transcriptLanguage:source.transcriptLanguage,transcriptCharacters:source.transcript?.length??0,frames:source.images?.length??0,audioBytes:source.audio?.length??0,errors:source.retrievalErrors}));
      if(!source.transcript && !source.images?.length && !source.audio && !source.description && !source.structured?.length)process.exitCode=1;
    } catch(error) { console.log(JSON.stringify({url:input.url,error:error.message}));process.exitCode=1; }
    continue;
  }
  const records=new Map([[path,{...input,status:'queued',attempt:1}],['users/parser-check/settings/cooking',{payload:JSON.stringify({voiceLanguage:process.env.IMPORT_CHECK_LANGUAGE??'English'})}]]);
  const db={doc(path){return {path,get:async()=>({exists:records.has(path),data:()=>records.get(path)}),set:async value=>records.set(path,value),update:async value=>records.set(path,{...records.get(path),...value}),collection:name=>({doc:id=>db.doc(`${path}/${name}/${id}`)})};},runTransaction:async fn=>fn({get:ref=>ref.get(),set:(ref,value)=>ref.set(value),update:(ref,value)=>ref.update(value)})};
  await runImport(db,'parser-check','check',1);
  const job=records.get(path),saved=records.get('users/parser-check/cookbook/check');
  console.log(JSON.stringify({url:input.url,status:job.status,message:job.message,failurePoint:job.failurePoint,reason:job.extractionReason,retrieval:job.retrieval,errors:job.retrievalErrors,originalTranscript:job.originalTranscript,translatedTranscript:job.translatedTranscript,videoObservations:job.videoObservations,recipe:saved?JSON.parse(saved.payload):null,runs:[...records].filter(([key])=>key.startsWith('aiRuns/')).map(([,value])=>value)}));
  if(job.status!=='ready')process.exitCode=1;
}
