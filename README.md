# Elm Lab — un pilote pour comprendre les tests

Une petite boutique en **Elm**, accompagnée d'une API locale Node et de tests exécutables. L'objectif : montrer concrètement ce que le langage apporte aux tests unitaires et à l'intégration, avec des erreurs réseau que l'on peut provoquer depuis l'interface.

Aucun compte, aucune base de données, aucun paiement. Les commandes sont validées puis oubliées. L'interface et les explications sont en français.

## Démarrer

Prérequis : **Node.js 22.12+** (Node 24 recommandé) et npm. Le compilateur Elm est installé dans le projet ; aucune installation globale n'est nécessaire.

```sh
npm ci
npx playwright install chromium --only-shell
npm run dev
```

Ouvrir **http://127.0.0.1:5173**. Le terminal indique le port choisi si 5173 est occupé. La première compilation télécharge les paquets Elm dans `.cache/elm` ; une connexion Internet est nécessaire à l'installation. Les changements des fichiers `.elm` recompilent l'application et rechargent la page : l'état de la démo est alors réinitialisé.

```sh
npm run test:elm                         # Tests métier, génératifs, JSON et intégration Elm
npm run test:elm -- --seed 42 --fuzz 1000 # 1 000 cas par propriété, exécution reproductible
npm run test:watch                       # Tests Elm en continu
npm run test:e2e                         # Chromium + vraie API HTTP locale
npm run test:e2e:ui                      # Explorateur interactif Playwright
npm run check                           # Format + tests Elm + compilation + tests navigateur
npm run build                           # Compilation Elm optimisée + distribution Vite
npm run preview                         # Tester dist/ avec l'API de démonstration
```

`test:e2e` construit automatiquement l'application et démarre un serveur isolé sur **4173**. Ce port doit être libre ; le serveur de développement peut rester ouvert sur 5173. Les tests ne réutilisent pas un serveur déjà lancé : ils vérifient la version construite pour cette exécution.

## Démonstration en dix minutes

1. Ajouter trois **Sacs quotidiens** : sous-total **126,00 €**, remise **12,60 €**, livraison offerte, total **113,40 €**. Observer les transitions sous la boutique.
2. Retirer un sac : sous-total **84,00 €**, plus de remise, livraison **4,90 €**, total **88,90 €**. Le calcul ne dépend ni du DOM ni d'un serveur.
3. Saisir `demo@example.com` puis confirmer. Une véritable requête POST part vers l'API ; le serveur recalcule le montant. La confirmation affiche sa référence et le panier se vide.
4. Ajouter un article, sélectionner **Erreur serveur · HTTP 503**, puis confirmer. L'erreur s'affiche et le panier reste intact. Revenir à **Réponse normale** et confirmer de nouveau.
5. Sélectionner **JSON invalide · catalogue**, puis **Recharger le catalogue**. Le serveur renvoie un HTTP 200 avec un prix texte : le décodeur refuse le contenu. Aucune donnée incohérente n'entre dans le modèle. Revenir à la réponse normale puis recharger.
6. Exécuter `npm run check`. Les cartes de l'interface expliquent les suites ; elles ne représentent pas un tableau de résultats en direct.

L'option de scénario affecte les **prochaines requêtes**. L'option JSON invalide s'applique seulement au catalogue. Les scénarios d'erreur sont des fonctionnalités de cette API pédagogique, pas un mécanisme destiné à la production.

## Ce que chaque niveau prouve

| Niveau | Fichier | Ce qui est vérifié | Ce qui n'est pas exécuté |
| --- | --- | --- | --- |
| Unitaire | `tests/CartTest.elm` | Total, seuil à 100 €, arrondi, retrait, limite de 99 unités | DOM, réseau |
| Génératif / fuzz | `tests/CartTest.elm` | Trois propriétés sur des valeurs générées : réversibilité dans le domaine testé, décomposition comptable, indépendance de l'ordre | Le monde entier : les générateurs ont un domaine borné |
| Contrat JSON | `tests/ApiTest.elm` | Décodage, données invalides, forme de la commande | Transport HTTP |
| Intégration Elm en mémoire | `tests/IntegrationTest.elm` | Vue → événement → message → update → nouvelle vue ; effets attendus, erreurs et double soumission | Navigateur et exécution des effets HTTP |
| Intégration HTTP / parcours E2E | `e2e/checkout.spec.js` | Application compilée + navigateur + vraie API, commande, reprise, JSON invalide, contrôles serveur, mobile | Paiement et base de données, absents du pilote |

Les suites E2E n'interceptent pas le réseau avec `page.route` : elles utilisent l'API locale réelle. Deux scénarios interrogent directement cette API avec le client HTTP de Playwright pour vérifier qu'elle refuse des commandes invalides et ignore les prix falsifiés du client.

### 1. Les fonctions pures rendent les tests directs

`Cart.totals` reçoit un panier et retourne des montants. Pas d'horloge, de variable globale, de dépendance à remplacer ou de contexte à initialiser.

```elm
Cart.empty
    |> Cart.add { id = "bundle", name = "Ensemble", price = 10000 }
    |> Cart.totals
    |> Expect.equal
        { subtotal = 10000, discount = 1000, shipping = 0, total = 9000 }
```

Les montants sont exprimés en **centimes entiers**. La remise est de 10 %, arrondie au centime inférieur, et s'applique à partir de 10 000 centimes de sous-total. À ce même seuil, la livraison est offerte. Sinon, elle coûte 490 centimes ; un panier vide ne facture rien.

Le constructeur de `Cart` est privé. Ses opérations assurent des quantités entre 1 et 99 ; retirer la dernière unité supprime la ligne. Les produits externes passent par un décodeur qui borne leurs prix entre 0 et 1 000 000 centimes. Le type alias `Product` reste constructible dans le code Elm : le compilateur, à lui seul, ne garantit pas un prix positif.

### 2. Les tests génératifs expriment une propriété

Au lieu d'écrire seulement « trois articles donnent ce montant », on vérifie par exemple que **l'ordre d'ajout des produits ne change pas le total**.

`Fuzz` fournit les entrées. En cas d'échec, elm-test cherche un contre-exemple plus simple et donne la graine permettant de reproduire l'exécution. Les trois propriétés du projet peuvent être exécutées chacune sur 1 000 cas avec `--fuzz 1000`.

La propriété « ajouter puis retirer conserve le panier » utilise des quantités de 1 à 50, donc reste sous la limite de 99. Elle ne prétend pas être vraie à saturation : ce domaine fait partie du test.

### 3. L'architecture rend l'intégration Elm déterministe

```text
              ┌──────────────────────────┐
Événement ──► Msg ──► App.update ──► Model ──► App.view
                         │
                         └──► Effect ──► Main ──► HTTP ──► Msg
              └──────────────────────────┘
```

```elm
update : Msg -> Model -> ( Model, Effect )
```

`Effect` est un type applicatif : `None`, `LoadCatalog` ou `SubmitOrder`. Cette petite séparation est un **choix du pilote**, pas une bibliothèque ni une obligation d'Elm. Elle rend les décisions d'effet inspectables dans les tests. `Main` transforme ensuite ces descriptions en `Cmd Msg` et exécute le HTTP.

Le test d'intégration simule un clic sur le véritable `Html Msg`, récupère le message produit, appelle `update`, puis vérifie le nouveau HTML. Il ne se limite pas à vérifier une fonction appelée à la main. Le test du formulaire vérifie aussi la saisie et l'effet de commande attendu.

Une description d'effet correcte ne suffit pas à prouver qu'une requête a été envoyée : c'est précisément le rôle des tests navigateur qui couvrent `Main`, le transport et le serveur.

### 4. Les types éliminent certains scénarios impossibles

```elm
type Checkout
    = Editing
    | Sending
    | Confirmed Receipt
    | Rejected String
```

Le statut ne peut pas être simultanément `Sending` et `Confirmed`. Une confirmation transporte nécessairement un `Receipt`. Les expressions `case` doivent traiter les variantes : un oubli est signalé à la compilation. Les erreurs HTTP sont des `Result`, et les données JSON sont vérifiées à l'entrée.

Les valeurs sont immuables. Une transition ne modifie donc pas un ancien modèle réutilisé par un autre test. On réduit ainsi les problèmes de nettoyage d'état entre tests.

## Visite du code

```text
src/
  Cart.elm           Règles du panier, sans dépendance UI ou HTTP
  Api.elm            Décodeurs JSON et encodage des commandes
  App.elm            Modèle, messages, transitions, effets décrits et vues
  Main.elm           Browser.element et interprétation des effets HTTP
  main.js            Montage de l'application Elm uniquement
  style.css          Présentation et adaptation mobile
api/
  server.mjs         API de démonstration, validation et recalcul serveur
  (montée par vite.config.js en développement et en preview)
tests/
  CartTest.elm       Règles métier et propriétés génératives
  ApiTest.elm        Contrats JSON
  IntegrationTest.elm  Intégration des modules Elm en mémoire
e2e/
  checkout.spec.js   Parcours navigateur et contrat HTTP réel
.github/workflows/
  ci.yml            Vérification automatisée sur GitHub Actions
```

À lire dans cet ordre : `Cart.elm`, `CartTest.elm`, `App.update`, `IntegrationTest.elm`, `Main.elm`, puis `checkout.spec.js`.

## Trois expériences pour voir la valeur des tests

Les modifications suivantes sont volontaires et **à annuler après chaque expérience**.

1. **Introduire un bug métier.** Dans `Cart.elm`, remplacer `subtotal // 10` par `subtotal // 20`. Lancer `npm run test:elm`. Les tests du seuil et de l'arrondi échouent : le compilateur ne peut pas deviner la remise métier attendue.
2. **Oublier un effet.** Dans `Main.run`, remplacer la branche `SubmitOrder` par `Cmd.none`. Les tests Elm peuvent toujours passer, car la décision applicative est correcte. `npm run test:e2e` échoue : la commande n'arrive jamais au serveur. C'est la complémentarité des niveaux.
3. **Oublier un cas.** Retirer la branche `Failed` de `catalogView` dans `App.elm`. `npm run build:elm` échoue avant même les tests : le compilateur signale le cas manquant.

## Avantages et limites, sans promesse magique

- **Moins de préparation de tests** : les fonctions pures et les modèles immuables se testent directement. Ce principe existe aussi ailleurs ; Elm l'impose plus largement dans le code applicatif.
- **Moins de tests défensifs sur les types** : les unions et le traitement exhaustif des cas remplacent certaines vérifications de valeurs absentes ou de combinaisons incohérentes.
- **Des contrats externes explicites** : un décodeur repère un changement d'API ; il faut encore tester le comportement affiché en cas d'échec.
- **Des tests rapides en mémoire** : une grande partie du comportement se vérifie sans navigateur. Aucun benchmark comparatif avec un autre langage n'est revendiqué ici.
- **Un E2E toujours nécessaire** : réseau, JavaScript d'amorçage, serveur, CSS et interaction réelle restent en dehors de la preuve des tests unitaires.
- **Un coût d'apprentissage** : types algébriques, fonctions pures, décodeurs et architecture à messages demandent une prise en main. L'interopérabilité JavaScript via les ports demande aussi ses propres contrats et tests ; aucun port n'est nécessaire dans ce pilote.

Le pilote n'est pas une boutique de production : pas de persistance, d'authentification, de gestion de stock ni d'idempotence serveur. La double soumission est bloquée côté état Elm pendant une requête, sans prétendre garantir un traitement unique en cas de retry réseau. Les tests mobiles vérifient un parcours et l'absence de débordement horizontal, pas un audit complet d'accessibilité ou tous les navigateurs.

Les polices de présentation sont demandées à Google Fonts avec une police système de secours ; les fonctionnalités de l'application ne dépendent pas de ce service.

## Outils et reproductibilité

- Elm **0.19.1** et elm-test **0.19.1-revision17**, versions volontairement fixées et compatibles.
- `elm-explorations/test` **2.2.1** ; fichiers de versions `elm.json` et `package-lock.json` conservés.
- Playwright et Vite sont installés localement par npm.
- La CI exécute `npm run check` et publie le rapport Playwright en cas d'échec.
- Après `test:e2e`, `npx playwright show-report` ouvre le rapport ; les captures desktop/mobile se trouvent dans `test-results/`. Une trace est conservée pour les tests en échec.

Si un navigateur compatible est déjà installé dans un emplacement personnalisé, on peut indiquer `PLAYWRIGHT_CHROMIUM_EXECUTABLE_PATH=/chemin/vers/chromium npm run test:e2e`. Sinon, garder l'installation standard ci-dessus. Sur Linux, utiliser `npx playwright install --with-deps chromium --only-shell` pour installer aussi les bibliothèques système nécessaires.

`npm run build` crée `dist/`. Une publication purement statique de ce dossier ne suffit pas pour les commandes : il faut également fournir les routes `/api/products` et `/api/orders`. `npm run preview` les fournit localement via Vite.

## Sources pour approfondir

- [The Elm Architecture — guide officiel](https://guide.elm-lang.org/architecture/) : séparation Model, Update, View.
- [HTTP et Result — guide officiel](https://guide.elm-lang.org/effects/http) : description des commandes et gestion des succès/échecs.
- [elm-explorations/test](https://package.elm-lang.org/packages/elm-explorations/test/2.2.1/) : assertions, générateurs et tests HTML.
- [Code source de Test.Html.Event](https://github.com/elm-explorations/test/blob/2.2.1/src/Test/Html/Event.elm) : simulation des événements utilisée dans le pilote.
- [Serveur de test Playwright](https://playwright.dev/docs/test-webserver) : démarrage isolé de l'application pendant les tests.

## Expériences de solidité des preuves

```sh
npm run test:evidence
```

Cette commande crée quatre copies isolées : la référence, une remise erronée,
le rejet des prix négatifs supprimé et l'envoi HTTP de commande supprimé.
Chaque variante doit compiler, puis les 27 tests Elm s'exécutent avec la graine
42 et 1 000 cas par propriété. `src/` et `tests/` d'origine restent inchangés.

Le rapport `output/evidence/latest.json` contient les résultats détaillés,
l'empreinte des fichiers et la date d'exécution. Les journaux sont dans le même dossier.
Le code de sortie vaut **1 si une mutation n'est pas détectée**, **2 en cas de
problème d'exécution**, et **0 si toutes ces mutations ciblées sont détectées**.
Ce contrôle est volontairement séparé de `npm run check`.

Avec les tests actuels, supprimer l'envoi HTTP dans `Main` laisse les tests Elm
au vert : ils contrôlent la décision de soumettre une commande, pas son transport.
C'est une lacune observée, pas une régression introduite dans l'application.
Trois mutations choisies ne mesurent pas la couverture de mutation globale et
ne prouvent ni l'absence de bugs ni la possibilité de supprimer tous les E2E.
