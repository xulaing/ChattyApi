SET ANSI_NULLS ON
SET QUOTED_IDENTIFIER ON
SET NOCOUNT ON
GO
PRINT '=== DÉBUT DE LA MIGRATION [dbo].[Project_Version_Document_Class] ==='
GO
-- =======================================================
-- [FUSION ML] Remplace : DocumentClassProjects (sans IdModel : la version connaît déjà son projet)
-- Utilisable par les versions LLM comme par les versions de modèles.
-- =======================================================
-- 1. CRÉATION DE LA TABLE (Si elle n'existe pas)
--    Clé primaire seule : défauts, clés étrangères, contrôles et index
--    sont posés en section 2 (idempotente, rejouable sur une table existante).
-- =======================================================
IF NOT EXISTS (
SELECT 1
FROM sys.objects
WHERE object_id = OBJECT_ID(N'[dbo].[Project_Version_Document_Class]')
AND type in (N'U')
) BEGIN
PRINT 'Création de la table [dbo].[Project_Version_Document_Class]...';
CREATE TABLE [dbo].[Project_Version_Document_Class](
    [ProjectVersionId] [int] NOT NULL,
    [DocumentClassId] [int] NOT NULL,
    CONSTRAINT [PK_Project_Version_Document_Class] PRIMARY KEY CLUSTERED ([ProjectVersionId] ASC, [DocumentClassId] ASC)
) ON [PRIMARY];
PRINT 'Table [dbo].[Project_Version_Document_Class] créée avec succès.';
END
ELSE BEGIN
PRINT 'Table [dbo].[Project_Version_Document_Class] déjà existante.';
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
    WHERE fk.parent_object_id = OBJECT_ID(N'[dbo].[Project_Version_Document_Class]')
      AND fk.referenced_object_id = OBJECT_ID(N'[dbo].[Project_Version]')
      AND fkc.parent_column_id = COLUMNPROPERTY(OBJECT_ID(N'[dbo].[Project_Version_Document_Class]'), 'ProjectVersionId', 'ColumnId')
) BEGIN
    ALTER TABLE [dbo].[Project_Version_Document_Class] WITH CHECK ADD CONSTRAINT [FK_PVDocumentClass_ProjectVersion]
        FOREIGN KEY ([ProjectVersionId]) REFERENCES [dbo].[Project_Version] ([Id]) ON DELETE CASCADE;
    PRINT 'Contrainte [FK_PVDocumentClass_ProjectVersion] ajoutée.';
END
ELSE BEGIN
    PRINT 'Clé étrangère [Project_Version_Document_Class].[ProjectVersionId] -> [Project_Version] existante.';
END
-- FK recherchée par colonne et table cible (et non par nom) : pas de doublon possible
IF NOT EXISTS (
    SELECT 1
    FROM sys.foreign_keys fk
    JOIN sys.foreign_key_columns fkc ON fkc.constraint_object_id = fk.object_id
    WHERE fk.parent_object_id = OBJECT_ID(N'[dbo].[Project_Version_Document_Class]')
      AND fk.referenced_object_id = OBJECT_ID(N'[dbo].[Document_Class]')
      AND fkc.parent_column_id = COLUMNPROPERTY(OBJECT_ID(N'[dbo].[Project_Version_Document_Class]'), 'DocumentClassId', 'ColumnId')
) BEGIN
    ALTER TABLE [dbo].[Project_Version_Document_Class] WITH CHECK ADD CONSTRAINT [FK_PVDocumentClass_DocumentClass]
        FOREIGN KEY ([DocumentClassId]) REFERENCES [dbo].[Document_Class] ([Id]) ON DELETE CASCADE;
    PRINT 'Contrainte [FK_PVDocumentClass_DocumentClass] ajoutée.';
END
ELSE BEGIN
    PRINT 'Clé étrangère [Project_Version_Document_Class].[DocumentClassId] -> [Document_Class] existante.';
END
IF NOT EXISTS (
    SELECT 1 FROM sys.indexes
    WHERE name = N'IX_PVDocumentClass_DocumentClassId' AND object_id = OBJECT_ID(N'[dbo].[Project_Version_Document_Class]')
) BEGIN
    CREATE NONCLUSTERED INDEX [IX_PVDocumentClass_DocumentClassId] ON [dbo].[Project_Version_Document_Class] ([DocumentClassId] ASC);
    PRINT 'Index [IX_PVDocumentClass_DocumentClassId] créé.';
END
ELSE BEGIN
    PRINT 'Index [IX_PVDocumentClass_DocumentClassId] existant.';
END
IF NOT EXISTS (
    SELECT 1 FROM sys.extended_properties
    WHERE major_id = OBJECT_ID(N'[dbo].[Project_Version_Document_Class]') AND minor_id = 0 AND name = N'MS_Description'
) BEGIN
    EXEC sys.sp_addextendedproperty
        @name = N'MS_Description', @value = N'Classes de documents traitées par une version',
        @level0type = N'SCHEMA', @level0name = N'dbo',
        @level1type = N'TABLE',  @level1name = N'Project_Version_Document_Class';
    PRINT 'Description de [Project_Version_Document_Class] ajoutée.';
END
GO
PRINT '=== FIN DE LA MIGRATION [dbo].[Project_Version_Document_Class] ==='
GO
