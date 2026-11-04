// Ouvre la fenêtre que GhostDev pilote. Lancé depuis le dossier du projet :
//   node "<plugin>/outils/navigateur/ouvrir.mjs" [adresse]
// La première fois dans un projet : installe Playwright dans .machine-a-app/navigateur/ (sans navigateur à
// télécharger, il se sert de Chrome, ou d'Edge sur Windows) et ajoute ce dossier à .gitignore : le profil garde la
// session de la personne, il ne part jamais dans git. La fenêtre reste ouverte en fond, pas.mjs s'y branche.
// Déjà ouverte : elle va seulement à l'adresse donnée.
import { spawn, spawnSync } from 'node:child_process';
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const port = process.env.GHOSTDEV_NAVIGATEUR_PORT || '9333';
const adresse = process.argv[2];
const ici = path.dirname(fileURLToPath(import.meta.url));
const dossier = path.join(process.cwd(), '.machine-a-app', 'navigateur');

async function ouverte() {
  try { return (await fetch(`http://127.0.0.1:${port}/json/version`)).ok; } catch { return false; }
}

// Les scripts sont recopiés à chaque ouverture : une mise à jour du plugin arrive dans le projet.
fs.mkdirSync(dossier, { recursive: true });
for (const f of ['navigateur.mjs', 'pas.mjs']) fs.copyFileSync(path.join(ici, f), path.join(dossier, f));

if (await ouverte()) {
  if (adresse) spawnSync(process.execPath, [path.join(dossier, 'pas.mjs'), 'aller', adresse], { stdio: 'inherit' });
  else console.log('déjà ouverte');
  process.exit(0);
}

if (!fs.existsSync(path.join(dossier, 'node_modules', 'playwright'))) {
  fs.writeFileSync(path.join(dossier, 'package.json'), JSON.stringify({ private: true, dependencies: { playwright: '1.56.1' } }, null, 2));
  console.log('installation de Playwright, une fois par projet…');
  const r = spawnSync('npm', ['install', '--no-audit', '--no-fund', '--loglevel=error'], {
    cwd: dossier, stdio: 'inherit', shell: process.platform === 'win32',
    env: { ...process.env, PLAYWRIGHT_SKIP_BROWSER_DOWNLOAD: '1' },
  });
  if (r.status !== 0) { console.log('npm install a échoué'); process.exit(1); }
}

const gitignore = path.join(process.cwd(), '.gitignore');
const ligne = '.machine-a-app/navigateur/';
const actuel = fs.existsSync(gitignore) ? fs.readFileSync(gitignore, 'utf8') : '';
if (!actuel.split(/\r?\n/).includes(ligne)) {
  fs.appendFileSync(gitignore, (actuel && !actuel.endsWith('\n') ? '\n' : '') + ligne + '\n');
}

const journal = fs.openSync(path.join(dossier, 'fenetre.log'), 'a');
spawn(process.execPath, [path.join(dossier, 'navigateur.mjs'), adresse || 'about:blank'], {
  cwd: dossier, detached: true, stdio: ['ignore', journal, journal], windowsHide: true,
}).unref();
for (let i = 0; i < 60; i++) {
  if (await ouverte()) { console.log('ouverte', adresse || ''); process.exit(0); }
  await new Promise(r => setTimeout(r, 500));
}
console.log('la fenêtre ne répond pas, voir .machine-a-app/navigateur/fenetre.log');
process.exit(1);
