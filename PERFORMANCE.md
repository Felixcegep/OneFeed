# OneFeed — performance

Mis à jour le 18 septembre 2026. Lag des onglets, freeze au refresh des flux, Main Actor, SwiftData. Pas du style visuel : voir [`UI_UX_STYLE_GUIDE.md`](UI_UX_STYLE_GUIDE.md). Index : [`agent.md`](agent.md).

Ce n’est pas un profil Instruments. Les tests unitaires cités prouvent le comportement, pas le Time Profiler.

## 1. Lag au changement d’onglet

Le 18 septembre, le freeze Queue / Feed / Today / Settings ne venait pas d’un `NavigationStack` mal câblé. Les onglets iOS sont déjà quatre piles natives. Le freeze venait du **travail relancé quand une page réapparaît**, souvent sur le thread principal.

Vérifié sur iPhone 17 Pro : `testExample` passe (Today → Queue → Feed → Today).

| Endroit | Avant | Après |
| --- | --- | --- |
| Queue | `SavedView` refetchait SwiftData dans `.task` *et* `.onAppear` à chaque visite d’onglet | `@Query` sur les articles `.saved` ; le ViewModel garde le contexte pour Done / Restore, sans reload au simple tap d’onglet |
| Today | `.task` relançait un backfill YouTube ; la `List` s’animait à chaque variation de `stories.count` | Refresh réseau seulement si les flux sont périmés ; backfill une fois ; au retour, `syncVisibleDeck()` relit le deck sans réseau ; plus d’animation de structure de liste |
| Feed | `openArticles` / today / summaries recalculés séparément, O(dossiers × articles) | Un `FeedRootDirectory` par `body` ; compteurs par `feed.id` |
| Settings | `LibrarySyncService.configure` relançait `restoreIfNeeded` ; `SettingsViewModel.configure` refetchait comptes et flux | Restore une fois par session ; reload du ViewModel au premier `configure` et à l’ouverture d’une rubrique, pas au tap d’onglet |
| Lecteur | Extraction / résumé YouTube pouvaient écrire dans SwiftData après fermeture | `Task.checkCancellation()` après les `await` ; pas de save si la vue a disparu |

Pas d’animation ajoutée sur le changement d’onglet : ces allers-retours sont trop fréquents. Animer tout le contenu masque le freeze et le rend plus long. La barre d’onglets iOS anime déjà l’indicateur.

## 2. Freeze pendant « Updating sources »

Le jank au **chargement / mise à jour du feed** n’était pas le réseau. Les `URLSession` partent déjà dans un `TaskGroup`. Ça venait d’écrire les articles dans le même `ModelContext` que SwiftUI :

- `FoldersView` a un `@Query` de tous les queued/current.
- Chaque `context.insert` + `save` toutes les 6 sources invalidait ce query, puis `FeedRootDirectory` relisait tout.
- FreshRSS faisait `fetch` par `remoteID` pour chaque item d’un stream (jusqu’à 1 000 × N dossiers) **et** `wordCount` deux fois sur le HTML.
- `RefreshProgressBanner` animait `progress.fraction` (300 ms) à chaque source.

| Endroit | Avant | Après |
| --- | --- | --- |
| Refresh des flux | `insert` / `save` sur le `ModelContext` de l’écran, toutes les 6 sources | Un save groupé, plus de fetch FreshRSS par item ; index `remoteID` en mémoire |
| Save de fin | `context.save()` encore sur le Main Actor → freeze SQLite + `@Query` | `LibraryIngestActor` (`@ModelActor`) : inserts, merge, deck du jour, purge et `save()` hors du thread principal |

Un contexte privé **sans** changer d’acteur ne suffisait pas : le `save()` de fin restait sur le Main Actor. SQLite + fusion SwiftData gelaient encore l’UI au moment où la barre passait à « Building today ».

Ne pas « corriger » ça en animant la `List` Feed pendant l’ingest : ça empile layout + animation + save.

## 3. Save hors du thread principal

`LibraryIngestActor` (`@ModelActor`, `SwiftDataIngest.swift` / `FeedIngest.swift`) possède son propre `ModelContext` sur un exécuteur de fond :

1. Le contexte de l’écran est sauvé s’il a des changements locaux, pour que l’actor voie les flux déjà ajoutés.
2. RSS, FreshRSS, `mergeDuplicates`, `generateIfNeeded` et `purge` tournent sur l’actor.
3. Un seul `save()` (ou presque) **sur l’actor**, pas sur le Main Actor.
4. La barre de progression revient au main via `RefreshProgressSink` : texte seulement, pas le store.
5. Après le save, `@Query` Feed / Queue se met à jour **une fois**. Un court à-coup de liste est possible ; ce n’est plus le freeze du write SQLite.

`classify` / `wordCount` tournent sur cet actor. L’échantillon HTML est plafonné ; ne pas relancer un regex sur tout le body RSS depuis le Main Actor.

`Task.detached` + `ModelContext` passé dans une fonction `nonisolated async` est interdit : le contexte quitterait l’exécuteur qui l’a créé. Les méthodes d’ingest sont des méthodes de l’actor, pour que `await` (réseau, `Task.yield`) reprenne sur le même actor.

Vérifié par `MonoRssTests` / `SwiftDataFreshRSSSyncTests` / `DailyDeckTests` (iPhone 17 Pro).

## 4. Patterns à ne pas faire

Ces habitudes font geler, buggent l’état, ou recréent des requêtes. Elles ont déjà coincé OneFeed.

1. **Recharger dans `.onAppear` d’un onglet.** `onAppear` se rejoue à chaque visite. Queue faisait `reload()` à chaque tap. Préférer `@Query` ou un `loadIfNeeded` / `guard context == nil`.
2. **Recréer le ViewModel dans `body`.** `let vm = SavedViewModel()` à chaque redraw perd l’état et relance le travail. Garder `@State private var viewModel = …` chez le propriétaire (`@Observable` + `@State`, pas un nouvel objet par frame).
3. **Deux copies de la même liste.** Queue avait un tableau manuel *et* SwiftData. Today a encore un tableau (`remainingArticles`) : le relire au retour d’onglet, ne pas le remplir par un refresh réseau. Une source de vérité (idéalement `@Query` ou le deck du jour).
4. **Démarrer le réseau dès qu’une page apparaît.** `startRefreshIfNeeded` ne doit pas relancer `backfillYouTubeDurations` à chaque `.task`. Le refresh complet reste pour les flux périmés, le pull-to-refresh, et `BackgroundRefreshCoordinator`.
5. **Animer une `List` entière** (`.animation(..., value: stories.count)`). Ça relayout tout le fil pendant que l’utilisateur change d’onglet. Réserver le mouvement à l’appui (échelle 0,99), Reduce Motion respecté, pas aux mutations de collection.
6. **Lancer `Task { }` dans `onAppear` sans annulation.** En quittant le lecteur, l’extraction continuait et sauvait l’article. Utiliser `.task` (lié à la durée de vie) et `Task.checkCancellation()` après chaque `await` avant de toucher le modèle.
7. **Gros calcul dans `body`.** Recalculer les dossiers N fois, parser du HTML, ou construire le document lecteur à chaque frame. Une passe, un cache (`documentHTML` a déjà une clé), un snapshot local (`let directory = …` en tête de `body`).
8. **Configurer un singleton à chaque écran.** `LibrarySyncService.shared.configure` depuis AppRoot *et* Settings relançait le restore. Une fois par session ; mettre à jour le `ModelContext`, pas relancer l’I/O.
9. **`user!.name`, `as!`, `array[0]` pendant une transition.** Si la donnée n’est pas encore là ou vient d’être retirée : crash. `if let`, `array.first`, `indices.contains`.
10. **Travail lourd sur le Main Actor au tap.** Ingest RSS, upsert FreshRSS, décode d’images pleine taille : le tap d’onglet doit rester libre. Ne pas enchaîner ça dans le même geste que `path.append` ou `selectedTab =`.
11. **Croire qu’un `.task` d’onglet ne s’exécute qu’une fois.** Si TabView démonte la vue, `.task` repart. Le travail dedans doit être idempotent (`didRunUtilityBackfill`, `hasScheduledRestore`).
12. **Réécrire toute la navigation en `NavigationPath` pour « corriger le lag ».** Les quatre onglets ont déjà chacun un `NavigationStack`. Un AppRouter unique n’enlève pas un fetch `onAppear`.
13. **Insérer le refresh RSS dans le `ModelContext` de l’écran, et `save()` sur le Main Actor.** `@Query` voit chaque `insert`. Utiliser `LibraryIngestActor` : le write SQLite part sur un autre exécuteur. Un save de fin sur le thread principal gèle encore l’UI, même si les inserts étaient ailleurs.
14. **Fetcher SwiftData dans une boucle d’items** (`FetchDescriptor` par `remoteID` FreshRSS). Construire un `ArticleIdentityIndex` une fois, y compris `remoteID`.
15. **Animer `progress.fraction`.** La barre de 1 pt n’a pas besoin d’un ease de 300 ms à chaque source. Animer seulement `isActive` (apparition / disparition). `wordCount` : une passe, un plafond de caractères, pas deux regex sur le HTML complet.
16. **`Task.detached` + `ModelContext` dans une fonction `nonisolated async`.** Le contexte n’est pas Sendable ; il doit rester sur l’exécuteur qui l’a créé. Passer par `@ModelActor`, pas par un hop vers le pool concurrent.

## 5. Patterns à garder

- View → demande au ViewModel → le ViewModel change l’état → SwiftUI redessine. Pas Page A qui mute Page B.
- `@MainActor` + `@Observable` pour l’état d’écran.
- `.task` pour le chargement lié à la vue ; pull-to-refresh et le coordinateur pour le réseau global.
- `@Query` pour les listes qui doivent suivre SwiftData (Queue, Feed). Today relit le deck au retour, sans refetch général.
- Une action utilisateur (Done, Restore, Sync Now) *peut* recharger : ce n’est pas un changement d’onglet.
- `TimelineView` / pulse : uniquement tant que `isActive` ; déjà en pause sinon.
- Ingest / `save()` sur `@ModelActor`. L’écran (`@MainActor` + `@Observable`) affiche la progression, il n’écrit pas le store.

Fichiers : `SavedView.swift`, `CurrentViewModel.swift`, `FoldersView.swift`, `FeedFolderGrouping.swift`, `LibrarySyncService.swift`, `ReaderViewModel.swift`, `SettingsViewModel.swift`, `SwiftDataIngest.swift`, `FeedIngest.swift`, `FeedService.swift`, `FreshRSSSyncService.swift`.
