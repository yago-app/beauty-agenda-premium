// Supabase Edge Function: invite-collaborator
// Configure RESEND_API_KEY and INVITE_FROM_EMAIL in Supabase Edge Function secrets.
// Deploy with JWT verification enabled.
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
Deno.serve(async (request) => {
 const origin=request.headers.get("origin")||"";
 const allowed="https://yago-app.github.io";
 const headers={"Access-Control-Allow-Origin":allowed,"Access-Control-Allow-Headers":"authorization, apikey, content-type","Access-Control-Allow-Methods":"POST, OPTIONS","Content-Type":"application/json"};
 if(request.method==="OPTIONS")return new Response(null,{headers});
 const respond=(status:number,message:string)=>new Response(JSON.stringify({message}),{status,headers});
 if(request.method!=="POST")return respond(405,"Método não permitido");
 try{
  const authorization=request.headers.get("Authorization");
  if(!authorization?.startsWith("Bearer "))return respond(401,"Faça login");
  const supabase=createClient(Deno.env.get("SUPABASE_URL")!,Deno.env.get("SUPABASE_ANON_KEY")!,{global:{headers:{Authorization:authorization}}});
  const {data:{user},error:authError}=await supabase.auth.getUser();
  if(authError||!user)return respond(401,"Sessão inválida");
  const {member_id}=await request.json();
  if(typeof member_id!=="string"||!/^[0-9a-f-]{36}$/i.test(member_id))return respond(400,"Colaborador inválido");
  const {data:member,error}=await supabase.from("business_team").select("id,full_name,invite_email,invitation_status,owner_id,active").eq("id",member_id).eq("owner_id",user.id).single();
  if(error||!member||!member.active||member.invitation_status!=="pendente"||!member.invite_email)return respond(403,"Convite indisponível");
  const apiKey=Deno.env.get("RESEND_API_KEY"),from=Deno.env.get("INVITE_FROM_EMAIL");
  if(!apiKey||!from)return respond(503,"Envio de e-mail ainda não configurado");
  const url=new URL("https://yago-app.github.io/beauty-agenda-premium/colaborador.html");
  url.searchParams.set("convite",member.id);
  const escape=(s:string)=>s.replace(/[&<>"']/g,c=>({"&":"&amp;","<":"&lt;",">":"&gt;",'"':"&quot;","'":"&#39;"}[c]!));
  const html='<div style="font-family:Arial,sans-serif;max-width:560px;margin:auto;padding:28px"><h1 style="color:#c53676">Beauty Agenda Premium</h1><p>Olá, '+escape(member.full_name)+'!</p><p>Você recebeu um convite para integrar uma equipe no Beauty Agenda Premium.</p><p><a style="display:inline-block;background:#d84680;color:white;text-decoration:none;padding:14px 22px;border-radius:10px" href="'+escape(url.toString())+'">Aceitar convite</a></p><p>Entre ou cadastre-se usando este mesmo e-mail: '+escape(member.invite_email)+'</p><p>Se não esperava este convite, ignore esta mensagem.</p></div>';
  const response=await fetch("https://api.resend.com/emails",{method:"POST",headers:{"Authorization":"Bearer "+apiKey,"Content-Type":"application/json"},body:JSON.stringify({from,to:[member.invite_email],subject:"Convite para colaborar | Beauty Agenda Premium",html})});
  if(!response.ok)return respond(502,"Não foi possível enviar o e-mail. Confira a configuração do remetente.");
  return respond(200,"Convite enviado por e-mail");
 }catch{return respond(500,"Erro ao processar o convite");}
});
