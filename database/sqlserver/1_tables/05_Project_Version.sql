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
--      Le default est retiré avant l'ALTER (sinon erreur 5074) puis recréé.
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
    ALTER TABLE [dbo].[Project_Version]
    ADD CONSTRAINT DF_ProjectVersion_DeliveredToProduction DEFAULT 0 FOR [DeliveredToProduction];
    PRINT 'Colonne [DeliveredToProduction] convertie en bit.';
END
GO
-- [RÉORGANISATION] Les triggers de [Project_Version] sont dans 2_procedures/trg_Project_Version.sql
PRINT '=== FIN DE LA MIGRATION [dbo].[Project_Version] ==='
GO
