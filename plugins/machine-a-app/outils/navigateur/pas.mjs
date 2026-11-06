// Un geste dans la fenêtre ouverte par ouvrir.mjs. Lancé depuis le dossier du projet :
//   node .machine-a-app/navigateur/pas.mjs <action> …
// Lire : url | texte [n] | champs | capture <fichier.png>
// Agir : aller <adresse> | clic <sélecteur> | clics <sél1> <sél2> … | souris <x> <y> | remplir <sélecteur> <valeur>
//        cocher <sélecteur> | choisir <sélecteur> <option> | touche <touche> | attendre <ms> | eval "<js>"
//        telecharger <sélecteur> <fichier> : clique et range le fichier reçu là (une clé .p8 ne se télécharge qu'une fois)
//        deposer <sélecteur> <fichier> : envoie un fichier par un champ fichier ou un bouton « Importer », sans la
//        fenêtre de choix du Mac (un AAB, une vidéo, une capture d'écran)
// Les sélecteurs sont ceux de Playwright : 'text="Continue"', 'role=button[name="Save"]', '[aria-label="…"]',
// 'dialog[open] >> text=Annuler'. « clics » enchaîne dans la même connexion : un menu ne se referme pas entre deux.
// La capture est à l'échelle de la page : ses pixels sont les coordonnées de « souris ».
import { chromium } from 'playwright';
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const [action, a, b] = process.argv.slice(2);
const navigateur = await chromium.connectOverCDP(`http://127.0.0.1:${process.env.GHOSTDEV_NAVIGATEUR_PORT || '9333'}`);
// Les pages internes de Chrome (la bulle « Se connecter à Chrome » après une connexion Google) ne comptent pas.
const toutes = navigateur.contexts()[0].pages();
const pages = toutes.filter(p => !p.url().startsWith('chrome://'));
const page = pages[pages.length - 1] || toutes[toutes.length - 1];
page.setDefaultTimeout(15000);

// Les champs et les boutons visibles, avec leur nom : de quoi choisir le sélecteur sans rien toucher.
const champs = () => page.evaluate(() => {
  const vu = e => { const r = e.getBoundingClientRect(); return r.width > 0 && r.height > 0; };
  const nom = e => ((e.labels && e.labels[0] && e.labels[0].innerText) || e.getAttribute('aria-label') || e.placeholder || e.name || '').trim();
  const out = [];
  for (const e of document.querySelectorAll('input, select, textarea')) {
    if (!vu(e) || e.type === 'hidden') continue;
    let l = `[${e.tagName.toLowerCase()}${e.type ? ':' + e.type : ''}] ${nom(e).slice(0, 80)}`;
    if (e.tagName === 'SELECT') l += ' = ' + [...e.options].map(o => o.text.trim()).slice(0, 25).join(' | ');
    if (e.checked) l += ' (coché)';
    if (e.disabled) l += ' (grisé)';
    out.push(l);
  }
  for (const e of document.querySelectorAll('button, [role=button], [aria-label]:not(input, select, textarea)')) {
    if (!vu(e)) continue;
    const t = (e.innerText || e.getAttribute('aria-label') || '').trim().replace(/\s+/g, ' ');
    const grise = e.disabled || e.getAttribute('aria-disabled') === 'true';
    if (t) out.push(`[${e.matches('button, [role=button]') ? 'bouton' : 'icône'}] ${t.slice(0, 60)}${grise ? ' (grisé)' : ''}`);
  }
  return [...new Set(out)].join('\n');
});

switch (action) {
  case 'url': console.log(page.url(), '|', await page.title()); break;
  case 'texte': console.log((await page.innerText('body')).slice(0, Number(a) || 4000)); break;
  case 'champs': console.log(page.url(), '\n' + await champs()); break;
  case 'capture': await page.screenshot({ path: a, scale: 'css' }); console.log('capture', a); break;
  case 'aller': await page.goto(a, { waitUntil: 'domcontentloaded' }); console.log(page.url()); break;
  case 'clic': await page.locator(a).first().click(); console.log('clic', a); break;
  case 'clics':
    for (const s of process.argv.slice(3)) { await page.locator(s).first().click(); console.log('clic', s); await page.waitForTimeout(1000); }
    break;
  case 'souris': await page.mouse.click(Number(a), Number(b)); console.log('clic à', a, b); break;
  case 'remplir': await page.locator(a).first().fill(b); console.log('rempli', a); break;
  case 'cocher': await page.locator(a).first().check(); console.log('coché', a); break;
  case 'choisir': await page.locator(a).first().selectOption({ label: b }); console.log('choisi', b); break;
  case 'touche': await page.keyboard.press(a); console.log('touche', a); break;
  case 'telecharger': {
    // Chrome dépose le fichier dans telechargements/ : le dossier est dit juste avant le clic, sinon il part
    // dans un dossier temporaire de Playwright, effacé quand ce script se débranche.
    const recus = path.join(path.dirname(fileURLToPath(import.meta.url)), 'telechargements');
    fs.mkdirSync(recus, { recursive: true });
    const cdp = await navigateur.newBrowserCDPSession();
    await cdp.send('Browser.setDownloadBehavior', { behavior: 'allow', downloadPath: recus });
    const debut = Date.now();
    await page.locator(a).first().click();
    let nom;
    for (let i = 0; i < 60 && !nom; i++) {
      await page.waitForTimeout(500);
      nom = (fs.existsSync(recus) ? fs.readdirSync(recus) : [])
        .find(f => !f.endsWith('.crdownload') && fs.statSync(path.join(recus, f)).mtimeMs >= debut - 1000);
    }
    if (!nom) { console.log('aucun fichier reçu en 30 secondes'); process.exit(1); }
    fs.mkdirSync(path.dirname(path.resolve(b)), { recursive: true });
    fs.copyFileSync(path.join(recus, nom), b);
    fs.unlinkSync(path.join(recus, nom));
    console.log('téléchargé', nom, '→', b);
    break;
  }
  case 'deposer': {
    // La fenêtre de choix de fichier du Mac ne se pilote pas : un champ fichier reçoit le fichier directement, un
    // bouton qui ouvre le choix le reçoit par l'événement « filechooser ». Le fichier passe par la connexion de
    // pilotage : 46 Mo prennent plus de 15 s, d'où le délai long.
    const cible = page.locator(a).first();
    const fichier = path.resolve(b);
    if (await cible.evaluate(e => e.tagName === 'INPUT' && e.type === 'file')) {
      await cible.setInputFiles(fichier, { timeout: 300000 });
    } else {
      const [choix] = await Promise.all([page.waitForEvent('filechooser'), cible.click()]);
      await choix.setFiles(fichier, { timeout: 300000 });
    }
    console.log('déposé', fichier);
    break;
  }
  case 'attendre': await page.waitForTimeout(Number(a) || 1000); break;
  case 'eval': console.log(JSON.stringify(await page.evaluate(a), null, 1)); break;
  default: console.log('action inconnue :', action);
}
process.exit(0); // se débranche sans rien fermer : la fenêtre reste ouverte
