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
