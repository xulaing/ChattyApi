SET ANSI_NULLS ON
SET QUOTED_IDENTIFIER ON
SET NOCOUNT ON
GO
PRINT '=== DÉBUT DE LA MIGRATION [dbo].[Inference_Request] ==='
GO
-- =======================================================
-- [FUSION ML] Remplace : Classification_Test, Segmentation_Test, Detection_Test, Extraction_Test, Decoupage_Test (5 tables identiques)
-- [TaskType] est conservé même si la version le connaît : les inférences historiques
-- n'ont pas de version (ProjectVersionId NULL).
-- Table à forte volumétrie : index sur DocId et (TaskType, CreatedAt).
-- Supprimer une version conserve ses inférences (ON DELETE SET NULL).
-- [Id] en uniqueidentifier : identifiant de corrélation avec le service d'inférence et
-- renvoyé au client (non devinable, générable avant l'insertion). Table de traces,
-- comme [Project_History] qui est déjà en uniqueidentifier.
-- Valeur par défaut NEWSEQUENTIALID() : GUID croissants, donc pas de fragmentation
-- de l'index cluster quand la base génère l'identifiant.
-- =======================================================
-- 0. [GUID] TABLE CRÉÉE PAR UNE VERSION PRÉCÉDENTE AVEC UN [Id] NUMÉRIQUE
--    Vide : elle est supprimée puis recréée en section 1 (aucune table ne la référence).
--    Non vide : arrêt, la conversion des données doit être décidée manuellement.
-- =======================================================
IF EXISTS (
    SELECT 1 FROM sys.columns
    WHERE object_id = OBJECT_ID(N'[dbo].[Inference_Request]') AND name = N'Id'
      AND TYPE_NAME(system_type_id) <> N'uniqueidentifier'
) BEGIN
    IF EXISTS (SELECT 1 FROM [dbo].[Inference_Request]) BEGIN
        RAISERROR ('ERREUR CRITIQUE : [Inference_Request] contient des données avec un [Id] numérique. Conversion en uniqueidentifier à traiter manuellement.', 16, 1);
        RETURN;
    END
    DROP TABLE [dbo].[Inference_Request];
    PRINT 'Table [dbo].[Inference_Request] (Id numérique, vide) supprimée pour être recréée avec un Id uniqueidentifier.';
END
GO
-- =======================================================
-- 1. CRÉATION DE LA TABLE (Si elle n'existe pas)
--    Clé primaire seule : défauts, clés étrangères, contrôles et index
--    sont posés en section 2 (idempotente, rejouable sur une table existante).
-- =======================================================
IF NOT EXISTS (
SELECT 1
FROM sys.objects
WHERE object_id = OBJECT_ID(N'[dbo].[Inference_Request]')
AND type in (N'U')
) BEGIN
PRINT 'Création de la table [dbo].[Inference_Request]...';
CREATE TABLE [dbo].[Inference_Request](
    [Id] [uniqueidentifier] NOT NULL,
    [TaskType] [varchar](20) NOT NULL,
    [ProjectVersionId] [int] NULL,
    [DocId] [nvarchar](200) NOT NULL,
    [StatusCode] [int] NULL,
    [ResMessage] [nvarchar](max) NULL,
    [ResContent] [nvarchar](max) NULL,
    [EndStatus] [nvarchar](50) NULL,
    [CreatedAt] [datetime2](7) NOT NULL,
    CONSTRAINT [PK_Inference_Request] PRIMARY KEY CLUSTERED ([Id] ASC)
) ON [PRIMARY] TEXTIMAGE_ON [PRIMARY];
PRINT 'Table [dbo].[Inference_Request] créée avec succès.';
END
ELSE BEGIN
PRINT 'Table [dbo].[Inference_Request] déjà existante.';
END
GO
-- =======================================================
-- 2. CONTRAINTES, INDEX ET DESCRIPTION
-- =======================================================
DECLARE @df SYSNAME, @dfDef NVARCHAR(MAX), @dfOld NVARCHAR(300);
SET @df = NULL; SET @dfDef = NULL;
SELECT @df = name, @dfDef = definition
FROM sys.default_constraints
WHERE parent_object_id = OBJECT_ID(N'[dbo].[Inference_Request]')
  AND parent_column_id = COLUMNPROPERTY(OBJECT_ID(N'[dbo].[Inference_Request]'), 'Id', 'ColumnId');
IF COL_LENGTH(N'[dbo].[Inference_Request]', N'Id') IS NULL BEGIN
    PRINT 'ATTENTION : colonne [Inference_Request].[Id] absente, default [DF_InferenceRequest_Id] non traité.';
END
-- Aucun default sur la colonne (ni nommé, ni anonyme) : création
ELSE IF @df IS NULL BEGIN
    IF OBJECT_ID(N'[dbo].[DF_InferenceRequest_Id]') IS NOT NULL BEGIN
        PRINT 'ATTENTION : le nom [DF_InferenceRequest_Id] est déjà utilisé par un autre objet, default non créé.';
    END
    ELSE BEGIN
        ALTER TABLE [dbo].[Inference_Request] ADD CONSTRAINT [DF_InferenceRequest_Id] DEFAULT (newsequentialid()) FOR [Id];
        PRINT 'Default [DF_InferenceRequest_Id] ajouté.';
    END
END
-- Un default existe déjà (éventuellement anonyme) : on n'en crée JAMAIS un second
ELSE BEGIN
    IF @df <> N'DF_InferenceRequest_Id' BEGIN
        IF OBJECT_ID(N'[dbo].[DF_InferenceRequest_Id]') IS NOT NULL BEGIN
            PRINT 'ATTENTION : default ' + @df + ' conservé, le nom [DF_InferenceRequest_Id] est déjà utilisé par un autre objet.';
        END
        ELSE BEGIN
            SET @dfOld = N'[dbo].' + QUOTENAME(@df);
            EXEC sp_rename @dfOld, N'DF_InferenceRequest_Id', N'OBJECT';
            PRINT 'Default ' + @df + ' renommé en [DF_InferenceRequest_Id].';
        END
    END
    ELSE BEGIN
        PRINT 'Default [DF_InferenceRequest_Id] existant.';
    END
    IF @dfDef <> N'(newsequentialid())' BEGIN
        PRINT 'ATTENTION : le default de [Inference_Request].[Id] vaut ' + @dfDef + ' au lieu de (newsequentialid()) (conservé, à vérifier).';
    END
END
SET @df = NULL; SET @dfDef = NULL;
SELECT @df = name, @dfDef = definition
FROM sys.default_constraints
WHERE parent_object_id = OBJECT_ID(N'[dbo].[Inference_Request]')
  AND parent_column_id = COLUMNPROPERTY(OBJECT_ID(N'[dbo].[Inference_Request]'), 'CreatedAt', 'ColumnId');
IF COL_LENGTH(N'[dbo].[Inference_Request]', N'CreatedAt') IS NULL BEGIN
    PRINT 'ATTENTION : colonne [Inference_Request].[CreatedAt] absente, default [DF_InferenceRequest_CreatedAt] non traité.';
END
-- Aucun default sur la colonne (ni nommé, ni anonyme) : création
ELSE IF @df IS NULL BEGIN
    IF OBJECT_ID(N'[dbo].[DF_InferenceRequest_CreatedAt]') IS NOT NULL BEGIN
        PRINT 'ATTENTION : le nom [DF_InferenceRequest_CreatedAt] est déjà utilisé par un autre objet, default non créé.';
    END
    ELSE BEGIN
        ALTER TABLE [dbo].[Inference_Request] ADD CONSTRAINT [DF_InferenceRequest_CreatedAt] DEFAULT (getdate()) FOR [CreatedAt];
        PRINT 'Default [DF_InferenceRequest_CreatedAt] ajouté.';
    END
END
-- Un default existe déjà (éventuellement anonyme) : on n'en crée JAMAIS un second
ELSE BEGIN
    IF @df <> N'DF_InferenceRequest_CreatedAt' BEGIN
        IF OBJECT_ID(N'[dbo].[DF_InferenceRequest_CreatedAt]') IS NOT NULL BEGIN
            PRINT 'ATTENTION : default ' + @df + ' conservé, le nom [DF_InferenceRequest_CreatedAt] est déjà utilisé par un autre objet.';
        END
        ELSE BEGIN
            SET @dfOld = N'[dbo].' + QUOTENAME(@df);
            EXEC sp_rename @dfOld, N'DF_InferenceRequest_CreatedAt', N'OBJECT';
            PRINT 'Default ' + @df + ' renommé en [DF_InferenceRequest_CreatedAt].';
        END
    END
    ELSE BEGIN
        PRINT 'Default [DF_InferenceRequest_CreatedAt] existant.';
    END
    IF @dfDef <> N'(getdate())' BEGIN
        PRINT 'ATTENTION : le default de [Inference_Request].[CreatedAt] vaut ' + @dfDef + ' au lieu de (getdate()) (conservé, à vérifier).';
    END
END
-- FK recherchée par colonne et table cible (et non par nom) : pas de doublon possible
IF NOT EXISTS (
    SELECT 1
    FROM sys.foreign_keys fk
    JOIN sys.foreign_key_columns fkc ON fkc.constraint_object_id = fk.object_id
    WHERE fk.parent_object_id = OBJECT_ID(N'[dbo].[Inference_Request]')
      AND fk.referenced_object_id = OBJECT_ID(N'[dbo].[Ref_TaskType]')
      AND fkc.parent_column_id = COLUMNPROPERTY(OBJECT_ID(N'[dbo].[Inference_Request]'), 'TaskType', 'ColumnId')
) BEGIN
    ALTER TABLE [dbo].[Inference_Request] WITH CHECK ADD CONSTRAINT [FK_InferenceRequest_TaskType]
        FOREIGN KEY ([TaskType]) REFERENCES [dbo].[Ref_TaskType] ([Code]);
    PRINT 'Contrainte [FK_InferenceRequest_TaskType] ajoutée.';
END
ELSE BEGIN
    PRINT 'Clé étrangère [Inference_Request].[TaskType] -> [Ref_TaskType] existante.';
END
-- FK recherchée par colonne et table cible (et non par nom) : pas de doublon possible
IF NOT EXISTS (
    SELECT 1
    FROM sys.foreign_keys fk
    JOIN sys.foreign_key_columns fkc ON fkc.constraint_object_id = fk.object_id
    WHERE fk.parent_object_id = OBJECT_ID(N'[dbo].[Inference_Request]')
      AND fk.referenced_object_id = OBJECT_ID(N'[dbo].[Project_Version]')
      AND fkc.parent_column_id = COLUMNPROPERTY(OBJECT_ID(N'[dbo].[Inference_Request]'), 'ProjectVersionId', 'ColumnId')
) BEGIN
    ALTER TABLE [dbo].[Inference_Request] WITH CHECK ADD CONSTRAINT [FK_InferenceRequest_ProjectVersion]
        FOREIGN KEY ([ProjectVersionId]) REFERENCES [dbo].[Project_Version] ([Id]) ON DELETE SET NULL;
    PRINT 'Contrainte [FK_InferenceRequest_ProjectVersion] ajoutée.';
END
ELSE BEGIN
    PRINT 'Clé étrangère [Inference_Request].[ProjectVersionId] -> [Project_Version] existante.';
END
IF NOT EXISTS (
    SELECT 1 FROM sys.check_constraints
    WHERE name = N'CK_InferenceRequest_ResContent_JSON' AND parent_object_id = OBJECT_ID(N'[dbo].[Inference_Request]')
) BEGIN
    ALTER TABLE [dbo].[Inference_Request] WITH CHECK ADD CONSTRAINT [CK_InferenceRequest_ResContent_JSON] CHECK ([ResContent] IS NULL OR ISJSON([ResContent]) = 1);
    PRINT 'Contrainte [CK_InferenceRequest_ResContent_JSON] ajoutée.';
END
ELSE BEGIN
    PRINT 'Contrainte [CK_InferenceRequest_ResContent_JSON] existante.';
END
IF NOT EXISTS (
    SELECT 1 FROM sys.indexes
    WHERE name = N'IX_InferenceRequest_DocId' AND object_id = OBJECT_ID(N'[dbo].[Inference_Request]')
) BEGIN
    CREATE NONCLUSTERED INDEX [IX_InferenceRequest_DocId] ON [dbo].[Inference_Request] ([DocId] ASC);
    PRINT 'Index [IX_InferenceRequest_DocId] créé.';
END
ELSE BEGIN
    PRINT 'Index [IX_InferenceRequest_DocId] existant.';
END
IF NOT EXISTS (
    SELECT 1 FROM sys.indexes
    WHERE name = N'IX_InferenceRequest_TaskType_CreatedAt' AND object_id = OBJECT_ID(N'[dbo].[Inference_Request]')
) BEGIN
    CREATE NONCLUSTERED INDEX [IX_InferenceRequest_TaskType_CreatedAt] ON [dbo].[Inference_Request] ([TaskType] ASC, [CreatedAt] ASC);
    PRINT 'Index [IX_InferenceRequest_TaskType_CreatedAt] créé.';
END
ELSE BEGIN
    PRINT 'Index [IX_InferenceRequest_TaskType_CreatedAt] existant.';
END
IF NOT EXISTS (
    SELECT 1 FROM sys.indexes
    WHERE name = N'IX_InferenceRequest_ProjectVersionId' AND object_id = OBJECT_ID(N'[dbo].[Inference_Request]')
) BEGIN
    CREATE NONCLUSTERED INDEX [IX_InferenceRequest_ProjectVersionId] ON [dbo].[Inference_Request] ([ProjectVersionId] ASC);
    PRINT 'Index [IX_InferenceRequest_ProjectVersionId] créé.';
END
ELSE BEGIN
    PRINT 'Index [IX_InferenceRequest_ProjectVersionId] existant.';
END
IF NOT EXISTS (
    SELECT 1 FROM sys.extended_properties
    WHERE major_id = OBJECT_ID(N'[dbo].[Inference_Request]') AND minor_id = 0 AND name = N'MS_Description'
) BEGIN
    EXEC sys.sp_addextendedproperty
        @name = N'MS_Description', @value = N'Résultats d''inférence sur un document',
        @level0type = N'SCHEMA', @level0name = N'dbo',
        @level1type = N'TABLE',  @level1name = N'Inference_Request';
    PRINT 'Description de [Inference_Request] ajoutée.';
END
GO
PRINT '=== FIN DE LA MIGRATION [dbo].[Inference_Request] ==='
GO
