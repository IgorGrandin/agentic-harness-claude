#!/usr/bin/env node
// Captura a tela RENDERIZADA do app (DOM + todo o CSS que o navegador aplicou,
// inclusive os estilos encapsulados do Angular e os internos do Material) num
// HTML que abre sozinho, igual ao app. É a base do mockup: edita-se a captura,
// não se redesenha a tela.
//
// Uso:
//   node capturar-tela.mjs capturar --url <url> --out <pasta> --nome <arquivo-sem-ext>
//        --data-dir <dir persistente> [--viewport 1440x900] [--esperar <seletor>]
//        [--antes <arquivo.js>] [--headed] [--sem-interativo]
//   node capturar-tela.mjs auth --url <url do app> --data-dir <dir>
//        [--realm-json <realm.json> --usuario <user>] [--sem-interativo]
//        Credencial, nesta ordem: env HARNESS_LOGIN_USER/PASSWORD → --realm-json/--usuario →
//        <data-dir>/auth/credenciais-dev.json (por origem, só app local) → janela para o dev entrar.
//        [--realm-json <arquivo do realm> --usuario <username>]   (senha lida do realm, nunca impressa)
//        (ou credenciais em HARNESS_LOGIN_USER / HARNESS_LOGIN_PASSWORD)
//        [--checar]   (só diz se a sessão salva ainda vale; não loga)
//   node capturar-tela.mjs screenshot --arquivo <html> --out <png> [--viewport 1440x900] [--recorte x,y,w,h]
//   node capturar-tela.mjs comparar --a <png> --b <png> --out <diff.png> [--ignorar x,y,w,h;...]
//   node capturar-tela.mjs conferir --arquivo <html> --ref <png> --out <pasta> [--ignorar x,y,w,h;...]
//        [--limite 0.5] [--nome <n>] [--viewport 1440x900]   (screenshot + comparar numa chamada:
//        {ok, percentual, regiao da diferença, mock, diff}; só abra imagem quando ok=false)
//   node capturar-tela.mjs lote --manifesto <json>   (várias capturas numa chamada; manifesto =
//        {"out":"<pasta>","itens":[{"nome","url","viewport"?,"esperar"?,"antes"?,"out"?}]}; uma linha por item)
//   node capturar-tela.mjs pecas      --arquivo <html> [--filtro <texto>] [--max 60]   (uma linha por componente, com um seletor)
//   node capturar-tela.mjs extrair    --arquivo <html> --seletor <css> [--indice N] [--max 8000] [--esqueleto [N]]
//   node capturar-tela.mjs substituir --arquivo <html> --seletor <css> --com <fragmento.html>
//                                     [--modo trocar|antes|depois|dentro] [--indice N] [--saida <html>]
//   node capturar-tela.mjs css-de     --arquivo <doador.html> --para <html>   (anexa o CSS do doador)
//   node capturar-tela.mjs sessao-mcp --url <url do app>      (renova a sessão e grava o que o
//        Playwright MCP carrega: <data-dir>/auth/mcp-storage-state.json e mcp-init.js)
//   node capturar-tela.mjs medir --url <url> --itens <itens.json> [--antes <passos.mjs>]
//        [--esperar <seletor>] [--viewport 1440x900]   (estilo computado, texto e caixa de cada
//        seletor na tela autenticada do app; fallback da verificação visual sem MCP)
//
// --data-dir é opcional: o padrão é %USERPROFILE%/.claude/brixbroker/captura (fora do repo,
// o mesmo nos três hosts).
//
// pecas/extrair/substituir/css-de existem para NUNCA ler a captura inteira (ela traz todo o
// CSS do app): o agente vê e mexe só no trecho que a WI muda.
//
// Origem: harness de Arthur Sena (github.com/ASsena/Harness-claude), adaptado.
//
// Login (Keycloak): sessão salva em <data-dir>/auth/<host>.json (cookies + localStorage,
// formato storageState do Playwright) e <host>.session.json (sessionStorage — onde o
// cliente OIDC costuma guardar o token, e que o storageState NÃO cobre).
// Ordem ao capturar: 1) sessão salva; 2) login automático headless com o usuário de
// dev (mesmas fontes do comando auth); 3) navegador visível para o dev entrar (até
// 5 min) — desligado com --sem-interativo. Toda captura bem-sucedida renova a sessão.
// A senha nunca é impressa nem gravada pelo script; só o estado da sessão.
//
// Dependências (playwright-core, pngjs, pixelmatch) são instaladas uma vez em
// <data-dir>/deps. Navegador: Edge ou Chrome já instalados (sem download).

import { createRequire } from 'node:module';
import { execFileSync, spawnSync } from 'node:child_process';
import fs from 'node:fs';
import path from 'node:path';
import os from 'node:os';

const PW_VERSION = '1.64.1';
const DEPS = { 'playwright-core': PW_VERSION, pngjs: '7.0.0', pixelmatch: '5.3.0' };

// ---------------------------------------------------------------- argumentos
const [cmd, ...rest] = process.argv.slice(2);
const opt = {};
for (let i = 0; i < rest.length; i++) {
  const a = rest[i];
  if (!a.startsWith('--')) continue;
  const k = a.slice(2);
  const v = rest[i + 1] && !rest[i + 1].startsWith('--') ? rest[++i] : true;
  opt[k] = v;
}
opt['data-dir'] = path.resolve(String(opt['data-dir'] && opt['data-dir'] !== true
  ? opt['data-dir'] : path.join(os.homedir(), '.claude', 'brixbroker', 'captura')));
// Segredos em uso (senha, usuário): o call log do Playwright repete o valor de fill() no stack.
// Toda saída de erro passa por ocultar().
const SEGREDOS = new Set();
const ocultar = (m) => { let s = String(m); for (const x of SEGREDOS) if (x) s = s.split(x).join('***'); return s; };
const die = (m) => { console.error(`ERRO: ${ocultar(m)}`); process.exit(1); };
const viewport = (() => {
  const [w, h] = String(opt.viewport || '1440x900').split('x').map(Number);
  return { width: w || 1440, height: h || 900 };
})();

// ---------------------------------------------------------------- dependências
function loadDeps(dataDir) {
  const tryFrom = [process.cwd(), dataDir ? path.join(dataDir, 'deps') : null].filter(Boolean);
  const load = (name) => {
    for (const base of tryFrom) {
      try { return createRequire(path.join(base, 'noop.js'))(name); } catch { /* tenta o próximo */ }
    }
    return null;
  };
  let pw = load('playwright-core') || load('playwright');
  let PNG = load('pngjs')?.PNG;
  let pixelmatch = load('pixelmatch');
  if ((!pw || !PNG || !pixelmatch) && dataDir) {
    const depsDir = path.join(dataDir, 'deps');
    fs.mkdirSync(depsDir, { recursive: true });
    if (!fs.existsSync(path.join(depsDir, 'package.json'))) {
      fs.writeFileSync(path.join(depsDir, 'package.json'), '{"name":"harness-capture-deps","private":true}');
    }
    console.error(`Instalando dependências da captura em ${depsDir} (uma vez só)…`);
    const npm = process.platform === 'win32' ? 'npm.cmd' : 'npm';
    execFileSync(npm, ['install', '--no-audit', '--no-fund', '--loglevel=error',
      ...Object.entries(DEPS).map(([n, v]) => `${n}@${v}`)],
      { cwd: depsDir, stdio: ['ignore', 'inherit', 'inherit'], shell: process.platform === 'win32' });
    pw = load('playwright-core'); PNG = load('pngjs')?.PNG; pixelmatch = load('pixelmatch');
  }
  if (!pw) die('playwright-core indisponível (passe --data-dir para instalar).');
  return { chromium: pw.chromium, PNG, pixelmatch };
}

async function launch(chromium, headed) {
  const errors = [];
  for (const channel of ['msedge', 'chrome', undefined]) {
    try {
      return await chromium.launch({ headless: !headed, ...(channel ? { channel } : {}) });
    } catch (e) { errors.push(`${channel || 'chromium'}: ${String(e.message).split('\n')[0]}`); }
  }
  die(`nenhum navegador abriu.\n  ${errors.join('\n  ')}\nInstale o Edge/Chrome ou rode: npx playwright install chromium`);
}

// ---------------------------------------------------------------- sessão (login)
// Só o caminho: o hash da volta do Keycloak traz `iss=…/realms/…` e não é tela de login.
// Rotas do Keycloak (direto ou atrás do proxy /auth): /realms/<r>/protocol/… e /realms/<r>/login-actions/….
const isKeycloakPage = (u) => { try { return /^(\/auth)?\/realms\/[^/]+\/(protocol|login-actions)\//.test(new URL(u).pathname); } catch { return false; } };
const HOST_LOCAL = /^(localhost|127\.0\.0\.1|\[::1\]|.+\.localhost|.+\.test)$/;
const semHash = (u) => { try { const x = new URL(u); return x.origin + x.pathname; } catch { return ''; } };
// O broker-web e o admin-web têm uma rota /login própria (botão "Entrar com Keycloak")
// antes do formulário do Keycloak: ela também é tela de login.
const isAppLoginPage = (u) => { try { return /^\/login\/?$/.test(new URL(u).pathname); } catch { return false; } };
const isLoginPage = (u) => isKeycloakPage(u) || isAppLoginPage(u);

function authPaths(url, dataDir) {
  if (!dataDir) return null;
  const host = new URL(url).host.replace(/[^\w.-]/g, '_');
  const dir = path.join(dataDir, 'auth');
  return { dir, state: path.join(dir, `${host}.json`), session: path.join(dir, `${host}.session.json`) };
}

// Contexto já com a sessão salva: storageState + sessionStorage reinjetado antes do app subir.
async function contextoComSessao(browser, url, ap) {
  const hasState = ap && fs.existsSync(ap.state);
  const context = await browser.newContext({ viewport, ...(hasState ? { storageState: ap.state } : {}) });
  if (ap && fs.existsSync(ap.session)) {
    let saved = {};
    try { saved = JSON.parse(fs.readFileSync(ap.session, 'utf8')); } catch { /* arquivo corrompido: ignora */ }
    await context.addInitScript(([origin, data]) => {
      if (location.origin !== origin) return;
      for (const [k, v] of Object.entries(data)) { try { if (sessionStorage.getItem(k) === null) sessionStorage.setItem(k, v); } catch {} }
    }, [new URL(url).origin, saved]);
  }
  return context;
}

async function salvarSessao(context, page, url, ap) {
  if (!ap) return;
  fs.mkdirSync(ap.dir, { recursive: true });
  // Keycloak atrás do proxy do dev server (/auth → Keycloak, com pathRewrite): os cookies de SSO
  // saem com caminho /realms/… e o navegador, que fala com /auth/realms/…, não os devolve — todo
  // reload cai no formulário. Uma cópia em /auth/realms/… faz o SSO valer na sessão salva.
  const host = new URL(url).hostname;
  const copias = (await context.cookies())
    .filter((c) => c.path.startsWith('/realms/') && c.domain.replace(/^\./, '') === host)
    .map((c) => ({ ...c, path: `/auth${c.path}` }));
  if (copias.length) await context.addCookies(copias).catch(() => {});
  await context.storageState({ path: ap.state });
  let ss = {};
  if (new URL(page.url()).origin === new URL(url).origin) {
    ss = await page.evaluate(() => Object.fromEntries(Object.keys(sessionStorage).map((k) => [k, sessionStorage.getItem(k)]))).catch(() => ({}));
  }
  fs.writeFileSync(ap.session, JSON.stringify(ss));
  try { fs.chmodSync(ap.state, 0o600); fs.chmodSync(ap.session, 0o600); } catch { /* Windows */ }
}

// Credencial de teste salva pelo dev, por origem, em <data-dir>/auth/credenciais-dev.json
// ({ "http://localhost:4201": { "usuario": "...", "senha": "..." } }), fora de qualquer repo.
// Só vale para app local (localhost, 127.0.0.1, *.localhost, *.test).
function credenciaisLocais() {
  if (!opt.url || !opt['data-dir']) return null;
  let origem;
  try { origem = new URL(String(opt.url)); } catch { return null; }
  if (!HOST_LOCAL.test(origem.hostname)) return null;
  try {
    const todas = JSON.parse(fs.readFileSync(path.join(String(opt['data-dir']), 'auth', 'credenciais-dev.json'), 'utf8'));
    const c = todas[origem.origin];
    return c && c.usuario && c.senha ? { usuario: c.usuario, senha: c.senha, fonte: 'credenciais-dev.json' } : null;
  } catch { return null; }
}

// Credenciais do usuário de dev: env HARNESS_LOGIN_USER/PASSWORD, ou o JSON do realm
// do AppHost (--realm-json + --usuario). Nunca loga, imprime nem devolve a senha.
function credenciaisDev() {
  const envUser = process.env.HARNESS_LOGIN_USER; const envPass = process.env.HARNESS_LOGIN_PASSWORD;
  if (envUser && envPass) return { usuario: envUser, senha: envPass, fonte: 'env' };
  if (!opt['realm-json'] || !opt.usuario) return credenciaisLocais();
  let realm;
  try { realm = JSON.parse(fs.readFileSync(String(opt['realm-json']), 'utf8')); }
  catch (e) { die(`não consegui ler o realm (${String(e.message).split('\n')[0]}).`); }
  const nome = String(opt.usuario).toLowerCase();
  const u = (realm.users || []).find((x) => String(x.username).toLowerCase() === nome || String(x.email || '').toLowerCase() === nome);
  if (!u) die(`usuário "${opt.usuario}" não existe em ${opt['realm-json']}. Usuários: ${(realm.users || []).map((x) => x.username).join(', ') || '(nenhum)'}`);
  const cred = (u.credentials || []).find((c) => c.type === 'password' && typeof c.value === 'string');
  if (!cred) die(`"${u.username}" não tem senha em texto no realm (só hash ou nenhuma). Use HARNESS_LOGIN_USER/HARNESS_LOGIN_PASSWORD ou escale ao dev.`);
  return { usuario: u.username, senha: cred.value, fonte: 'realm' };
}

// SPA com guard assíncrono: o redirecionamento para /login ou para o Keycloak chega depois do
// networkidle. Espera a URL ficar parada por `quieto` ms (no máximo `max` ms).
async function assentar(page, { quieto = 3000, max = 20000 } = {}) {
  await page.waitForLoadState('networkidle', { timeout: 30000 }).catch(() => {});
  const fim = Date.now() + max;
  let ultima = page.url(), desde = Date.now();
  while (Date.now() < fim) {
    await page.waitForTimeout(250);
    const agora = page.url();
    if (agora !== ultima) { ultima = agora; desde = Date.now(); continue; }
    if (Date.now() - desde >= quieto) break;
  }
  await page.waitForLoadState('networkidle', { timeout: 15000 }).catch(() => {});
}

// Preenche o formulário padrão do Keycloak e espera voltar ao app. Devolve null ou o motivo da falha.
async function loginKeycloak(page, url, cred) {
  const appOrigin = new URL(url).origin;
  if (!isLoginPage(page.url())) return null;
  if (isAppLoginPage(page.url())) {
    // Tela de login do próprio app: o botão leva ao Keycloak.
    const btn = page.locator('button, a[role="button"]', { hasText: /keycloak|entrar|login|sign in/i }).first();
    try { await btn.waitFor({ timeout: 15000 }); } catch { return 'tela /login do app sem botão de entrada reconhecível.'; }
    await Promise.all([
      page.waitForURL((u) => isKeycloakPage(u.href) || (u.origin === appOrigin && !isLoginPage(u.href)), { timeout: 30000 }).catch(() => {}),
      btn.click(),
    ]);
    await assentar(page);
    if (!isLoginPage(page.url())) return null;
  }
  SEGREDOS.add(cred.senha); SEGREDOS.add(cred.usuario);
  // Credencial só vai para tela de login no host do app ou em host local, nunca para IdP externo.
  const hostLogin = new URL(page.url()).hostname;
  if (hostLogin !== new URL(url).hostname && !HOST_LOCAL.test(hostLogin)) {
    return `a tela de login está em outro host (${hostLogin}); a credencial de dev não é enviada para lá.`;
  }
  const user = page.locator('#username, input[name="username"]').first();
  try { await user.waitFor({ timeout: 20000 }); } catch { return 'formulário de login do Keycloak não apareceu (#username).'; }
  try {
    await user.fill(cred.usuario, { timeout: 10000 });
    await page.locator('#password, input[name="password"]').first().fill(cred.senha, { timeout: 10000 });
    await Promise.all([
      page.waitForURL((u) => u.origin === appOrigin && !isLoginPage(u.href), { timeout: 45000 }).catch(() => {}),
      page.locator('#kc-login, input[type="submit"], button[type="submit"]').first().click({ timeout: 10000 }),
    ]);
  } catch {
    return 'não consegui preencher ou enviar o formulário de login (campo oculto, tema diferente ou login em duas etapas).';
  }
  // De volta ao app, o guard ainda pode mandar de novo ao login (troca de código recusada).
  await assentar(page);
  if (isLoginPage(page.url())) {
    const msg = await page.locator('[id^="input-error"], .kc-feedback-text, .alert-error, [role="alert"]')
      .filter({ hasText: /\S/ }).first().innerText({ timeout: 2000 }).catch(() => '');
    if (/update.?password|atualizar|required.?action|otp|totp/i.test(page.url() + ' ' + msg)) {
      return 'o Keycloak pediu ação extra (trocar senha, OTP…) para esse usuário. Ajuste o usuário no realm ou escale ao dev.';
    }
    return `login recusado pelo Keycloak${msg ? `: ${msg.trim().replace(/\.$/, '').slice(0, 160)}` : ''} (parou em ${new URL(page.url()).pathname}).`;
  }
  return null;
}

// Garante a página autenticada em `url`. Devolve { browser, context, page, via }.
async function abrirAutenticado(chromium, url, ap, { headed = false, interativo = true, ignorarSessao = false } = {}) {
  const appOrigin = new URL(url).origin;
  let browser = await launch(chromium, headed);
  let context = ignorarSessao ? await browser.newContext({ viewport }) : await contextoComSessao(browser, url, ap);
  let page = await context.newPage();
  await page.goto(url, { waitUntil: 'domcontentloaded', timeout: 60000 });
  await assentar(page);
  if (!isLoginPage(page.url())) return { browser, context, page, via: 'sessao-salva' };

  const cred = credenciaisDev();
  if (cred) {
    // Contexto limpo: sessão velha pode atrapalhar o fluxo do Keycloak.
    await context.close();
    context = await browser.newContext({ viewport });
    page = await context.newPage();
    await page.goto(url, { waitUntil: 'domcontentloaded', timeout: 60000 });
    await assentar(page);
    const falha = await loginKeycloak(page, url, cred);
    if (!falha) {
      await salvarSessao(context, page, url, ap);
      if (page.url() !== url) { await page.goto(url, { waitUntil: 'domcontentloaded', timeout: 60000 }).catch(() => {}); await assentar(page); }
      return { browser, context, page, via: `login-automatico (${cred.fonte})` };
    }
    console.error(`Login automático falhou: ${ocultar(falha)}`);
  }

  if (!interativo) {
    await browser.close();
    die('sem sessão válida e sem login automático. Rode o comando auth (com --realm-json/--usuario ou HARNESS_LOGIN_USER/PASSWORD) ou escale ao dev.');
  }
  if (!headed) {
    await browser.close();
    console.error('Sem sessão válida. Abrindo o navegador para você entrar com o usuário de desenvolvimento (até 5 min)…');
    browser = await launch(chromium, true);
    context = await browser.newContext({ viewport });
    page = await context.newPage();
    await page.goto(url, { waitUntil: 'domcontentloaded', timeout: 60000 });
  }
  // O app abre em "/" e só depois o guard manda ao login: espere a URL assentar no app fora do login.
  const limite = Date.now() + 300000;
  for (;;) {
    await assentar(page, { quieto: 2000, max: 10000 }).catch(() => {});
    let atual = '';
    try { atual = page.url(); } catch { die('a janela de login foi fechada antes do fim.'); }
    if (new URL(atual).origin === appOrigin && !isLoginPage(atual)) break;
    if (Date.now() > limite) die('o login não foi concluído em 5 minutos.');
    await page.waitForURL((u) => u.origin === appOrigin && !isLoginPage(u.href), { timeout: Math.max(1000, limite - Date.now()) }).catch(() => {});
  }
  await salvarSessao(context, page, url, ap);
  if (page.url() !== url) { await page.goto(url, { waitUntil: 'domcontentloaded', timeout: 60000 }).catch(() => {}); await assentar(page); }
  return { browser, context, page, via: 'login-manual' };
}

// ---------------------------------------------------------------- serialização (roda na página)
// Devolve o HTML autossuficiente e a lista de URLs de recursos (fontes, imagens) a embutir.
function serializePage() {
  const abs = (u, base) => { try { return new URL(u, base).href; } catch { return u; } };
  const urls = new Set();
  const rewriteUrls = (css, base) => css.replace(/url\(\s*(['"]?)([^'")]+)\1\s*\)/g, (m, q, u) => {
    if (/^(data:|#)/.test(u)) return m;
    const a = abs(u, base); urls.add(a); return `url("${a}")`;
  });

  // 1) Todo o CSS aplicado, na ordem do documento (inclui <style> do Angular e adoptedStyleSheets).
  const chunks = [];
  const sheets = [...document.styleSheets, ...(document.adoptedStyleSheets || [])];
  for (const sh of sheets) {
    const base = sh.href || document.baseURI;
    try {
      const media = sh.media && sh.media.mediaText && sh.media.mediaText !== 'all' ? sh.media.mediaText : '';
      const css = [...sh.cssRules].map((r) => r.cssText).join('\n');
      chunks.push(media ? `@media ${media} {\n${css}\n}` : css);
      chunks[chunks.length - 1] = rewriteUrls(chunks[chunks.length - 1], base);
    } catch { chunks.push(`/* folha não lida (CORS): ${sh.href} */`); }
  }

  // 2) Clone do DOM com o estado atual dos controles.
  const live = document.documentElement;
  const clone = live.cloneNode(true);
  const liveAll = live.querySelectorAll('*');
  const cloneAll = clone.querySelectorAll('*');
  liveAll.forEach((el, i) => {
    const c = cloneAll[i];
    if (!c) return;
    if (el instanceof HTMLInputElement) {
      if (el.type === 'checkbox' || el.type === 'radio') { if (el.checked) c.setAttribute('checked', ''); else c.removeAttribute('checked'); }
      else c.setAttribute('value', el.value);
    } else if (el instanceof HTMLTextAreaElement) { c.textContent = el.value; }
    else if (el instanceof HTMLSelectElement) {
      [...c.options].forEach((o, j) => { if (el.options[j]?.selected) o.setAttribute('selected', ''); else o.removeAttribute('selected'); });
    } else if (el instanceof HTMLCanvasElement) {
      try { const img = document.createElement('img'); img.src = el.toDataURL(); img.width = el.width; img.height = el.height;
        img.style.cssText = el.style.cssText; [...el.attributes].forEach((a) => { if (!['width','height'].includes(a.name)) img.setAttribute(a.name, a.value); });
        c.replaceWith(img); } catch { /* canvas contaminado: fica vazio */ }
    }
    if (el.scrollTop || el.scrollLeft) c.setAttribute('data-captura-scroll', `${el.scrollLeft},${el.scrollTop}`);
    for (const attr of ['src', 'srcset', 'poster']) {
      const v = c.getAttribute && c.getAttribute(attr);
      if (v && attr !== 'srcset' && !/^data:/.test(v)) { const a = abs(v, document.baseURI); urls.add(a); c.setAttribute(attr, a); }
    }
    const st = c.getAttribute && c.getAttribute('style');
    if (st && st.includes('url(')) c.setAttribute('style', rewriteUrls(st, document.baseURI));
  });

  // 3) Remove o que é comportamento ou carregamento: o mockup é estático.
  clone.querySelectorAll('script, noscript, link[rel="stylesheet"], link[rel="preload"], link[rel="modulepreload"], link[rel="prefetch"], base, style').forEach((n) => n.remove());
  clone.querySelectorAll('[srcset]').forEach((n) => n.removeAttribute('srcset'));

  const head = clone.querySelector('head');
  const style = document.createElement('style');
  style.setAttribute('data-captura', 'css-do-app');
  style.textContent = chunks.join('\n');
  head.appendChild(style);
  const meta = document.createElement('meta');
  meta.setAttribute('name', 'captura');
  meta.setAttribute('content', `${location.href} | ${new Date().toISOString()} | ${innerWidth}x${innerHeight}`);
  head.prepend(meta);
  if (!head.querySelector('meta[charset]')) { const m = document.createElement('meta'); m.setAttribute('charset', 'utf-8'); head.prepend(m); }

  // Restaura rolagens internas ao abrir o arquivo.
  const restore = document.createElement('script');
  restore.textContent = "document.querySelectorAll('[data-captura-scroll]').forEach(e=>{const[x,y]=e.dataset.capturaScroll.split(',');e.scrollLeft=+x;e.scrollTop=+y;});";
  clone.querySelector('body').appendChild(restore);

  return { html: '<!doctype html>\n' + clone.outerHTML, urls: [...urls] };
}

// ---------------------------------------------------------------- comandos
async function capturar() {
  const { url, out, nome = 'captura', 'data-dir': dataDir } = opt;
  if (!url || !out) die('capturar exige --url e --out.');
  const { chromium } = loadDeps(dataDir);
  const ap = authPaths(url, dataDir);
  const { browser, context, page, via } = await abrirAutenticado(chromium, url, ap,
    { headed: !!opt.headed, interativo: !opt['sem-interativo'] });
  console.error(`Sessão: ${via}`);

  if (opt.esperar) await page.waitForSelector(String(opt.esperar), { timeout: 30000 });
  if (opt.antes) {
    // Passos para chegar ao estado desejado (abrir aba, aplicar filtro…): export default async (page) => {}
    const mod = await import(new URL(`file://${path.resolve(String(opt.antes))}`).href);
    await (mod.default || mod)(page);
    await page.waitForLoadState('networkidle', { timeout: 30000 }).catch(() => {});
  }
  await page.evaluate(() => document.fonts && document.fonts.ready);
  await page.waitForTimeout(500); // animações de entrada do Material

  fs.mkdirSync(out, { recursive: true });
  const pngPath = path.join(out, `${nome}.referencia.png`);
  await page.screenshot({ path: pngPath, fullPage: false, animations: 'disabled' });

  const { html, urls } = await page.evaluate(serializePage);

  // Recursos (fontes, imagens) vão para <out>/assets e o HTML aponta para eles.
  const assetsDir = path.join(out, 'assets');
  let out_html = html; let bytes = 0; const faltando = [];
  for (const u of urls) {
    try {
      const res = await context.request.get(u, { timeout: 30000 });
      if (!res.ok()) { faltando.push(`${res.status()} ${u}`); continue; }
      const body = await res.body();
      const ext = (path.extname(new URL(u).pathname) || '').slice(0, 8);
      const name = `${Buffer.from(u).toString('base64url').slice(-40)}${ext}`;
      fs.mkdirSync(assetsDir, { recursive: true });
      fs.writeFileSync(path.join(assetsDir, name), body);
      bytes += body.length;
      out_html = out_html.split(u).join(`assets/${name}`);
    } catch (e) { faltando.push(`${String(e.message).split('\n')[0]} ${u}`); }
  }
  const htmlPath = path.join(out, `${nome}.html`);
  fs.writeFileSync(htmlPath, out_html);
  await salvarSessao(context, page, url, ap).catch(() => {}); // renova a sessão para a próxima
  await browser.close();

  console.log(JSON.stringify({
    html: htmlPath, referencia: pngPath, viewport: `${viewport.width}x${viewport.height}`,
    recursos: urls.length - faltando.length, recursosKB: Math.round(bytes / 1024),
    htmlKB: Math.round(Buffer.byteLength(out_html) / 1024), faltando,
  }, null, 2));
}

async function screenshot() {
  const { arquivo, out, 'data-dir': dataDir } = opt;
  if (!arquivo || !out) die('screenshot exige --arquivo e --out.');
  const { chromium } = loadDeps(dataDir);
  const browser = await launch(chromium, false);
  const page = await (await browser.newContext({ viewport })).newPage();
  await page.goto(new URL(`file://${path.resolve(String(arquivo))}`).href, { waitUntil: 'load' });
  await page.evaluate(() => document.fonts && document.fonts.ready);
  // --recorte x,y,w,h: salva só a região que a WI mudou — é o que se olha com Read,
  // em vez da tela inteira (uma imagem cheia por conferência pesa no contexto).
  let clip;
  if (opt.recorte) {
    const [x, y, width, height] = String(opt.recorte).split(',').map(Number);
    if ([x, y, width, height].some((n) => !Number.isFinite(n)) || width <= 0 || height <= 0) {
      die('--recorte espera x,y,w,h (números, w e h > 0).');
    }
    clip = { x, y, width, height };
  }
  await page.screenshot({ path: String(out), fullPage: false, animations: 'disabled', ...(clip ? { clip } : {}) });
  await browser.close();
  console.log(JSON.stringify({ png: out, ...(clip ? { recorte: clip } : {}) }));
}

// Compara duas imagens do mesmo tamanho fora das regiões ignoradas (a área que a WI muda de
// propósito, "x,y,w,h;x,y,w,h"). Devolve a contagem, o percentual e a caixa onde as diferenças
// se concentram, para recortar só ali em vez de olhar a tela inteira.
function diferenca(PNG, pixelmatch, A, B, ignorar, diffPath) {
  const regs = String(ignorar || '').split(';').filter(Boolean).map((r) => r.split(',').map(Number));
  const mask = (img) => { for (const [x, y, w, h] of regs) for (let yy = y; yy < Math.min(y + h, img.height); yy++) for (let xx = x; xx < Math.min(x + w, img.width); xx++) { const i = (yy * img.width + xx) * 4; img.data[i] = img.data[i + 1] = img.data[i + 2] = 0; img.data[i + 3] = 255; } };
  mask(A); mask(B);
  const D = new PNG({ width: A.width, height: A.height });
  const diff = pixelmatch(A.data, B.data, D.data, A.width, A.height, { threshold: 0.1 });
  if (diffPath) fs.writeFileSync(String(diffPath), PNG.sync.write(D));
  let x0 = A.width, y0 = A.height, x1 = -1, y1 = -1;
  if (diff > 0) {
    for (let y = 0; y < D.height; y++) for (let x = 0; x < D.width; x++) {
      const i = (y * D.width + x) * 4; // cor de diferença do pixelmatch: vermelho puro
      if (D.data[i] === 255 && D.data[i + 1] === 0 && D.data[i + 2] === 0) { if (x < x0) x0 = x; if (x > x1) x1 = x; if (y < y0) y0 = y; if (y > y1) y1 = y; }
    }
  }
  const total = A.width * A.height - regs.reduce((s, [, , w, h]) => s + w * h, 0);
  const pct = total > 0 ? (diff / total) * 100 : 0;
  return { pixelsDiferentes: diff, percentual: Number(pct.toFixed(3)), regiao: x1 >= 0 ? { x: x0, y: y0, w: x1 - x0 + 1, h: y1 - y0 + 1 } : null };
}

async function comparar() {
  const { a, b, out, 'data-dir': dataDir } = opt;
  if (!a || !b) die('comparar exige --a e --b.');
  const { PNG, pixelmatch } = loadDeps(dataDir);
  if (!PNG || !pixelmatch) die('pngjs/pixelmatch indisponíveis (passe --data-dir).');
  const A = PNG.sync.read(fs.readFileSync(String(a)));
  const B = PNG.sync.read(fs.readFileSync(String(b)));
  if (A.width !== B.width || A.height !== B.height) die(`tamanhos diferentes: ${A.width}x${A.height} × ${B.width}x${B.height}`);
  const r = diferenca(PNG, pixelmatch, A, B, opt.ignorar, out);
  console.log(JSON.stringify({ ...r, diff: out || null }));
}

// screenshot + comparar numa chamada só: renderiza o HTML do mockup no tamanho da referência e
// devolve o veredito (percentual ≤ --limite, padrão 0,5), a caixa da diferença e os dois PNGs.
// Só abra uma imagem quando "ok" for false, e só o --recorte da "regiao".
async function conferir() {
  const { arquivo, ref, out, 'data-dir': dataDir } = opt;
  if (!arquivo || !ref || !out) die('conferir exige --arquivo, --ref e --out (pasta).');
  const { chromium, PNG, pixelmatch } = loadDeps(dataDir);
  if (!PNG || !pixelmatch) die('pngjs/pixelmatch indisponíveis (passe --data-dir).');
  const limite = Number(opt.limite || 0.5);
  const nome = String(opt.nome || path.basename(String(arquivo)).replace(/\.html?$/i, '')).replace(/[^\w.-]+/g, '_');
  fs.mkdirSync(String(out), { recursive: true });
  const pngMock = path.join(String(out), `${nome}.mock.png`);
  const pngDiff = path.join(String(out), `${nome}.diff.png`);
  const A = PNG.sync.read(fs.readFileSync(String(ref)));
  const vp = opt.viewport ? viewport : { width: A.width, height: A.height };
  const browser = await launch(chromium, false);
  const page = await (await browser.newContext({ viewport: vp })).newPage();
  await page.goto(new URL(`file://${path.resolve(String(arquivo))}`).href, { waitUntil: 'load' });
  await page.evaluate(() => document.fonts && document.fonts.ready);
  await page.screenshot({ path: pngMock, fullPage: false, animations: 'disabled' });
  await browser.close();
  const B = PNG.sync.read(fs.readFileSync(pngMock));
  if (A.width !== B.width || A.height !== B.height) die(`tamanhos diferentes: referência ${A.width}x${A.height} × mockup ${B.width}x${B.height} (passe --viewport ${A.width}x${A.height}).`);
  const r = diferenca(PNG, pixelmatch, A, B, opt.ignorar, pngDiff);
  console.log(JSON.stringify({ ok: r.percentual <= limite, limite, ...r, mock: pngMock, diff: pngDiff }));
}

// Várias capturas numa chamada só (telas × estados × larguras), sem um turno de modelo por captura.
// --manifesto <json>: { "out": "<pasta>", "itens": [{ "nome", "url", "viewport"?, "esperar"?, "antes"?, "out"? }] }
// (ou só a lista). A primeira captura entra na sessão; as outras a reaproveitam. Devolve uma linha
// por item. Falha de login interrompe o resto.
async function lote() {
  if (!opt.manifesto) die('lote exige --manifesto <json>.');
  let man;
  try { man = JSON.parse(fs.readFileSync(String(opt.manifesto), 'utf8')); } catch (e) { die(`não consegui ler o manifesto (${String(e.message).split('\n')[0]}).`); }
  const itens = Array.isArray(man) ? man : man.itens;
  const outPadrao = Array.isArray(man) ? null : man.out;
  if (!Array.isArray(itens) || !itens.length) die('manifesto sem itens.');
  const resultados = [];
  let parar = '';
  for (const [i, it] of itens.entries()) {
    const nome = it.nome || `#${i + 1}`;
    const destino = it.out || outPadrao;
    if (parar) { resultados.push({ nome, ok: false, erro: `não executado (${parar})` }); continue; }
    if (!it.url || !it.nome || !destino) { resultados.push({ nome, ok: false, erro: 'item precisa de url, nome e out.' }); continue; }
    const args = [process.argv[1], 'capturar', '--url', it.url, '--out', destino, '--nome', it.nome, '--sem-interativo', '--data-dir', opt['data-dir']];
    for (const k of ['viewport', 'esperar', 'antes']) if (it[k]) args.push(`--${k}`, String(it[k]));
    const r = spawnSync(process.execPath, args, { encoding: 'utf8', timeout: 300000, env: process.env });
    if (r.status === 0) {
      let j = {};
      try { j = JSON.parse(r.stdout); } catch { /* saída inesperada */ }
      resultados.push({ nome, ok: true, html: j.html, referencia: j.referencia, htmlKB: j.htmlKB, faltando: (j.faltando || []).length });
    } else {
      const erro = ocultar(((l) => l.find((x) => /^ERRO:/.test(x)) || l.filter(Boolean).pop() || 'falhou')(String(r.stderr || r.error || 'falhou').trim().split('\n'))).slice(0, 200);
      resultados.push({ nome, ok: false, erro });
      if (/sem sessão válida|login/i.test(erro)) parar = 'login falhou no item anterior';
    }
  }
  for (const r of resultados) console.log(JSON.stringify(r));
  const falhas = resultados.filter((r) => !r.ok).length;
  console.log(`// ${resultados.length - falhas} de ${resultados.length} capturas ok${falhas ? `, ${falhas} com erro` : ''}`);
  if (falhas) process.exitCode = 1;
}

// ---------------------------------------------------------------- edição sem ler o arquivo inteiro
// Abre a captura com JavaScript desligado (nada roda), mexe no DOM e grava de volta.
async function openStatic(arquivo) {
  const { chromium } = loadDeps(opt['data-dir']);
  const browser = await launch(chromium, false);
  const context = await browser.newContext({ javaScriptEnabled: false, viewport });
  const page = await context.newPage();
  await page.goto(new URL(`file://${path.resolve(String(arquivo))}`).href, { waitUntil: 'domcontentloaded' });
  return { browser, page };
}
const serializeDoc = () => '<!doctype html>\n' + document.documentElement.outerHTML;

async function pecas() {
  if (!opt.arquivo) die('pecas exige --arquivo.');
  const { browser, page } = await openStatic(opt.arquivo);
  const res = await page.evaluate(() => {
    const sel = (el) => {
      const parts = [];
      for (let e = el; e && e.nodeType === 1 && e !== document.body; e = e.parentElement) {
        if (e.id && /^[A-Za-z][\w-]*$/.test(e.id)) { parts.unshift(`#${e.id}`); break; }
        const tag = e.tagName.toLowerCase();
        const sib = [...(e.parentElement?.children || [])].filter((x) => x.tagName === e.tagName);
        parts.unshift(sib.length > 1 ? `${tag}:nth-of-type(${sib.indexOf(e) + 1})` : tag);
      }
      return parts.join(' > ');
    };
    const m = new Map();
    for (const el of document.body.querySelectorAll('*')) {
      const tag = el.tagName.toLowerCase();
      const marked = el.getAttribute('data-componente') || el.getAttribute('data-novo');
      if (!tag.includes('-') && !marked) continue;
      const key = marked ? `${tag} [${el.hasAttribute('data-novo') ? 'novo' : 'marcado'}: ${marked}]` : tag;
      const a = m.get(key) || { quantidade: 0, primeiro: sel(el), texto: (el.textContent || '').trim().replace(/\s+/g, ' ').slice(0, 60) };
      a.quantidade += 1; m.set(key, a);
    }
    return [...m].map(([componente, a]) => ({ componente, ...a }));
  });
  await browser.close();
  // Uma linha por componente (JSON compacto). --filtro <texto> mantém só os que o contêm;
  // --max <n> limita a quantidade de linhas (padrão 60).
  const filtro = opt.filtro ? String(opt.filtro).toLowerCase() : '';
  const max = Number(opt.max || 60);
  const lista = filtro ? res.filter((r) => JSON.stringify(r).toLowerCase().includes(filtro)) : res;
  for (const r of lista.slice(0, max)) console.log(JSON.stringify(r));
  console.log(`// ${lista.length} componente(s)${lista.length > max ? `; mostrando ${max} — use --filtro` : ''}`);
}

async function extrair() {
  if (!opt.arquivo || !opt.seletor) die('extrair exige --arquivo e --seletor.');
  const { browser, page } = await openStatic(opt.arquivo);
  const idx = Number(opt.indice || 0);
  // --esqueleto [N]: só tags e atributos de marcação até N níveis (padrão 3), sem texto longo,
  // para achar o trecho certo antes de extrair o HTML inteiro dele.
  const prof = opt.esqueleto ? (opt.esqueleto === true ? 3 : Number(opt.esqueleto) || 3) : 0;
  const out = await page.evaluate(([s, i, p]) => {
    const all = document.querySelectorAll(s);
    const el = all[i];
    if (!el) return { total: all.length, html: null };
    if (!p) return { total: all.length, html: el.outerHTML };
    const keep = ['id', 'data-componente', 'data-variacao', 'data-novo', 'role'];
    const walk = (e, d) => {
      const attrs = keep.filter((k) => e.hasAttribute(k)).map((k) => ` ${k}="${e.getAttribute(k)}"`).join('');
      const cls = e.getAttribute('class');
      const c = cls ? ` class="${cls.split(/\s+/).slice(0, 3).join(' ')}"` : '';
      const t = e.tagName.toLowerCase();
      const kids = [...e.children];
      if (d >= p || !kids.length) return `<${t}${attrs}${c}>${kids.length ? `…(${kids.length})` : (e.textContent || '').trim().replace(/\s+/g, ' ').slice(0, 40)}</${t}>`;
      return `<${t}${attrs}${c}>\n${kids.map((k) => walk(k, d + 1)).join('\n')}\n</${t}>`;
    };
    return { total: all.length, html: walk(el, 1) };
  }, [String(opt.seletor), idx, prof]);
  await browser.close();
  if (!out.html) die(`seletor não encontrou nada (total ${out.total}).`);
  const max = Number(opt.max || 8000);
  const cut = out.html.length > max;
  console.log(`<!-- ${out.total} ocorrência(s); mostrando a ${idx}${cut ? `; cortado em ${max} de ${out.html.length} caracteres — use um seletor mais específico` : ''} -->`);
  console.log(cut ? out.html.slice(0, max) : out.html);
}

async function substituir() {
  if (!opt.arquivo || !opt.seletor || !opt.com) die('substituir exige --arquivo, --seletor e --com.');
  const frag = fs.readFileSync(String(opt.com), 'utf8');
  const modo = String(opt.modo || 'trocar');
  const { browser, page } = await openStatic(opt.arquivo);
  const r = await page.evaluate(([s, i, f, mo]) => {
    const all = document.querySelectorAll(s);
    const el = all[i];
    if (!el) return { ok: false, total: all.length };
    const pos = { trocar: null, antes: 'beforebegin', depois: 'afterend', dentro: null }[mo];
    if (mo === 'trocar') el.outerHTML = f;
    else if (mo === 'dentro') el.innerHTML = f;
    else el.insertAdjacentHTML(pos, f);
    return { ok: true, total: all.length };
  }, [String(opt.seletor), Number(opt.indice || 0), frag, modo]);
  if (!r.ok) { await browser.close(); die(`seletor não encontrou nada (total ${r.total}).`); }
  const html = await page.evaluate(serializeDoc);
  await browser.close();
  const destino = String(opt.saida || opt.arquivo);
  fs.writeFileSync(destino, html);
  console.log(JSON.stringify({ arquivo: destino, modo, ocorrencias: r.total, kb: Math.round(Buffer.byteLength(html) / 1024) }));
}

async function cssDe() {
  if (!opt.arquivo || !opt.para) die('css-de exige --arquivo (doador) e --para.');
  const doador = fs.readFileSync(String(opt.arquivo), 'utf8');
  const m = doador.match(/<style data-captura="css-do-app">([\s\S]*?)<\/style>/);
  if (!m) die('o doador não tem <style data-captura>.');
  let alvo = fs.readFileSync(String(opt.para), 'utf8');
  const tag = `<style data-captura="doador:${path.basename(String(opt.arquivo))}">`;
  if (alvo.includes(tag)) { console.log(JSON.stringify({ jaAnexado: true })); return; }
  alvo = alvo.replace('</head>', `${tag}${m[1]}</style></head>`);
  fs.writeFileSync(String(opt.para), alvo);
  console.log(JSON.stringify({ para: opt.para, cssKB: Math.round(m[1].length / 1024) }));
}

async function auth() {
  const { url, 'data-dir': dataDir } = opt;
  if (!url || !dataDir) die('auth exige --url e --data-dir.');
  const ap = authPaths(url, dataDir);
  const { chromium } = loadDeps(dataDir);
  if (opt.checar) {
    const browser = await launch(chromium, false);
    const context = await contextoComSessao(browser, url, ap);
    const page = await context.newPage();
    await page.goto(url, { waitUntil: 'domcontentloaded', timeout: 60000 });
    await assentar(page);
    const valida = !isLoginPage(page.url());
    await browser.close();
    console.log(JSON.stringify({ valida, arquivo: ap.state }));
    process.exit(valida ? 0 : 2);
  }
  // Sem credencial de dev (ou com --sem-interativo ausente e a credencial recusada), abre o
  // navegador visível para o dev entrar; a senha nunca passa pelo script nem pelo modelo.
  const interativo = !opt['sem-interativo'];
  if (!credenciaisDev() && !interativo) die('auth --sem-interativo precisa de --realm-json + --usuario, ou HARNESS_LOGIN_USER/HARNESS_LOGIN_PASSWORD.');
  // Força login novo sem apagar a sessão anterior: ela só é sobrescrita se o login der certo.
  const { browser, page, via } = await abrirAutenticado(chromium, url, ap, { interativo, ignorarSessao: true });
  const final = page.url();
  if (isLoginPage(final)) { await browser.close(); die(`o login não chegou ao app (parou em ${new URL(final).pathname}).`); }
  await browser.close();
  console.log(JSON.stringify({ ok: true, via, url: semHash(final), arquivo: ap.state }, null, 2));
}

// Prepara o Playwright MCP para entrar já logado, sem a senha passar pelo modelo:
// renova a sessão (sessão salva → login automático, nunca janela) e grava dois arquivos em
// caminho fixo, que a config do MCP aponta com --storage-state e --init-script:
//   mcp-storage-state.json  cookies + localStorage (inclui o SSO do Keycloak, que o proxy /auth
//                           do ng serve serve na mesma origem do app)
//   mcp-init.js             reinjeta o sessionStorage salvo, só na origem do app
// O MCP lê os dois ao abrir o navegador: rode isto ANTES da primeira ferramenta do MCP, ou
// feche o navegador do MCP (browser_close) e navegue de novo.
async function sessaoMcp() {
  const { url, 'data-dir': dataDir } = opt;
  if (!url) die('sessao-mcp exige --url.');
  const ap = authPaths(url, dataDir);
  const { chromium } = loadDeps(dataDir);
  const { browser, context, page, via } = await abrirAutenticado(chromium, url, ap, { interativo: false });
  await salvarSessao(context, page, url, ap);
  await browser.close();
  const state = path.join(ap.dir, 'mcp-storage-state.json');
  const init = path.join(ap.dir, 'mcp-init.js');
  fs.copyFileSync(ap.state, state);
  let saved = {};
  try { saved = JSON.parse(fs.readFileSync(ap.session, 'utf8')); } catch { /* sem sessionStorage */ }
  const origin = new URL(url).origin;
  fs.writeFileSync(init, `(() => {\n  const origin = ${JSON.stringify(origin)};\n  const data = ${JSON.stringify(saved)};\n` +
    '  if (location.origin !== origin) return;\n' +
    '  for (const [k, v] of Object.entries(data)) { try { if (sessionStorage.getItem(k) === null) sessionStorage.setItem(k, v); } catch {} }\n})();\n');
  try { fs.chmodSync(state, 0o600); fs.chmodSync(init, 0o600); } catch { /* Windows */ }
  console.log(JSON.stringify({ ok: true, via, origem: origin, storageState: state, initScript: init,
    chavesSessionStorage: Object.keys(saved).length }, null, 2));
}

// Fallback da verificação visual quando não há Playwright MCP (Codex, Antigravity) ou para
// medir em lote. --itens é um JSON: [{ "id": "D1", "seletor": "css", "indice": 0,
// "props": ["width","font-size"], "vars": ["--md-primary"] }]. Devolve, por item, quantos
// elementos o seletor achou, a caixa (x, y, w, h), o texto e o estilo computado das props;
// "vars" resolve variáveis CSS no :root. Nada é escrito no app.
async function medir() {
  const { url, itens, 'data-dir': dataDir } = opt;
  if (!url || !itens) die('medir exige --url e --itens.');
  let lista;
  try { lista = JSON.parse(fs.readFileSync(String(itens), 'utf8')); } catch (e) { die(`--itens ilegível: ${String(e.message).split('\n')[0]}`); }
  if (!Array.isArray(lista)) die('--itens deve ser uma lista.');
  const ap = authPaths(url, dataDir);
  const { chromium } = loadDeps(dataDir);
  const { browser, context, page, via } = await abrirAutenticado(chromium, url, ap, { interativo: false });
  if (opt.esperar) await page.waitForSelector(String(opt.esperar), { timeout: 30000 });
  if (opt.antes) {
    const mod = await import(new URL(`file://${path.resolve(String(opt.antes))}`).href);
    await (mod.default || mod)(page);
    await page.waitForLoadState('networkidle', { timeout: 30000 }).catch(() => {});
  }
  await page.evaluate(() => document.fonts && document.fonts.ready);
  await page.waitForTimeout(500);
  const res = await page.evaluate((items) => items.map((it) => {
    const all = document.querySelectorAll(it.seletor);
    const el = all[it.indice || 0];
    const vars = {};
    for (const v of it.vars || []) vars[v] = getComputedStyle(document.documentElement).getPropertyValue(v).trim();
    if (!el) return { id: it.id, seletor: it.seletor, encontrados: all.length, vars };
    const r = el.getBoundingClientRect();
    const cs = getComputedStyle(el);
    const estilo = {};
    for (const p of it.props || []) estilo[p] = cs.getPropertyValue(p);
    return { id: it.id, seletor: it.seletor, encontrados: all.length,
      caixa: { x: Math.round(r.x), y: Math.round(r.y), w: Math.round(r.width), h: Math.round(r.height) },
      texto: (el.textContent || '').trim().replace(/\s+/g, ' ').slice(0, 120), estilo, vars };
  }), lista);
  await salvarSessao(context, page, url, ap).catch(() => {});
  await browser.close();
  console.log(JSON.stringify({ url: semHash(page.url()), sessao: via, viewport: `${viewport.width}x${viewport.height}`, itens: res }, null, 1));
}

const run = { auth, capturar, screenshot, comparar, pecas, extrair, substituir, 'css-de': cssDe,
  'sessao-mcp': sessaoMcp, medir, conferir, lote }[cmd];
if (!run) die('comando: auth | capturar | lote | screenshot | comparar | conferir | pecas | extrair | substituir | css-de | sessao-mcp | medir');
run().catch((e) => die(e.stack || String(e)));  // die() oculta os segredos
