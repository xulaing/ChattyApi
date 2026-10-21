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
| `03_Project` | Default de `CreatedAt` nommé dans le `CREATE TABLE` ; defaults recherchés par colonne (erreur 1781 « Column already has a DEFAULT ») |
| `04_Project_History` | Defaults recherchés par colonne |
| `05_Project_Version` | Passage de `ProjectId` en NOT NULL uniquement si nécessaire, avant la FK, FK retirée avant l'`ALTER` (erreur 5074) ; `DeliveredToProduction` ajoutée en `bit` au lieu de `nvarchar(max)` et convertie si déjà créée en nvarchar |
| `06_Project_Member` | Conversion `UserId` bigint → int : PK/FK retirées avant l'`ALTER` puis PK recréée (erreur 5074) ; `UpdatedBy` en `nvarchar(max)` au lieu de `nvarchar` (= 1 caractère), élargie si besoin |
