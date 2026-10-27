SET ANSI_NULLS ON
SET QUOTED_IDENTIFIER ON
SET NOCOUNT ON
GO
PRINT '=== DÉBUT DE LA MIGRATION [dbo].[Project_Version] ==='
GO
-- =======================================================
-- 1. CRÉATION DE LA TABLE (Si elle n'existe pas)
-- =======================================================
IF NOT EXISTS (
SELECT *
FROM sys.objects
WHERE object_id = OBJECT_ID(N'[dbo].[Project_Version]')
AND type in (N'U')
) BEGIN
PRINT 'Création de la table [dbo].[Project_Version]...';
CREATE TABLE [dbo].[Project_Version](
    [Id] [int] IDENTITY(1, 1) NOT NULL,
    [ProjectId] [int] NOT NULL,
    [VersionNumber] [int] NOT NULL,
    [Description] [nvarchar](max) NULL,
    [ConfigLLMPath] [nvarchar](max) NULL,
    [SdaConfigPath] [nvarchar](max) NULL,
    [CreatedAt] [datetime2](7) NULL,
    [CreatedBy] [nvarchar](max) NULL,
    [UpdatedBy] [nvarchar](max) NULL,
    [Title] [nvarchar](50) NULL,
    [DeliveredToProduction] [bit] NOT NULL,
    [State] nvarchar(max) NOT NULL,
    -- [FUSION ML] colonnes issues de l'ancienne table model_version (voir section 3)
    [Algo] [nvarchar](100) NULL,
    [ModelPath] [nvarchar](max) NULL,
    [AnnotationFile] [nvarchar](max) NULL,
    [TrainDataPath] [nvarchar](max) NULL,
    [TrainDataCount] [int] NULL,
    [ValidDataCount] [int] NULL,
    [IsItc] [bit] NOT NULL,
    CONSTRAINT [PK_Project_Version] PRIMARY KEY CLUSTERED ([Id] ASC) WITH (
        PAD_INDEX = OFF,
        STATISTICS_NORECOMPUTE = OFF,
        IGNORE_DUP_KEY = OFF,
        ALLOW_ROW_LOCKS = ON,
        ALLOW_PAGE_LOCKS = ON,
        OPTIMIZE_FOR_SEQUENTIAL_KEY = OFF
    ) ON [PRIMARY]
) ON [PRIMARY] TEXTIMAGE_ON [PRIMARY];

PRINT 'Table [dbo].[Project_Version] créée avec succès.';

END
GO
-- =======================================================
-- 2. MODIFICATIONS DE STRUCTURE (Si la table existe déjà)
-- =======================================================
PRINT 'Vérification et application des modifications de structure...'
GO
IF EXISTS (
SELECT 1 FROM sys.tables WHERE name = N'Project_Version' AND schema_id = SCHEMA_ID('dbo')
) BEGIN

-- 2.3. Modification de la colonne [ProjectId] en NOT NULL
-- [CORRECTIF] étape placée AVANT la création de la FK, exécutée seulement si la colonne
--             est encore nullable, et les FK sur [ProjectId] sont retirées avant l'ALTER :
--             un ALTER COLUMN sur une colonne portant une FK échoue (erreur 5074).
--             La FK est (re)créée à l'étape 2.1 juste après.
PRINT 'Vérification des données avant passage en NOT NULL pour ProjectId...';

IF EXISTS (
    SELECT 1
    FROM sys.columns
    WHERE Name = N'ProjectId' AND Object_ID = OBJECT_ID(N'[dbo].[Project_Version]') AND is_nullable = 1
) BEGIN
    IF EXISTS (
        SELECT 1 FROM [dbo].[Project_Version] WHERE [ProjectId] IS NULL
    ) BEGIN
        PRINT 'ERREUR CRITIQUE : La colonne ProjectId contient des valeurs NULL.';
        -- RAISERROR arrête l'exécution dans SSMS, mais dans les projets DB, mieux de signaler
        RAISERROR ('ERREUR CRITIQUE : La colonne ProjectId contient des valeurs NULL. Impossible de la passer en NOT NULL.', 16, 1);
        RETURN; -- Arrête le script proprement si utilisé dans une proc
    END
    ELSE BEGIN
        DECLARE @DropFk NVARCHAR(MAX) = N'';
        SELECT @DropFk += N'ALTER TABLE [dbo].[Project_Version] DROP CONSTRAINT ' + QUOTENAME(fk.name) + N';'
        FROM sys.foreign_keys fk
        JOIN sys.foreign_key_columns fkc ON fkc.constraint_object_id = fk.object_id
        WHERE fk.parent_object_id = OBJECT_ID(N'[dbo].[Project_Version]')
          AND fkc.parent_column_id = COLUMNPROPERTY(OBJECT_ID(N'[dbo].[Project_Version]'), 'ProjectId', 'ColumnId');
        IF @DropFk <> N'' EXEC sys.sp_executesql @DropFk;

        ALTER TABLE [dbo].[Project_Version] ALTER COLUMN [ProjectId] [int] NOT NULL;
        PRINT 'Colonne [ProjectId] mise à jour en NOT NULL.';
    END
END
ELSE BEGIN
    PRINT 'Colonne [ProjectId] déjà NOT NULL.';
END

-- 2.1. Renommage de la Contrainte Étrangère (FK)
-- Nettoyage de l'ancien nom si présent
IF EXISTS (
    SELECT 1
    FROM sys.foreign_keys
    WHERE object_id = OBJECT_ID(N'[dbo].[FK_Project_ProjectVersion]')
      AND parent_object_id = OBJECT_ID(N'[dbo].[Project_Version]')
) BEGIN
    PRINT 'Suppression de l''ancienne contrainte FK_Project_ProjectVersion...';
    ALTER TABLE [dbo].[Project_Version] DROP CONSTRAINT [FK_Project_ProjectVersion];
    PRINT 'Ancienne contrainte supprimée.';
END

-- Création de la nouvelle contrainte avec le bon nom
IF NOT EXISTS (
    SELECT 1
    FROM sys.foreign_keys
    WHERE object_id = OBJECT_ID(N'[dbo].[FK_ProjectVersion_Project]')
      AND parent_object_id = OBJECT_ID(N'[dbo].[Project_Version]')
) BEGIN
    PRINT 'Création de la nouvelle contrainte FK_ProjectVersion_Project...';
    ALTER TABLE [dbo].[Project_Version] WITH CHECK
    ADD CONSTRAINT [FK_ProjectVersion_Project] FOREIGN KEY([ProjectId]) REFERENCES [dbo].[Project] ([Id]);

    ALTER TABLE [dbo].[Project_Version] CHECK CONSTRAINT [FK_ProjectVersion_Project];
    PRINT 'Nouvelle contrainte créée et validée.';
END
ELSE BEGIN
    PRINT 'Contrainte FK_ProjectVersion_Project existante.';
END

-- 2.2. Modification du type datetime vers datetime2
PRINT 'Vérification du type [CreatedAt]...';

-- On sépare ici pour être sûr que le batch est propre avant les actions suivantes
IF EXISTS (
    SELECT 1
    FROM sys.columns
    WHERE Name = N'CreatedAt' AND Object_ID = OBJECT_ID(N'[dbo].[Project_Version]')
) BEGIN
    DECLARE @CurrentDataType NVARCHAR(50);
    SELECT @CurrentDataType = DATA_TYPE
    FROM INFORMATION_SCHEMA.COLUMNS
    WHERE TABLE_NAME = N'Project_Version' AND COLUMN_NAME = N'CreatedAt' AND TABLE_SCHEMA = N'dbo';

    IF @CurrentDataType = 'datetime' BEGIN
        PRINT 'Conversion du type [CreatedAt] de datetime vers datetime2(7)...';
        ALTER TABLE [dbo].[Project_Version] ALTER COLUMN [CreatedAt] [datetime2](7) NULL;
        PRINT 'Type modifié avec succès.';
    END
    ELSE IF @CurrentDataType = 'datetime2' BEGIN
        PRINT 'Colonne [CreatedAt] est déjà de type datetime2.';
    END
    ELSE BEGIN
        PRINT 'Colonne [CreatedAt] a un type inattendu (' + @CurrentDataType + ').';
    END
END


-- 2.4. Ajout de la colonne [State] si manquante
PRINT 'Vérification de la colonne [State]...'
IF NOT EXISTS (
    SELECT 1
    FROM INFORMATION_SCHEMA.COLUMNS
    WHERE TABLE_SCHEMA = 'dbo' AND TABLE_NAME = 'Project_Version' AND COLUMN_NAME = 'State'
) BEGIN
    ALTER TABLE [dbo].[Project_Version]
    ADD [State] nvarchar(max) NOT NULL
    CONSTRAINT DF_ProjectVersion_State DEFAULT 'ONGOING';
    PRINT 'Colonne [State] ajoutée.';
END
ELSE BEGIN
    PRINT 'Colonne [State] existante.';
END

 -- 2.5. Ajout de la colonne [DeliveredToProduction] si manquante
 -- [CORRECTIF] type bit (comme dans le CREATE TABLE) au lieu de nvarchar(max)
PRINT 'Vérification de la colonne [DeliveredToProduction]...'
IF NOT EXISTS (
    SELECT 1
    FROM INFORMATION_SCHEMA.COLUMNS
    WHERE TABLE_SCHEMA = 'dbo' AND TABLE_NAME = 'Project_Version' AND COLUMN_NAME = 'DeliveredToProduction'
) BEGIN
    ALTER TABLE [dbo].[Project_Version]
    ADD [DeliveredToProduction] [bit] NOT NULL
    CONSTRAINT DF_ProjectVersion_DeliveredToProduction DEFAULT 0;
    PRINT 'Colonne [DeliveredToProduction] ajoutée.';
END
ELSE BEGIN
    PRINT 'Colonne [DeliveredToProduction] existante.';
END

END
GO
-- 2.6. [CORRECTIF] Si [DeliveredToProduction] a déjà été créée en nvarchar(max) par l'ancien
--      script, conversion en bit. Batch séparé : la colonne existe forcément à la compilation.
--      Le default est retiré avant l'ALTER (sinon erreur 5074) ; il est recréé à l'étape 2.7.
IF EXISTS (
    SELECT 1
    FROM INFORMATION_SCHEMA.COLUMNS
    WHERE TABLE_SCHEMA = 'dbo' AND TABLE_NAME = 'Project_Version'
      AND COLUMN_NAME = 'DeliveredToProduction' AND DATA_TYPE <> 'bit'
) BEGIN
    IF EXISTS (SELECT 1 FROM [dbo].[Project_Version] WHERE TRY_CAST([DeliveredToProduction] AS bit) IS NULL)
    BEGIN
        RAISERROR ('ERREUR CRITIQUE : [DeliveredToProduction] contient des valeurs non convertibles en bit.', 16, 1);
        RETURN;
    END

    DECLARE @DropDf NVARCHAR(MAX) = N'';
    SELECT @DropDf += N'ALTER TABLE [dbo].[Project_Version] DROP CONSTRAINT ' + QUOTENAME(name) + N';'
    FROM sys.default_constraints
    WHERE parent_object_id = OBJECT_ID(N'[dbo].[Project_Version]')
      AND parent_column_id = COLUMNPROPERTY(OBJECT_ID(N'[dbo].[Project_Version]'), 'DeliveredToProduction', 'ColumnId');
    IF @DropDf <> N'' EXEC sys.sp_executesql @DropDf;

    ALTER TABLE [dbo].[Project_Version] ALTER COLUMN [DeliveredToProduction] [bit] NOT NULL;
    PRINT 'Colonne [DeliveredToProduction] convertie en bit.';
END
GO
-- 2.7. [CORRECTIF] Defaults de [State] ('ONGOING') et [DeliveredToProduction] (0) garantis
--      aussi quand la table est créée par le CREATE TABLE (qui n'en pose pas).
--      Recherche par colonne ; un default existant au nom auto-généré est renommé.
DECLARE @df SYSNAME, @dfDef NVARCHAR(MAX), @dfOld NVARCHAR(300);

SET @df = NULL; SET @dfDef = NULL;
SELECT @df = name, @dfDef = definition
FROM sys.default_constraints
WHERE parent_object_id = OBJECT_ID(N'[dbo].[Project_Version]')
  AND parent_column_id = COLUMNPROPERTY(OBJECT_ID(N'[dbo].[Project_Version]'), 'State', 'ColumnId');
IF COL_LENGTH(N'[dbo].[Project_Version]', N'State') IS NULL BEGIN
    PRINT 'ATTENTION : colonne [Project_Version].[State] absente, default [DF_ProjectVersion_State] non traité.';
END
-- Aucun default sur la colonne (ni nommé, ni anonyme) : création
ELSE IF @df IS NULL BEGIN
    IF OBJECT_ID(N'[dbo].[DF_ProjectVersion_State]') IS NOT NULL BEGIN
        PRINT 'ATTENTION : le nom [DF_ProjectVersion_State] est déjà utilisé par un autre objet, default non créé.';
    END
    ELSE BEGIN
        ALTER TABLE [dbo].[Project_Version] ADD CONSTRAINT [DF_ProjectVersion_State] DEFAULT ('ONGOING') FOR [State];
        PRINT 'Default [DF_ProjectVersion_State] ajouté.';
    END
END
-- Un default existe déjà (éventuellement anonyme) : on n'en crée JAMAIS un second
ELSE BEGIN
    IF @df <> N'DF_ProjectVersion_State' BEGIN
        IF OBJECT_ID(N'[dbo].[DF_ProjectVersion_State]') IS NOT NULL BEGIN
            PRINT 'ATTENTION : default ' + @df + ' conservé, le nom [DF_ProjectVersion_State] est déjà utilisé par un autre objet.';
        END
        ELSE BEGIN
            SET @dfOld = N'[dbo].' + QUOTENAME(@df);
            EXEC sp_rename @dfOld, N'DF_ProjectVersion_State', N'OBJECT';
            PRINT 'Default ' + @df + ' renommé en [DF_ProjectVersion_State].';
        END
    END
    ELSE BEGIN
        PRINT 'Default [DF_ProjectVersion_State] existant.';
    END
    IF @dfDef <> N'(''ONGOING'')' BEGIN
        PRINT 'ATTENTION : le default de [Project_Version].[State] vaut ' + @dfDef + ' au lieu de (''ONGOING'') (conservé, à vérifier).';
    END
END

SET @df = NULL; SET @dfDef = NULL;
SELECT @df = name, @dfDef = definition
FROM sys.default_constraints
WHERE parent_object_id = OBJECT_ID(N'[dbo].[Project_Version]')
  AND parent_column_id = COLUMNPROPERTY(OBJECT_ID(N'[dbo].[Project_Version]'), 'DeliveredToProduction', 'ColumnId');
IF COL_LENGTH(N'[dbo].[Project_Version]', N'DeliveredToProduction') IS NULL BEGIN
    PRINT 'ATTENTION : colonne [Project_Version].[DeliveredToProduction] absente, default [DF_ProjectVersion_DeliveredToProduction] non traité.';
END
-- Aucun default sur la colonne (ni nommé, ni anonyme) : création
ELSE IF @df IS NULL BEGIN
    IF OBJECT_ID(N'[dbo].[DF_ProjectVersion_DeliveredToProduction]') IS NOT NULL BEGIN
        PRINT 'ATTENTION : le nom [DF_ProjectVersion_DeliveredToProduction] est déjà utilisé par un autre objet, default non créé.';
    END
    ELSE BEGIN
        ALTER TABLE [dbo].[Project_Version] ADD CONSTRAINT [DF_ProjectVersion_DeliveredToProduction] DEFAULT ((0)) FOR [DeliveredToProduction];
        PRINT 'Default [DF_ProjectVersion_DeliveredToProduction] ajouté.';
    END
END
-- Un default existe déjà (éventuellement anonyme) : on n'en crée JAMAIS un second
ELSE BEGIN
    IF @df <> N'DF_ProjectVersion_DeliveredToProduction' BEGIN
        IF OBJECT_ID(N'[dbo].[DF_ProjectVersion_DeliveredToProduction]') IS NOT NULL BEGIN
            PRINT 'ATTENTION : default ' + @df + ' conservé, le nom [DF_ProjectVersion_DeliveredToProduction] est déjà utilisé par un autre objet.';
        END
        ELSE BEGIN
            SET @dfOld = N'[dbo].' + QUOTENAME(@df);
            EXEC sp_rename @dfOld, N'DF_ProjectVersion_DeliveredToProduction', N'OBJECT';
            PRINT 'Default ' + @df + ' renommé en [DF_ProjectVersion_DeliveredToProduction].';
        END
    END
    ELSE BEGIN
        PRINT 'Default [DF_ProjectVersion_DeliveredToProduction] existant.';
    END
    IF @dfDef <> N'((0))' BEGIN
        PRINT 'ATTENTION : le default de [Project_Version].[DeliveredToProduction] vaut ' + @dfDef + ' au lieu de ((0)) (conservé, à vérifier).';
    END
END
GO
-- =======================================================
-- 3. [FUSION ML] VERSIONS LLM ET VERSIONS DE MODÈLES DANS LA MÊME TABLE
--    L'ancienne table model_version est absorbée par [Project_Version] :
--      model_version.version_nb       -> [VersionNumber]          (existant)
--      model_version.comment          -> [Description]            (existant)
--      model_version.in_prod          -> [DeliveredToProduction]  (existant : même
--                                        règle « une seule version en prod par projet »,
--                                        déjà appliquée par trg_ProjectVersion_Update)
--      model_version.created_by/at    -> [CreatedBy] / [CreatedAt] (existants)
--      algo, model_path, annotation_file, train_data_path,
--      train_data_count, valid_data_count, is_itc -> nouvelles colonnes ci-dessous
--                                        (NULL pour les versions LLM)
--    Les métriques de validation (ex-colonnes Accuracy, f1_score, kappa...) sont
--    stockées en lignes dans [Project_Version_Metric].
-- =======================================================
PRINT 'Vérification des colonnes de fusion ML...'
GO
IF COL_LENGTH(N'[dbo].[Project_Version]', N'Algo') IS NULL BEGIN
    ALTER TABLE [dbo].[Project_Version] ADD [Algo] [nvarchar](100) NULL;
    PRINT 'Colonne [Algo] ajoutée.';
END
ELSE BEGIN
    PRINT 'Colonne [Algo] déjà présente.';
END
IF COL_LENGTH(N'[dbo].[Project_Version]', N'ModelPath') IS NULL BEGIN
    ALTER TABLE [dbo].[Project_Version] ADD [ModelPath] [nvarchar](max) NULL;
    PRINT 'Colonne [ModelPath] ajoutée.';
END
ELSE BEGIN
    PRINT 'Colonne [ModelPath] déjà présente.';
END
IF COL_LENGTH(N'[dbo].[Project_Version]', N'AnnotationFile') IS NULL BEGIN
    ALTER TABLE [dbo].[Project_Version] ADD [AnnotationFile] [nvarchar](max) NULL;
    PRINT 'Colonne [AnnotationFile] ajoutée.';
END
ELSE BEGIN
    PRINT 'Colonne [AnnotationFile] déjà présente.';
END
IF COL_LENGTH(N'[dbo].[Project_Version]', N'TrainDataPath') IS NULL BEGIN
    ALTER TABLE [dbo].[Project_Version] ADD [TrainDataPath] [nvarchar](max) NULL;
    PRINT 'Colonne [TrainDataPath] ajoutée.';
END
ELSE BEGIN
    PRINT 'Colonne [TrainDataPath] déjà présente.';
END
IF COL_LENGTH(N'[dbo].[Project_Version]', N'TrainDataCount') IS NULL BEGIN
    ALTER TABLE [dbo].[Project_Version] ADD [TrainDataCount] [int] NULL;
    PRINT 'Colonne [TrainDataCount] ajoutée.';
END
ELSE BEGIN
    PRINT 'Colonne [TrainDataCount] déjà présente.';
END
IF COL_LENGTH(N'[dbo].[Project_Version]', N'ValidDataCount') IS NULL BEGIN
    ALTER TABLE [dbo].[Project_Version] ADD [ValidDataCount] [int] NULL;
    PRINT 'Colonne [ValidDataCount] ajoutée.';
END
ELSE BEGIN
    PRINT 'Colonne [ValidDataCount] déjà présente.';
END
IF COL_LENGTH(N'[dbo].[Project_Version]', N'IsItc') IS NULL BEGIN
    -- Colonne bit NOT NULL ajoutée avec son default nommé à 0
    ALTER TABLE [dbo].[Project_Version] ADD [IsItc] [bit] NOT NULL
        CONSTRAINT [DF_ProjectVersion_IsItc] DEFAULT ((0));
    PRINT 'Colonne [IsItc] ajoutée.';
END
ELSE BEGIN
    PRINT 'Colonne [IsItc] déjà présente.';
END
GO
-- Batch séparé : les colonnes ajoutées ci-dessus existent à la compilation
DECLARE @df SYSNAME, @dfDef NVARCHAR(MAX), @dfOld NVARCHAR(300);
SET @df = NULL; SET @dfDef = NULL;
SELECT @df = name, @dfDef = definition
FROM sys.default_constraints
WHERE parent_object_id = OBJECT_ID(N'[dbo].[Project_Version]')
  AND parent_column_id = COLUMNPROPERTY(OBJECT_ID(N'[dbo].[Project_Version]'), 'IsItc', 'ColumnId');
IF COL_LENGTH(N'[dbo].[Project_Version]', N'IsItc') IS NULL BEGIN
    PRINT 'ATTENTION : colonne [Project_Version].[IsItc] absente, default [DF_ProjectVersion_IsItc] non traité.';
END
-- Aucun default sur la colonne (ni nommé, ni anonyme) : création
ELSE IF @df IS NULL BEGIN
    IF OBJECT_ID(N'[dbo].[DF_ProjectVersion_IsItc]') IS NOT NULL BEGIN
        PRINT 'ATTENTION : le nom [DF_ProjectVersion_IsItc] est déjà utilisé par un autre objet, default non créé.';
    END
    ELSE BEGIN
        ALTER TABLE [dbo].[Project_Version] ADD CONSTRAINT [DF_ProjectVersion_IsItc] DEFAULT ((0)) FOR [IsItc];
        PRINT 'Default [DF_ProjectVersion_IsItc] ajouté.';
    END
END
-- Un default existe déjà (éventuellement anonyme) : on n'en crée JAMAIS un second
ELSE BEGIN
    IF @df <> N'DF_ProjectVersion_IsItc' BEGIN
        IF OBJECT_ID(N'[dbo].[DF_ProjectVersion_IsItc]') IS NOT NULL BEGIN
            PRINT 'ATTENTION : default ' + @df + ' conservé, le nom [DF_ProjectVersion_IsItc] est déjà utilisé par un autre objet.';
        END
        ELSE BEGIN
            SET @dfOld = N'[dbo].' + QUOTENAME(@df);
            EXEC sp_rename @dfOld, N'DF_ProjectVersion_IsItc', N'OBJECT';
            PRINT 'Default ' + @df + ' renommé en [DF_ProjectVersion_IsItc].';
        END
    END
    ELSE BEGIN
        PRINT 'Default [DF_ProjectVersion_IsItc] existant.';
    END
    IF @dfDef <> N'((0))' BEGIN
        PRINT 'ATTENTION : le default de [Project_Version].[IsItc] vaut ' + @dfDef + ' au lieu de ((0)) (conservé, à vérifier).';
    END
END
IF NOT EXISTS (
    SELECT 1 FROM sys.check_constraints
    WHERE name = N'CK_ProjectVersion_TrainDataCount' AND parent_object_id = OBJECT_ID(N'[dbo].[Project_Version]')
) BEGIN
    ALTER TABLE [dbo].[Project_Version] WITH CHECK ADD CONSTRAINT [CK_ProjectVersion_TrainDataCount] CHECK ([TrainDataCount] IS NULL OR [TrainDataCount] >= 0);
    PRINT 'Contrainte [CK_ProjectVersion_TrainDataCount] ajoutée.';
END
ELSE BEGIN
    PRINT 'Contrainte [CK_ProjectVersion_TrainDataCount] existante.';
END
IF NOT EXISTS (
    SELECT 1 FROM sys.check_constraints
    WHERE name = N'CK_ProjectVersion_ValidDataCount' AND parent_object_id = OBJECT_ID(N'[dbo].[Project_Version]')
) BEGIN
    ALTER TABLE [dbo].[Project_Version] WITH CHECK ADD CONSTRAINT [CK_ProjectVersion_ValidDataCount] CHECK ([ValidDataCount] IS NULL OR [ValidDataCount] >= 0);
    PRINT 'Contrainte [CK_ProjectVersion_ValidDataCount] ajoutée.';
END
ELSE BEGIN
    PRINT 'Contrainte [CK_ProjectVersion_ValidDataCount] existante.';
END
GO
-- 3.1 Unicité (ProjectId, VersionNumber) : un numéro de version n'existe qu'une fois par
--     projet. Sert aussi de cible à la clé étrangère composite de [Evaluation].
--     Pas créée (avertissement) si des doublons existent déjà : à corriger d'abord.
IF NOT EXISTS (
    SELECT 1 FROM sys.indexes
    WHERE name = N'UQ_Project_Version_ProjectId_VersionNumber'
      AND object_id = OBJECT_ID(N'[dbo].[Project_Version]')
) BEGIN
    IF EXISTS (
        SELECT 1 FROM [dbo].[Project_Version]
        GROUP BY [ProjectId], [VersionNumber]
        HAVING COUNT(*) > 1
    ) BEGIN
        PRINT 'ATTENTION : numéros de version en doublon dans [Project_Version], contrainte [UQ_Project_Version_ProjectId_VersionNumber] non créée.';
        PRINT '            Liste : SELECT ProjectId, VersionNumber, COUNT(*) FROM dbo.Project_Version GROUP BY ProjectId, VersionNumber HAVING COUNT(*) > 1;';
    END
    ELSE BEGIN
        ALTER TABLE [dbo].[Project_Version] ADD CONSTRAINT [UQ_Project_Version_ProjectId_VersionNumber]
            UNIQUE NONCLUSTERED ([ProjectId] ASC, [VersionNumber] ASC);
        PRINT 'Contrainte [UQ_Project_Version_ProjectId_VersionNumber] ajoutée.';
    END
END
ELSE BEGIN
    PRINT 'Contrainte [UQ_Project_Version_ProjectId_VersionNumber] existante.';
END
-- 3.2 Pas d'index unique filtré « une seule version en prod » (WHERE DeliveredToProduction = 1) :
--     il ferait échouer l'UPDATE qui flague une nouvelle version AVANT que le trigger
--     trg_ProjectVersion_Update n'ait déflagué l'ancienne. La règle reste portée par le trigger.
GO
-- [RÉORGANISATION] Les triggers de [Project_Version] sont dans 2_procedures/trg_Project_Version.sql
PRINT '=== FIN DE LA MIGRATION [dbo].[Project_Version] ==='
GO
