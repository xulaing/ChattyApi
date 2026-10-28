SET ANSI_NULLS ON
SET QUOTED_IDENTIFIER ON
SET NOCOUNT ON
GO
PRINT '=== DÉBUT DE LA MIGRATION [dbo].[Migration_Rejected] ==='
GO
-- =======================================================
-- [FUSION ML] Lignes de l'ancienne base des modèles entraînés écartées par la reprise
-- des données (4_migration_ml) parce que leur parent est introuvable : version sans
-- modèle, test sans version, entraînement sans modèle, champ sans classe, association
-- dont la version ou l'élément n'existe pas (l'ancienne base n'avait pas de clés
-- étrangères). La ligne JSON d'origine est conservée avec la raison du rejet : rien
-- n'est perdu, et les lignes peuvent être reprises une fois le parent corrigé.
-- Le contenu est recalculé à chaque exécution de la migration, pour les tables sources
-- présentes dans l'export.
-- =======================================================
IF NOT EXISTS (
SELECT 1
FROM sys.objects
WHERE object_id = OBJECT_ID(N'[dbo].[Migration_Rejected]')
AND type in (N'U')
) BEGIN
PRINT 'Création de la table [dbo].[Migration_Rejected]...';
CREATE TABLE [dbo].[Migration_Rejected](
    [SourceTable] [nvarchar](128) NOT NULL,
    [SourceId] [bigint] NOT NULL,
    [Reason] [nvarchar](400) NOT NULL,
    [RowJson] [nvarchar](max) NOT NULL,
    [RejectedAt] [datetime2](7) NOT NULL,
    CONSTRAINT [PK_Migration_Rejected] PRIMARY KEY CLUSTERED ([SourceTable] ASC, [SourceId] ASC)
) ON [PRIMARY] TEXTIMAGE_ON [PRIMARY];
PRINT 'Table [dbo].[Migration_Rejected] créée avec succès.';
END
ELSE BEGIN
PRINT 'Table [dbo].[Migration_Rejected] déjà existante.';
END
GO
-- =======================================================
-- 2. CONTRAINTES ET DESCRIPTION
-- =======================================================
DECLARE @df SYSNAME, @dfDef NVARCHAR(MAX), @dfOld NVARCHAR(300);
SET @df = NULL; SET @dfDef = NULL;
SELECT @df = name, @dfDef = definition
FROM sys.default_constraints
WHERE parent_object_id = OBJECT_ID(N'[dbo].[Migration_Rejected]')
  AND parent_column_id = COLUMNPROPERTY(OBJECT_ID(N'[dbo].[Migration_Rejected]'), 'RejectedAt', 'ColumnId');
IF COL_LENGTH(N'[dbo].[Migration_Rejected]', N'RejectedAt') IS NULL BEGIN
    PRINT 'ATTENTION : colonne [Migration_Rejected].[RejectedAt] absente, default [DF_Migration_Rejected_RejectedAt] non traité.';
END
-- Aucun default sur la colonne (ni nommé, ni anonyme) : création
ELSE IF @df IS NULL BEGIN
    IF OBJECT_ID(N'[dbo].[DF_Migration_Rejected_RejectedAt]') IS NOT NULL BEGIN
        PRINT 'ATTENTION : le nom [DF_Migration_Rejected_RejectedAt] est déjà utilisé par un autre objet, default non créé.';
    END
    ELSE BEGIN
        ALTER TABLE [dbo].[Migration_Rejected] ADD CONSTRAINT [DF_Migration_Rejected_RejectedAt] DEFAULT (sysdatetime()) FOR [RejectedAt];
        PRINT 'Default [DF_Migration_Rejected_RejectedAt] ajouté.';
    END
END
-- Un default existe déjà (éventuellement anonyme) : on n'en crée JAMAIS un second
ELSE BEGIN
    IF @df <> N'DF_Migration_Rejected_RejectedAt' BEGIN
        IF OBJECT_ID(N'[dbo].[DF_Migration_Rejected_RejectedAt]') IS NOT NULL BEGIN
            PRINT 'ATTENTION : default ' + @df + ' conservé, le nom [DF_Migration_Rejected_RejectedAt] est déjà utilisé par un autre objet.';
        END
        ELSE BEGIN
            SET @dfOld = N'[dbo].' + QUOTENAME(@df);
            EXEC sp_rename @dfOld, N'DF_Migration_Rejected_RejectedAt', N'OBJECT';
            PRINT 'Default ' + @df + ' renommé en [DF_Migration_Rejected_RejectedAt].';
        END
    END
    ELSE BEGIN
        PRINT 'Default [DF_Migration_Rejected_RejectedAt] existant.';
    END
    IF @dfDef <> N'(sysdatetime())' BEGIN
        PRINT 'ATTENTION : le default de [Migration_Rejected].[RejectedAt] vaut ' + @dfDef + ' au lieu de (sysdatetime()) (conservé, à vérifier).';
    END
END
IF NOT EXISTS (
    SELECT 1 FROM sys.extended_properties
    WHERE major_id = OBJECT_ID(N'[dbo].[Migration_Rejected]') AND minor_id = 0 AND name = N'MS_Description'
) BEGIN
    EXEC sys.sp_addextendedproperty
        @name = N'MS_Description', @value = N'Lignes de l''ancienne base écartées par la reprise des données (parent introuvable), avec la raison et la ligne JSON d''origine',
        @level0type = N'SCHEMA', @level0name = N'dbo',
        @level1type = N'TABLE',  @level1name = N'Migration_Rejected';
    PRINT 'Description de [Migration_Rejected] ajoutée.';
END
GO
PRINT '=== FIN DE LA MIGRATION [dbo].[Migration_Rejected] ==='
GO
