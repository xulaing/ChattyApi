SET ANSI_NULLS ON
SET QUOTED_IDENTIFIER ON
SET NOCOUNT ON
GO
PRINT '=== DÉBUT DE LA MIGRATION [dbo].[Training_Run] ==='
GO
-- =======================================================
-- [FUSION ML] Remplace : TrainTrack, SegmentationTrainTrack, DetectionTrainTrack, ExtractionTrainTrack
-- [StatusCode] contrôlé par [Ref_RunStatus] (ex-ENUM run_status).
-- [Classes] : liste JSON des classes entraînées (contrôlée par ISJSON).
-- =======================================================
-- 1. CRÉATION DE LA TABLE (Si elle n'existe pas)
--    Clé primaire seule : défauts, clés étrangères, contrôles et index
--    sont posés en section 2 (idempotente, rejouable sur une table existante).
-- =======================================================
IF NOT EXISTS (
SELECT 1
FROM sys.objects
WHERE object_id = OBJECT_ID(N'[dbo].[Training_Run]')
AND type in (N'U')
) BEGIN
PRINT 'Création de la table [dbo].[Training_Run]...';
CREATE TABLE [dbo].[Training_Run](
    [Id] [int] IDENTITY(1, 1) NOT NULL,
    [ProjectVersionId] [int] NOT NULL,
    [StatusCode] [varchar](20) NOT NULL,
    [StartedAt] [datetime2](7) NULL,
    [EndedAt] [datetime2](7) NULL,
    [Epoch] [int] NULL,
    [CurrentStep] [int] NULL,
    [TotalStep] [int] NULL,
    [CurrentPhase] [nvarchar](100) NULL,
    [Classes] [nvarchar](max) NULL,
    [ImageSize] [int] NULL,
    [DatasetPath] [nvarchar](max) NULL,
    [OutputPath] [nvarchar](max) NULL,
    [CreatedBy] [nvarchar](50) NOT NULL,
    [CreatedAt] [datetime2](7) NOT NULL,
    CONSTRAINT [PK_Training_Run] PRIMARY KEY CLUSTERED ([Id] ASC)
) ON [PRIMARY] TEXTIMAGE_ON [PRIMARY];
PRINT 'Table [dbo].[Training_Run] créée avec succès.';
END
ELSE BEGIN
PRINT 'Table [dbo].[Training_Run] déjà existante.';
END
GO
-- =======================================================
-- 2. CONTRAINTES, INDEX ET DESCRIPTION
-- =======================================================
DECLARE @df SYSNAME, @dfDef NVARCHAR(MAX), @dfOld NVARCHAR(300);
SET @df = NULL; SET @dfDef = NULL;
SELECT @df = name, @dfDef = definition
FROM sys.default_constraints
WHERE parent_object_id = OBJECT_ID(N'[dbo].[Training_Run]')
  AND parent_column_id = COLUMNPROPERTY(OBJECT_ID(N'[dbo].[Training_Run]'), 'StatusCode', 'ColumnId');
IF COL_LENGTH(N'[dbo].[Training_Run]', N'StatusCode') IS NULL BEGIN
    PRINT 'ATTENTION : colonne [Training_Run].[StatusCode] absente, default [DF_TrainingRun_StatusCode] non traité.';
END
-- Aucun default sur la colonne (ni nommé, ni anonyme) : création
ELSE IF @df IS NULL BEGIN
    IF OBJECT_ID(N'[dbo].[DF_TrainingRun_StatusCode]') IS NOT NULL BEGIN
        PRINT 'ATTENTION : le nom [DF_TrainingRun_StatusCode] est déjà utilisé par un autre objet, default non créé.';
    END
    ELSE BEGIN
        ALTER TABLE [dbo].[Training_Run] ADD CONSTRAINT [DF_TrainingRun_StatusCode] DEFAULT ('PENDING') FOR [StatusCode];
        PRINT 'Default [DF_TrainingRun_StatusCode] ajouté.';
    END
END
-- Un default existe déjà (éventuellement anonyme) : on n'en crée JAMAIS un second
ELSE BEGIN
    IF @df <> N'DF_TrainingRun_StatusCode' BEGIN
        IF OBJECT_ID(N'[dbo].[DF_TrainingRun_StatusCode]') IS NOT NULL BEGIN
            PRINT 'ATTENTION : default ' + @df + ' conservé, le nom [DF_TrainingRun_StatusCode] est déjà utilisé par un autre objet.';
        END
        ELSE BEGIN
            SET @dfOld = N'[dbo].' + QUOTENAME(@df);
            EXEC sp_rename @dfOld, N'DF_TrainingRun_StatusCode', N'OBJECT';
            PRINT 'Default ' + @df + ' renommé en [DF_TrainingRun_StatusCode].';
        END
    END
    ELSE BEGIN
        PRINT 'Default [DF_TrainingRun_StatusCode] existant.';
    END
    IF @dfDef <> N'(''PENDING'')' BEGIN
        PRINT 'ATTENTION : le default de [Training_Run].[StatusCode] vaut ' + @dfDef + ' au lieu de (''PENDING'') (conservé, à vérifier).';
    END
END
SET @df = NULL; SET @dfDef = NULL;
SELECT @df = name, @dfDef = definition
FROM sys.default_constraints
WHERE parent_object_id = OBJECT_ID(N'[dbo].[Training_Run]')
  AND parent_column_id = COLUMNPROPERTY(OBJECT_ID(N'[dbo].[Training_Run]'), 'CreatedAt', 'ColumnId');
IF COL_LENGTH(N'[dbo].[Training_Run]', N'CreatedAt') IS NULL BEGIN
    PRINT 'ATTENTION : colonne [Training_Run].[CreatedAt] absente, default [DF_TrainingRun_CreatedAt] non traité.';
END
-- Aucun default sur la colonne (ni nommé, ni anonyme) : création
ELSE IF @df IS NULL BEGIN
    IF OBJECT_ID(N'[dbo].[DF_TrainingRun_CreatedAt]') IS NOT NULL BEGIN
        PRINT 'ATTENTION : le nom [DF_TrainingRun_CreatedAt] est déjà utilisé par un autre objet, default non créé.';
    END
    ELSE BEGIN
        ALTER TABLE [dbo].[Training_Run] ADD CONSTRAINT [DF_TrainingRun_CreatedAt] DEFAULT (getdate()) FOR [CreatedAt];
        PRINT 'Default [DF_TrainingRun_CreatedAt] ajouté.';
    END
END
-- Un default existe déjà (éventuellement anonyme) : on n'en crée JAMAIS un second
ELSE BEGIN
    IF @df <> N'DF_TrainingRun_CreatedAt' BEGIN
        IF OBJECT_ID(N'[dbo].[DF_TrainingRun_CreatedAt]') IS NOT NULL BEGIN
            PRINT 'ATTENTION : default ' + @df + ' conservé, le nom [DF_TrainingRun_CreatedAt] est déjà utilisé par un autre objet.';
        END
        ELSE BEGIN
            SET @dfOld = N'[dbo].' + QUOTENAME(@df);
            EXEC sp_rename @dfOld, N'DF_TrainingRun_CreatedAt', N'OBJECT';
            PRINT 'Default ' + @df + ' renommé en [DF_TrainingRun_CreatedAt].';
        END
    END
    ELSE BEGIN
        PRINT 'Default [DF_TrainingRun_CreatedAt] existant.';
    END
    IF @dfDef <> N'(getdate())' BEGIN
        PRINT 'ATTENTION : le default de [Training_Run].[CreatedAt] vaut ' + @dfDef + ' au lieu de (getdate()) (conservé, à vérifier).';
    END
END
-- FK recherchée par colonne et table cible (et non par nom) : pas de doublon possible
IF NOT EXISTS (
    SELECT 1
    FROM sys.foreign_keys fk
    JOIN sys.foreign_key_columns fkc ON fkc.constraint_object_id = fk.object_id
    WHERE fk.parent_object_id = OBJECT_ID(N'[dbo].[Training_Run]')
      AND fk.referenced_object_id = OBJECT_ID(N'[dbo].[Project_Version]')
      AND fkc.parent_column_id = COLUMNPROPERTY(OBJECT_ID(N'[dbo].[Training_Run]'), 'ProjectVersionId', 'ColumnId')
) BEGIN
    ALTER TABLE [dbo].[Training_Run] WITH CHECK ADD CONSTRAINT [FK_TrainingRun_ProjectVersion]
        FOREIGN KEY ([ProjectVersionId]) REFERENCES [dbo].[Project_Version] ([Id]) ON DELETE CASCADE;
    PRINT 'Contrainte [FK_TrainingRun_ProjectVersion] ajoutée.';
END
ELSE BEGIN
    PRINT 'Clé étrangère [Training_Run].[ProjectVersionId] -> [Project_Version] existante.';
END
-- FK recherchée par colonne et table cible (et non par nom) : pas de doublon possible
IF NOT EXISTS (
    SELECT 1
    FROM sys.foreign_keys fk
    JOIN sys.foreign_key_columns fkc ON fkc.constraint_object_id = fk.object_id
    WHERE fk.parent_object_id = OBJECT_ID(N'[dbo].[Training_Run]')
      AND fk.referenced_object_id = OBJECT_ID(N'[dbo].[Ref_RunStatus]')
      AND fkc.parent_column_id = COLUMNPROPERTY(OBJECT_ID(N'[dbo].[Training_Run]'), 'StatusCode', 'ColumnId')
) BEGIN
    ALTER TABLE [dbo].[Training_Run] WITH CHECK ADD CONSTRAINT [FK_TrainingRun_Status]
        FOREIGN KEY ([StatusCode]) REFERENCES [dbo].[Ref_RunStatus] ([Code]);
    PRINT 'Contrainte [FK_TrainingRun_Status] ajoutée.';
END
ELSE BEGIN
    PRINT 'Clé étrangère [Training_Run].[StatusCode] -> [Ref_RunStatus] existante.';
END
IF NOT EXISTS (
    SELECT 1 FROM sys.check_constraints
    WHERE name = N'CK_TrainingRun_Dates' AND parent_object_id = OBJECT_ID(N'[dbo].[Training_Run]')
) BEGIN
    ALTER TABLE [dbo].[Training_Run] WITH CHECK ADD CONSTRAINT [CK_TrainingRun_Dates] CHECK ([EndedAt] IS NULL OR [StartedAt] IS NULL OR [EndedAt] >= [StartedAt]);
    PRINT 'Contrainte [CK_TrainingRun_Dates] ajoutée.';
END
ELSE BEGIN
    PRINT 'Contrainte [CK_TrainingRun_Dates] existante.';
END
IF NOT EXISTS (
    SELECT 1 FROM sys.check_constraints
    WHERE name = N'CK_TrainingRun_Steps' AND parent_object_id = OBJECT_ID(N'[dbo].[Training_Run]')
) BEGIN
    ALTER TABLE [dbo].[Training_Run] WITH CHECK ADD CONSTRAINT [CK_TrainingRun_Steps] CHECK (([CurrentStep] IS NULL OR [CurrentStep] >= 0) AND ([TotalStep] IS NULL OR [TotalStep] >= 0) AND ([CurrentStep] IS NULL OR [TotalStep] IS NULL OR [CurrentStep] <= [TotalStep]));
    PRINT 'Contrainte [CK_TrainingRun_Steps] ajoutée.';
END
ELSE BEGIN
    PRINT 'Contrainte [CK_TrainingRun_Steps] existante.';
END
IF NOT EXISTS (
    SELECT 1 FROM sys.check_constraints
    WHERE name = N'CK_TrainingRun_Classes_JSON' AND parent_object_id = OBJECT_ID(N'[dbo].[Training_Run]')
) BEGIN
    ALTER TABLE [dbo].[Training_Run] WITH CHECK ADD CONSTRAINT [CK_TrainingRun_Classes_JSON] CHECK ([Classes] IS NULL OR ISJSON([Classes]) = 1);
    PRINT 'Contrainte [CK_TrainingRun_Classes_JSON] ajoutée.';
END
ELSE BEGIN
    PRINT 'Contrainte [CK_TrainingRun_Classes_JSON] existante.';
END
IF NOT EXISTS (
    SELECT 1 FROM sys.indexes
    WHERE name = N'IX_TrainingRun_ProjectVersionId' AND object_id = OBJECT_ID(N'[dbo].[Training_Run]')
) BEGIN
    CREATE NONCLUSTERED INDEX [IX_TrainingRun_ProjectVersionId] ON [dbo].[Training_Run] ([ProjectVersionId] ASC);
    PRINT 'Index [IX_TrainingRun_ProjectVersionId] créé.';
END
ELSE BEGIN
    PRINT 'Index [IX_TrainingRun_ProjectVersionId] existant.';
END
IF NOT EXISTS (
    SELECT 1 FROM sys.extended_properties
    WHERE major_id = OBJECT_ID(N'[dbo].[Training_Run]') AND minor_id = 0 AND name = N'MS_Description'
) BEGIN
    EXEC sys.sp_addextendedproperty
        @name = N'MS_Description', @value = N'Suivi des entraînements d''une version de modèle',
        @level0type = N'SCHEMA', @level0name = N'dbo',
        @level1type = N'TABLE',  @level1name = N'Training_Run';
    PRINT 'Description de [Training_Run] ajoutée.';
END
GO
PRINT '=== FIN DE LA MIGRATION [dbo].[Training_Run] ==='
GO
