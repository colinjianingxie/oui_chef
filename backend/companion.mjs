import { createHash, createHmac, timingSafeEqual } from 'node:crypto';
import { applicationDefault } from 'firebase-admin/app';
import { getStorage } from 'firebase-admin/storage';
import { importInput, readPage, readSocial, safeFetch, retrievalError, descriptionLinks } from './import-source.mjs';
import { classifySource, extractRecipe, transcribe, translateTranscript, researchSource, inspectYouTube, answerQuestion, validateRecipe } from './recipe-agent.mjs';
const allowedID = value => typeof value==='string' && /^[A-Za-z0-9_-]{1,128}$/.test(value);
export const importTaskID = (uid,id,attempt) => `import-${createHash('sha256').update(uid).digest('hex').slice(0,24)}-${id}-${attempt}`;
const signature = body => createHmac('sha256',process.env.XAI_API_KEY??'').update('oui-import:'+body).digest('hex');
const importDay = () => new Date().toISOString().slice(0,10);
const sharedRecipeID = (url,text,profile) => url && !text ? createHash('sha256').update(`companion-9\0${url}\0${profile}`).digest('hex') : null;
const activeImport = (limit,id,attempt) => limit?.activeID===id && limit?.activeAttempt===attempt;
const importDebug = data => Object.fromEntries(['sourceTitle','previewCreator','sourceDurationSeconds','sourceExtractor','sourceText','originalTranscript','transcriptLanguage','translatedTranscript','translationLanguage','videoObservations','frameSeconds','retrieval','retrievalErrors','scope','scopeReason','recipeTitle','previewSummary','previewIngredients','previewSteps','extractionReason','failurePoint'].filter(key=>data[key]!==undefined).map(key=>[key,data[key]]));
async function releaseImport(db,uid,id,attempt) {
  const ref=db.doc(`importLimits/${uid}`);
  await db.runTransaction(async tx=>{const doc=await tx.get(ref);if(activeImport(doc.data(),id,attempt))tx.set(ref,{day:doc.data().day,count:doc.data().count});});
}
const send=(res,status,body)=>{res.writeHead(status,{'Content-Type':'application/json','Cache-Control':'no-store'});res.end(JSON.stringify(body));};
const extractionPreview=(recipe,failurePoint) => ({
  recipeTitle:recipe.title?.trim()?.slice(0,500)||null,
  previewIngredients:(recipe.ingredients??[]).map(item=>`${item.quantity} ${item.name}`).slice(0,150),
  previewSteps:(recipe.steps??[]).map(step=>step.title||step.instruction).slice(0,150),
  extractionReason:recipe.outcome==='recipe'?null:recipe.reason?.slice(0,1000)||null,
  failurePoint:recipe.outcome==='recipe'?null:failurePoint
});
async function readBody(req) {let size=0,chunks=[];for await(const chunk of req){size+=chunk.length;if(size>3_200_000)throw new Error('Request too large.');chunks.push(chunk);}return Buffer.concat(chunks).toString();}
async function enqueue(uid,id,attempt) {
  const body=JSON.stringify({uid,id,attempt});
  if(process.env.IMPORT_INLINE==='1' && !process.env.K_SERVICE) return false;
  const {IMPORT_TASK_QUEUE:queue,IMPORT_WORKER_URL:url}=process.env;
  if(!queue||!url) throw new Error('Recipe import is not configured yet.');
  const {access_token}=await applicationDefault().getAccessToken();
  const response=await fetch(`https://cloudtasks.googleapis.com/v2/${queue}/tasks`,{method:'POST',headers:{Authorization:`Bearer ${access_token}`,'Content-Type':'application/json'},body:JSON.stringify({task:{name:`${queue}/tasks/${importTaskID(uid,id,attempt)}`,dispatchDeadline:'900s',httpRequest:{httpMethod:'POST',url,headers:{'Content-Type':'application/json','X-Oui-Task':signature(body)},body:Buffer.from(body).toString('base64')}}}),signal:AbortSignal.timeout(15000)});
  if(!response.ok && response.status!==409) throw new Error('Could not queue this import. Please retry.');
  return true;
}
export async function runImport(db,uid,id,attempt) {
  const ref=db.doc(`users/${uid}/imports/${id}`);
  const claimed=await db.runTransaction(async tx=>{
    const [doc,deleted]=await Promise.all([tx.get(ref),tx.get(db.doc(`deletedAccounts/${uid}`))]),data=doc.data();
    if(deleted.exists)return null;
    if(!data||data.attempt!==attempt||data.status!=='queued')return null;
    tx.update(ref,{status:'fetching',stage:0,message:'Reading the original source…',startedAt:Date.now()});return data;
  });
  if(!claimed)return;
  const progress=async(status,message,stage,details={})=>{
    await db.runTransaction(async tx=>{
      const current=await tx.get(ref);if(!current.exists||current.data()?.status==='canceled'||current.data()?.attempt!==attempt)throw new Error('Import canceled.');
      tx.update(ref,{status,message,...(stage == null ? {} : {stage}),...details,updatedAt:Date.now()});
    });
  };
  try {
    const profileDoc=await db.doc(`users/${uid}/settings/cooking`).get();
    const profilePayload=profileDoc.data()?.payload??'{}',profile=JSON.parse(profilePayload);
    const targetLanguage=typeof profile.voiceLanguage==='string' && profile.voiceLanguage.trim() ? profile.voiceLanguage.trim().slice(0,80) : 'English';
    let evidence={url:claimed.url,text:'',images:[],mediaAttempted:false}, retrievalErrors=[];
    let retrieval={source:claimed.source,method:claimed.url?'html':'pasted_text',hasTranscript:false};
    const metadata = async source => progress('fetching','Found the source. Reading its metadata and transcript…',0,{
      previewTitle: typeof source.title === 'string' ? source.title.slice(0,500) : null,
      sourceTitle: typeof source.title === 'string' ? source.title.slice(0,500) : null,
      previewCreator: typeof source.creator === 'string' ? source.creator.slice(0,200) : null,
      sourceDurationSeconds: Number.isFinite(source.duration) ? source.duration : null,
      sourceExtractor: typeof source.extractor === 'string' ? source.extractor.slice(0,100) : null
    });
    if(claimed.url) {
      if(claimed.source==='Website') {
        try {evidence={...evidence,...await readPage(claimed.url,{onMetadata:metadata})};}catch{retrievalErrors.push('The public page could not be read.');}
      } else {
        try {
          const social=await readSocial(claimed.url,{captions:true,translatedCaptions:false,onMetadata:metadata});
          evidence={...evidence,...social};
          retrievalErrors.push(...social.retrievalErrors);
          retrieval={source:claimed.source,method:'yt-dlp',extractor:social.extractor,hasTranscript:!!social.transcript,transcriptLanguage:social.transcriptLanguage??null};
        } catch(error) {
          retrievalErrors.push(retrievalError(error));
          retrieval.method='html_fallback';
          try {
            const page=await readPage(claimed.url,{captions:true,translatedCaptions:false,onMetadata:metadata});
            evidence={...evidence,...page}; retrievalErrors.push(...page.retrievalErrors);
            retrieval.hasTranscript=!!page.transcript; retrieval.transcriptLanguage=page.transcriptLanguage??null;
          }
          catch{retrievalErrors.push('The public page could not be read.');}
        }
      }
    }
    if(claimed.text)evidence.text+='\nUser-supplied recipe text:\n'+claimed.text;
    await progress('checking','Checking the metadata and original transcript for a food recipe…',1,{
      originalTranscript:evidence.transcript?.slice(0,80000)||null,
      transcriptLanguage:evidence.transcriptLanguage??null,retrieval,retrievalErrors
    });
    let scope=await classifySource(db,uid,id,evidence), result;
    await ref.update({scope:scope.scope,scopeReason:scope.reason,scopeRunID:scope.runID});
    const collectMedia=async()=>{
      await progress('transcribing','Reading speech and inspecting video frames…',2);
      evidence.mediaAttempted=true;
      let media;
      try {media=await readSocial(claimed.url,{captions:true,translatedCaptions:false,withMedia:true,previous:evidence});}
      catch(error) {
        retrievalErrors.push(retrievalError(error));
        try {media=await readPage(claimed.url,{captions:true,translatedCaptions:false,withMedia:true});}
        catch {retrievalErrors.push('The public video captions could not be read.');}
      }
      if(media) {
        retrievalErrors.push(...media.retrievalErrors);
        evidence.transcript=media.transcript||evidence.transcript||'';
        evidence.transcriptLanguage=media.transcriptLanguage??evidence.transcriptLanguage??null;
        evidence.duration=media.duration??evidence.duration;
        evidence.images=media.images??[];
        if(media.audio) {
          try {
            const speech=await transcribe(db,uid,id,media.audio);
            evidence.transcript=[evidence.transcript,speech.text].filter(Boolean).join('\n'); evidence.transcriptLanguage??=speech.language;
            retrieval.audioTranscribed=!!speech.text.trim();
          }
          catch {retrievalErrors.push('Audio transcription was unavailable.');}
        }
      }
      retrieval.hasTranscript=!!evidence.transcript;
      retrieval.transcriptLanguage=evidence.transcriptLanguage??null;
      retrieval.frameCount=evidence.images.filter(image=>Number.isFinite(image.second)).length;
      retrieval.imageCount=evidence.images.length-retrieval.frameCount;
      if(claimed.source==='YouTube' && process.env.YOUTUBE_VIDEO_MODEL && (!evidence.transcript || !retrieval.frameCount)) {
        try {
          await progress('transcribing','Reading the public video with the native video reader…',2);
          const video=await inspectYouTube(db,uid,id,claimed.url);
          evidence.transcript ||= video.transcript;
          evidence.transcriptLanguage ??= video.transcriptLanguage;
          evidence.videoObservations=video.videoObservations;
          evidence.duration ??= video.duration;
          retrieval.videoReader='google';retrieval.videoRunID=video.runID;
          retrieval.hasTranscript=!!evidence.transcript;retrieval.transcriptLanguage=evidence.transcriptLanguage??null;
        } catch(error) {retrievalErrors.push(error.name==='TimeoutError'?'Native public-video inspection timed out.':'Native public-video inspection was unavailable.');}
      }
    };
    const translate=async()=>{
      const alreadyEnglish=/^en(?:-|$)/i.test(evidence.transcriptLanguage??'') && /^(English|en(?:-|$))/i.test(targetLanguage);
      if(evidence.transcript && !evidence.transcriptTranslation && !alreadyEnglish) {
        try {evidence.transcriptTranslation=await translateTranscript(db,uid,id,evidence.transcript,evidence.transcriptLanguage,targetLanguage);}
        catch {retrievalErrors.push('Transcript translation was unavailable.');}
      }
    };
    const research=async()=>{
      try {evidence.writtenResearch=await researchSource(db,uid,id,claimed.url,`${result?.recipe.reason??scope.reason}\nSource title: ${evidence.title??''}\nCreator: ${evidence.creator??''}\nDescription links: ${descriptionLinks(evidence.description).join(' ')}`);}
      catch {retrievalErrors.push('The original written recipe search was unavailable.');}
    };
    const evidenceProgress=()=>progress('transcribing','Source evidence is ready.',2,{
      sourceText:evidence.text?.slice(0,20000)||null,
      originalTranscript:evidence.transcript?.slice(0,80000)||null,transcriptLanguage:evidence.transcriptLanguage??null,
      translatedTranscript:evidence.transcriptTranslation?.slice(0,80000)||null,translationLanguage:targetLanguage,
      videoObservations:evidence.videoObservations?.slice(0,80000)||null,
      sourceDurationSeconds:Number.isFinite(evidence.duration)?evidence.duration:null,
      frameSeconds:evidence.images.map(frame=>frame.second).filter(Number.isFinite),retrieval,retrievalErrors:[...new Set(retrievalErrors)]
    });
    if(scope.scope!=='non_food' && claimed.url && (claimed.source!=='Website' || scope.scope==='unknown')) {
      await collectMedia();
      if(scope.scope==='unknown' && (evidence.transcript || evidence.images.length || evidence.videoObservations)) scope=await classifySource(db,uid,id,evidence);
    }
    if(scope.scope==='unknown' && claimed.url) {
      await research();
      if(evidence.writtenResearch) scope=await classifySource(db,uid,id,evidence);
    }
    await ref.update({scope:scope.scope,scopeReason:scope.reason,scopeRunID:scope.runID});
    if(scope.scope==='unknown') await ref.update({failurePoint:'Food classification after source retrieval and research',extractionReason:scope.reason?.slice(0,1000)||null});
    if(scope.scope==='food') {
      await translate();
      evidence.linkedRecipes=[];
      for(const url of descriptionLinks(evidence.description)) {
        try {
          const page=await readPage(url);
          evidence.linkedRecipes.push({url:page.url,title:page.title,text:page.text.slice(0,20000),structured:page.structured});
        } catch {retrievalErrors.push('A description link could not be read.');}
      }
      await evidenceProgress();
      await progress('extracting','Building the ingredients and cooking steps…',3);
      result=await extractRecipe(db,uid,id,evidence,profile);
      await ref.update(extractionPreview(result.recipe,evidence.videoObservations?'Recipe normalization from native video evidence and original speech':evidence.images.length?'Recipe normalization from written evidence, transcript, translation, and source images':evidence.transcriptTranslation?'Recipe normalization from written evidence, transcript, and translation':evidence.transcript?'Recipe normalization from written evidence and original transcript':'Recipe normalization from written evidence'));
      if(result.recipe.outcome==='insufficient' && claimed.url && !evidence.mediaAttempted) {
        await collectMedia();
        await translate();
        await evidenceProgress();
        await progress('extracting','Building the recipe from the page and its video…',3);
        result=await extractRecipe(db,uid,id,evidence,profile);
        await ref.update(extractionPreview(result.recipe,'Recipe normalization after page video inspection'));
      }
      if(result.recipe.outcome==='insufficient' && claimed.url) {
        await progress('extracting','Searching for recipe evidence matching this source…',3,{extractionReason:result.recipe.reason});
        if(!evidence.writtenResearch) await research();
        if(evidence.writtenResearch) {
          result=await extractRecipe(db,uid,id,evidence,profile);
          await ref.update(extractionPreview(result.recipe,'Recipe normalization after original-recipe research'));
        }
      }
    }
    retrievalErrors=[...new Set(retrievalErrors)];
    await ref.update({retrieval,retrievalErrors});
    if(scope.scope!=='food') {
      await progress('skipped',scope.scope==='non_food'?'Oui Chef only imports food and drink recipes. This source is outside cooking.':`We could not read enough of this source to identify a recipe. ${retrievalErrors[0]??''} Try pasting the ingredients and cooking steps.`);
      await ref.update({finishedAt:Date.now()});await releaseImport(db,uid,id,attempt);return;
    }
    if(result.recipe.outcome!=='recipe') {
      await progress('skipped',result.recipe.reason?.slice(0,500)||'There were not enough ingredients and cooking instructions to save a recipe.');
      await ref.update({retrievalErrors,finishedAt:Date.now()});await releaseImport(db,uid,id,attempt);return;
    }
    await progress('checking','Saving your recipe and finishing its details…',4,{
      previewTitle:result.recipe.title,previewSummary:result.recipe.summary??null,
      previewIngredients:result.recipe.ingredients.map(item=>`${item.quantity} ${item.name}`),
      previewSteps:result.recipe.steps.map(step=>step.title||step.instruction),extractionRunID:result.runID
    });
    const {outcome,reason,...content}=result.recipe;
    let imagePath=null;
    if(evidence.imageURL){try {const image=await safeFetch(new URL(evidence.imageURL,claimed.url).href,2_000_000);if(/^image\/(jpeg|png|webp)/.test(image.headers['content-type']??'')){const path=`users/${uid}/recipeMedia/${id}/cover-${attempt}`;await getStorage().bucket().file(path).save(image.bytes,{metadata:{contentType:image.headers['content-type']}});imagePath=path;}}catch{/* The recipe remains usable without artwork. */}}
    const recipe={...content,imagePath,id,sourceURL:claimed.url,sourceName:claimed.source,imageURL:typeof evidence.imageURL==='string'&&evidence.imageURL.startsWith('https://')?evidence.imageURL:null,modelRunID:result.runID,favorite:false,reviewed:false,createdAt:Date.now(),version:1};
    if(claimed.source==='YouTube' && !evidence.transcript && !evidence.videoObservations && !retrieval.frameCount) recipe.warnings=[...new Set([...(recipe.warnings??[]),'Video speech and actions could not be checked; this recipe uses written source material.'])];
    validateRecipe(recipe);
    const payload=JSON.stringify(recipe),sharedID=sharedRecipeID(claimed.url,claimed.text,profilePayload),sharedRef=sharedID?db.doc(`sharedRecipes/${sharedID}`):null,limitRef=db.doc(`importLimits/${uid}`);
    const saved=await db.runTransaction(async tx=>{
      const [state,deleted,limit,cached]=await Promise.all([tx.get(ref),tx.get(db.doc(`deletedAccounts/${uid}`)),tx.get(limitRef),sharedRef?tx.get(sharedRef):null]);if(deleted.exists||!state.exists||state.data()?.status==='canceled'||state.data()?.attempt!==attempt)return;
      if(state.data()?.free && !activeImport(limit.data(),id,attempt)){tx.update(ref,{status:'failed',message:'This import expired. Please try again.'});return;}
      const recipeRef=db.doc(`users/${uid}/cookbook/${id}`);
      tx.set(recipeRef,{id,payload,updatedAt:Date.now()});
      if(sharedRef&&!cached?.exists)tx.set(sharedRef,{sourceURL:claimed.url,profileHash:createHash('sha256').update(profilePayload).digest('hex'),payload:JSON.stringify({...recipe,imagePath:null}),debug:importDebug(state.data()),createdAt:Date.now()});
      if(activeImport(limit.data(),id,attempt))tx.set(limitRef,{day:importDay(),count:(limit.data()?.day===importDay()?limit.data()?.count??0:0)+1});
      tx.update(ref,{status:'ready',stage:5,message:'Your recipe is ready.',recipeID:id,previewTitle:recipe.title,updatedAt:Date.now(),finishedAt:Date.now(),sharedID});
      return true;
    });
    if(!saved&&imagePath)await getStorage().bucket().file(imagePath).delete({ignoreNotFound:true});
  }catch(error){const latest=await ref.get();if(latest.exists&&latest.data()?.status!=='canceled'&&latest.data()?.attempt===attempt)await ref.update({status:'failed',message:error.message==='Import canceled.'?error.message:'This import could not finish. Retry, or add the recipe text.',failurePoint:latest.data()?.message??latest.data()?.status??'Import',extractionReason:error.message?.slice(0,1000)??'Import failed.',finishedAt:Date.now()});await releaseImport(db,uid,id,attempt);}
}
export async function handleCompanion(req,res,{db,auth}) {
  try {
    if(req.method!=='POST'){send(res,405,{error:'Use POST.'});return;}
    const raw=await readBody(req),body=JSON.parse(raw);
    if(req.url==='/companion/worker') {
      const sig=req.headers['x-oui-task'];
      if(!process.env.XAI_API_KEY||typeof sig!=='string'||sig.length!==64||!timingSafeEqual(Buffer.from(sig),Buffer.from(signature(raw)))||!allowedID(body.uid)||!allowedID(body.id)) {send(res,403,{error:'Invalid task.'});return;}
      await runImport(db,body.uid,body.id,body.attempt);send(res,200,{ok:true});return;
    }
    const token=req.headers.authorization?.match(/^Bearer (\S+)$/)?.[1];
    if(!token||token.length>10000){send(res,401,{error:'Sign in to your cookbook.'});return;}
    const identity=await auth.verifyIdToken(token),uid=identity.uid;
    if(!allowedID(uid)||identity.firebase?.sign_in_provider==='anonymous'){send(res,403,{error:'Sign in to your cookbook.'});return;}
    if(req.url!=='/companion/delete-account-data'&&(await db.doc(`deletedAccounts/${uid}`).get()).exists){send(res,403,{error:'This account is being deleted.'});return;}
    if(req.url==='/companion/import') {
      const {url,text,source}=importInput(body);
      const id=createHash('sha256').update(url||'text:'+text).digest('hex').slice(0,32),ref=db.doc(`users/${uid}/imports/${id}`);
      const admin=identity.admin===true;
      const limitRef=db.doc(`importLimits/${uid}`),profilePayload=(await db.doc(`users/${uid}/settings/cooking`).get()).data()?.payload??'{}';
      const sharedID=sharedRecipeID(url,text,profilePayload),sharedRef=sharedID?db.doc(`sharedRecipes/${sharedID}`):null;
      const result=await db.runTransaction(async tx=>{
        const [previous,deleted,limit,cached]=await Promise.all([tx.get(ref),tx.get(db.doc(`deletedAccounts/${uid}`)),tx.get(limitRef),sharedRef?tx.get(sharedRef):null]),old=previous.data();
        if(deleted.exists)throw new Error('Account deleted.');
        if(old && ['queued','fetching','transcribing','extracting','checking'].includes(old.status) && Date.now()-(old.startedAt??old.createdAt)>1200000) old.status='failed';
        if(old&&!['failed','skipped','canceled'].includes(old.status))return {id,attempt:old.attempt,existing:true};
        const today=importDay(),used=limit.data()?.day===today?limit.data()?.count??0:0;
        if(!admin && used>=1)throw new Error('Your free recipe for today is already saved. Try again tomorrow.');
        if(!admin && limit.data()?.activeID && Date.now()-(limit.data()?.activeAt??0)<1200000)throw new Error('Finish your current recipe import first.');
        // Cleared history must not reuse a Cloud Tasks name or match an old worker.
        const attempt=(old?.attempt??Date.now())+1;
        if(cached?.exists) {
          const recipe={...JSON.parse(cached.data().payload),id,imagePath:null,favorite:false,reviewed:false,createdAt:Date.now()};
          validateRecipe(recipe);
          tx.set(db.doc(`users/${uid}/cookbook/${id}`),{id,payload:JSON.stringify(recipe),updatedAt:Date.now()});
          tx.set(ref,{...cached.data().debug,id,url,source,status:'ready',stage:5,message:'Your recipe is ready.',recipeID:id,previewTitle:recipe.title,createdAt:Date.now(),updatedAt:Date.now(),finishedAt:Date.now(),attempt,sharedID,cacheHit:true});
          if(!admin)tx.set(limitRef,{day:today,count:used+1});
          return {id,attempt,existing:false,cached:true};
        }
        if(!process.env.XAI_API_KEY)throw new Error('Recipe AI is not configured.');
        // ponytail: simultaneous first imports can parse twice; add a shared lease if that becomes costly.
        if(!admin)tx.set(limitRef,{day:today,count:used,activeID:id,activeAttempt:attempt,activeAt:Date.now()});
        tx.set(ref,{id,url,source,text,status:'queued',message:'Waiting to read your recipe…',createdAt:Date.now(),attempt,free:!admin});
        return {id,attempt,existing:false,cached:false};
      });
      if(!result.existing&&!result.cached){try {if(!await enqueue(uid,id,result.attempt))void runImport(db,uid,id,result.attempt);}catch(error){await ref.update({status:'failed',message:error.message});await releaseImport(db,uid,id,result.attempt);throw error;}}
      send(res,200,result);return;
    }
    if(req.url==='/companion/cancel') {
      if(!allowedID(body.id))throw new Error('Invalid import.');
      const ref=db.doc(`users/${uid}/imports/${body.id}`),doc=await ref.get();
      await ref.update({status:'canceled',message:'Import canceled.'});
      if(doc.exists)await releaseImport(db,uid,body.id,doc.data().attempt);
      send(res,200,{ok:true});return;
    }
    if(req.url==='/companion/delete-recipe') {
      if(!allowedID(body.id))throw new Error('Invalid recipe.');
      await db.runTransaction(async tx=>{
        const recipe=db.doc(`users/${uid}/cookbook/${body.id}`),job=db.doc(`users/${uid}/imports/${body.id}`);
        const [saved,imported,deleted]=await Promise.all([tx.get(recipe),tx.get(job),tx.get(db.doc(`deletedAccounts/${uid}`))]);
        if(deleted.exists)throw new Error('Account deleted.');
        if(!saved.exists)return;
        // A tombstone prevents stale/offline clients from restoring a deleted recipe.
        tx.set(recipe,{id:body.id,deleted:true,updatedAt:Date.now()});
        tx.delete(recipe.collection('versions').doc('1'));
        if(imported.exists)tx.update(job,{status:'canceled',message:'Recipe removed from your cookbook.',updatedAt:Date.now()});
      });
      // Cooking attempts keep their recipe snapshots and cover images.
      send(res,200,{ok:true});return;
    }
    if(req.url==='/companion/question') {
      const budgetRef=db.doc(`aiQuestionLimits/${uid}`);
      await db.runTransaction(async tx=>{const doc=await tx.get(budgetRef),old=doc.data(),day=new Date().toISOString().slice(0,10),count=old?.day===day?old.count:0;
        if(count>=Number(process.env.QUESTION_DAILY_LIMIT??60))throw new Error('Today’s beta question allowance has been reached.');tx.set(budgetRef,{day,count:count+1});});
      send(res,200,await answerQuestion(db,uid,body));return;
    }
    if(req.url==='/companion/sync') {
      const {id,payload,expectedRevision}=body;
      if(!allowedID(id)||typeof payload!=='string'||payload.length>650000||!Number.isInteger(expectedRevision))throw new Error('Invalid cooking session.');
      const session=JSON.parse(payload);if(session.id!==id||!Array.isArray(session.events)||!Array.isArray(session.timers))throw new Error('Invalid session.');validateRecipe(session.recipe);
      const result=await db.runTransaction(async tx=>{
        const ref=db.doc(`users/${uid}/cooks/${id}`);
        const [doc,deleted]=await Promise.all([tx.get(ref),tx.get(db.doc(`deletedAccounts/${uid}`))]),old=doc.data();
        if(deleted.exists)throw new Error('Account deleted.');
        if(old?.payload===payload)return {revision:old.revision};
        if((old?.revision??0)!==expectedRevision)return {conflict:true};
        tx.set(ref,{id,payload,revision:expectedRevision+1,updatedAt:Date.now(),finishedAt:session.finishedAt??null});return {revision:expectedRevision+1};
      });send(res,result.conflict?409:200,result);return;
    }
    if(req.url==='/companion/delete-account-data') {
      if(Date.now()/1000-identity.auth_time>300)throw new Error('Please sign in again before deleting your account.');
      // Mark queued/running jobs canceled before removing their records.
      await db.doc(`deletedAccounts/${uid}`).set({deletedAt:Date.now()});
      const jobs=await db.collection(`users/${uid}/imports`).get();
      for(const doc of jobs.docs)await doc.ref.update({status:'canceled'});
      await getStorage().bucket().deleteFiles({prefix:`users/${uid}/`});
      await db.recursiveDelete(db.doc(`users/${uid}`));
      await Promise.all([db.doc(`importLimits/${uid}`).delete(),db.doc(`aiQuestionLimits/${uid}`).delete()]);
      send(res,200,{ok:true});return;
    }
    send(res,404,{error:'Not found.'});
  }catch(error){const safe=['Paste a recipe link or ingredients and steps.','Keep recipe text under 40,000 characters.','Use a public recipe link.','Recipe import is not configured yet.','Recipe AI is not configured.','Could not queue this import. Please retry.','Your free recipe for today is already saved. Try again tomorrow.','Finish your current recipe import first.','Today’s beta question allowance has been reached.','Please sign in again before deleting your account.'];send(res,400,{error:safe.includes(error.message)?error.message:'This request could not be completed. Please try again.'});}
}
