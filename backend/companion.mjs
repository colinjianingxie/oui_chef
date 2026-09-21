import { createHash, createHmac, timingSafeEqual } from 'node:crypto';
import { applicationDefault } from 'firebase-admin/app';
import { getStorage } from 'firebase-admin/storage';
import { importInput, readPage, readSocial, safeFetch, retrievalError, descriptionLinks } from './import-source.mjs';
import { classifySource, extractRecipe, transcribe, translateTranscript, researchSource, answerQuestion, validateRecipe } from './recipe-agent.mjs';
const allowedID = value => typeof value==='string' && /^[A-Za-z0-9_-]{1,128}$/.test(value);
export const importTaskID = (uid,id,attempt) => `import-${createHash('sha256').update(uid).digest('hex').slice(0,24)}-${id}-${attempt}`;
const signature = body => createHmac('sha256',process.env.XAI_API_KEY??'').update('oui-import:'+body).digest('hex');
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
    const profile=JSON.parse(profileDoc.data()?.payload??'{}');
    let evidence={url:claimed.url,text:'',images:[],mediaAttempted:false}, retrievalErrors=[];
    let retrieval={source:claimed.source,method:claimed.url?'html':'pasted_text',hasTranscript:false};
    const metadata = async source => progress('fetching','Found the source. Reading its written recipe…',0,{
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
          const social=await readSocial(claimed.url,{onMetadata:metadata});
          evidence={...evidence,...social};
          retrieval={source:claimed.source,method:'yt-dlp',extractor:social.extractor,hasTranscript:false};
        } catch(error) {
          retrievalErrors.push(retrievalError(error));
          retrieval.method='html_fallback';
          try {evidence={...evidence,...await readPage(claimed.url,{onMetadata:metadata})};}
          catch{retrievalErrors.push('The public page could not be read.');}
        }
      }
      await progress('fetching','Reading the description and linked original recipes…',1);
      evidence.linkedRecipes=[];
      for(const url of descriptionLinks(evidence.description)) {
        try {
          const page=await readPage(url);
          evidence.linkedRecipes.push({url:page.url,title:page.title,text:page.text.slice(0,20000),structured:page.structured});
        } catch {retrievalErrors.push('A description link could not be read.');}
      }
    }
    if(claimed.text)evidence.text+='\nUser-supplied recipe text:\n'+claimed.text;
    await progress('checking','Checking that this is a food recipe…',2,{retrieval,retrievalErrors});
    let scope=await classifySource(db,uid,id,evidence), result;
    await ref.update({scope:scope.scope,scopeReason:scope.reason,scopeRunID:scope.runID});
    if(scope.scope==='food') {
      await progress('extracting','Organizing the written ingredients and cooking steps…',3);
      result=await extractRecipe(db,uid,id,evidence,profile);
      await ref.update(extractionPreview(result.recipe,'Written source'));
      if(result.recipe.outcome==='insufficient' && claimed.url) {
        await progress('extracting','Looking for the creator’s original written recipe…',3,{extractionReason:result.recipe.reason});
        try {
          evidence.writtenResearch=await researchSource(db,uid,id,claimed.url,`${result.recipe.reason}\nSource title: ${evidence.title??''}\nCreator: ${evidence.creator??''}\nDescription links: ${descriptionLinks(evidence.description).join(' ')}`);
        } catch {retrievalErrors.push('The original written recipe search was unavailable.');}
        if(evidence.writtenResearch) {
          result=await extractRecipe(db,uid,id,evidence,profile);
          await ref.update(extractionPreview(result.recipe,'Written source and recipe research'));
        }
      }
    }
    if(claimed.url && claimed.source!=='Website' && (scope.scope==='unknown' || result?.recipe.outcome==='insufficient')) {
      await progress('transcribing','Filling missing details from captions or audio…',3);
      evidence.mediaAttempted=true;
      let media;
      try {media=await readSocial(claimed.url,{captions:true,withMedia:true});}
      catch(error) {
        retrievalErrors.push(retrievalError(error));
        try {media=await readPage(claimed.url,{captions:true});}
        catch {retrievalErrors.push('The public video captions could not be read.');}
      }
      if(media) {
        retrievalErrors.push(...media.retrievalErrors);
        evidence.transcript=media.transcript??'';
        evidence.transcriptLanguage=media.transcriptLanguage??null;
        evidence.transcriptTranslation=media.transcriptTranslation??'';
        evidence.images=media.images??[];
        if(media.audio) {
          try {
            const speech=await transcribe(db,uid,id,media.audio);
            evidence.transcript+='\n'+speech.text; evidence.transcriptLanguage??=speech.language;
          }
          catch {retrievalErrors.push('Audio transcription was unavailable.');}
        }
        if(evidence.transcript && !evidence.transcriptTranslation && !/^en(?:-|$)/i.test(evidence.transcriptLanguage??'')) {
          try {evidence.transcriptTranslation=await translateTranscript(db,uid,id,evidence.transcript,evidence.transcriptLanguage);}
          catch {retrievalErrors.push('Transcript translation was unavailable.');}
        }
        retrieval.hasTranscript=!!evidence.transcript;
        retrieval.transcriptLanguage=evidence.transcriptLanguage;
        await progress('transcribing','Reading captions, translation, and video frames…',3,{
          originalTranscript:evidence.transcript.slice(0,80000)||null,
          transcriptLanguage:evidence.transcriptLanguage,
          translatedTranscript:evidence.transcriptTranslation.slice(0,80000)||null,
          frameSeconds:evidence.images.map(frame=>frame.second),retrieval,retrievalErrors
        });
        if(evidence.transcript || evidence.images.length) {
          scope=await classifySource(db,uid,id,evidence);
          await ref.update({scope:scope.scope,scopeReason:scope.reason,scopeRunID:scope.runID});
          if(scope.scope==='food') {
            await progress('extracting','Completing the recipe while preserving its written instructions…',3);
            result=await extractRecipe(db,uid,id,evidence,profile);
            await ref.update(extractionPreview(result.recipe,evidence.images.length?'Captions, translation, and sampled video frames':'Captions or audio transcript'));
          } else if(scope.scope==='unknown') {
            await ref.update({failurePoint:'Recipe classification after media recovery',extractionReason:scope.reason?.slice(0,1000)||null});
          }
        } else {
          await ref.update({failurePoint:'Caption, audio, and frame recovery',extractionReason:retrievalErrors.at(-1)?.slice(0,1000)||'No readable media evidence was recovered.'});
        }
      }
    }
    await ref.update({retrieval,retrievalErrors});
    if(scope.scope!=='food') {
      await progress('skipped',scope.scope==='non_food'?'Oui Chef only imports food and drink recipes. This source is outside cooking.':`We could not read enough of this source to identify a recipe. ${retrievalErrors[0]??''} Try pasting the ingredients and cooking steps.`);
      await ref.update({finishedAt:Date.now()});return;
    }
    if(result.recipe.outcome!=='recipe') {
      await progress('skipped',result.recipe.reason?.slice(0,500)||'There were not enough ingredients and cooking instructions to save a recipe.');
      await ref.update({retrievalErrors,finishedAt:Date.now()});return;
    }
    await progress('checking','Saving your recipe and finishing its details…',4,{
      previewTitle:result.recipe.title,previewSummary:result.recipe.summary??null,
      previewIngredients:result.recipe.ingredients.map(item=>`${item.quantity} ${item.name}`),
      previewSteps:result.recipe.steps.map(step=>step.title||step.instruction),extractionRunID:result.runID
    });
    const {outcome,reason,...content}=result.recipe;
    let imagePath=null;
    if(evidence.imageURL){try {const image=await safeFetch(new URL(evidence.imageURL,claimed.url).href,2_000_000);if(/^image\/(jpeg|png|webp)/.test(image.headers['content-type']??'')){imagePath=`users/${uid}/recipeMedia/${id}/cover-${attempt}`;await getStorage().bucket().file(imagePath).save(image.bytes,{metadata:{contentType:image.headers['content-type']}});}}catch{/* The recipe remains usable without artwork. */}}
    const recipe={...content,imagePath,id,sourceURL:claimed.url,sourceName:claimed.source,imageURL:typeof evidence.imageURL==='string'&&evidence.imageURL.startsWith('https://')?evidence.imageURL:null,modelRunID:result.runID,favorite:false,reviewed:false,createdAt:Date.now(),version:1};
    validateRecipe(recipe);
    const payload=JSON.stringify(recipe);
    const saved=await db.runTransaction(async tx=>{
      const [state,deleted]=await Promise.all([tx.get(ref),tx.get(db.doc(`deletedAccounts/${uid}`))]);if(deleted.exists||!state.exists||state.data()?.status==='canceled'||state.data()?.attempt!==attempt)return;
      const recipeRef=db.doc(`users/${uid}/cookbook/${id}`);
      tx.set(recipeRef,{id,payload,updatedAt:Date.now()});
      tx.set(recipeRef.collection('versions').doc('1'),{payload,createdAt:Date.now(),modelRunID:result.runID});
      tx.update(ref,{status:'ready',stage:5,message:'Your recipe is ready.',recipeID:id,finishedAt:Date.now(),retrievalErrors});
      return true;
    });
    if(!saved&&imagePath)await getStorage().bucket().file(imagePath).delete({ignoreNotFound:true});
  }catch(error){const latest=await ref.get();if(latest.exists&&latest.data()?.status!=='canceled'&&latest.data()?.attempt===attempt)await ref.update({status:'failed',message:error.message==='Import canceled.'?error.message:'This import could not finish. Retry, or add the recipe text.',failurePoint:latest.data()?.message??latest.data()?.status??'Import',extractionReason:error.message?.slice(0,1000)??'Import failed.',finishedAt:Date.now()});}
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
      if(!process.env.XAI_API_KEY)throw new Error('Recipe AI is not configured.');
      const {url,text,source}=importInput(body);
      const id=createHash('sha256').update(url||'text:'+text).digest('hex').slice(0,32),ref=db.doc(`users/${uid}/imports/${id}`);
      const result=await db.runTransaction(async tx=>{
        const [previous,deleted]=await Promise.all([tx.get(ref),tx.get(db.doc(`deletedAccounts/${uid}`))]),old=previous.data();
        if(deleted.exists)throw new Error('Account deleted.');
        if(old && ['fetching','transcribing','extracting','checking'].includes(old.status) && Date.now()-(old.startedAt??old.createdAt)>900000) old.status='failed';
        if(old&&!['failed','skipped','canceled'].includes(old.status))return {id,attempt:old.attempt,existing:true};
        const budgetRef=db.doc('aiBudget/imports'),budget=await tx.get(budgetRef);
        const allocated=(budget.data()?.reservedCents??0)+100;
        if(allocated>Number(process.env.IMPORT_BUDGET_CENTS??1500))throw new Error('The beta import allowance has been reached.');
        // Cleared history must not reuse a Cloud Tasks name or match an old worker.
        const attempt=(old?.attempt??Date.now())+1;
        tx.set(budgetRef,{reservedCents:allocated,updatedAt:Date.now()});
        tx.set(ref,{id,url,source,text,status:'queued',message:'Waiting to read your recipe…',createdAt:Date.now(),attempt,reservedCents:100});
        return {id,attempt,existing:false};
      });
      if(!result.existing){try {if(!await enqueue(uid,id,result.attempt))void runImport(db,uid,id,result.attempt);}catch(error){await ref.update({status:'failed',message:error.message});throw error;}}
      send(res,200,result);return;
    }
    if(req.url==='/companion/cancel') {
      if(!allowedID(body.id))throw new Error('Invalid import.');
      await db.doc(`users/${uid}/imports/${body.id}`).update({status:'canceled',message:'Import canceled.'});send(res,200,{ok:true});return;
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
      await db.recursiveDelete(db.doc(`users/${uid}`));send(res,200,{ok:true});return;
    }
    send(res,404,{error:'Not found.'});
  }catch(error){const safe=['Paste a recipe link or ingredients and steps.','Keep recipe text under 40,000 characters.','Use a public recipe link.','Recipe import is not configured yet.','Recipe AI is not configured.','Could not queue this import. Please retry.','The beta import allowance has been reached.','Today’s beta question allowance has been reached.','Please sign in again before deleting your account.'];send(res,400,{error:safe.includes(error.message)?error.message:'This request could not be completed. Please try again.'});}
}
