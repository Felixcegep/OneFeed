# OneFeed — guide de style et de parcours

Mis à jour le 18 septembre 2026. Surfaces, typo, chrome, captures. Complément de [`UI_UX_IMPROVEMENT_PLAN.md`](UI_UX_IMPROVEMENT_PLAN.md). Lag et SwiftData : [`PERFORMANCE.md`](PERFORMANCE.md). Index : [`agent.md`](agent.md).

## 1. Intention

« One article at a time. » Une interface de lecture calme, pas un tableau de bord de consommation. Garder les surfaces chaudes, les titres éditoriaux serif et les contrôles natifs. La clarté doit venir de la hiérarchie, des marges et des limites des objets, pas de décorations supplémentaires.

Le README exclut les compteurs et les catégories, alors que le code actuel expose des totaux et des dossiers. Cette divergence est une décision produit à résoudre séparément : ce chantier de style ne supprime ni données ni fonctions.

## 2. Fondations

Source de vérité : `OneFeed/DesignSystem/OneFeedTheme.swift` et les couleurs adaptatives de `OneFeed/Platform/PlatformSupport.swift`.

| Rôle | Token | Usage |
| --- | --- | --- |
| Fond de page | `plaster` | Toile derrière les groupes |
| Contenu | `paper` | Articles et sections natives |
| Appui | `warm1` | Retour tactile visuel temporaire |
| Texte principal | `ink` | Titres et en-têtes |
| Texte secondaire | `graphite` | Source, date, durée, explications |
| Contour | `sand` | Trait de 1 point, pas une ombre |
| Accent | `accent` | Actions et sélection, pas les titres |
| Texte d'erreur | `error` / `oneFeedErrorText` | Rouge adaptatif, accompagné d'un message explicite |

Utiliser les couleurs adaptatives, jamais recopier leurs valeurs claires dans une nouvelle vue. Le contraste des états sombres et des actions colorées reste à mesurer ; l'existence d'un token n'est pas une garantie d'accessibilité.

Contraste du texte d'erreur calculé à partir des composantes sRGB le 18 septembre : papier clair 5,98:1, plâtre clair 5,75:1, papier sombre 7,43:1, plâtre sombre 8,37:1. Ces mesures concernent le texte opaque sur ces fonds précis, pas toutes les combinaisons possibles.

### Typographie implémentée sur les articles

- Article ordinaire : `.headline`, source `.subheadline`, détails `.caption`.
- Article principal : `.title2` serif, extrait `.body` serif, détails `.caption`.
- En-tête de section : `.subheadline` semibold, couleur `ink`.
- Légende éditoriale : `.caption` semibold, capitales légèrement espacées, couleur `graphite` par défaut.
- Ne pas augmenter tous les textes au même poids. Le titre, la source et les détails ont trois niveaux distincts.
- Autoriser les retours à la ligne ; aux tailles d'accessibilité, ne pas plafonner le titre ni l'extrait principal.

### Espacements et surfaces

- Carte : rayon continu de 12 points, contour de 1 point, aucune ombre ajoutée.
- Carte Queue ordinaire : marge intérieure de 16 points.
- Carte principale : texte rentré de 20 points, marge verticale de 16 points, intervalle image/texte de 16 points.
- Carte dans une liste groupée : retrait horizontal de 12 points et vertical de 8 points pour éviter que le masque natif coupe le contour. Contour complet confirmé sur les nouvelles captures Today et Queue à 11:07.
- Ligne compacte : marges natives 16 horizontal / 12 vertical et séparateur inférieur `sand`.
- En-tête : marge supérieure de 4 points et inférieure de 8 points ; l'espacement entre sections reste fourni par la liste.

## 3. Choisir le bon composant

| Contexte | Composant | Règle |
| --- | --- | --- |
| Pièce principale Today ou Queue | `FeaturedStory` + `ArticleCardButtonStyle` | Même surface, mêmes marges ; titre serif |
| Pièce conservée dans Queue | `QueueArticleRow` + `ArticleCardButtonStyle` | Une pièce = une carte identifiable |
| Collection, historique, autres articles Today | `ArticleRow` + `articleListRow()` | Liste compacte avec séparateurs, pas une pile de cartes imbriquées |
| Dossiers et navigation | Composants de répertoire existants | Ne pas appliquer le style carte aux contrôles de navigation |

Les miniatures des lignes sont à droite, 64 × 64 points, alignées en haut. Leur absence ne doit pas laisser une colonne vide. Aux tailles d'accessibilité, elles sont omises pour laisser de la place au texte. Les images principales gardent actuellement leur hauteur de 248 points ; leur rendu avec images réelles reste à vérifier.

L'attribution utilise le nom de l'abonnement, puis le domaine du lien, puis « Saved link » : ne pas afficher « Source » comme faux contenu. La première section de Queue est nommée « Recently saved », conformément au tri existant par date de sauvegarde ; aucun ordre de lecture ou tri métier n'a été changé.

Les réglages de lecture montrent un spécimen en tête de groupe, dans la police et la taille choisies (`ReaderTextSize.points`, interligne 1,55). Pas de titre « Preview » redondant : le texte d'exemple *est* l'aperçu.

L'appui d'une carte modifie sa surface dans le même contour arrondi et utilise une échelle de 0,99. Reduce Motion supprime cette mise à l'échelle et son animation. Ne pas ajouter d'animation automatique de décoration.

## 4. Parcours : contrat visuel et travail restant

### Architecture de navigation actuelle — 22 septembre

- Onglets : **Today → Queue → Feed → Settings**. Today reste l'écran d'ouverture.
- Today porte la sélection quotidienne et ne montre que l'actualisation dans sa barre d'outils. Quand il n'y a aucune source, son action « Add Source » ouvre directement le formulaire d'ajout.
- Queue contient les pièces sauvegardées et donne accès à **History** dans sa barre d'outils.
- Feed présente **New articles** et les dossiers de sources ; la recherche filtre les titres, sources et extraits dans chaque collection. Une ligne **Manage sources** avant les dossiers ouvre la gestion des abonnements. Le second raccourci « Today » et les comptes d'articles non lus ont été retirés du répertoire.
- Settings contient les préférences de lecture, comptes et synchronisation, stockage, vidéo et IA, puis l'import/export OPML et About. La gestion des sources et la restauration du catalogue habitent l'écran Sources ; le laboratoire expérimental est sous Video & AI.
- Vérification de cette réorganisation : build Simulator, `testExample` et `testCaptureSettingsDestinations` réussis sur iPhone 17 / iOS 27. Le tour `testCaptureAllScreens` a capturé Today à Sources, puis a expiré en ouvrant History depuis Queue ; ce parcours reste à vérifier séparément.

Ces descriptions résument le code actuel et les intentions de présentation. Elles n'autorisent pas une modification des transitions métier.

| Parcours | Présentation attendue | À vérifier ou confier à la logique |
| --- | --- | --- |
| Today → article → retour | Une pièce principale évidente, lecture dédiée, retour identifiable | Distinguer fermeture et article terminé ; maintien de la sélection |
| Feed → dossier → article | Navigation native, titres cohérents et lignes séparées | Identité des dossiers, filtres, comptage, conservation de position |
| Queue → article | Cartes indépendantes ; source et durée lisibles avant ouverture | Effets exacts de Done, Remove et restauration |
| Queue → Add → lien ou article existant | Formulaire natif ; saisie distincte des suggestions ; progression visible | Validation URL, erreurs réseau, doublons, annulation en cours |
| Feed → Sources | Liste de sources identifiable, action d'ajout explicite | Synchronisation et gestion des abonnements |
| Premier lancement | Une action principale par étape, texte court | Persistance, reprise et fin d'onboarding |

### États à couvrir avant validation finale

- Vide : titre informatif et prochaine action explicite, sans décoration massive.
- Chargement : contexte conservé, progression proche de l'action ; pas de clignotement du contenu.
- Erreur : message lisible et reprise identifiable ; ne pas utiliser seulement la couleur rouge.
- Succès : retour discret, sans célébration qui détourne de la lecture.
- Texte long : source longue, titre multiligne, durée absente et image indisponible.
- Accessibilité : grandes tailles de texte, VoiceOver, Reduce Motion, contraste accru, mode sombre.

Les règles d'état ci-dessus sont des critères de conception, pas des corrections métier déjà implémentées.

## 5. État réel de la vérification

### Point de contrôle du 18 septembre — taille standard

Les quatre tests `testCaptureAllScreens`, `testCaptureEmptyQueueAndOnboarding`, `testCaptureLongLayouts` et `testCaptureSettingsDestinations` ont réussi (4/4, 115,6 s) sur iPhone 17 Pro / iOS 26.5, taille de texte par défaut. Cette exécution inclut l'aperçu de lecture, `Manage sources`, le rouge d'erreur adaptatif et le titre « Recently saved ».

Inspection des captures `/tmp/onefeed-uitest-screenshots/` à 11:08–11:12 :

- Queue (`03`, `15`, `16`) : cartes papier séparées sur plâtre, contour sable, intervalle de sections plus large que l'intervalle entre cartes. La dernière carte d'une liste longue reste entière au-dessus de la barre d'onglets.
- Today (`01`) : une pièce principale en carte ; « Also today » reste une liste compacte dans un groupe papier.
- Lecture (`17-Settings-Reading`) : un spécimen serif en tête de groupe, lié à `ReaderTextSize.points` et à un interligne 1,55 comme le lecteur. Les pickers Font / Text Size sont visibles sans défiler.
- Queue vide (`11`) et Settings (`10`) : actions et six rubriques entièrement visibles.
- `UITestScreenshots/01–11` du dépôt ont été remplacés par ces captures standard (plus les barres colorées du 15 septembre).

Une tentative de validation « finale » sous `/tmp/onefeed-final-20260918/` a exécuté 0 test : ne pas la citer comme preuve. Le mode sombre et les très grandes tailles de texte n'ont pas été recapturés sur cet arbre exact.

### Point de contrôle antérieur du 18 septembre — accessibilité

Une passe précédente à très grande taille (4/4, 165,9 s) a montré : lecteur sans défilement horizontal, actions de Queue vide au-dessus des onglets, dernière carte atteignable. Ces PNG AX ne reflètent pas l'aperçu de lecture ni `Manage sources`. À cette taille, « Recently saved · Video » orphelinait le point médian (corrigé depuis par des espaces insécables) et le bas de certains écrans Settings passait sous la barre d'onglets tant que l'utilisateur n'avait pas défilé.

### Historique du 16 septembre

- Revue de code ciblée : typographie adaptative, cumul de marges, retour d'appui arrondi, barre d'actions du lecteur, cibles emoji, insets Settings.
- `testCaptureEmptyQueueAndOnboarding` et `testCaptureAllScreens` : réussis après correction du sélecteur `folder-Security` (bouton de navigation, pas l'édition d'icône).
- Douze captures standard renouvelées le 16 septembre. Ne pas les assimiler à la validation du mode sombre, des très grandes tailles de texte, ni de cette passe d'accessibilité.
- Captures ad hoc sous `/tmp/onefeed-dark` et `/tmp/onefeed-accessibility` : les tests passent, mais l'inspection visuelle a révélé un débordement de la barre du lecteur et un CTA Queue vide coupé par la barre d'onglets.
- `testCaptureLongLayouts` existe (lecteur riche + file Queue jusqu'en bas). Ses PNG `13–16` n'étaient pas encore dans le dépôt au moment de cette mise à jour.
- Les captures du dépôt `UITestScreenshots/01–11` datent du 15 septembre : Feed y montre encore des barres colorées, alors que le code actuel utilise des emoji.

Les captures temporaires sont sous `/tmp/onefeed-uitest-screenshots/`. Leur nom seul ne prouve pas leur fraîcheur.

### Avancement — 16 septembre, passe d'accessibilité

- Lecteur : aux tailles d'accessibilité, Done, Queue et Skip sont des boutons pleine largeur, lisibles, sans défilement horizontal. Share et Browser passent dans le menu AA. Le sélecteur Reader/Website devient un menu.
- Queue vide : actions (Open Today, Add a link) placées sous le titre, au-dessus de la description, pour rester hors de la barre d'onglets. La description peut défiler.
- HTML du lecteur : papier sombre aligné sur `#2A2520` ; liens `light-dark(#A04B32, #E89B7A)` pour un contraste de texte ordinaire, soulignement conservé. Le terracotta `#D97757` reste la bordure de citation.
- Emoji de dossier : zone tactile ≥ 44 × 44 ; grille adaptative à largeur minimale de 44 points (Notion : l'emoji change l'icône, le reste de la ligne ouvre le dossier).
- Queue vide, History vide et Sources vides : dégagement bas de 96 points pour que l'action secondaire ne passe plus sous la barre d'onglets.
- Settings : spacer de 72 points et dégagement racine de 88 points retirés ; un seul inset de 96 points, comme les listes groupées. Feuille Gemini extensible au focus. Valeurs longues empilées via `StackedLabeledValue`.
- Add to Queue : l'erreur s'affiche sous le champ, avant les suggestions ; Cancel est désactivé pendant l'ajout.
- History : en-têtes Today / Yesterday en casse de phrase, plus en capitales forcées.
- Compteurs de dossiers en `ink` ; titres de répertoire capables de revenir à la ligne ; image principale omise aux tailles d'accessibilité.
- Les actions, états d'article, synchro et filtres restent inchangés.

Le chantier complet reste ouvert jusqu'à inspection des nouvelles captures. Les changements de logique du plan d'audit restent hors périmètre de cette passe.

## 6. Priorités suivantes

### Passe du 22 septembre — navigation des sources et repère de lecture

- Sources : les dossiers contenant des abonnements précèdent les dossiers vides ; recherche sur les noms de dossiers et de sources ; création depuis le menu d'ajout dans la barre d'outils.
- Un dossier vide propose directement d'ajouter une source. Dans un dossier rempli, l'ajout reste dans la barre d'outils et une recherche filtre les abonnements.
- Le repère du lecteur interpole la position et la longueur des lignes sur les images suivantes ; le texte proche change d'opacité brièvement. Reduce Motion garde des changements immédiats.
- La progression de rafraîchissement est superposée au bord supérieur de l'écran (2 points) pour rester à une position stable sans déplacer la liste.
- Vérification : build iOS Simulator, syntaxe du script de lecture et `testCaptureAllScreens` sur iPhone 17 / iOS 27 (10 captures). La capture Sources confirme les deux sections et leurs actions. Le lecteur était encore en chargement sur sa capture immédiate ; l'animation du repère et la position de la progression pendant un rafraîchissement restent à vérifier visuellement.

1. Recapturer en mode sombre et à très grande taille l'aperçu de lecture et `Manage sources` (absents des PNG AX du matin).
2. Grand format / iPad : encore ouvert.
3. La réorganisation métier des réglages, de la synchro et des transitions d'articles reste hors de ce chantier de présentation.

Lag des onglets, freeze au refresh, `save()` hors main : [`PERFORMANCE.md`](PERFORMANCE.md).

## 7. Garde-fous anti-slop et répartition du travail

Le skill UI Slop Score demande une preuve rendue : ne pas qualifier de réussi un écran seulement parce que son code paraît correct. Garder au plus trois problèmes visuels prioritaires par passe. Ne pas pénaliser les composants natifs, les polices système ou la sobriété ; corriger ce qui nuit à la tâche.

Éviter les dégradés de décoration, les badges sans information, les ombres répétées et la multiplication des panneaux. Préserver la personnalité éditoriale plutôt qu'ajouter une esthétique de dashboard.

- UI/Astra : hiérarchie, composants, espacements, lisibilité, retour d'appui et revue visuelle.
- Luna : builds et tests de capture existants, rapport précis des états réellement capturés.
- Luna en raisonnement élevé : écriture et exécution des tests, selon la demande du 18 septembre ; réserver Astra aux décisions et changements UI/UX.
- Grok : logique et corrections fonctionnelles séparées (synchronisation, validation, stockage, transitions et filtres).
- Une étape à la fois : correction limitée → compilation/tests disponibles → capture → inspection → mise à jour de ce guide.
