# Refonte du schéma de base de données

La base actuelle compte **~28 tables**, dont la grande majorité sont des copies
quasi identiques déclinées par type de modèle (classification, segmentation,
détection, extraction, découpage). Le schéma proposé les fusionne en
**13 tables** grâce à un discriminateur `model_type` et à une table de
métriques clé/valeur.

- DDL complet : [`schema.sql`](./schema.sql) (PostgreSQL)
- Diagramme ER : [`schema.mmd`](./schema.mmd) (Mermaid)

## Problèmes du schéma actuel

1. **Duplication massive par type de modèle** — 4 familles de tables recopiées
   pour chaque type de tâche ML :
   - 5 tables `Model*_Version` (~15 colonnes communes chacune)
   - 5 tables `Model*_Version_Test`
   - 4 tables `*TrainTrack`
   - 5 tables `*_Test` (résultats d'inférence) **strictement identiques**
     colonne pour colonne.

   Conséquence : chaque évolution (nouvelle colonne, nouvel index, nouveau
   type de modèle) doit être répétée 4 à 5 fois, et toute requête transverse
   (« toutes les versions en prod », « tous les entraînements en cours »)
   nécessite des `UNION` sur 5 tables.

2. **Métriques en colonnes** — chaque variante ajoute ses propres colonnes de
   métriques (`AP_bbox`, `Recall_segm`, `kappa`, `MeanErrors`…), ce qui est la
   cause première de la duplication des tables.

3. **Préfixes de colonnes redondants** — `NameClass`, `CreatorClass`,
   `DateCreateClass`… le nom de la table suffit.

4. **Colonnes dénormalisées** — `VersionNb` recopié dans les tables de test et
   de suivi d'entraînement alors que `IdModelVersion` le porte déjà ;
   `IdModel` recopié dans les tables d'association alors que la version
   connaît déjà son modèle.

5. **Absence de traçabilité** — les tables `*_Test` d'inférence ne référencent
   aucun modèle : impossible de savoir quelle version a produit un résultat.

6. **Audit incohérent** — certaines tables ont créateur/updater/dates,
   d'autres seulement une partie.

## Principes du nouveau schéma

| Principe | Mise en œuvre |
|---|---|
| Un concept = une table | `model_version`, `training_run`, `test_run`, `inference_request` uniques, quel que soit le type de modèle |
| Discriminateur de type | `model.model_type` (ENUM) — le type est porté une seule fois, au niveau du modèle |
| Métriques en lignes | table `metric (name, value, scope)` : accepte `accuracy` comme `ap_bbox` ou `kappa` sans changer le schéma |
| Clés étrangères réelles | toutes les relations sont contraintes (`REFERENCES` + `ON DELETE`) |
| Audit uniforme | `created_by/created_at` partout, `updated_by/updated_at` sur les référentiels |
| Invariants en base | une seule version `in_prod` par modèle (index unique partiel), unicité `(model_id, version_nb)` |

## Correspondance ancien → nouveau

| Tables actuelles | Nouvelle table |
|---|---|
| `Model` | `model` (+ colonne `model_type`) |
| `Model_Version`, `ModelSegmentation_Version`, `ModelDecoupage_Version`, `ModelDetection_Version`, `ModelExtraction_Version` | `model_version` (métriques → `metric` avec `scope='validation'`) |
| `Model_Version_Test`, `ModelSegmentation_Version_Test`, `ModelDecoupage_Version_Test`, `ModelDetection_Version_Test`, `ModelExtraction_Version_Test` | `test_run` (métriques → `metric` avec `scope='test'`) |
| `Evaluation_Run` | `test_run` (une évaluation est un test sur un dataset) |
| `TrainTrack`, `SegmentationTrainTrack`, `DetectionTrainTrack`, `ExtractionTrainTrack` | `training_run` |
| `Classification_Test`, `Segmentation_Test`, `Detection_Test`, `Extraction_Test`, `Decoupage_Test` | `inference_request` (le type part dans `task_type`) |
| `DocumentClass` | `document_class` |
| `DocumentField` | `document_field` |
| `DocumentProperty` | `document_property` |
| `DocumentClassProjects` | `model_version_document_class` (sans `IdModel`, redondant) |
| `DocumentFieldProjects` | `model_version_document_field` |
| `DocumentPropertyProjects` | `model_version_document_property` |
| `DocumentRequest` | `document_request` |

**Bilan : 28 tables → 13 tables**, sans perte d'information.

## Correspondance des colonnes de métriques

Les colonnes de métriques des anciennes tables deviennent des lignes de
`metric` :

| Ancienne colonne | `metric.name` |
|---|---|
| `Accuracy` | `accuracy` |
| `ErrorRate` | `error_rate` |
| `PrecisionScore` | `precision` |
| `RecallScore` | `recall` |
| `f1_score` | `f1` |
| `kappa` | `kappa` |
| `AP_bbox` / `Recall_bbox` | `ap_bbox` / `recall_bbox` |
| `AP_segm` / `Recall_segm` | `ap_segm` / `recall_segm` |
| `MeanErrors` / `NbErrors` | `mean_errors` / `nb_errors` |

Exemple de lecture « à plat » des métriques de validation d'une version :

```sql
SELECT mv.version_nb,
       MAX(value) FILTER (WHERE m.name = 'accuracy') AS accuracy,
       MAX(value) FILTER (WHERE m.name = 'f1')       AS f1,
       MAX(value) FILTER (WHERE m.name = 'ap_bbox')  AS ap_bbox
FROM model_version mv
JOIN metric m ON m.model_version_id = mv.id AND m.scope = 'validation'
WHERE mv.model_id = $1
GROUP BY mv.id, mv.version_nb
ORDER BY mv.version_nb;
```

## Notes de migration

- Les identifiants des 5 anciennes tables de versions se chevauchent :
  prévoir une table de correspondance `(ancienne_table, ancien_id) → nouvel_id`
  pendant la migration pour recâbler les FK.
- Les anciennes tables d'inférence n'ayant pas de FK modèle,
  `inference_request.model_version_id` est nullable ; le renseigner pour
  toutes les nouvelles inférences.
- `run_status` (ENUM) remplace les statuts texte libres de `StatusTrain` :
  mapper les valeurs existantes lors de la migration.
