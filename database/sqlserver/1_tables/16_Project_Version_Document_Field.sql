SET ANSI_NULLS ON
SET QUOTED_IDENTIFIER ON
SET NOCOUNT ON
GO
PRINT '=== DÉBUT DE LA MIGRATION [dbo].[Project_Version_Document_Field] ==='
GO
-- =======================================================
-- [FUSION ML] Remplace : DocumentFieldProjects
-- =======================================================
-- 1. CRÉATION DE LA TABLE (Si elle n'existe pas)
--    Clé primaire seule : défauts, clés étrangères, contrôles et index
--    sont posés en section 2 (idempotente, rejouable sur une table existante).
-- =======================================================
IF NOT EXISTS (
SELECT 1
FROM sys.objects
WHERE object_id = OBJECT_ID(N'[dbo].[Project_Version_Document_Field]')
AND type in (N'U')
) BEGIN
PRINT 'Création de la table [dbo].[Project_Version_Document_Field]...';
CREATE TABLE [dbo].[Project_Version_Document_Field](
    [ProjectVersionId] [int] NOT NULL,
    [DocumentFieldId] [int] NOT NULL,
    CONSTRAINT [PK_Project_Version_Document_Field] PRIMARY KEY CLUSTERED ([ProjectVersionId] ASC, [DocumentFieldId] ASC)
) ON [PRIMARY];
PRINT 'Table [dbo].[Project_Version_Document_Field] créée avec succès.';
END
ELSE BEGIN
PRINT 'Table [dbo].[Project_Version_Document_Field] déjà existante.';
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
    WHERE fk.parent_object_id = OBJECT_ID(N'[dbo].[Project_Version_Document_Field]')
      AND fk.referenced_object_id = OBJECT_ID(N'[dbo].[Project_Version]')
      AND fkc.parent_column_id = COLUMNPROPERTY(OBJECT_ID(N'[dbo].[Project_Version_Document_Field]'), 'ProjectVersionId', 'ColumnId')
) BEGIN
    ALTER TABLE [dbo].[Project_Version_Document_Field] WITH CHECK ADD CONSTRAINT [FK_PVDocumentField_ProjectVersion]
        FOREIGN KEY ([ProjectVersionId]) REFERENCES [dbo].[Project_Version] ([Id]) ON DELETE CASCADE;
    PRINT 'Contrainte [FK_PVDocumentField_ProjectVersion] ajoutée.';
END
ELSE BEGIN
    PRINT 'Clé étrangère [Project_Version_Document_Field].[ProjectVersionId] -> [Project_Version] existante.';
END
-- FK recherchée par colonne et table cible (et non par nom) : pas de doublon possible
IF NOT EXISTS (
    SELECT 1
    FROM sys.foreign_keys fk
    JOIN sys.foreign_key_columns fkc ON fkc.constraint_object_id = fk.object_id
    WHERE fk.parent_object_id = OBJECT_ID(N'[dbo].[Project_Version_Document_Field]')
      AND fk.referenced_object_id = OBJECT_ID(N'[dbo].[Document_Field]')
      AND fkc.parent_column_id = COLUMNPROPERTY(OBJECT_ID(N'[dbo].[Project_Version_Document_Field]'), 'DocumentFieldId', 'ColumnId')
) BEGIN
    ALTER TABLE [dbo].[Project_Version_Document_Field] WITH CHECK ADD CONSTRAINT [FK_PVDocumentField_DocumentField]
        FOREIGN KEY ([DocumentFieldId]) REFERENCES [dbo].[Document_Field] ([Id]) ON DELETE CASCADE;
    PRINT 'Contrainte [FK_PVDocumentField_DocumentField] ajoutée.';
END
ELSE BEGIN
    PRINT 'Clé étrangère [Project_Version_Document_Field].[DocumentFieldId] -> [Document_Field] existante.';
END
IF NOT EXISTS (
    SELECT 1 FROM sys.indexes
    WHERE name = N'IX_PVDocumentField_DocumentFieldId' AND object_id = OBJECT_ID(N'[dbo].[Project_Version_Document_Field]')
) BEGIN
    CREATE NONCLUSTERED INDEX [IX_PVDocumentField_DocumentFieldId] ON [dbo].[Project_Version_Document_Field] ([DocumentFieldId] ASC);
    PRINT 'Index [IX_PVDocumentField_DocumentFieldId] créé.';
END
ELSE BEGIN
    PRINT 'Index [IX_PVDocumentField_DocumentFieldId] existant.';
END
IF NOT EXISTS (
    SELECT 1 FROM sys.extended_properties
    WHERE major_id = OBJECT_ID(N'[dbo].[Project_Version_Document_Field]') AND minor_id = 0 AND name = N'MS_Description'
) BEGIN
    EXEC sys.sp_addextendedproperty
        @name = N'MS_Description', @value = N'Champs de documents traités par une version',
        @level0type = N'SCHEMA', @level0name = N'dbo',
        @level1type = N'TABLE',  @level1name = N'Project_Version_Document_Field';
    PRINT 'Description de [Project_Version_Document_Field] ajoutée.';
END
GO
PRINT '=== FIN DE LA MIGRATION [dbo].[Project_Version_Document_Field] ==='
GO
