# OneFeed — guide de style et de parcours

Mis à jour le 16 septembre 2026. Document de référence du chantier UI, complément de `UI_UX_IMPROVEMENT_PLAN.md`, pas une déclaration de validation complète.

## 1. Intention

« One article at a time. » Une interface de lecture calme, pas un tableau de bord de consommation. Garder les surfaces chaudes, les titres éditoriaux serif et les contrôles natifs. La clarté doit venir de la hiérarchie, des marges et des limites des objets, pas de décorations supplémentaires.

Le README exclut les compteurs et les catégories, alors que le code actuel expose des totaux et des dossiers. Cette divergence est une décision produit à résoudre séparément : ce chantier de style ne supprime ni données ni fonctions.

## 2. Fondations

Source de vérité : `OneFeed/Shared/DesignSystem/OneFeedTheme.swift` et les couleurs adaptatives de `OneFeed/Shared/Utilities/PlatformSupport.swift`.

| Rôle | Token | Usage |
| --- | --- | --- |
| Fond de page | `plaster` | Toile derrière les groupes |
| Contenu | `paper` | Articles et sections natives |
| Appui | `warm1` | Retour tactile visuel temporaire |
| Texte principal | `ink` | Titres et en-têtes |
| Texte secondaire | `graphite` | Source, date, durée, explications |
| Contour | `sand` | Trait de 1 point, pas une ombre |
| Accent | `accent` | Actions et sélection, pas les titres |

Utiliser les couleurs adaptatives, jamais recopier leurs valeurs claires dans une nouvelle vue. Le contraste des états sombres et des actions colorées reste à mesurer ; l'existence d'un token n'est pas une garantie d'accessibilité.

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

L'appui d'une carte modifie sa surface dans le même contour arrondi et utilise une échelle de 0,99. Reduce Motion supprime cette mise à l'échelle et son animation. Ne pas ajouter d'animation automatique de décoration.

## 4. Parcours : contrat visuel et travail restant

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

- Revue de code ciblée : typographie adaptative, cumul de marges, retour d'appui arrondi, barre d'actions du lecteur, cibles emoji, insets Settings.
- `testCaptureEmptyQueueAndOnboarding` et `testCaptureAllScreens` : réussis après correction du sélecteur `folder-Security` (bouton de navigation, pas l'édition d'icône).
- Douze captures standard renouvelées le 16 septembre. Ne pas les assimiler à la validation du mode sombre, des très grandes tailles de texte, ni de cette passe d'accessibilité.
- Captures ad hoc sous `/tmp/onefeed-dark` et `/tmp/onefeed-accessibility` : les tests passent, mais l'inspection visuelle a révélé un débordement de la barre du lecteur et un CTA Queue vide coupé par la barre d'onglets.
- `testCaptureLongLayouts` existe (lecteur riche + file Queue jusqu'en bas). Ses PNG `13–16` n'étaient pas encore dans le dépôt au moment de cette mise à jour.
- Les captures du dépôt `UITestScreenshots/01–11` datent du 15 septembre : Feed y montre encore des barres colorées, alors que le code actuel utilise des emoji.

Les captures temporaires sont sous `/tmp/onefeed-uitest-screenshots/`. Leur nom seul ne prouve pas leur fraîcheur.

## 6. Priorités suivantes

1. Recapturer le lecteur en très grande taille : Done pleine largeur + deuxième rangée, plus de défilement horizontal des cinq actions.
2. Recapturer Queue vide en très grande taille : « Add a link » entièrement au-dessus de la barre d'onglets.
3. Vérifier une liste longue défilée jusqu'en bas (`16-Queue-Bottom`) et le lecteur avec contenu long (`13–14`).
4. Harmoniser les captures du dépôt avec le code actuel (emoji, en-têtes de section, Settings en sous-parcours).
5. Grand format / iPad : encore ouvert. La réorganisation métier des réglages, de la synchro et des transitions d'articles reste hors de ce chantier de présentation.

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

## 7. Garde-fous anti-slop et répartition du travail

Le skill UI Slop Score demande une preuve rendue : ne pas qualifier de réussi un écran seulement parce que son code paraît correct. Garder au plus trois problèmes visuels prioritaires par passe. Ne pas pénaliser les composants natifs, les polices système ou la sobriété ; corriger ce qui nuit à la tâche.

Éviter les dégradés de décoration, les badges sans information, les ombres répétées et la multiplication des panneaux. Préserver la personnalité éditoriale plutôt qu'ajouter une esthétique de dashboard.

- UI/Astra : hiérarchie, composants, espacements, lisibilité, retour d'appui et revue visuelle.
- Luna : builds et tests de capture existants, rapport précis des états réellement capturés.
- Grok : logique et corrections fonctionnelles séparées (synchronisation, validation, stockage, transitions et filtres).
- Une étape à la fois : correction limitée → compilation/tests disponibles → capture → inspection → mise à jour de ce guide.
