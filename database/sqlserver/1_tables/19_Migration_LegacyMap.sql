SET ANSI_NULLS ON
SET QUOTED_IDENTIFIER ON
SET NOCOUNT ON
GO
PRINT '=== DÉBUT DE LA MIGRATION [dbo].[Migration_LegacyMap] ==='
GO
-- =======================================================
-- [FUSION ML] Correspondance (table source, ancien Id) -> nouvel Id pour la reprise
-- des données de l'ancienne base des modèles entraînés (4_migration_ml).
-- - rend le script de migration rejouable (une ligne déjà migrée n'est pas recopiée) ;
-- - garde la traçabilité ancien Id -> nouvel Id après la migration.
-- Créée ici, avec les autres tables : le script de migration n'a ainsi besoin que de
-- droits SELECT / INSERT, et pas du droit de créer des tables.
-- Pas de clé étrangère, de CHECK ni de trigger : elle est alimentée par des clauses
-- OUTPUT ... INTO, qui l'interdisent sur la table destination.
-- =======================================================
IF NOT EXISTS (
SELECT 1
FROM sys.objects
WHERE object_id = OBJECT_ID(N'[dbo].[Migration_LegacyMap]')
AND type in (N'U')
) BEGIN
PRINT 'Création de la table [dbo].[Migration_LegacyMap]...';
CREATE TABLE [dbo].[Migration_LegacyMap](
    [SourceTable] [nvarchar](128) NOT NULL,
    [SourceId] [bigint] NOT NULL,
    [SourceParentId] [bigint] NULL,
    [TargetTable] [nvarchar](128) NOT NULL,
    [TargetId] [int] NULL,
    [TargetGuid] [uniqueidentifier] NULL,
    [MigratedAt] [datetime2](7) NOT NULL,
    CONSTRAINT [PK_Migration_LegacyMap] PRIMARY KEY CLUSTERED ([SourceTable] ASC, [SourceId] ASC)
) ON [PRIMARY];
PRINT 'Table [dbo].[Migration_LegacyMap] créée avec succès.';
END
ELSE BEGIN
PRINT 'Table [dbo].[Migration_LegacyMap] déjà existante.';
END
GO
-- =======================================================
-- 2. CONTRAINTES, INDEX ET DESCRIPTION
-- =======================================================
DECLARE @df SYSNAME, @dfDef NVARCHAR(MAX), @dfOld NVARCHAR(300);
SET @df = NULL; SET @dfDef = NULL;
SELECT @df = name, @dfDef = definition
FROM sys.default_constraints
WHERE parent_object_id = OBJECT_ID(N'[dbo].[Migration_LegacyMap]')
  AND parent_column_id = COLUMNPROPERTY(OBJECT_ID(N'[dbo].[Migration_LegacyMap]'), 'MigratedAt', 'ColumnId');
IF COL_LENGTH(N'[dbo].[Migration_LegacyMap]', N'MigratedAt') IS NULL BEGIN
    PRINT 'ATTENTION : colonne [Migration_LegacyMap].[MigratedAt] absente, default [DF_Migration_LegacyMap_MigratedAt] non traité.';
END
-- Aucun default sur la colonne (ni nommé, ni anonyme) : création
ELSE IF @df IS NULL BEGIN
    IF OBJECT_ID(N'[dbo].[DF_Migration_LegacyMap_MigratedAt]') IS NOT NULL BEGIN
        PRINT 'ATTENTION : le nom [DF_Migration_LegacyMap_MigratedAt] est déjà utilisé par un autre objet, default non créé.';
    END
    ELSE BEGIN
        ALTER TABLE [dbo].[Migration_LegacyMap] ADD CONSTRAINT [DF_Migration_LegacyMap_MigratedAt] DEFAULT (sysdatetime()) FOR [MigratedAt];
        PRINT 'Default [DF_Migration_LegacyMap_MigratedAt] ajouté.';
    END
END
-- Un default existe déjà (éventuellement anonyme) : on n'en crée JAMAIS un second
ELSE BEGIN
    IF @df <> N'DF_Migration_LegacyMap_MigratedAt' BEGIN
        IF OBJECT_ID(N'[dbo].[DF_Migration_LegacyMap_MigratedAt]') IS NOT NULL BEGIN
            PRINT 'ATTENTION : default ' + @df + ' conservé, le nom [DF_Migration_LegacyMap_MigratedAt] est déjà utilisé par un autre objet.';
        END
        ELSE BEGIN
            SET @dfOld = N'[dbo].' + QUOTENAME(@df);
            EXEC sp_rename @dfOld, N'DF_Migration_LegacyMap_MigratedAt', N'OBJECT';
            PRINT 'Default ' + @df + ' renommé en [DF_Migration_LegacyMap_MigratedAt].';
        END
    END
    ELSE BEGIN
        PRINT 'Default [DF_Migration_LegacyMap_MigratedAt] existant.';
    END
    IF @dfDef <> N'(sysdatetime())' BEGIN
        PRINT 'ATTENTION : le default de [Migration_LegacyMap].[MigratedAt] vaut ' + @dfDef + ' au lieu de (sysdatetime()) (conservé, à vérifier).';
    END
END
IF NOT EXISTS (
    SELECT 1 FROM sys.indexes
    WHERE name = N'IX_Migration_LegacyMap_Target' AND object_id = OBJECT_ID(N'[dbo].[Migration_LegacyMap]')
) BEGIN
    CREATE NONCLUSTERED INDEX [IX_Migration_LegacyMap_Target] ON [dbo].[Migration_LegacyMap] ([TargetTable] ASC, [TargetId] ASC);
    PRINT 'Index [IX_Migration_LegacyMap_Target] créé.';
END
ELSE BEGIN
    PRINT 'Index [IX_Migration_LegacyMap_Target] existant.';
END
IF NOT EXISTS (
    SELECT 1 FROM sys.extended_properties
    WHERE major_id = OBJECT_ID(N'[dbo].[Migration_LegacyMap]') AND minor_id = 0 AND name = N'MS_Description'
) BEGIN
    EXEC sys.sp_addextendedproperty
        @name = N'MS_Description', @value = N'Correspondance ancien Id -> nouvel Id de la reprise des données de l''ancienne base des modèles entraînés',
        @level0type = N'SCHEMA', @level0name = N'dbo',
        @level1type = N'TABLE',  @level1name = N'Migration_LegacyMap';
    PRINT 'Description de [Migration_LegacyMap] ajoutée.';
END
GO
PRINT '=== FIN DE LA MIGRATION [dbo].[Migration_LegacyMap] ==='
GO
