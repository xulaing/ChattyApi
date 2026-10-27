SET ANSI_NULLS ON
SET QUOTED_IDENTIFIER ON
SET NOCOUNT ON
GO
PRINT '=== DÉBUT DE LA MIGRATION [dbo].[Document_Field] ==='
GO
-- =======================================================
-- [FUSION ML] Remplace : DocumentField
-- Un nom de champ est unique au sein d'une classe.
-- =======================================================
-- 1. CRÉATION DE LA TABLE (Si elle n'existe pas)
--    Clé primaire seule : défauts, clés étrangères, contrôles et index
--    sont posés en section 2 (idempotente, rejouable sur une table existante).
-- =======================================================
IF NOT EXISTS (
SELECT 1
FROM sys.objects
WHERE object_id = OBJECT_ID(N'[dbo].[Document_Field]')
AND type in (N'U')
) BEGIN
PRINT 'Création de la table [dbo].[Document_Field]...';
CREATE TABLE [dbo].[Document_Field](
    [Id] [int] IDENTITY(1, 1) NOT NULL,
    [DocumentClassId] [int] NOT NULL,
    [Name] [nvarchar](200) NOT NULL,
    [Description] [nvarchar](max) NULL,
    [CreatedBy] [nvarchar](50) NOT NULL,
    [CreatedAt] [datetime2](7) NOT NULL,
    [UpdatedBy] [nvarchar](50) NULL,
    [UpdatedAt] [datetime2](7) NULL,
    CONSTRAINT [PK_Document_Field] PRIMARY KEY CLUSTERED ([Id] ASC)
) ON [PRIMARY] TEXTIMAGE_ON [PRIMARY];
PRINT 'Table [dbo].[Document_Field] créée avec succès.';
END
ELSE BEGIN
PRINT 'Table [dbo].[Document_Field] déjà existante.';
END
GO
-- =======================================================
-- 2. CONTRAINTES, INDEX ET DESCRIPTION
-- =======================================================
DECLARE @df SYSNAME, @dfDef NVARCHAR(MAX), @dfOld NVARCHAR(300);
SET @df = NULL; SET @dfDef = NULL;
SELECT @df = name, @dfDef = definition
FROM sys.default_constraints
WHERE parent_object_id = OBJECT_ID(N'[dbo].[Document_Field]')
  AND parent_column_id = COLUMNPROPERTY(OBJECT_ID(N'[dbo].[Document_Field]'), 'CreatedAt', 'ColumnId');
IF COL_LENGTH(N'[dbo].[Document_Field]', N'CreatedAt') IS NULL BEGIN
    PRINT 'ATTENTION : colonne [Document_Field].[CreatedAt] absente, default [DF_DocumentField_CreatedAt] non traité.';
END
-- Aucun default sur la colonne (ni nommé, ni anonyme) : création
ELSE IF @df IS NULL BEGIN
    IF OBJECT_ID(N'[dbo].[DF_DocumentField_CreatedAt]') IS NOT NULL BEGIN
        PRINT 'ATTENTION : le nom [DF_DocumentField_CreatedAt] est déjà utilisé par un autre objet, default non créé.';
    END
    ELSE BEGIN
        ALTER TABLE [dbo].[Document_Field] ADD CONSTRAINT [DF_DocumentField_CreatedAt] DEFAULT (getdate()) FOR [CreatedAt];
        PRINT 'Default [DF_DocumentField_CreatedAt] ajouté.';
    END
END
-- Un default existe déjà (éventuellement anonyme) : on n'en crée JAMAIS un second
ELSE BEGIN
    IF @df <> N'DF_DocumentField_CreatedAt' BEGIN
        IF OBJECT_ID(N'[dbo].[DF_DocumentField_CreatedAt]') IS NOT NULL BEGIN
            PRINT 'ATTENTION : default ' + @df + ' conservé, le nom [DF_DocumentField_CreatedAt] est déjà utilisé par un autre objet.';
        END
        ELSE BEGIN
            SET @dfOld = N'[dbo].' + QUOTENAME(@df);
            EXEC sp_rename @dfOld, N'DF_DocumentField_CreatedAt', N'OBJECT';
            PRINT 'Default ' + @df + ' renommé en [DF_DocumentField_CreatedAt].';
        END
    END
    ELSE BEGIN
        PRINT 'Default [DF_DocumentField_CreatedAt] existant.';
    END
    IF @dfDef <> N'(getdate())' BEGIN
        PRINT 'ATTENTION : le default de [Document_Field].[CreatedAt] vaut ' + @dfDef + ' au lieu de (getdate()) (conservé, à vérifier).';
    END
END
-- FK recherchée par colonne et table cible (et non par nom) : pas de doublon possible
IF NOT EXISTS (
    SELECT 1
    FROM sys.foreign_keys fk
    JOIN sys.foreign_key_columns fkc ON fkc.constraint_object_id = fk.object_id
    WHERE fk.parent_object_id = OBJECT_ID(N'[dbo].[Document_Field]')
      AND fk.referenced_object_id = OBJECT_ID(N'[dbo].[Document_Class]')
      AND fkc.parent_column_id = COLUMNPROPERTY(OBJECT_ID(N'[dbo].[Document_Field]'), 'DocumentClassId', 'ColumnId')
) BEGIN
    ALTER TABLE [dbo].[Document_Field] WITH CHECK ADD CONSTRAINT [FK_DocumentField_DocumentClass]
        FOREIGN KEY ([DocumentClassId]) REFERENCES [dbo].[Document_Class] ([Id]) ON DELETE CASCADE;
    PRINT 'Contrainte [FK_DocumentField_DocumentClass] ajoutée.';
END
ELSE BEGIN
    PRINT 'Clé étrangère [Document_Field].[DocumentClassId] -> [Document_Class] existante.';
END
IF NOT EXISTS (
    SELECT 1 FROM sys.indexes
    WHERE name = N'UQ_DocumentField_DocumentClassId_Name' AND object_id = OBJECT_ID(N'[dbo].[Document_Field]')
) BEGIN
    CREATE UNIQUE NONCLUSTERED INDEX [UQ_DocumentField_DocumentClassId_Name] ON [dbo].[Document_Field] ([DocumentClassId] ASC, [Name] ASC);
    PRINT 'Index [UQ_DocumentField_DocumentClassId_Name] créé.';
END
ELSE BEGIN
    PRINT 'Index [UQ_DocumentField_DocumentClassId_Name] existant.';
END
IF NOT EXISTS (
    SELECT 1 FROM sys.extended_properties
    WHERE major_id = OBJECT_ID(N'[dbo].[Document_Field]') AND minor_id = 0 AND name = N'MS_Description'
) BEGIN
    EXEC sys.sp_addextendedproperty
        @name = N'MS_Description', @value = N'Champs d''une classe de documents',
        @level0type = N'SCHEMA', @level0name = N'dbo',
        @level1type = N'TABLE',  @level1name = N'Document_Field';
    PRINT 'Description de [Document_Field] ajoutée.';
END
GO
PRINT '=== FIN DE LA MIGRATION [dbo].[Document_Field] ==='
GO
