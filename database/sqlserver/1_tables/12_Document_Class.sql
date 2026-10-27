SET ANSI_NULLS ON
SET QUOTED_IDENTIFIER ON
SET NOCOUNT ON
GO
PRINT '=== DÉBUT DE LA MIGRATION [dbo].[Document_Class] ==='
GO
-- =======================================================
-- [FUSION ML] Remplace : DocumentClass (préfixes de colonnes supprimés, audit normalisé)
-- =======================================================
-- 1. CRÉATION DE LA TABLE (Si elle n'existe pas)
--    Clé primaire seule : défauts, clés étrangères, contrôles et index
--    sont posés en section 2 (idempotente, rejouable sur une table existante).
-- =======================================================
IF NOT EXISTS (
SELECT 1
FROM sys.objects
WHERE object_id = OBJECT_ID(N'[dbo].[Document_Class]')
AND type in (N'U')
) BEGIN
PRINT 'Création de la table [dbo].[Document_Class]...';
CREATE TABLE [dbo].[Document_Class](
    [Id] [int] IDENTITY(1, 1) NOT NULL,
    [Name] [nvarchar](200) NOT NULL,
    [Description] [nvarchar](max) NULL,
    [CreatedBy] [nvarchar](50) NOT NULL,
    [CreatedAt] [datetime2](7) NOT NULL,
    [UpdatedBy] [nvarchar](50) NULL,
    [UpdatedAt] [datetime2](7) NULL,
    CONSTRAINT [PK_Document_Class] PRIMARY KEY CLUSTERED ([Id] ASC)
) ON [PRIMARY] TEXTIMAGE_ON [PRIMARY];
PRINT 'Table [dbo].[Document_Class] créée avec succès.';
END
ELSE BEGIN
PRINT 'Table [dbo].[Document_Class] déjà existante.';
END
GO
-- =======================================================
-- 2. CONTRAINTES, INDEX ET DESCRIPTION
-- =======================================================
DECLARE @df SYSNAME, @dfDef NVARCHAR(MAX), @dfOld NVARCHAR(300);
SET @df = NULL; SET @dfDef = NULL;
SELECT @df = name, @dfDef = definition
FROM sys.default_constraints
WHERE parent_object_id = OBJECT_ID(N'[dbo].[Document_Class]')
  AND parent_column_id = COLUMNPROPERTY(OBJECT_ID(N'[dbo].[Document_Class]'), 'CreatedAt', 'ColumnId');
IF COL_LENGTH(N'[dbo].[Document_Class]', N'CreatedAt') IS NULL BEGIN
    PRINT 'ATTENTION : colonne [Document_Class].[CreatedAt] absente, default [DF_DocumentClass_CreatedAt] non traité.';
END
-- Aucun default sur la colonne (ni nommé, ni anonyme) : création
ELSE IF @df IS NULL BEGIN
    IF OBJECT_ID(N'[dbo].[DF_DocumentClass_CreatedAt]') IS NOT NULL BEGIN
        PRINT 'ATTENTION : le nom [DF_DocumentClass_CreatedAt] est déjà utilisé par un autre objet, default non créé.';
    END
    ELSE BEGIN
        ALTER TABLE [dbo].[Document_Class] ADD CONSTRAINT [DF_DocumentClass_CreatedAt] DEFAULT (getdate()) FOR [CreatedAt];
        PRINT 'Default [DF_DocumentClass_CreatedAt] ajouté.';
    END
END
-- Un default existe déjà (éventuellement anonyme) : on n'en crée JAMAIS un second
ELSE BEGIN
    IF @df <> N'DF_DocumentClass_CreatedAt' BEGIN
        IF OBJECT_ID(N'[dbo].[DF_DocumentClass_CreatedAt]') IS NOT NULL BEGIN
            PRINT 'ATTENTION : default ' + @df + ' conservé, le nom [DF_DocumentClass_CreatedAt] est déjà utilisé par un autre objet.';
        END
        ELSE BEGIN
            SET @dfOld = N'[dbo].' + QUOTENAME(@df);
            EXEC sp_rename @dfOld, N'DF_DocumentClass_CreatedAt', N'OBJECT';
            PRINT 'Default ' + @df + ' renommé en [DF_DocumentClass_CreatedAt].';
        END
    END
    ELSE BEGIN
        PRINT 'Default [DF_DocumentClass_CreatedAt] existant.';
    END
    IF @dfDef <> N'(getdate())' BEGIN
        PRINT 'ATTENTION : le default de [Document_Class].[CreatedAt] vaut ' + @dfDef + ' au lieu de (getdate()) (conservé, à vérifier).';
    END
END
IF NOT EXISTS (
    SELECT 1 FROM sys.indexes
    WHERE name = N'UQ_DocumentClass_Name' AND object_id = OBJECT_ID(N'[dbo].[Document_Class]')
) BEGIN
    CREATE UNIQUE NONCLUSTERED INDEX [UQ_DocumentClass_Name] ON [dbo].[Document_Class] ([Name] ASC);
    PRINT 'Index [UQ_DocumentClass_Name] créé.';
END
ELSE BEGIN
    PRINT 'Index [UQ_DocumentClass_Name] existant.';
END
IF NOT EXISTS (
    SELECT 1 FROM sys.extended_properties
    WHERE major_id = OBJECT_ID(N'[dbo].[Document_Class]') AND minor_id = 0 AND name = N'MS_Description'
) BEGIN
    EXEC sys.sp_addextendedproperty
        @name = N'MS_Description', @value = N'Référentiel des classes de documents',
        @level0type = N'SCHEMA', @level0name = N'dbo',
        @level1type = N'TABLE',  @level1name = N'Document_Class';
    PRINT 'Description de [Document_Class] ajoutée.';
END
GO
PRINT '=== FIN DE LA MIGRATION [dbo].[Document_Class] ==='
GO
