# EmojiPill

J'utilise toujours les mêmes 8 emojis, et ouvrir le sélecteur de macOS à chaque fois m'agaçait. Alors j'ai fait une petite « pilule » dans la barre des menus : un clic, je choisis, c'est copié. Un seul fichier Swift, rien à installer à côté.

*A tiny macOS menu-bar pill with your 8 favourite emojis: click, pick, it's copied. One Swift file, no dependencies.*

## Ce qu'elle fait

- Icône dans la barre des menus ; la pilule s'ouvre juste en dessous, avec une animation douce.
- **Clic** sur un emoji, ou **touches 1 à 8** : l'emoji est copié dans le presse-papiers.
- **Mode crayon** : remplace la liste par tes propres emojis (tape-les, valide). La liste est gardée.
- **Échap** ferme la pilule.
- Option « Ouvrir à l'ouverture de session ».
- Thème clair et sombre.

## Installer

Il faut macOS 13 ou plus récent et les outils de ligne de commande de Xcode (`xcode-select --install`).

```bash
git clone https://github.com/alxhe3-lab/EmojiPill.git
cd EmojiPill
./build.sh
```

`build.sh` compile l'app, la signe localement, l'installe dans `/Applications` (ou `~/Applications`) et la lance. Pour ne pas la lancer : `NO_OPEN=1 ./build.sh`.

## Licence

MIT.
