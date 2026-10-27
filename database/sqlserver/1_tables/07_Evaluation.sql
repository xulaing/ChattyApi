SET ANSI_NULLS ON
SET QUOTED_IDENTIFIER ON
SET NOCOUNT ON
GO
PRINT '=== DÉBUT DE LA MIGRATION [dbo].[Evaluation] ==='
GO
-- =======================================================
-- 1. CRÉATION DE LA TABLE (Si elle n'existe pas)
-- =======================================================
IF NOT EXISTS (
SELECT
*
FROM
sys.objects
WHERE
object_id = OBJECT_ID(N'[dbo].[Evaluation]')
AND type in (N'U')
) BEGIN
PRINT 'Création de la table [dbo].[Evaluation]...';
CREATE TABLE [dbo].[Evaluation](
    [Id] [int] IDENTITY(1, 1) NOT NULL,
    [ProjectId] [int] NOT NULL,
    [VersionNumber] [int] NOT NULL,
    [Name] [nvarchar](max) NULL,
    [Timestamp] [datetime2](7) NULL,
    [EvalPath] [nvarchar](max) NOT NULL,
    [GroundTruthFile] [nvarchar](max) NOT NULL,
    [PredictionFile] [nvarchar](max) NOT NULL,
    [TriggeredBy] [nvarchar](max) NULL,
    -- [FUSION ML] colonnes issues de l'ancienne table test_run (voir section 3)
    [TestDataCount] [int] NULL,
    [IsItc] [bit] NOT NULL,
    [Comment] [nvarchar](max) NULL,
    CONSTRAINT [PK_Evaluation] PRIMARY KEY CLUSTERED ([Id] ASC) WITH (
        PAD_INDEX = OFF,
        STATISTICS_NORECOMPUTE = OFF,
        IGNORE_DUP_KEY = OFF,
        ALLOW_ROW_LOCKS = ON,
        ALLOW_PAGE_LOCKS = ON,
        OPTIMIZE_FOR_SEQUENTIAL_KEY = OFF
    ) ON [PRIMARY]
) ON [PRIMARY];

PRINT 'Table [dbo].[Evaluation] créée avec succès.';

END
GO
-- =======================================================
-- 2. AJOUT DE CONTRAINTES (Si la table existe déjà)
-- =======================================================
PRINT 'Vérification et application des contraintes...'
GO
IF EXISTS (
SELECT 1 FROM sys.tables WHERE name = N'Evaluation' AND schema_id = SCHEMA_ID('dbo')
) BEGIN
-- 2.2. Gestion de la Contrainte Étrangère (FK) - Renommage
PRINT 'Gestion de la contrainte étrangère [FK_Evaluation_Project]...';

-- 2.2.A Suppression de l'ancienne contrainte si elle existe
IF EXISTS (
    SELECT 1
    FROM sys.foreign_keys
    WHERE object_id = OBJECT_ID(N'[dbo].[FK_Project_Evaluation]')
      AND parent_object_id = OBJECT_ID(N'[dbo].[Evaluation]')
) BEGIN
    PRINT 'Suppression de l''ancienne contrainte FK_Project_Evaluation...';
    ALTER TABLE [dbo].[Evaluation] DROP CONSTRAINT [FK_Project_Evaluation];
    PRINT 'Ancienne contrainte supprimée.';
END


-- 2.2.B Création de la nouvelle contrainte avec le bon nom
IF NOT EXISTS (
    SELECT 1
    FROM sys.foreign_keys
    WHERE object_id = OBJECT_ID(N'[dbo].[FK_Evaluation_Project]')
      AND parent_object_id = OBJECT_ID(N'[dbo].[Evaluation]')
) BEGIN
    PRINT 'Création de la nouvelle contrainte FK_Evaluation_Project...';
    ALTER TABLE [dbo].[Evaluation] WITH CHECK
    ADD CONSTRAINT [FK_Evaluation_Project] FOREIGN KEY([ProjectId]) REFERENCES [dbo].[Project] ([Id]);

    ALTER TABLE [dbo].[Evaluation] CHECK CONSTRAINT [FK_Evaluation_Project];
    PRINT 'Nouvelle contrainte FK_Evaluation_Project créée et vérifiée.';
END
ELSE BEGIN
    PRINT 'Contrainte FK_Evaluation_Project existante.';
END


-- 2.3. Modification du type datetime vers datetime2
PRINT '=== ÉTAPE 3 : Modernisation du type de date [Timestamp] ==='

IF EXISTS (
    SELECT 1
    FROM sys.columns
    WHERE Name = N'Timestamp' AND Object_ID = OBJECT_ID(N'[dbo].[Evaluation]')
) BEGIN
    DECLARE @CurrentDataType NVARCHAR(50);
    SELECT @CurrentDataType = DATA_TYPE
    FROM INFORMATION_SCHEMA.COLUMNS
    WHERE TABLE_NAME = N'Evaluation'
      AND COLUMN_NAME = N'Timestamp'
      AND TABLE_SCHEMA = N'dbo';

    IF @CurrentDataType = 'datetime' BEGIN
        PRINT 'Conversion du type [Timestamp] de datetime vers datetime2(7)...';
        ALTER TABLE [dbo].[Evaluation] ALTER COLUMN [Timestamp] [datetime2](7) NULL;
        PRINT 'Type modifié avec succès.';
    END
    ELSE IF @CurrentDataType = 'datetime2' BEGIN
        PRINT 'La colonne [Timestamp] est déjà de type datetime2(7).';
    END
    ELSE BEGIN
        PRINT 'Colonne [Timestamp] a un type inattendu : ' + @CurrentDataType;
    END
END
ELSE BEGIN
    PRINT 'Colonne [Timestamp] non trouvée, aucune action.';
END

END
GO
-- =======================================================
-- 3. [FUSION ML] ÉVALUATIONS LLM ET TESTS DE MODÈLES DANS LA MÊME TABLE
--    Une évaluation LLM et un test de modèle (ex-test_run) sont le même concept :
--    une version testée sur un jeu de données annoté. Correspondance :
--      test_run.model_version_id   -> ([ProjectId], [VersionNumber])  (existants)
--      test_run.test_data_path     -> [EvalPath]
--      test_run.annotation_file    -> [GroundTruthFile]
--      test_run.test_results_path  -> [PredictionFile]
--      test_run.created_by / _at   -> [TriggeredBy] / [Timestamp]
--      test_data_count, is_itc, comment -> nouvelles colonnes ci-dessous
--    Les métriques de test sont stockées en lignes dans [Evaluation_Metric].
-- =======================================================
PRINT 'Vérification des colonnes de fusion ML...'
GO
IF COL_LENGTH(N'[dbo].[Evaluation]', N'TestDataCount') IS NULL BEGIN
    ALTER TABLE [dbo].[Evaluation] ADD [TestDataCount] [int] NULL;
    PRINT 'Colonne [TestDataCount] ajoutée.';
END
ELSE BEGIN
    PRINT 'Colonne [TestDataCount] déjà présente.';
END
IF COL_LENGTH(N'[dbo].[Evaluation]', N'IsItc') IS NULL BEGIN
    -- Colonne bit NOT NULL ajoutée avec son default nommé à 0
    ALTER TABLE [dbo].[Evaluation] ADD [IsItc] [bit] NOT NULL
        CONSTRAINT [DF_Evaluation_IsItc] DEFAULT ((0));
    PRINT 'Colonne [IsItc] ajoutée.';
END
ELSE BEGIN
    PRINT 'Colonne [IsItc] déjà présente.';
END
IF COL_LENGTH(N'[dbo].[Evaluation]', N'Comment') IS NULL BEGIN
    ALTER TABLE [dbo].[Evaluation] ADD [Comment] [nvarchar](max) NULL;
    PRINT 'Colonne [Comment] ajoutée.';
END
ELSE BEGIN
    PRINT 'Colonne [Comment] déjà présente.';
END
GO
-- Batch séparé : les colonnes ajoutées ci-dessus existent à la compilation
DECLARE @df SYSNAME, @dfDef NVARCHAR(MAX), @dfOld NVARCHAR(300);
SET @df = NULL; SET @dfDef = NULL;
SELECT @df = name, @dfDef = definition
FROM sys.default_constraints
WHERE parent_object_id = OBJECT_ID(N'[dbo].[Evaluation]')
  AND parent_column_id = COLUMNPROPERTY(OBJECT_ID(N'[dbo].[Evaluation]'), 'IsItc', 'ColumnId');
IF COL_LENGTH(N'[dbo].[Evaluation]', N'IsItc') IS NULL BEGIN
    PRINT 'ATTENTION : colonne [Evaluation].[IsItc] absente, default [DF_Evaluation_IsItc] non traité.';
END
-- Aucun default sur la colonne (ni nommé, ni anonyme) : création
ELSE IF @df IS NULL BEGIN
    IF OBJECT_ID(N'[dbo].[DF_Evaluation_IsItc]') IS NOT NULL BEGIN
        PRINT 'ATTENTION : le nom [DF_Evaluation_IsItc] est déjà utilisé par un autre objet, default non créé.';
    END
    ELSE BEGIN
        ALTER TABLE [dbo].[Evaluation] ADD CONSTRAINT [DF_Evaluation_IsItc] DEFAULT ((0)) FOR [IsItc];
        PRINT 'Default [DF_Evaluation_IsItc] ajouté.';
    END
END
-- Un default existe déjà (éventuellement anonyme) : on n'en crée JAMAIS un second
ELSE BEGIN
    IF @df <> N'DF_Evaluation_IsItc' BEGIN
        IF OBJECT_ID(N'[dbo].[DF_Evaluation_IsItc]') IS NOT NULL BEGIN
            PRINT 'ATTENTION : default ' + @df + ' conservé, le nom [DF_Evaluation_IsItc] est déjà utilisé par un autre objet.';
        END
        ELSE BEGIN
            SET @dfOld = N'[dbo].' + QUOTENAME(@df);
            EXEC sp_rename @dfOld, N'DF_Evaluation_IsItc', N'OBJECT';
            PRINT 'Default ' + @df + ' renommé en [DF_Evaluation_IsItc].';
        END
    END
    ELSE BEGIN
        PRINT 'Default [DF_Evaluation_IsItc] existant.';
    END
    IF @dfDef <> N'((0))' BEGIN
        PRINT 'ATTENTION : le default de [Evaluation].[IsItc] vaut ' + @dfDef + ' au lieu de ((0)) (conservé, à vérifier).';
    END
END
IF NOT EXISTS (
    SELECT 1 FROM sys.check_constraints
    WHERE name = N'CK_Evaluation_TestDataCount' AND parent_object_id = OBJECT_ID(N'[dbo].[Evaluation]')
) BEGIN
    ALTER TABLE [dbo].[Evaluation] WITH CHECK ADD CONSTRAINT [CK_Evaluation_TestDataCount] CHECK ([TestDataCount] IS NULL OR [TestDataCount] >= 0);
    PRINT 'Contrainte [CK_Evaluation_TestDataCount] ajoutée.';
END
ELSE BEGIN
    PRINT 'Contrainte [CK_Evaluation_TestDataCount] existante.';
END
GO
-- 3.1 Clé étrangère composite vers la version évaluée.
--     Jusqu'ici [VersionNumber] n'était relié à rien : une évaluation pouvait viser une
--     version inexistante. La FK s'appuie sur la contrainte unique
--     UQ_Project_Version_ProjectId_VersionNumber (05_Project_Version.sql).
--     - ON UPDATE CASCADE : une version renumérotée garde ses évaluations ;
--     - pas de ON DELETE : supprimer une version qui a des évaluations est refusé
--       (aucune suppression silencieuse de résultats).
--     Pas créée (avertissement) si la contrainte unique est absente ou si des
--     évaluations visent une version inexistante.
IF NOT EXISTS (
    SELECT 1 FROM sys.foreign_keys
    WHERE name = N'FK_Evaluation_ProjectVersion'
      AND parent_object_id = OBJECT_ID(N'[dbo].[Evaluation]')
) BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM sys.indexes
        WHERE name = N'UQ_Project_Version_ProjectId_VersionNumber'
          AND object_id = OBJECT_ID(N'[dbo].[Project_Version]')
    ) BEGIN
        PRINT 'ATTENTION : [UQ_Project_Version_ProjectId_VersionNumber] absente (doublons de versions), FK [FK_Evaluation_ProjectVersion] non créée.';
    END
    ELSE IF EXISTS (
        SELECT 1 FROM [dbo].[Evaluation] e
        WHERE NOT EXISTS (
            SELECT 1 FROM [dbo].[Project_Version] pv
            WHERE pv.[ProjectId] = e.[ProjectId] AND pv.[VersionNumber] = e.[VersionNumber]
        )
    ) BEGIN
        PRINT 'ATTENTION : des évaluations visent une version inexistante, FK [FK_Evaluation_ProjectVersion] non créée.';
        PRINT '            Liste : SELECT e.* FROM dbo.Evaluation e WHERE NOT EXISTS (SELECT 1 FROM dbo.Project_Version pv WHERE pv.ProjectId = e.ProjectId AND pv.VersionNumber = e.VersionNumber);';
    END
    ELSE BEGIN
        ALTER TABLE [dbo].[Evaluation] WITH CHECK ADD CONSTRAINT [FK_Evaluation_ProjectVersion]
            FOREIGN KEY ([ProjectId], [VersionNumber])
            REFERENCES [dbo].[Project_Version] ([ProjectId], [VersionNumber])
            ON UPDATE CASCADE;
        PRINT 'Contrainte [FK_Evaluation_ProjectVersion] ajoutée.';
    END
END
ELSE BEGIN
    PRINT 'Contrainte [FK_Evaluation_ProjectVersion] existante.';
END
GO
-- 3.2 Index de la FK (SQL Server n'indexe pas automatiquement les clés étrangères)
IF NOT EXISTS (
    SELECT 1 FROM sys.indexes
    WHERE name = N'IX_Evaluation_ProjectId_VersionNumber' AND object_id = OBJECT_ID(N'[dbo].[Evaluation]')
) BEGIN
    CREATE NONCLUSTERED INDEX [IX_Evaluation_ProjectId_VersionNumber] ON [dbo].[Evaluation] ([ProjectId] ASC, [VersionNumber] ASC);
    PRINT 'Index [IX_Evaluation_ProjectId_VersionNumber] créé.';
END
ELSE BEGIN
    PRINT 'Index [IX_Evaluation_ProjectId_VersionNumber] existant.';
END
GO
PRINT '=== FIN DE LA MIGRATION [dbo].[Evaluation] ==='
GO
