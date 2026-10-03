import test from 'node:test';
import assert from 'node:assert/strict';
import {createRecipeShare,receiveRecipeShare,handleRecipePage,shareOrigin} from './recipe-sharing.mjs';
import {handleCompanion} from './companion.mjs';

test('shared recipe links copy content once, preserve recipient edits, and expose no private account state',async()=>{
  const records=new Map();
  const db={doc(path){return {path,get:async()=>({exists:records.has(path),data:()=>records.get(path)})};},runTransaction:async fn=>fn({get:ref=>ref.get(),set:(ref,value)=>records.set(ref.path,value)})};
  const recipe={id:'private-id',title:'<script>alert("bread")</script>',summary:'A & B',sourceURL:'https://example.com/bread',sourceName:'Website',ingredients:[{id:'flour',name:'Flour',quantity:'500 g'}],steps:[{id:'rest',instruction:'Rest before folding.',durationSeconds:1800,ingredients:[]}],imagePath:'users/owner/private.jpg',modelRunID:'private-run',favorite:true,evidence:[{detail:'private evidence'}],messages:[{text:'private chat'}]};
  const share=await createRecipeShare(db,'owner',JSON.stringify(recipe));
  assert.match(share.url,new RegExp('^'+shareOrigin+'/r/[a-f0-9]{32}$'));
  assert.deepEqual(await createRecipeShare(db,'owner',JSON.stringify(recipe)),share);
  const id=share.url.split('/').at(-1),snapshot=JSON.parse(records.get('recipeLinks/'+id).payload);
  for(const key of ['id','imagePath','modelRunID','messages'])assert.equal(snapshot[key],undefined);
  assert.equal(snapshot.favorite,false);assert.deepEqual(snapshot.evidence,[]);
  const first=await receiveRecipeShare(db,'recipient',id),copy=JSON.parse(first.payload);
  assert.equal(copy.id,'shared-'+id);assert.deepEqual(copy.steps,recipe.steps);
  const savedPath='users/recipient/cookbook/'+copy.id;
  records.set(savedPath,{payload:JSON.stringify({...copy,title:'My edited bread',favorite:true})});
  assert.equal(JSON.parse((await receiveRecipeShare(db,'recipient',id)).payload).title,'My edited bread');
  assert.equal(records.size,3,'A repeated link must not create duplicate cookbook entries.');
  const other=JSON.parse((await receiveRecipeShare(db,'other',id)).payload);
  assert.equal(other.title,recipe.title);assert.equal(other.favorite,false);
  async function page(url,method='GET') {
    let status,headers,body;
    await handleRecipePage({url,method},{writeHead:(code,value)=>{status=code;headers=value;},end:value=>body=value},{db});
    return {status,headers,body};
  }
  const landing=await page('/r/'+id);
  assert.equal(landing.status,200);assert.equal(landing.headers['Cache-Control'],'no-store');
  assert.match(landing.body,/<a class="button" href="ouichef:\/\/recipe\/[a-f0-9]{32}">Open in Oui Chef<\/a>/);
  assert.ok(!landing.body.includes('<script>'));assert.ok(landing.body.includes('&lt;script&gt;'));
  for(const secret of ['private-id','private.jpg','private-run','private chat','private evidence'])assert.ok(!landing.body.includes(secret));
  assert.equal((await page('/r/'+id,'HEAD')).body,'');
  assert.equal((await page('/r/'+id,'POST')).status,405);
  assert.equal((await page('/r/invalid')).status,404);
  await assert.rejects(receiveRecipeShare(db,'recipient','../owner'));
  records.set('deletedAccounts/owner',{deletedAt:Date.now()});
  assert.equal((await page('/r/'+id)).status,404);
  await assert.rejects(receiveRecipeShare(db,'new-recipient',id));
});

test('sharing and receiving require a signed-in, non-deleted account',async()=>{
  const records=new Map([['deletedAccounts/deleted',{deletedAt:1}]]);
  const db={doc:path=>({get:async()=>({exists:records.has(path),data:()=>records.get(path)})})};
  for(const path of ['share-recipe','receive-share'])for(const mode of ['missing','anonymous','deleted']) {
    let status;
    await handleCompanion({url:'/companion/'+path,method:'POST',headers:mode==='missing'?{}:{authorization:'Bearer test'},async *[Symbol.asyncIterator](){yield Buffer.from('{}');}},
      {writeHead:code=>status=code,end:()=>{}},{db,auth:{verifyIdToken:async()=>({uid:mode,firebase:{sign_in_provider:mode==='anonymous'?'anonymous':'password'}})}});
    assert.equal(status,mode==='missing'?401:403);
  }
});
