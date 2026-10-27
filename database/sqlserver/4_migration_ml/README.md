# Migration des données de l'ancienne base des modèles entraînés

Reprise ponctuelle des données de l'ancienne base (28 tables `Model*`,
`*TrainTrack`, `*_Test`, `Document*`) dans la base fusionnée.

## Utilisation

```powershell
# 1. Contrôle de l'export et génération du script SQL
.\Convert-LegacyMlExport.ps1 -InputFile .\export_ancienne_base.txt -Strict

# 2. Exécution sur la base cible (schéma 1_tables déjà déployé)
sqlcmd -S <serveur> -d <base> -b -i .\export_ancienne_base_migration.sql
```

| Paramètre | Rôle |
|---|---|
| `-InputFile` | Export texte de l'ancienne base (format ci-dessous) |
| `-OutputFile` | Script SQL généré (défaut : `<InputFile>_migration.sql`) |
| `-Strict` | Aucun script généré si une table migrée présente un écart (recommandé en production) |
| `-TrainStatusMap` | `StatusTrain` → `Ref_RunStatus`. Défaut `@{0='RUNNING';1='SUCCEEDED';2='FAILED'}` : **à valider** |
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
- Le JSON coupé en lignes de ~2000 caractères (sortie `FOR JSON`, parfois au
  milieu d'un mot) est recollé sans séparateur.
- `Table vide : []` = table vide.

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
4. **Tables sans cible** (`Logs_IHM`, `Parameters`, `Processor`, `Pipeline*`) :
   contrôlées et affichées, mais pas migrées.

## Le script SQL généré

- **Chargement :** les lignes sont chargées dans `#Src`, une table temporaire. Le
  script vérifie qu'elles sont toutes arrivées et que chacune est un JSON valide.
- **Transaction unique :** les 14 tables cibles sont alimentées dans **une seule
  transaction**. Si une table échoue, tout est annulé (`XACT_ABORT` + `TRY/CATCH`).
  Le message indique l'étape et les lignes en cause.
- **Rejouable :** `dbo.Migration_LegacyMap` (créée si besoin) garde la correspondance
  `(table source, ancien Id) → nouvel Id`. Une ligne déjà migrée n'est jamais recopiée,
  ce qui permet de relancer avec un export complété.
- **Historique :** les triggers d'insertion (`trg_Project_Insert`,
  `trg_ProjectVersion_Insert`) sont suspendus pendant la transaction. Sans cela,
  chaque élément migré créerait une entrée « a été créé » datée du jour de la migration.
- **Exécution :** dans une seule session (sqlcmd ou SSMS), car `#Src` est une table
  temporaire.

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

### Erreurs bloquantes (rollback complet)

- Une ligne dont l'identifiant source est introuvable : nom de colonne inattendu.
- Un identifiant source en double.
- Un modèle dont le type de tâche n'est pas reconnu.
- Une version, un test ou un entraînement dont le parent est introuvable.
- Un numéro de version en double pour un même modèle.
- Un test sans `TestDataPath`.
- Un `StatusTrain` absent de `-TrainStatusMap`.
- Une association dont la version ou l'élément est introuvable.
- Une valeur trop longue ou invalide pour la colonne cible.

## À valider avant la migration de production

1. **`-TrainStatusMap`** : 0 = `RUNNING`, 1 = `SUCCEEDED`, 2 = `FAILED`. Cette
   correspondance a été déduite des données : statut 1 pour les entraînements longs
   terminés par « End Training », statut 2 pour les arrêts au bout de quelques secondes.
2. **Noms de colonnes des tables vides ou non visibles dans l'extrait**
   (`ModelDetection_*`, `ModelSegmentation_*`, `Detection_Test`, `Segmentation_Test`,
   `DocumentField`, `DocumentProperty`) : ils ont été déduits par analogie
   (`IdModelDetectionVersion`, `IdField`, `NameField`…). S'ils diffèrent, la
   migration s'arrête avec « Identifiant source introuvable » et le nom de la table.
   Il suffit alors d'ajouter le nom de colonne réel dans le `OPENJSON ... WITH`
   correspondant.
