$ErrorActionPreference = 'Stop'
$ProjectRoot = Split-Path -Parent $PSScriptRoot
$SourcePath = Join-Path $ProjectRoot 'source\roadmap-original.html'
$OutputPath = Join-Path $ProjectRoot 'public\index.html'
$ApiPath = Join-Path $ProjectRoot 'api\progress.js'

$html = Get-Content -Raw -Encoding UTF8 $SourcePath
$scriptStart = $html.IndexOf('<script>')
$scriptEnd = $html.LastIndexOf('</script>')
if ($scriptStart -lt 0 -or $scriptEnd -le $scriptStart) { throw 'Could not find the roadmap script.' }
$script = $html.Substring($scriptStart + 8, $scriptEnd - ($scriptStart + 8))

$functionStart = $script.IndexOf('function itemHTML(it){')
$functionEnd = $script.IndexOf("`nfunction render()", $functionStart)
if ($functionStart -lt 0 -or $functionEnd -lt 0) { throw 'Could not find the roadmap item renderer.' }
$newItemRenderer = @'
function itemHTML(it){
  const title = it.u ? `<a href="${esc(it.u)}" target="_blank" rel="noopener">${esc(it.t)}${ic("ext","ext")}</a>` : `<span class="t">${esc(it.t)}</span>`;
  const tags=(it.tags||[]).map(([c,l])=>`<span class="tag ${c}">${esc(l)}</span>`).join("") + (it.par?`<span class="tag">${esc(it.par)}</span>`:"");
  return `<div class="item" id="it-${it.id}" data-state="todo">
    <div class="ibody"><div class="ititle">${it.code?`<span class="code">${esc(it.code)}</span>`:ic(KIND_ICON[it.k]||"task")}${title}</div>
    ${it.note?`<p class="inote">${esc(it.note)}</p>`:""}${tags?`<div class="tags">${tags}</div>`:""}
    <div class="task-controls"><label class="control-label" for="state-${it.id}">Status</label>
      <select class="task-status" id="state-${it.id}" data-id="${it.id}" aria-label="Status for ${esc(it.t)}">
        <option value="todo">Not started</option><option value="doing">In progress</option><option value="done">Finished</option>
      </select></div>
    <details class="task-notes"><summary><span>My work notes</span><span class="note-state" data-note-label="${it.id}">Add a note</span></summary>
      <textarea data-note-id="${it.id}" maxlength="2000" aria-label="Personal progress note for ${esc(it.t)}" placeholder="What did you do? What is your next step? Any blocker?"></textarea>
    </details></div></div>`;
}
'@
$script = $script.Substring(0, $functionStart) + $newItemRenderer + $script.Substring($functionEnd)

$oldGate = '<span><input type="checkbox" id="cb-g${s.n}" data-id="g${s.n}"><label class="gcheck" for="cb-g${s.n}"><span class="box">${CHECK}</span>I can do this. On to ${s.n<6?"Stage "+(s.n+1):"the first study"}.</label></span>'
$newGate = '<div class="gate-actions"><span class="gate-prompt">I can do this. On to ${s.n<6?"Stage "+(s.n+1):"the first study"}.</span><label class="control-label" for="state-g${s.n}">Gate</label><select class="task-status gate-status" id="state-g${s.n}" data-id="g${s.n}" aria-label="Stage ${s.n} gate status"><option value="todo">Not started</option><option value="doing">In progress</option><option value="done">Finished</option></select></div>'
if (-not $script.Contains($oldGate)) { throw 'Could not find the stage gate control.' }
$script = $script.Replace($oldGate, $newGate)

$logicStart = $script.IndexOf('const KEY="thesis-roadmap-progress-v1";')
if ($logicStart -lt 0) { throw 'Could not find the original progress logic.' }
$newLogic = @'
const KEY="thesis-roadmap-private-v1";
const LEGACY_KEY="thesis-roadmap-progress-v1";
const TASKS=[];
S.forEach(s=>{
  LANES.forEach(([track,label])=>(s[track]||[]).forEach(it=>TASKS.push({id:it.id,title:it.t,stage:s.n,stageTitle:s.title,stageId:s.id,track,label})));
  TASKS.push({id:"g"+s.n,title:"Stage "+s.n+" gate",stage:s.n,stageTitle:s.title,stageId:s.id,track:"gate",label:"Gate",gate:true});
});
const TASK_BY_ID=new Map(TASKS.map(task=>[task.id,task]));
let items={};
let dirty={};
let saveTimer=null;
let retryTimer=null;
let saving=false;
let retryDelay=2500;
let authenticated=false;

function safeEntry(value){
  if(!value||typeof value!=="object") return null;
  return {status:["todo","doing","done"].includes(value.status)?value.status:"todo",note:typeof value.note==="string"?value.note.slice(0,2000):"",updatedAt:typeof value.updatedAt==="string"?value.updatedAt:"1970-01-01T00:00:00.000Z"};
}
function readLocal(){
  let local={};
  try{ const parsed=JSON.parse(localStorage.getItem(KEY)||"{}"); if(parsed&&typeof parsed==="object") local=parsed.items||parsed; }catch(e){}
  const migrated={};
  try{
    const legacy=JSON.parse(localStorage.getItem(LEGACY_KEY)||"{}");
    Object.entries(legacy||{}).forEach(([id,value])=>{ if(value===true&&TASK_BY_ID.has(id)) migrated[id]={status:"done",note:"",updatedAt:"1970-01-01T00:00:00.000Z"} });
  }catch(e){}
  return {...migrated,...local};
}
function saveLocal(){ try{localStorage.setItem(KEY,JSON.stringify({items,updatedAt:new Date().toISOString()}))}catch(e){} }
function setSync(message,failed=false){
  const el=document.getElementById("sync"); if(el) el.textContent=message;
  const retry=document.getElementById("retry-save"); if(retry) retry.hidden=!failed;
}
function setSignedIn(value){
  authenticated=value;
  document.getElementById("app").hidden=!value;
  document.getElementById("login-screen").hidden=value;
  if(value) document.getElementById("password").value="";
}
function allIds(){ return [...document.querySelectorAll(".task-status")].map(select=>select.dataset.id) }
function allStepsDone(){ return allIds().filter(id=>(items[id]?.status||"todo")==="done").length }
function statusValue(id){ return items[id]?.status||"todo" }
function renderDashboard(){
  const total=TASKS.length;
  const finished=TASKS.filter(task=>statusValue(task.id)==="done").length;
  const active=TASKS.filter(task=>statusValue(task.id)==="doing");
  const next=TASKS.find(task=>statusValue(task.id)==="todo");
  document.getElementById("stat-finished").textContent=finished;
  document.getElementById("stat-active").textContent=active.length;
  document.getElementById("stat-remaining").textContent=total-finished;
  document.getElementById("focus-count").textContent=active.length;
  document.getElementById("focus-list").innerHTML=active.length?active.map(task=>`<button class="focus-task" data-go="${task.id}"><span class="focus-dot"></span><span><b>${esc(task.title)}</b><small>Stage ${task.stage} · ${esc(task.stageTitle)} · ${esc(task.label)}</small></span>${ic("arrow")}</button>`).join(""):`<p class="focus-empty">No steps marked in progress yet. Set a task to <b>In progress</b> and it will show up here.</p>`;
  document.getElementById("next-step").innerHTML=next?`<span class="next-kicker">SUGGESTED NEXT STEP · STAGE ${next.stage}</span><b>${esc(next.title)}</b><small>${esc(next.stageTitle)} · ${esc(next.label)}</small><button class="next-button" data-go="${next.id}">Open this step ${ic("arrow")}</button>`:`<span class="next-kicker">ROADMAP COMPLETE</span><b>Every roadmap step is finished.</b><small>You can still add notes, revisit papers, or update any status.</small>`;
  document.getElementById("pc-done").textContent=finished;
  document.getElementById("pc-total").textContent=total;
  document.getElementById("pc-bar").style.width=(total?finished/total*100:0)+"%";
}
function apply(){
  document.querySelectorAll(".task-status").forEach(select=>{
    const status=statusValue(select.dataset.id); select.value=status;
    const parent=select.closest(".item, .gate"); if(parent) parent.dataset.state=status;
  });
  document.querySelectorAll("textarea[data-note-id]").forEach(area=>{
    const entry=items[area.dataset.noteId]; const note=entry?.note||"";
    if(area.value!==note) area.value=note;
    const label=document.querySelector(`[data-note-label="${area.dataset.noteId}"]`);
    if(label) label.textContent=note.trim()?"Note added":"Add a note";
  });
  S.forEach(s=>{
    const box=document.getElementById(s.id); const controls=[...box.querySelectorAll(".task-status")];
    const p=Math.round(controls.filter(control=>statusValue(control.dataset.id)==="done").length/controls.length*100);
    const ring=document.getElementById("ring-"+s.id); ring.style.setProperty("--p",p); ring.firstElementChild.textContent=p+"%";
  });
  document.querySelectorAll('.mchip[data-go]').forEach(button=>{
    const status=statusValue(button.dataset.go); button.classList.toggle("done",status==="done"); button.classList.toggle("doing",status==="doing");
  });
  renderDashboard();
}
function touch(id, patch){
  const previous=items[id]||{status:"todo",note:""};
  items[id]={...previous,...patch,updatedAt:new Date().toISOString()};
  dirty[id]={status:items[id].status,note:items[id].note};
  saveLocal(); apply();
  setSync("Saving to your account…");
  clearTimeout(saveTimer); saveTimer=setTimeout(flushSaves,650);
}
function mergeCloud(remote){
  const local=readLocal();
  items={}; dirty={};
  const ids=new Set([...Object.keys(remote||{}),...Object.keys(local||{})]);
  ids.forEach(id=>{
    if(!TASK_BY_ID.has(id)) return;
    const cloud=safeEntry(remote?.[id]); const browser=safeEntry(local?.[id]);
    if(browser&&(!cloud||browser.updatedAt>cloud.updatedAt)) {items[id]=browser;dirty[id]={status:browser.status,note:browser.note}}
    else if(cloud) items[id]=cloud;
  });
  saveLocal(); apply();
  if(Object.keys(dirty).length) { setSync("Syncing this browser's saved work…"); flushSaves(); }
  else setSync("Saved to your Vercel database");
}
async function api(path, options={}){
  const response=await fetch(path,{cache:"no-store",credentials:"same-origin",...options});
  let data={}; try{data=await response.json()}catch(e){}
  if(!response.ok) {const error=new Error(data.error||"Request failed."); error.status=response.status; throw error}
  return data;
}
async function flushSaves(){
  if(saving||!authenticated||!Object.keys(dirty).length) return;
  clearTimeout(retryTimer); retryTimer=null; saving=true;
  const batch=dirty; dirty={};
  try{
    const data=await api("/api/progress",{method:"POST",headers:{"Content-Type":"application/json"},body:JSON.stringify({action:"save",items:batch})});
    const remote=data.items||{};
    Object.entries(remote).forEach(([id,value])=>{
      if(TASK_BY_ID.has(id)&&!dirty[id]) items[id]=safeEntry(value);
    });
    retryTimer=null; retryDelay=2500; saveLocal(); apply();
    setSync(Object.keys(dirty).length?"Saved; syncing latest edits…":"Saved to your Vercel database");
  }catch(error){
    dirty={...batch,...dirty}; saveLocal();
    if(error.status===401){setSignedIn(false);document.getElementById("login-message").textContent=error.message;setSync("Sign in to continue saving");}
    else {setSync("Cloud save unavailable · retrying",true); retryTimer=setTimeout(flushSaves,retryDelay); retryDelay=Math.min(retryDelay*2,60000);}
  }finally{
    saving=false;
    if(Object.keys(dirty).length&&!retryTimer) saveTimer=setTimeout(flushSaves,100);
  }
}
async function syncFromCloud(){
  if(!authenticated||Object.keys(dirty).length||saving) return;
  try{
    const data=await api("/api/progress");
    Object.entries(data.items||{}).forEach(([id,value])=>{
      if(!TASK_BY_ID.has(id)||dirty[id]) return;
      const incoming=safeEntry(value), current=safeEntry(items[id]);
      if(!current||incoming.updatedAt>current.updatedAt) items[id]=incoming;
    });
    saveLocal(); apply(); setSync("Saved to your Vercel database");
  }catch(error){ if(error.status===401){setSignedIn(false);document.getElementById("login-message").textContent=error.message;} else setSync("Offline · browser backup available"); }
}
function goTo(id){
  const target=document.getElementById("it-"+id);
  if(target){ target.scrollIntoView({behavior:"smooth",block:"center"}); target.classList.remove("flash"); void target.offsetWidth; target.classList.add("flash"); }
}
function downloadBackup(){
  const payload={app:"thesis-roadmap-progress",version:1,exportedAt:new Date().toISOString(),items};
  const blob=new Blob([JSON.stringify(payload,null,2)],{type:"application/json"});
  const url=URL.createObjectURL(blob); const link=document.createElement("a"); link.href=url; link.download="thesis-roadmap-backup.json"; link.click(); URL.revokeObjectURL(url);
}
async function importBackup(file){
  const payload=JSON.parse(await file.text());
  if(payload?.app!=="thesis-roadmap-progress"||payload.version!==1||!payload.items||typeof payload.items!=="object") throw new Error("This file is not a Thesis Roadmap backup.");
  const timestamp=new Date().toISOString(); let count=0;
  Object.entries(payload.items).forEach(([id,value])=>{
    if(!TASK_BY_ID.has(id)||!value||!["todo","doing","done"].includes(value.status)||typeof value.note!=="string") return;
    items[id]={status:value.status,note:value.note.slice(0,2000),updatedAt:timestamp}; dirty[id]={status:items[id].status,note:items[id].note}; count++;
  });
  if(!count) throw new Error("No valid roadmap progress was found in this backup.");
  saveLocal(); apply(); setSync("Importing backup to your account…"); flushSaves();
}

render();
setSignedIn(false);
document.getElementById("login-screen").hidden=false;
setSync("Connect to load your saved progress");
document.getElementById("login-form").addEventListener("submit",async event=>{
  event.preventDefault(); const message=document.getElementById("login-message");
  const button=document.getElementById("login-submit"); button.disabled=true; button.textContent="Opening…"; message.textContent="";
  try{
    const data=await api("/api/progress",{method:"POST",headers:{"Content-Type":"application/json"},body:JSON.stringify({action:"login",password:document.getElementById("password").value})});
    setSignedIn(true); mergeCloud(data.items||{}); document.getElementById("app").scrollTop=0;
  }catch(error){message.textContent=error.message;}
  finally{button.disabled=false;button.textContent="Open my roadmap";}
});
document.getElementById("logout").addEventListener("click",async()=>{
  try{await api("/api/progress",{method:"POST",headers:{"Content-Type":"application/json"},body:JSON.stringify({action:"logout"})})}catch(e){}
  setSignedIn(false);document.getElementById("login-message").textContent="You are signed out.";
});
document.getElementById("retry-save").addEventListener("click",()=>{clearTimeout(retryTimer);retryTimer=null;setSync("Retrying cloud save…");flushSaves();});
document.getElementById("export-backup").addEventListener("click",downloadBackup);
document.getElementById("import-backup").addEventListener("click",()=>document.getElementById("backup-file").click());
document.getElementById("backup-file").addEventListener("change",async event=>{
  const file=event.target.files?.[0]; if(!file) return;
  try{await importBackup(file);document.getElementById("backup-message").textContent="Backup imported. Saving to your account.";}
  catch(error){document.getElementById("backup-message").textContent=error.message;}
  finally{event.target.value="";}
});
document.addEventListener("change",event=>{
  const select=event.target.closest(".task-status");
  if(select){touch(select.dataset.id,{status:select.value});return;}
});
document.addEventListener("input",event=>{
  const area=event.target.closest("textarea[data-note-id]");
  if(area) touch(area.dataset.noteId,{note:area.value.slice(0,2000)});
});
document.addEventListener("click",event=>{
  const jump=event.target.closest("[data-go]");
  if(jump){goTo(jump.dataset.go);return;}
  const chip=event.target.closest(".chip[data-f]");
  if(chip){
    document.querySelectorAll(".chip[data-f]").forEach(button=>button.setAttribute("aria-pressed",button===chip?"true":"false"));
    if(chip.dataset.f==="all") delete document.body.dataset.focus; else document.body.dataset.focus=chip.dataset.f;
    try{localStorage.setItem(KEY+"-focus",chip.dataset.f)}catch(e){}
  }
});
try{const focus=localStorage.getItem(KEY+"-focus");if(focus&&focus!=="all")document.querySelector(`.chip[data-f="${focus}"]`)?.click()}catch(e){}
(async()=>{
  try{
    const data=await api("/api/progress"); setSignedIn(true); mergeCloud(data.items||{});
  }catch(error){
    setSignedIn(false);
    document.getElementById("login-message").textContent=error.status===401?"Enter your private password to open your roadmap.":error.message;
  }
})();
setInterval(syncFromCloud,30000);
'@
$script = $script.Substring(0, $logicStart) + $newLogic
$html = $html.Substring(0, $scriptStart) + '<script>' + $script + '</script>' + $html.Substring($scriptEnd + 9)

$extraCss = @'

/* Personal progress tracker */
.wrap[hidden]{display:none!important}
.login-screen{min-height:100vh;display:grid;place-items:center;padding:24px;background:var(--paper);background-image:linear-gradient(var(--grid) 1px,transparent 1px),linear-gradient(90deg,var(--grid) 1px,transparent 1px);background-size:24px 24px}
.login-card{width:min(100%,460px);padding:32px;border:1.5px solid var(--line);border-radius:20px;background:var(--card);box-shadow:0 18px 55px rgba(16,36,29,.1)}
.login-eyebrow,.dashboard-eyebrow{color:var(--learn)}
.login-card h1{margin-top:16px;font-size:clamp(34px,7vw,48px)}
.login-card h1 span{color:var(--learn)}
.login-card>p{color:var(--ink-2);margin:12px 0 22px}
.login-card form{display:grid;gap:9px}
.login-card form label,.control-label{font-size:12px;font-weight:600;color:var(--ink-2)}
.login-card input{width:100%;border:1.5px solid var(--line);background:var(--card-2);color:var(--ink);border-radius:10px;padding:12px 13px;font:inherit}
.primary-button,.quiet-button,.retry-button,.next-button{font:600 13px var(--f-body);border-radius:9px;padding:9px 13px;cursor:pointer}
.primary-button{margin-top:7px;border:1px solid var(--learn);background:var(--learn);color:#fff;padding:12px}
.primary-button:disabled{opacity:.65;cursor:wait}
.login-card small{color:var(--ink-3)}
.login-message{min-height:20px;font-size:13px!important;color:var(--warn)!important;margin:12px 0!important}
.bar .prog-top{align-items:center}
.retry-button{border:1px solid var(--warn);background:var(--warn-bg);color:var(--warn);padding:4px 8px;font-size:11px}
.retry-button[hidden]{display:none}
.dashboard{border:1.5px solid var(--line);border-radius:16px;background:var(--card);padding:20px;margin:10px 0 24px;box-shadow:0 2px 0 rgba(16,36,29,.04)}
.dashboard-top{display:flex;justify-content:space-between;gap:16px;align-items:flex-start}
.dashboard-top h2{font-size:25px;margin-top:4px}
.dashboard-top p{margin:5px 0 0;color:var(--ink-2);font-size:13.5px}
.dashboard-actions{display:flex;gap:7px;flex-wrap:wrap;justify-content:flex-end}
.quiet-button{border:1px solid var(--line);background:var(--card-2);color:var(--ink-2)}
.quiet-button:hover{border-color:var(--ink-3);color:var(--ink)}
.signout-button{background:transparent}
.backup-message{margin:4px 0 0;min-height:16px;font-size:11px;color:var(--ink-3);text-align:right}
.stats-grid{display:grid;grid-template-columns:repeat(3,minmax(0,1fr));gap:10px;margin:12px 0}
.stat-card{border:1px solid var(--line);background:var(--card-2);border-radius:11px;padding:12px 14px;display:flex;justify-content:space-between;align-items:center;color:var(--ink-2);font-size:13px}
.stat-card b{font:700 24px var(--f-display);color:var(--ink);font-variant-numeric:tabular-nums}
.stat-finished b{color:var(--learn)} .stat-active b{color:var(--prove)}
.focus-grid{display:grid;grid-template-columns:1.4fr 1fr;gap:10px}
.focus-card,.next-card{border:1px solid var(--line);border-radius:12px;background:var(--card);padding:13px 15px;min-width:0}
.focus-heading{display:flex;justify-content:space-between;align-items:center;gap:8px;margin-bottom:7px}
.focus-heading h3{font-size:16px}
.focus-heading>span{min-width:25px;height:25px;border-radius:50%;display:grid;place-items:center;background:var(--prove-bg);color:var(--prove);font:600 12px var(--f-mono)}
.focus-task{width:100%;border:0;border-top:1px solid var(--line);background:transparent;color:var(--ink);padding:10px 0;display:grid;grid-template-columns:9px minmax(0,1fr) 18px;gap:10px;text-align:left;align-items:center;cursor:pointer}
.focus-task b,.focus-task small,.next-card b,.next-card small{display:block}
.focus-task b{font-size:13px;line-height:1.3}
.focus-task small{color:var(--ink-3);font-size:11px;margin-top:3px}
.focus-task>.ic{width:16px;color:var(--ink-3)}
.focus-dot{width:8px;height:8px;border-radius:50%;background:var(--prove)}
.focus-empty{margin:8px 0 2px;color:var(--ink-3);font-size:12.5px}
.next-card{display:grid;align-content:start;gap:7px;background:var(--learn-bg);border-color:color-mix(in srgb,var(--learn) 30%,var(--line))}
.next-kicker{font:500 10px var(--f-mono);letter-spacing:.05em;color:var(--learn)}
.next-card b{font:700 17px/1.2 var(--f-display);color:var(--ink)}
.next-card small{font-size:11.5px;color:var(--ink-2)}
.next-button{justify-self:start;margin-top:5px;border:1px solid color-mix(in srgb,var(--learn) 40%,var(--line));background:var(--card);color:var(--learn);display:inline-flex;align-items:center;gap:6px}
.next-button .ic{width:15px;height:15px}
.item{grid-template-columns:minmax(0,1fr);gap:9px}
.item[data-state="doing"]{border-color:var(--prove);box-shadow:0 0 0 1px color-mix(in srgb,var(--prove) 28%,transparent)}
.item[data-state="done"]{opacity:.78}
.item[data-state="done"] .ititle a,.item[data-state="done"] .ititle span.t{text-decoration:line-through;text-decoration-color:var(--ink-3)}
.task-controls{display:flex;align-items:center;gap:8px}
.task-status{width:100%;max-width:175px;border:1px solid var(--line);border-radius:8px;padding:6px 8px;background:var(--card-2);color:var(--ink);font:500 12px var(--f-body)}
.task-status:focus-visible,.task-notes textarea:focus-visible,.login-card input:focus-visible,button:focus-visible,summary:focus-visible{outline:2.5px solid var(--read);outline-offset:2px}
.task-status option{background:var(--card)}
.task-notes{border-top:1px solid var(--line);padding-top:7px}
.task-notes summary{display:flex;justify-content:space-between;gap:10px;cursor:pointer;color:var(--ink-2);font-size:12px;font-weight:600;list-style:none}
.task-notes summary::-webkit-details-marker{display:none}
.task-notes summary::after{content:"+";color:var(--learn);font-size:15px;line-height:1;margin-left:auto}
.task-notes[open] summary::after{content:"−"}
.note-state{color:var(--ink-3);font-weight:400;font-size:11px}
.task-notes textarea{display:block;width:100%;min-height:75px;resize:vertical;margin-top:8px;padding:8px 9px;border:1px solid var(--line);border-radius:8px;background:var(--card-2);color:var(--ink);font:12px/1.5 var(--f-body)}
.gate{grid-template-columns:auto minmax(0,1fr);}
.gate[data-state="done"]{border-color:var(--learn)}
.gate[data-state="doing"]{border-color:var(--prove)}
.gate-actions{display:flex;flex-wrap:wrap;align-items:center;gap:6px 10px;margin-top:5px}
.gate-prompt{font-size:13px;color:var(--ink-2);margin-right:auto}
.gate-status{max-width:160px}
.mchip.doing{border-color:var(--prove);color:var(--prove);background:var(--prove-bg)}
#sync{color:var(--ink-3)}
@media(max-width:760px){.dashboard-top{display:grid}.dashboard-actions{justify-content:flex-start}.backup-message{text-align:left}.focus-grid{grid-template-columns:1fr}}
@media(max-width:500px){.login-card{padding:24px}.dashboard{padding:15px}.dashboard-top h2{font-size:22px}.dashboard-actions .quiet-button{font-size:12px;padding:8px 10px}.stats-grid{gap:6px}.stat-card{padding:10px 9px;display:grid;gap:2px;font-size:11px}.stat-card b{font-size:21px}.gate{grid-template-columns:1fr}.gate-actions{align-items:flex-start}.task-status{max-width:none}}
'@
$styleEnd = $html.LastIndexOf('</style>')
if ($styleEnd -lt 0) { throw 'Could not find the roadmap style section.' }
$html = $html.Substring(0, $styleEnd) + $extraCss + $html.Substring($styleEnd)

$login = @'
<div class="login-screen" id="login-screen" hidden>
  <section class="login-card" aria-labelledby="login-title">
    <span class="mono login-eyebrow">PRIVATE THESIS WORKSPACE</span>
    <h1 id="login-title">Pick up your <span>roadmap</span></h1>
    <p>Sign in to load your saved statuses and personal notes from the cloud.</p>
    <form id="login-form">
      <label for="password">Workspace password</label>
      <input id="password" name="password" type="password" autocomplete="current-password" required maxlength="512" placeholder="Enter your password">
      <button class="primary-button" id="login-submit" type="submit">Open my roadmap</button>
    </form>
    <p class="login-message" id="login-message" role="status" aria-live="polite"></p>
    <small>Your progress and work notes require this password.</small>
  </section>
</div>
'@
$html = $html.Replace('<body>', "<body>`n$login")
$html = $html.Replace('<div class="wrap">', '<div class="wrap" id="app" hidden>')
$html = $html.Replace('<html>', '<html lang="en">')
$html = $html.Replace('</head>', '<title>Thesis AI Roadmap - Progress Tracker</title><meta name="description" content="A private, saveable progress tracker for your greenhouse AI thesis roadmap."></head>')
$html = $html.Replace('<title>Thesis AI Roadmap</title>', '')
$html = $html.Replace('<meta name="claude:viewport-fit-sides" content="cover">', '')
$html = $html.Replace('Saved in this browser', 'Loading saved progress…')
$html = $html.Replace('<span class="sync" id="sync">Loading saved progress…</span>', '<span class="sync" id="sync" role="status" aria-live="polite">Loading saved progress…</span><button class="retry-button" id="retry-save" type="button" hidden>Retry save</button>')

$dashboard = @'
  <section class="dashboard" id="dashboard" aria-labelledby="dashboard-title">
    <div class="dashboard-top">
      <div><span class="mono dashboard-eyebrow">YOUR WORKSPACE</span><h2 id="dashboard-title">Pick up where you left off</h2><p>Your notes stay with the task. Every change saves automatically.</p></div>
      <div class="dashboard-actions">
        <button class="quiet-button" id="export-backup" type="button">Export backup</button>
        <button class="quiet-button" id="import-backup" type="button">Import backup</button>
        <input id="backup-file" type="file" accept="application/json,.json" hidden>
        <button class="quiet-button signout-button" id="logout" type="button">Sign out</button>
      </div>
    </div>
    <p class="backup-message" id="backup-message" role="status" aria-live="polite"></p>
    <div class="stats-grid">
      <div class="stat-card stat-finished"><span>Finished</span><b id="stat-finished">0</b></div>
      <div class="stat-card stat-active"><span>In progress</span><b id="stat-active">0</b></div>
      <div class="stat-card"><span>Still to do</span><b id="stat-remaining">0</b></div>
    </div>
    <div class="focus-grid">
      <section class="focus-card" aria-labelledby="focus-title"><div class="focus-heading"><h3 id="focus-title">What I’m working on</h3><span id="focus-count">0</span></div><div id="focus-list"></div></section>
      <section class="next-card" id="next-step" aria-label="Suggested next step"></section>
    </div>
  </section>
'@
$html = $html.Replace('  <main class="diagram" id="diagram">', "$dashboard`n  <main class=`"diagram`" id=`"diagram`">")

Set-Content -Path $OutputPath -Value $html -Encoding UTF8

$sourceScript = $html.Substring($html.IndexOf('<script>') + 8, $html.LastIndexOf('</script>') - ($html.IndexOf('<script>') + 8))
if (-not $sourceScript.Contains('const S = [')) { throw 'Roadmap data was not preserved in the generated page.' }
if (-not $html.Contains('id="login-form"') -or -not $html.Contains('id="dashboard"')) { throw 'The tracker UI was not added correctly.' }
Write-Output "Generated $OutputPath"
