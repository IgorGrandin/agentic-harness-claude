#!/usr/bin/env node
// PreToolUse em Read: bloqueia a leitura inteira de capturas de tela do mockup.
// Uma captura carrega todo o CSS do app (centenas de KB): lida inteira, custa dezenas de
// milhares de tokens e fica no contexto pelo resto da sessão. O caminho certo são os
// comandos pecas / extrair / substituir do capturar-tela.mjs (skill mockup-task).
// Origem: harness de Arthur Sena (github.com/ASsena/Harness-claude), adaptado.

import fs from 'node:fs';

let input;
try { input = JSON.parse(fs.readFileSync(0, 'utf8')); } catch { process.exit(0); }
const file = input?.tool_input?.file_path;
if (!file || !/\.html?$/i.test(file)) process.exit(0);

let head = '';
try {
  const fd = fs.openSync(file, 'r');
  // O <meta name="captura"> fica no <head>, depois de um <html> que pode ter atributos longos.
  const buf = Buffer.alloc(16384);
  const n = fs.readSync(fd, buf, 0, buf.length, 0);
  fs.closeSync(fd);
  head = buf.subarray(0, n).toString('utf8');
} catch { process.exit(0); }

if (!/<meta name="captura"|data-captura="css-do-app"/.test(head)) process.exit(0);

let kb = 0;
try { kb = Math.round(fs.statSync(file).size / 1024); } catch { /* tamanho desconhecido */ }
const s = '"$env:USERPROFILE/.claude/skills/mockup-task/scripts/capturar-tela.mjs"';
process.stdout.write(JSON.stringify({
  hookSpecificOutput: {
    hookEventName: 'PreToolUse',
    permissionDecision: 'deny',
    permissionDecisionReason:
      `Este arquivo é uma captura de tela do mockup (${kb} KB, com todo o CSS do app). Não leia inteiro. Use:\n` +
      `- node ${s} pecas --arquivo "<html>"  → componentes da tela e um seletor de cada\n` +
      `- node ${s} extrair --arquivo "<html>" --seletor "<css>"  → só o trecho que importa\n` +
      `- node ${s} substituir --arquivo "<html>" --seletor "<css>" --com <fragmento.html> [--modo trocar|antes|depois|dentro]`,
  },
}));
process.exit(0);
