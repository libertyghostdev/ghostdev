// La fenêtre que GhostDev pilote : un Chrome à part, avec son propre profil, gardé ouvert. La personne s'y connecte
// elle-même ; pas.mjs s'y branche par le port. Lancé par ouvrir.mjs, qui le recopie dans .machine-a-app/navigateur/.
// Un Chrome lancé tel quel, jamais par Playwright : les réglages d'automatisation de Playwright font refuser la
// connexion par Google (« Ce navigateur ou cette application ne sont peut-être pas sécurisés », vu le 22/10/2026).
import { spawn } from 'node:child_process';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const ici = path.dirname(fileURLToPath(import.meta.url));
const port = process.env.GHOSTDEV_NAVIGATEUR_PORT || '9333';
const adresse = process.argv[2] || 'about:blank';

// Chrome d'abord ; Edge est toujours là sur Windows.
const pf = [process.env.PROGRAMFILES, process.env['PROGRAMFILES(X86)'], process.env.LOCALAPPDATA].filter(Boolean);
const candidats = {
  darwin: ['/Applications/Google Chrome.app/Contents/MacOS/Google Chrome',
    path.join(os.homedir(), 'Applications/Google Chrome.app/Contents/MacOS/Google Chrome'),
    '/Applications/Microsoft Edge.app/Contents/MacOS/Microsoft Edge'],
  win32: [...pf.map(d => path.join(d, 'Google', 'Chrome', 'Application', 'chrome.exe')),
    ...pf.map(d => path.join(d, 'Microsoft', 'Edge', 'Application', 'msedge.exe'))],
  linux: ['/usr/bin/google-chrome', '/usr/bin/google-chrome-stable', '/usr/bin/chromium', '/usr/bin/microsoft-edge'],
}[process.platform] || [];
const chrome = candidats.find(c => fs.existsSync(c));
if (!chrome) { console.log('ni Chrome ni Edge : il faut installer Google Chrome'); process.exit(1); }

const args = [
  `--remote-debugging-port=${port}`, `--user-data-dir=${path.join(ici, 'profil')}`,
  '--no-first-run', '--no-default-browser-check', '--window-size=1280,900',
];
if (process.env.GHOSTDEV_NAVIGATEUR_INVISIBLE) args.push('--headless=new');
const fenetre = spawn(chrome, [...args, adresse], { stdio: 'ignore' });
console.log('ouverte', adresse, '(' + path.basename(chrome) + ')');
fenetre.on('exit', () => { console.log('fermée'); process.exit(0); });
