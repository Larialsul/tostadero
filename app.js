/* global supabase, APP_CONFIG */
const { createClient } = window.supabase;
const cfg = window.APP_CONFIG || {};
const $ = id => document.getElementById(id);
const INGREDIENTS = [
 ["Tomate","🍅"],["Jamón","🥓"],["Aguacate","🥑"],["Queso","🧀"],["Huevo","🍳"],
 ["Setas","🍄"],["Miel","🍯"],["Fresas","🍓"],["Chocolate","🍫"],["Aceite de oliva","🫒"],
 ["Ajo","🧄"],["Pimienta","🌶️"],["Canela","✨"],["Mermelada","🍒"],["Mostaza","🟡"]
];
const sb = createClient(cfg.SUPABASE_URL, cfg.SUPABASE_ANON_KEY, {
  auth: { persistSession: true, autoRefreshToken: true, detectSessionInUrl: true }
});
let user = null, room = null, member = null, roomData = null, channel = null;
let toasts = [], members = [], votes = [], scores = [];

function message(id, text, error=false){ const el=$(id); if(el){el.textContent=text;el.style.color=error?"#e58a7d":"#f0ce83";} }
function esc(s){return String(s??"").replace(/[&<>"']/g,c=>({"&":"&amp;","<":"&lt;",">":"&gt;",'"':"&quot;","'":"&#39;"}[c]));}
function setTab(name){
 document.querySelectorAll(".tab").forEach(b=>b.classList.toggle("active",b.dataset.tab===name));
 document.querySelectorAll(".tab-panel").forEach(p=>p.classList.toggle("hidden",p.id!==name));
 if(name==="contest") renderToasts();
 if(name==="ranking") renderRanking();
 if(name==="host") renderHost();
}
document.querySelectorAll(".tab").forEach(b=>b.addEventListener("click",()=>setTab(b.dataset.tab)));

async function ensureUser(){
 const {data:{session},error}=await sb.auth.getSession();
 if(error) throw error;
 if(session?.user){user=session.user;return;}
 const {data,error:signError}=await sb.auth.signInAnonymously();
 if(signError) throw signError;
 user=data.user;
}
function renderIngredients(){
 $("ingredientList").innerHTML=INGREDIENTS.map(([name,emoji])=>`<label class="ingredient"><input type="checkbox" value="${esc(name)}"><span>${emoji} ${esc(name)}</span></label>`).join("");
 $("ingredientList").addEventListener("change",()=>{
  const checks=[...$("ingredientList").querySelectorAll("input")], n=checks.filter(c=>c.checked).length;
  checks.forEach(c=>c.disabled=!c.checked&&n>=5);
  $("ingredientCount").textContent=`${n} / 5 ingredientes elegidos`;
 });
}
function params(){return new URLSearchParams(location.search);}
async function init(){
 renderIngredients();
 if(!cfg.SUPABASE_URL || cfg.SUPABASE_URL.includes("TU-PROYECTO") || !cfg.SUPABASE_ANON_KEY || cfg.SUPABASE_ANON_KEY.includes("TU_SUPABASE")){
  message("setupMessage","Configura config.js con la URL y la anon/public key de Supabase.",true);
  $("createRoom").disabled=true;return;
 }
 try{
  await ensureUser();
  const p=params(), token=p.get("invite");
  if(token){$("joinRoom").classList.remove("hidden");$("createRoom").classList.add("hidden");}
 }catch(e){message("setupMessage",e.message,true);}
}
async function createRoom(){
 const name=$("displayName").value.trim();
 if(!name){message("setupMessage","Escribe tu nombre antes de crear la sala.",true);return;}
 message("setupMessage","Creando sala...");
 const {data,error}=await sb.rpc("create_toast_room",{p_room_name:"El Gran Maestro Tostadero",p_display_name:name});
 if(error){message("setupMessage",error.message,true);return;}
 const result=Array.isArray(data)?data[0]:data;
 const url=new URL(location.href);url.searchParams.set("invite",result.invite_token);
 history.replaceState({}, "", url);
 $("inviteLink").value=url.toString();$("inviteBox").classList.remove("hidden");
 await enterRoom(result.room_id,name,true);
}
async function joinRoom(){
 const token=params().get("invite"), name=$("displayName").value.trim();
 if(!token){message("setupMessage","El enlace de invitación no contiene un código válido.",true);return;}
 if(!name){message("setupMessage","Escribe tu nombre para entrar.",true);return;}
 message("setupMessage","Entrando en la sala...");
 const {data,error}=await sb.rpc("join_toast_room",{p_invite_token:token,p_display_name:name});
 if(error){message("setupMessage",error.message,true);return;}
 const result=Array.isArray(data)?data[0]:data;
 await enterRoom(result.room_id,name,false);
}
async function enterRoom(roomId,displayName,isHost){
 const {data:mem,error:memErr}=await sb.from("toast_room_members").select("*").eq("room_id",roomId).eq("user_id",user.id).single();
 if(memErr){message("setupMessage",memErr.message,true);return;}
 member=mem;
 const {data:r,error:rErr}=await sb.from("toast_rooms").select("id,name,status,challenge,created_at").eq("id",roomId).single();
 if(rErr){message("setupMessage",rErr.message,true);return;}
 room=r;
 $("setup").classList.add("hidden");$("room").classList.remove("hidden");
 $("roomTitle").textContent=room.name;$("roomCode").textContent=room.id.slice(0,8).toUpperCase();
 $("roleLabel").textContent=member.role==="director"?"Director del concurso":"Participante";
 document.querySelectorAll(".host-only").forEach(el=>el.classList.toggle("hidden",member.role!=="director"));
 $("challengeText").textContent=room.challenge||"El director todavía no ha anunciado un reto.";
 await refreshAll();subscribeRoom(roomId);setTab("make");
}
async function refreshAll(){
 const [m,t,v,s,r]=await Promise.all([
  sb.from("toast_room_members").select("*").eq("room_id",room.id),
  sb.from("toast_entries").select("*").eq("room_id",room.id).order("created_at"),
  sb.from("toast_votes").select("*").eq("room_id",room.id),
  sb.from("toast_judge_scores").select("*").eq("room_id",room.id),
  sb.from("toast_rooms").select("id,name,status,challenge").eq("id",room.id).single()
 ]);
 for(const x of [m,t,v,s,r]) if(x.error) console.warn(x.error);
 members=m.data||[];toasts=t.data||[];votes=v.data||[];scores=s.data||[];roomData=r.data||room;
 $("roomStatus").textContent=({lobby:"Preparación",submissions:"Presentación",voting:"Votaciones",finished:"Finalizado"})[roomData.status]||roomData.status;
 $("challengeText").textContent=roomData.challenge||"El director todavía no ha anunciado un reto.";
 renderToasts();renderRanking();renderHost();renderMyToast();
}
function subscribeRoom(roomId){
 if(channel) sb.removeChannel(channel);
 channel=sb.channel("toast-room-"+roomId)
 .on("postgres_changes",{event:"*",schema:"public",table:"toast_entries",filter:`room_id=eq.${roomId}`},refreshAll)
 .on("postgres_changes",{event:"*",schema:"public",table:"toast_votes",filter:`room_id=eq.${roomId}`},refreshAll)
 .on("postgres_changes",{event:"*",schema:"public",table:"toast_judge_scores",filter:`room_id=eq.${roomId}`},refreshAll)
 .on("postgres_changes",{event:"*",schema:"public",table:"toast_room_members",filter:`room_id=eq.${roomId}`},refreshAll)
 .on("postgres_changes",{event:"UPDATE",schema:"public",table:"toast_rooms",filter:`id=eq.${roomId}`},refreshAll)
 .subscribe();
}
function renderMyToast(){
 const mine=toasts.find(t=>t.member_id===member.id);
 if(mine){$("myToast").classList.remove("hidden");$("myToast").innerHTML=`<strong>Tu tostada ya está presentada:</strong><p>${esc(mine.title)}</p>`;$("toastForm").classList.add("hidden");}
 else{$("myToast").classList.add("hidden");$("toastForm").classList.remove("hidden");}
 $("submitToast").disabled=roomData?.status!=="submissions";
 if(roomData?.status==="lobby") message("toastMessage","El director todavía no ha abierto la presentación.");
 else if(roomData?.status==="voting") message("toastMessage","La fase de presentación ha terminado.");
 else if(roomData?.status==="finished") message("toastMessage","El concurso ha finalizado.");
 else message("toastMessage","");
}
$("toastForm").addEventListener("submit",async ev=>{
 ev.preventDefault();
 if(roomData?.status!=="submissions"){message("toastMessage","Ahora mismo no se pueden presentar tostadas.",true);return;}
 const selected=[...$("ingredientList").querySelectorAll("input:checked")].map(x=>x.value);
 if(selected.length<1||selected.length>5){message("toastMessage","Elige entre 1 y 5 ingredientes.",true);return;}
 const base=document.querySelector('input[name="base"]:checked').value;
 const {error}=await sb.rpc("submit_toast_entry",{p_room_id:room.id,p_title:$("toastName").value.trim(),p_base:base,p_ingredients:selected,p_recipe:$("recipe").value.trim(),p_pitch:$("pitch").value.trim()});
 if(error){message("toastMessage",error.message,true);return;}
 message("toastMessage","¡Tostada presentada!");await refreshAll();
});
function avgVotes(toastId){
 const list=votes.filter(v=>v.toast_id===toastId);
 return list.length?list.reduce((a,v)=>a+v.rating,0)/list.length:0;
}
function scoreFor(toastId){return scores.find(s=>s.toast_id===toastId);}
function renderToasts(){
 if(!room)return;
 if(!toasts.length){$("toastList").innerHTML='<p class="muted">Todavía no se ha presentado ninguna tostada.</p>';return;}
 $("toastList").innerHTML=toasts.map(t=>{
  const owner=members.find(m=>m.id===t.member_id);
  const myVote=votes.find(v=>v.toast_id===t.id&&v.voter_id===user.id);
  const isMine=t.member_id===member.id, canVote=roomData.status==="voting"&&!isMine&&!myVote;
  const voteControl=canVote?`<div class="vote-row"><label>Tu valoración</label><select id="vote-${t.id}"><option value="5">5 — Exquisita</option><option value="4">4 — Muy buena</option><option value="3" selected>3 — Correcta</option><option value="2">2 — Mejorable</option><option value="1">1 — Incomible</option></select><button class="secondary" onclick="castVote('${t.id}')">Votar</button></div>`:
   (myVote?`<p>Tu voto: ${myVote.rating}/5</p>`:"");
  const judge=scoreFor(t.id);
  return `<article class="toast-card"><div class="toast-meta">${esc(owner?.display_name||"Participante")} ${isMine?"· Tu creación":""}</div><h3>${esc(t.title)}</h3><p><b>Base:</b> ${esc(t.base)} · <b>Ingredientes:</b> ${esc(t.ingredients.join(", "))}</p><p><b>Preparación:</b> ${esc(t.recipe||"Sin descripción")}</p><p><b>Defensa:</b> ${esc(t.pitch||"—")}</p><p><b>Votos:</b> ${avgVotes(t.id).toFixed(1)}/5 (${votes.filter(v=>v.toast_id===t.id).length}) · <b>Jurado:</b> ${judge?judge.total_score+"/15":"Pendiente"}</p>${voteControl}</article>`;
 }).join("");
}
window.castVote=async toastId=>{
 const rating=+$("vote-"+toastId).value;
 const {error}=await sb.rpc("cast_toast_vote",{p_toast_id:toastId,p_rating:rating});
 if(error){alert(error.message);return;} await refreshAll();
};
function renderRanking(){
 if(!room)return;
 const rows=toasts.map(t=>{
  const judge=scoreFor(t.id), avg=avgVotes(t.id), count=votes.filter(v=>v.toast_id===t.id).length;
  const owner=members.find(m=>m.id===t.member_id);
  return {title:t.title,player:owner?.display_name||"Participante",judge:judge?.total_score||0,avg,count,total:(judge?.total_score||0)+avg,judged:!!judge};
 }).sort((a,b)=>b.total-a.total);
 if(!rows.length){$("rankingList").innerHTML='<p class="muted">La clasificación aparecerá cuando se presenten tostadas.</p>';return;}
 $("rankingList").innerHTML=rows.map((r,i)=>`<div class="rank-row"><span class="rank-no">#${i+1}</span><span><b>${esc(r.title)}</b><br><small class="muted">${esc(r.player)} · Jurado ${r.judge}/15 + votos ${r.avg.toFixed(1)}/5 (${r.count})</small></span><span class="rank-score">${r.total.toFixed(1)}/20</span></div>`).join("");
}
function renderHost(){
 if(!room||member.role!=="director")return;
 $("memberList").innerHTML=members.map(m=>`<p>${esc(m.display_name)} ${m.role==="director"?"· Director":""}</p>`).join("");
 $("judgeList").innerHTML=toasts.map(t=>{
  const sc=scoreFor(t.id);
  return `<div class="toast-card"><b>${esc(t.title)}</b><p>${sc?`Puntuada: ${sc.total_score}/15`:"Pendiente de puntuar"}</p><div class="score-fields">
   <label>Sabor (0-5)<input type="number" min="0" max="5" value="${sc?.taste??0}" id="taste-${t.id}"></label>
   <label>Originalidad (0-5)<input type="number" min="0" max="5" value="${sc?.originality??0}" id="original-${t.id}"></label>
   <label>Presentación (0-3)<input type="number" min="0" max="3" value="${sc?.presentation??0}" id="presentation-${t.id}"></label>
   <label>Explicación (0-2)<input type="number" min="0" max="2" value="${sc?.explanation??0}" id="explanation-${t.id}"></label>
  </div><button class="secondary" style="margin-top:10px" onclick="saveJudgeScore('${t.id}')">Guardar puntuación</button></div>`;
 }).join("")||'<p class="muted">Todavía no hay tostadas presentadas.</p>';
}
window.saveJudgeScore=async id=>{
 const vals={taste:+$("taste-"+id).value,originality:+$("original-"+id).value,presentation:+$("presentation-"+id).value,explanation:+$("explanation-"+id).value};
 if(vals.taste<0||vals.taste>5||vals.originality<0||vals.originality>5||vals.presentation<0||vals.presentation>3||vals.explanation<0||vals.explanation>2||Object.values(vals).some(n=>!Number.isInteger(n))){alert("Revisa las puntuaciones: sabor 0-5, originalidad 0-5, presentación 0-3 y explicación 0-2.");return;}
 const {error}=await sb.rpc("score_toast_entry",{p_toast_id:id,...Object.fromEntries(Object.entries(vals).map(([k,v])=>["p_"+k,v]))});
 if(error){alert(error.message);return;}await refreshAll();
};
async function hostAction(fn,args={}){
 const {error}=await sb.rpc(fn,args);if(error){message("hostMessage",error.message,true);return;}
 message("hostMessage","Cambio aplicado.");await refreshAll();
}
$("startSubmissions").addEventListener("click",()=>hostAction("set_toast_room_status",{p_room_id:room.id,p_status:"submissions"}));
$("startVoting").addEventListener("click",()=>hostAction("set_toast_room_status",{p_room_id:room.id,p_status:"voting"}));
$("finishRoom").addEventListener("click",()=>hostAction("set_toast_room_status",{p_room_id:room.id,p_status:"finished"}));
$("publishChallenge").addEventListener("click",()=>hostAction("set_toast_room_challenge",{p_room_id:room.id,p_challenge:$("hostChallenge").value.trim()}));
$("copyInvite").addEventListener("click",async()=>{await navigator.clipboard.writeText($("inviteLink").value);message("setupMessage","Enlace copiado.");});
$("copyRoomLink").addEventListener("click",async()=>{await navigator.clipboard.writeText(location.href);alert("Enlace de invitación copiado.");});
$("createRoom").addEventListener("click",createRoom);
$("joinRoom").addEventListener("click",joinRoom);
init();
