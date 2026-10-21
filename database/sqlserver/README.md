# Scripts SQL Server — OCR Studio

Scripts idempotents : ils peuvent être rejoués sur une base vide comme sur une
base déjà livrée.

## Ordre d'exécution

1. **`1_tables/`** — un script par table, **dans l'ordre des préfixes numériques**
   (les clés étrangères exigent que la table référencée existe déjà) :
   `01_Team` → `02_User` → `03_Project` → `04_Project_History` →
   `05_Project_Version` → `06_Project_Member` → `07_Evaluation`
2. **`2_procedures/`** — triggers (et procédures de l'application). Exécutés
   après toutes les tables, car ils écrivent dans `Project_History` et lisent `User`.
3. **`3_init/`** — données d'initialisation (équipes H620, H600, H500).

Exécuter avec `sqlcmd -b` (ou SSMS en mode SQLCMD avec `:on error exit`) pour
arrêter le déploiement à la première erreur.

## Correctifs par rapport au script d'origine

Chaque correctif est signalé dans le code par un commentaire `[CORRECTIF]`,
chaque déplacement par `[RÉORGANISATION]`.

| Script | Correctif |
|---|---|
| tous | Defaults recherchés **par colonne** : si la colonne a déjà un default, nommé ou anonyme, aucun second default n'est créé (erreur 1781). Un default anonyme (`DF__Project__Creat__XXXX`) est renommé au nom standard. Messages `ATTENTION` (sans erreur) si le nom standard est déjà pris par un autre objet, ou si le default existant n'a pas la valeur attendue (il est alors conservé) |
| `01_Team`, `02_User` | Defaults bit à 0 : `DF_Team_CanViewAll`, `DF_User_IsAdmin` |
| `03_Project` | Plus de default anonyme dans le `CREATE TABLE` : `DF_Project_CreatedAt` est posé avec les autres defaults (`IsActive` garde son default à 1) |
| `04_Project_History` | Suppression de `FK_ProjectHistory_Project` : elle empêchait toute suppression de projet (erreur 547). `EntityName` ajoutée en `varchar(25)`, alimentée pour les lignes existantes puis passée en NOT NULL |
| `05_Project_Version` | `ProjectId` passé en NOT NULL uniquement si nécessaire, avant la FK, FK retirée avant l'`ALTER` (erreur 5074) ; `DeliveredToProduction` en `bit` (convertie si déjà créée en nvarchar) ; defaults `State` = `'ONGOING'` et `DeliveredToProduction` = 0 garantis |
| `06_Project_Member` | Conversion `UserId` bigint → int : PK/FK retirées avant l'`ALTER` puis PK recréée (erreur 5074) ; `UpdatedBy` en `nvarchar(max)` au lieu de `nvarchar` (= 1 caractère), élargie si besoin |
| `2_procedures/trg_*` | `DeleterId` lu avec `TRY_CAST` en int (une valeur non numérique ne fait plus échouer la suppression) ; `**` en trop retiré du message « archivée » |
