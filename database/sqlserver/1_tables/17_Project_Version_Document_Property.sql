SET ANSI_NULLS ON
SET QUOTED_IDENTIFIER ON
SET NOCOUNT ON
GO
PRINT '=== DÉBUT DE LA MIGRATION [dbo].[Project_Version_Document_Property] ==='
GO
-- =======================================================
-- [FUSION ML] Remplace : DocumentPropertyProjects
-- =======================================================
-- 1. CRÉATION DE LA TABLE (Si elle n'existe pas)
--    Clé primaire seule : défauts, clés étrangères, contrôles et index
--    sont posés en section 2 (idempotente, rejouable sur une table existante).
-- =======================================================
IF NOT EXISTS (
SELECT 1
FROM sys.objects
WHERE object_id = OBJECT_ID(N'[dbo].[Project_Version_Document_Property]')
AND type in (N'U')
) BEGIN
PRINT 'Création de la table [dbo].[Project_Version_Document_Property]...';
CREATE TABLE [dbo].[Project_Version_Document_Property](
    [ProjectVersionId] [int] NOT NULL,
    [DocumentPropertyId] [int] NOT NULL,
    CONSTRAINT [PK_Project_Version_Document_Property] PRIMARY KEY CLUSTERED ([ProjectVersionId] ASC, [DocumentPropertyId] ASC)
) ON [PRIMARY];
PRINT 'Table [dbo].[Project_Version_Document_Property] créée avec succès.';
END
ELSE BEGIN
PRINT 'Table [dbo].[Project_Version_Document_Property] déjà existante.';
END
GO
-- =======================================================
-- 2. CONTRAINTES, INDEX ET DESCRIPTION
-- =======================================================
-- FK recherchée par colonne et table cible (et non par nom) : pas de doublon possible
IF NOT EXISTS (
    SELECT 1
    FROM sys.foreign_keys fk
    JOIN sys.foreign_key_columns fkc ON fkc.constraint_object_id = fk.object_id
    WHERE fk.parent_object_id = OBJECT_ID(N'[dbo].[Project_Version_Document_Property]')
      AND fk.referenced_object_id = OBJECT_ID(N'[dbo].[Project_Version]')
      AND fkc.parent_column_id = COLUMNPROPERTY(OBJECT_ID(N'[dbo].[Project_Version_Document_Property]'), 'ProjectVersionId', 'ColumnId')
) BEGIN
    ALTER TABLE [dbo].[Project_Version_Document_Property] WITH CHECK ADD CONSTRAINT [FK_PVDocumentProperty_ProjectVersion]
        FOREIGN KEY ([ProjectVersionId]) REFERENCES [dbo].[Project_Version] ([Id]) ON DELETE CASCADE;
    PRINT 'Contrainte [FK_PVDocumentProperty_ProjectVersion] ajoutée.';
END
ELSE BEGIN
    PRINT 'Clé étrangère [Project_Version_Document_Property].[ProjectVersionId] -> [Project_Version] existante.';
END
-- FK recherchée par colonne et table cible (et non par nom) : pas de doublon possible
IF NOT EXISTS (
    SELECT 1
    FROM sys.foreign_keys fk
    JOIN sys.foreign_key_columns fkc ON fkc.constraint_object_id = fk.object_id
    WHERE fk.parent_object_id = OBJECT_ID(N'[dbo].[Project_Version_Document_Property]')
      AND fk.referenced_object_id = OBJECT_ID(N'[dbo].[Document_Property]')
      AND fkc.parent_column_id = COLUMNPROPERTY(OBJECT_ID(N'[dbo].[Project_Version_Document_Property]'), 'DocumentPropertyId', 'ColumnId')
) BEGIN
    ALTER TABLE [dbo].[Project_Version_Document_Property] WITH CHECK ADD CONSTRAINT [FK_PVDocumentProperty_DocumentProperty]
        FOREIGN KEY ([DocumentPropertyId]) REFERENCES [dbo].[Document_Property] ([Id]) ON DELETE CASCADE;
    PRINT 'Contrainte [FK_PVDocumentProperty_DocumentProperty] ajoutée.';
END
ELSE BEGIN
    PRINT 'Clé étrangère [Project_Version_Document_Property].[DocumentPropertyId] -> [Document_Property] existante.';
END
IF NOT EXISTS (
    SELECT 1 FROM sys.indexes
    WHERE name = N'IX_PVDocumentProperty_DocumentPropertyId' AND object_id = OBJECT_ID(N'[dbo].[Project_Version_Document_Property]')
) BEGIN
    CREATE NONCLUSTERED INDEX [IX_PVDocumentProperty_DocumentPropertyId] ON [dbo].[Project_Version_Document_Property] ([DocumentPropertyId] ASC);
    PRINT 'Index [IX_PVDocumentProperty_DocumentPropertyId] créé.';
END
ELSE BEGIN
    PRINT 'Index [IX_PVDocumentProperty_DocumentPropertyId] existant.';
END
IF NOT EXISTS (
    SELECT 1 FROM sys.extended_properties
    WHERE major_id = OBJECT_ID(N'[dbo].[Project_Version_Document_Property]') AND minor_id = 0 AND name = N'MS_Description'
) BEGIN
    EXEC sys.sp_addextendedproperty
        @name = N'MS_Description', @value = N'Propriétés de documents traitées par une version',
        @level0type = N'SCHEMA', @level0name = N'dbo',
        @level1type = N'TABLE',  @level1name = N'Project_Version_Document_Property';
    PRINT 'Description de [Project_Version_Document_Property] ajoutée.';
END
GO
PRINT '=== FIN DE LA MIGRATION [dbo].[Project_Version_Document_Property] ==='
GO
