# Migration des données de l'ancienne base des modèles entraînés

Reprise ponctuelle des données de l'ancienne base (28 tables `Model*`,
`*TrainTrack`, `*_Test`, `Document*`) dans la base fusionnée.

## Utilisation

```powershell
# 1. Contrôle de l'export et génération du script SQL
.\Convert-LegacyMlExport.ps1 -InputFile .\export_ancienne_base.txt -Strict

```

Puis exécuter le script généré `export_ancienne_base_migration.sql` dans SSMS :

1. **Nouvelle requête** connectée à la **base cible**. Le script ne contient pas de
   `USE` : vérifier la base sélectionnée dans la liste déroulante. Le nom de la base
   et le compte utilisé sont affichés en tête des messages.
2. Ouvrir le fichier, ou le coller, puis exécuter **tout** le script (F5).
3. Lire l'onglet **Messages** : contrôle préalable, lignes insérées par table, puis
   `MIGRATION TERMINÉE` ou `MIGRATION ANNULÉE`.

Le mode SQLCMD n'est pas nécessaire. `sqlcmd -S <serveur> -d <base> -b -i <fichier>`
fonctionne aussi.

### Droits nécessaires

Les scripts `1_tables` doivent avoir été déployés au préalable par un compte ayant
les droits DDL, y compris `19_Migration_LegacyMap.sql` et `20_Migration_Rejected.sql`. Le script de migration ne
crée ensuite **aucun objet permanent** : il utilise uniquement des tables
temporaires `#`. Il lui faut :

| Droit | Objets | Si absent |
|---|---|---|
| `SELECT` + `INSERT` | les 14 tables cibles et `dbo.Migration_LegacyMap` | arrêt avant toute écriture, avec la liste des droits manquants |
| `SELECT` + `INSERT` + `DELETE` | `dbo.Migration_Rejected` | arrêt avant toute écriture |
| `SELECT` | `dbo.[User]`, `dbo.Ref_TaskType` | arrêt avant toute écriture |
| `ALTER` *(facultatif)* | `dbo.Project`, `dbo.Project_Version` | la migration a lieu quand même, mais les triggers d'historique restent actifs : chaque projet / version migré apparaît dans `Project_History` (« a été créé ») |

Un rôle `db_datareader` + `db_datawriter` suffit, sans le droit `ALTER`.

Prérequis vérifiés au même moment :
- SQL Server 2017 ou plus récent ;
- niveau de compatibilité de la base ≥ 130, nécessaire pour `OPENJSON` ;
- schéma cible à jour, ce qui détecte aussi une mauvaise base sélectionnée.

### Comportement dans SSMS

- **Arrêt avant écriture.** Dans SSMS, une erreur n'arrête pas les batches suivants.
  Si le contrôle préalable échoue, le script passe donc en `SET NOEXEC ON` : plus rien
  n'est exécuté. Le dernier batch remet `SET NOEXEC OFF` pour que la fenêtre reste
  utilisable.
- **Niveau de compatibilité insuffisant.** SQL Server analyse quand même les batches
  suivants : les erreurs « Incorrect syntax » qui s'affichent en découlent, et
  aucune donnée n'est écrite.
- **Chargement interrompu.** Si un batch de chargement échoue, le batch de migration
  constate que des lignes manquent et s'arrête avant d'écrire.
- **Une seule fenêtre.** Les données transitent par la table temporaire `#Src`, qui
  n'existe que dans la session : exécuter tout le script dans la même fenêtre.
- **Réexécution dans la même fenêtre.** Les tables temporaires restent en vie dans
  la fenêtre SSMS après une exécution. Le script les supprime dans un batch séparé
  avant le batch de migration, et n'ajoute jamais de colonne à une table temporaire
  existante. On peut donc relancer le script dans la même fenêtre, y compris après
  un échec.

| Paramètre | Rôle |
|---|---|
| `-InputFile` | Export texte de l'ancienne base (format ci-dessous) |
| `-OutputFile` | Script SQL généré (défaut : `<InputFile>_migration.sql`) |
| `-Strict` | Aucun script généré si une table migrée présente un écart (recommandé en production) |
| `-OrphanPolicy` | Lignes dont le parent est introuvable : `Reject` (défaut) = écartées et conservées dans `dbo.Migration_Rejected`, le reste est migré ; `Fail` = migration annulée |
| `-TrainStatusMap` | `StatusTrain` → `Ref_RunStatus`. Défaut `@{0='RUNNING';1='SUCCEEDED';2='FAILED'}` |
| `-InputEncoding` | `Auto` (défaut : UTF-8 si valide, sinon Windows-1252), `UTF8`, `Windows1252`, `Unicode` |
| `-RowsPerBatch` | Nombre d'INSERT par batch `GO` dans le script généré (défaut 200) |

Compatible Windows PowerShell 5.1 et PowerShell 7. Le fichier `.ps1` est en
UTF-8 avec BOM : c'est nécessaire pour que PowerShell 5.1 lise correctement les accents.

## Format d'entrée

```
--- Table : Model
Nombre de lignes : 66
--- Résultat JSON :
[Microsoft][ODBC Driver 13 for SQL Server][SQL Server][{"IdModel":2,...},{...}]
```

- Le préfixe ODBC est retiré.
- `Table vide : []` = table vide.
- **Sauts de ligne au milieu du JSON :** le JSON d'une table va de
  `--- Résultat JSON :` jusqu'à la section `--- Table :` suivante. Toutes ses lignes
  sont recollées **sans séparateur**, où que tombe la coupure : découpage `FOR JSON`
  en morceaux de ~2000 caractères, retour à la ligne au milieu d'un mot ou d'une
  chaîne, juste après un antislash, ou lignes vides intercalées.
  - Une ligne vide est ignorée, sauf au milieu d'une chaîne JSON : ses espaces font
    alors partie de la valeur.
  - Les sauts CR LF, LF et CR seul sont reconnus.
  - La colonne `LignesTxt` du rapport indique en combien de lignes le JSON était découpé.

## Contrôles du script PowerShell

1. **Nombre de lignes** : pour chaque table, le nombre annoncé (`Nombre de lignes`)
   est comparé au nombre d'éléments du JSON. En cas d'écart, le nom de la table est
   affiché (`ÉCART  <table>  (annoncé : N, éléments JSON : M)`).
2. **JSON invalide** (export tronqué) : la position de l'erreur est indiquée. Les
   éléments lisibles sont récupérés, les morceaux illisibles sont écartés.
3. **Logs IHM** : dans `Classification_Test`, `Decoupage_Test`, `Extraction_Test`,
   `Detection_Test` et `Segmentation_Test`, une ligne **sans `DocId`** est un log de
   l'IHM (« Start MailSend Exception… »), pas un résultat d'inférence. Elle n'est
   pas migrée, et le nombre de lignes écartées est affiché.
4. **Colonnes** (`COLONNES` / `STRUCTURE`) : une table vide dans un environnement
   peut être remplie dans un autre. Le script affiche :
   - chaque colonne présente dans l'export mais non reprise par la migration, par
     exemple une métrique `mAP50` inconnue : sa donnée serait perdue ;
   - chaque ligne à laquelle il manque une colonne obligatoire (identifiant,
     parent…), avec le nom de la colonne attendue.

   Les noms sont comparés en respectant la casse, comme `OPENJSON`.
5. **Tables sans cible** (`Logs_IHM`, `Parameters`, `Processor`, `Pipeline*`) :
   contrôlées et affichées, mais pas migrées.

Avec `-Strict`, tout écart, colonne non reprise ou colonne obligatoire manquante
sur une table migrée bloque la génération du script SQL.

## Le script SQL généré

- **Chargement :** les lignes sont chargées dans `#Src`, une table temporaire. Le
  script vérifie qu'elles sont toutes arrivées et que chacune est un JSON valide.
- **Transaction unique :** les 14 tables cibles sont alimentées dans **une seule
  transaction**. Si une table échoue, tout est annulé (`XACT_ABORT` + `TRY/CATCH`).
  Le message indique l'étape et les lignes en cause.
- **Rejouable :** `dbo.Migration_LegacyMap` (créée par `1_tables/19_Migration_LegacyMap.sql`) garde la correspondance
  `(table source, ancien Id) → nouvel Id`. Une ligne déjà migrée n'est jamais recopiée,
  ce qui permet de relancer avec un export complété.
- **Historique :** avec le droit `ALTER`, les triggers d'insertion
  (`trg_Project_Insert`, `trg_ProjectVersion_Insert`) sont suspendus pendant la
  transaction. Sans cela, chaque élément migré crée une entrée « a été créé » datée
  du jour de la migration.

### Correspondances

| Ancienne table | Nouvelle table | Règle |
|---|---|---|
| `Model` | `Project` (`Category = 'MODEL'`) | `TaskType` déduit de `ProjectType` (sans casse ni accents, ex. « Découpage » → `DECOUPAGE`), sinon de la famille de ses versions |
| `Model*_Version` (×5) | `Project_Version` | `InProd` → `DeliveredToProduction`, `Comment` → `Description` |
| métriques des versions | `Project_Version_Metric` | `Accuracy`, `ErrorRate`, `PrecisionScore`, `RecallScore`, `f1_score`, `kappa`, `AP_*`, `Recall_*`, `MeanErrors`, `NbErrors` |
| `Model*_Version_Test` (×5) | `Evaluation` (+ `Evaluation_Metric`) | `VersionNb` du test → `Name = 'Test n'` ; `TestDataPath` → `EvalPath` ; `TestResultsPath` → `PredictionFile` |
| `*TrainTrack` (×4) | `Training_Run` | `(IdModel, VersionNb)` → `(ProjectId, VersionNumber)` ; `StatusTrain` via `-TrainStatusMap` ; `ModelPath` → `OutputPath` |
| `*_Test` d'inférence (×5) | `Inference_Request` | `ResMessage` (JSON encodé en chaîne) décodé : `ResContent` = réponse JSON, `StatusCode` = `status_code`, `ResMessage` = `message` |
| `DocumentClass` / `DocumentField` / `DocumentProperty` | `Document_*` | Rapprochement par nom (par classe + nom pour les champs) : une entrée déjà présente est réutilisée |
| `Document*Projects` | `Project_Version_Document_*` | `IdModelVersion` lu comme Id de version du même `IdModel`, à défaut comme numéro de version |
| `DocumentRequest` | `Document_Request` | |

**Auteurs :** un nom complet (« DUPREZ Julien ») ou un identifiant (« CRETYSE »)
est remplacé par le `PersoId` quand l'utilisateur existe dans `[User]`. Sinon, la
valeur source est conservée. Si l'auteur est absent alors que la colonne est
obligatoire, on écrit `MIGRATION`.

### Lignes orphelines (parent introuvable)

L'ancienne base n'avait pas de clés étrangères : une ligne peut désigner un parent
qui n'existe pas (ou plus). Voici les cas pris en charge :

| Ligne | Parent introuvable |
|---|---|
| `Model*_Version` | modèle (`IdModel`) |
| `Model*_Version_Test` | version testée (y compris une version elle-même rejetée) |
| `*TrainTrack` | modèle |
| `DocumentField` | classe |
| `Document*Projects` | modèle, version (`IdModelVersion`) ou élément (classe / champ / propriété) |

Avec `-OrphanPolicy Reject` (défaut), ces lignes ne sont pas migrées. Elles sont
enregistrées dans `dbo.Migration_Rejected`, avec la raison du rejet et la ligne JSON
d'origine, et le reste est migré. Un message `ATTENTION` indique le nombre de lignes
rejetées à chaque étape, puis le total à la fin.

```sql
SELECT SourceTable, SourceId, Reason, RowJson
FROM dbo.Migration_Rejected
ORDER BY SourceTable, SourceId;
```

Le contenu de cette table est recalculé à chaque exécution, pour les tables présentes
dans l'export. Si le parent apparaît dans un export ultérieur (modèle ajouté, export
complété), la ligne est alors migrée et disparaît des rejets.

Avec `-OrphanPolicy Fail`, le premier orphelin annule toute la migration.

Le `IdModelVersion` des tables `Document*Projects` est interprété de deux façons,
dans cet ordre :
1. comme l'identifiant d'une version (tables `Model*_Version`) rattachée au même `IdModel` ;
2. à défaut, comme un numéro de version de ce modèle.

La ligne n'est rejetée que si aucune des deux lectures ne trouve de version.

### Erreurs bloquantes (rollback complet)

- Une ligne dont l'identifiant source est introuvable : nom de colonne inattendu.
- Un identifiant source en double.
- Un modèle dont le type de tâche n'est pas reconnu.
- Une version, un test, un entraînement, un champ ou une association dont le parent
  est introuvable, **uniquement avec `-OrphanPolicy Fail`**.
- Un numéro de version en double pour un même modèle.
- Un test sans `TestDataPath`.
- Un `StatusTrain` absent de `-TrainStatusMap`.
- Une valeur trop longue ou invalide pour la colonne cible.

## Ajouter une colonne ou une métrique

Si le contrôle signale une colonne non reprise (ex. `COLONNES ModelDetection_Version : mAP50`) :

- **Métrique :**
  1. Ajouter la colonne à `$MetricKeys` en tête du script PowerShell : `'mAP50' = 'MAP50'`.
  2. Ajouter le code dans `1_tables/00_Ref_Metric.sql`, puis rejouer ce script.
- **Autre colonne :**
  1. L'ajouter à la liste `Known` du type de table dans `$KindSpecs`.
  2. L'ajouter au `OPENJSON ... WITH` correspondant du script SQL intégré.
  3. L'ajouter à l'`INSERT` correspondant.
- **Colonne volontairement ignorée :** l'ajouter à la liste `Skipped`.

Les noms des colonnes des tables vides dans l'extrait de référence ont été déduits
par analogie avec les autres tables :
- `ModelDetection_*` et `ModelSegmentation_*` : `IdModelDetectionVersion`, ou
  `IdModelVersion` comme pour le découpage ;
- `Detection_Test` et `Segmentation_Test` : `IdDetection`, `IdSegmentation` ;
- `DocumentField` et `DocumentProperty` : `IdField`, `NameField`, etc.

S'ils diffèrent dans un autre environnement, le contrôle `COLONNES` / `STRUCTURE`
le signale avant toute exécution.
