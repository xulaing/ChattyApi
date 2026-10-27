SET ANSI_NULLS ON
SET QUOTED_IDENTIFIER ON
SET NOCOUNT ON
GO
PRINT '=== DÉBUT DE LA MIGRATION [dbo].[Document_Request] ==='
GO
-- =======================================================
-- [FUSION ML] Remplace : DocumentRequest (préfixes de colonnes supprimés, audit normalisé)
-- [Type] et [Status] restent en texte libre : leurs valeurs historiques ne sont pas
-- connues. Une table de référence pourra les remplacer une fois les valeurs recensées.
-- =======================================================
-- 1. CRÉATION DE LA TABLE (Si elle n'existe pas)
--    Clé primaire seule : défauts, clés étrangères, contrôles et index
--    sont posés en section 2 (idempotente, rejouable sur une table existante).
-- =======================================================
IF NOT EXISTS (
SELECT 1
FROM sys.objects
WHERE object_id = OBJECT_ID(N'[dbo].[Document_Request]')
AND type in (N'U')
) BEGIN
PRINT 'Création de la table [dbo].[Document_Request]...';
CREATE TABLE [dbo].[Document_Request](
    [Id] [int] IDENTITY(1, 1) NOT NULL,
    [Type] [nvarchar](50) NOT NULL,
    [Name] [nvarchar](200) NOT NULL,
    [Description] [nvarchar](max) NULL,
    [Status] [nvarchar](30) NOT NULL,
    [Comment] [nvarchar](max) NULL,
    [Response] [nvarchar](max) NULL,
    [CreatedBy] [nvarchar](50) NOT NULL,
    [CreatedAt] [datetime2](7) NOT NULL,
    [UpdatedBy] [nvarchar](50) NULL,
    [UpdatedAt] [datetime2](7) NULL,
    CONSTRAINT [PK_Document_Request] PRIMARY KEY CLUSTERED ([Id] ASC)
) ON [PRIMARY] TEXTIMAGE_ON [PRIMARY];
PRINT 'Table [dbo].[Document_Request] créée avec succès.';
END
ELSE BEGIN
PRINT 'Table [dbo].[Document_Request] déjà existante.';
END
GO
-- =======================================================
-- 2. CONTRAINTES, INDEX ET DESCRIPTION
-- =======================================================
DECLARE @df SYSNAME, @dfDef NVARCHAR(MAX), @dfOld NVARCHAR(300);
SET @df = NULL; SET @dfDef = NULL;
SELECT @df = name, @dfDef = definition
FROM sys.default_constraints
WHERE parent_object_id = OBJECT_ID(N'[dbo].[Document_Request]')
  AND parent_column_id = COLUMNPROPERTY(OBJECT_ID(N'[dbo].[Document_Request]'), 'Status', 'ColumnId');
IF COL_LENGTH(N'[dbo].[Document_Request]', N'Status') IS NULL BEGIN
    PRINT 'ATTENTION : colonne [Document_Request].[Status] absente, default [DF_DocumentRequest_Status] non traité.';
END
-- Aucun default sur la colonne (ni nommé, ni anonyme) : création
ELSE IF @df IS NULL BEGIN
    IF OBJECT_ID(N'[dbo].[DF_DocumentRequest_Status]') IS NOT NULL BEGIN
        PRINT 'ATTENTION : le nom [DF_DocumentRequest_Status] est déjà utilisé par un autre objet, default non créé.';
    END
    ELSE BEGIN
        ALTER TABLE [dbo].[Document_Request] ADD CONSTRAINT [DF_DocumentRequest_Status] DEFAULT (N'OPEN') FOR [Status];
        PRINT 'Default [DF_DocumentRequest_Status] ajouté.';
    END
END
-- Un default existe déjà (éventuellement anonyme) : on n'en crée JAMAIS un second
ELSE BEGIN
    IF @df <> N'DF_DocumentRequest_Status' BEGIN
        IF OBJECT_ID(N'[dbo].[DF_DocumentRequest_Status]') IS NOT NULL BEGIN
            PRINT 'ATTENTION : default ' + @df + ' conservé, le nom [DF_DocumentRequest_Status] est déjà utilisé par un autre objet.';
        END
        ELSE BEGIN
            SET @dfOld = N'[dbo].' + QUOTENAME(@df);
            EXEC sp_rename @dfOld, N'DF_DocumentRequest_Status', N'OBJECT';
            PRINT 'Default ' + @df + ' renommé en [DF_DocumentRequest_Status].';
        END
    END
    ELSE BEGIN
        PRINT 'Default [DF_DocumentRequest_Status] existant.';
    END
    IF @dfDef <> N'(N''OPEN'')' BEGIN
        PRINT 'ATTENTION : le default de [Document_Request].[Status] vaut ' + @dfDef + ' au lieu de (N''OPEN'') (conservé, à vérifier).';
    END
END
SET @df = NULL; SET @dfDef = NULL;
SELECT @df = name, @dfDef = definition
FROM sys.default_constraints
WHERE parent_object_id = OBJECT_ID(N'[dbo].[Document_Request]')
  AND parent_column_id = COLUMNPROPERTY(OBJECT_ID(N'[dbo].[Document_Request]'), 'CreatedAt', 'ColumnId');
IF COL_LENGTH(N'[dbo].[Document_Request]', N'CreatedAt') IS NULL BEGIN
    PRINT 'ATTENTION : colonne [Document_Request].[CreatedAt] absente, default [DF_DocumentRequest_CreatedAt] non traité.';
END
-- Aucun default sur la colonne (ni nommé, ni anonyme) : création
ELSE IF @df IS NULL BEGIN
    IF OBJECT_ID(N'[dbo].[DF_DocumentRequest_CreatedAt]') IS NOT NULL BEGIN
        PRINT 'ATTENTION : le nom [DF_DocumentRequest_CreatedAt] est déjà utilisé par un autre objet, default non créé.';
    END
    ELSE BEGIN
        ALTER TABLE [dbo].[Document_Request] ADD CONSTRAINT [DF_DocumentRequest_CreatedAt] DEFAULT (getdate()) FOR [CreatedAt];
        PRINT 'Default [DF_DocumentRequest_CreatedAt] ajouté.';
    END
END
-- Un default existe déjà (éventuellement anonyme) : on n'en crée JAMAIS un second
ELSE BEGIN
    IF @df <> N'DF_DocumentRequest_CreatedAt' BEGIN
        IF OBJECT_ID(N'[dbo].[DF_DocumentRequest_CreatedAt]') IS NOT NULL BEGIN
            PRINT 'ATTENTION : default ' + @df + ' conservé, le nom [DF_DocumentRequest_CreatedAt] est déjà utilisé par un autre objet.';
        END
        ELSE BEGIN
            SET @dfOld = N'[dbo].' + QUOTENAME(@df);
            EXEC sp_rename @dfOld, N'DF_DocumentRequest_CreatedAt', N'OBJECT';
            PRINT 'Default ' + @df + ' renommé en [DF_DocumentRequest_CreatedAt].';
        END
    END
    ELSE BEGIN
        PRINT 'Default [DF_DocumentRequest_CreatedAt] existant.';
    END
    IF @dfDef <> N'(getdate())' BEGIN
        PRINT 'ATTENTION : le default de [Document_Request].[CreatedAt] vaut ' + @dfDef + ' au lieu de (getdate()) (conservé, à vérifier).';
    END
END
IF NOT EXISTS (
    SELECT 1 FROM sys.indexes
    WHERE name = N'IX_DocumentRequest_Status' AND object_id = OBJECT_ID(N'[dbo].[Document_Request]')
) BEGIN
    CREATE NONCLUSTERED INDEX [IX_DocumentRequest_Status] ON [dbo].[Document_Request] ([Status] ASC);
    PRINT 'Index [IX_DocumentRequest_Status] créé.';
END
ELSE BEGIN
    PRINT 'Index [IX_DocumentRequest_Status] existant.';
END
IF NOT EXISTS (
    SELECT 1 FROM sys.extended_properties
    WHERE major_id = OBJECT_ID(N'[dbo].[Document_Request]') AND minor_id = 0 AND name = N'MS_Description'
) BEGIN
    EXEC sys.sp_addextendedproperty
        @name = N'MS_Description', @value = N'Demandes documentaires',
        @level0type = N'SCHEMA', @level0name = N'dbo',
        @level1type = N'TABLE',  @level1name = N'Document_Request';
    PRINT 'Description de [Document_Request] ajoutée.';
END
GO
PRINT '=== FIN DE LA MIGRATION [dbo].[Document_Request] ==='
GO
