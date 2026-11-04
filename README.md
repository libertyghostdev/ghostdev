# GhostDev

GhostDev est un plugin pour Claude, fait par Anas (Liberty Tech). Il construit ton application, une app de téléphone
ou une plateforme web, de l'idée jusqu'à sa publication, sans que tu saches coder.

Site : [libertyghostdev.fr](https://libertyghostdev.fr)

## L'ajouter à Claude

1. Ouvre Claude, sur l'app de bureau ou sur claude.ai.
2. Va dans **Personnaliser**, puis **Plugins**, puis **Ajouter**, puis **Ajouter une place de marché**.
3. Colle `libertyghostdev/ghostdev` et valide.
4. Choisis **GhostDev** dans la liste, puis **Ajouter**.

Ensuite, ouvre le dossier de ton projet dans l'onglet Code de Claude et écris « lance GhostDev ».

Déjà dans Claude Code ? Écris cette ligne dans la conversation :

```
/plugin install machine-a-app --marketplace libertyghostdev/ghostdev
```

Les nouvelles versions arrivent toutes seules.

## La licence

GhostDev demande une clé de licence, achetée sur [libertyghostdev.fr](https://libertyghostdev.fr). Sans elle, le
plugin s'installe, mais le serveur ne lui donne pas la méthode d'Anas.

## Ce que le plugin envoie

Le plugin se connecte au serveur GhostDev (`ghostdev.libertytechlab.com`), qui lui donne la méthode d'Anas, étape
par étape. Le serveur reçoit :

- ta clé de licence, pour savoir qui appelle ;
- le nom de l'outil appelé, l'heure, la version du plugin ;
- à chaque message, le type de la demande et une reformulation courte, sans nom ni donnée personnelle ;
- quand tu écris toi-même « SOS », ce message et tes trois messages d'avant, pour qu'Anas t'aide.

La mémoire de ton projet (`.machine-a-app/memoire/`) reste sur ton ordinateur. Les clés de tes services et tes mots
de passe ne partent jamais vers le serveur.

Le détail est écrit dans [`plugins/machine-a-app/skills/ghostdev/SKILL.md`](plugins/machine-a-app/skills/ghostdev/SKILL.md).
