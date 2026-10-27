SET ANSI_NULLS ON
SET QUOTED_IDENTIFIER ON
SET NOCOUNT ON
GO
PRINT '=== DÉBUT DE LA MIGRATION [dbo].[Project_Version_Metric] ==='
GO
-- =======================================================
-- [FUSION ML] Remplace : les colonnes de métriques des 5 tables Model*_Version (Accuracy, ErrorRate, f1_score, kappa, AP_bbox...)
-- Une ligne par (version, métrique) : la clé primaire interdit les doublons.
-- Le nom de la métrique est contrôlé par [Ref_Metric] (pas de texte libre).
-- Supprimer une version supprime ses métriques (ON DELETE CASCADE).
-- =======================================================
-- 1. CRÉATION DE LA TABLE (Si elle n'existe pas)
--    Clé primaire seule : défauts, clés étrangères, contrôles et index
--    sont posés en section 2 (idempotente, rejouable sur une table existante).
-- =======================================================
IF NOT EXISTS (
SELECT 1
FROM sys.objects
WHERE object_id = OBJECT_ID(N'[dbo].[Project_Version_Metric]')
AND type in (N'U')
) BEGIN
PRINT 'Création de la table [dbo].[Project_Version_Metric]...';
CREATE TABLE [dbo].[Project_Version_Metric](
    [ProjectVersionId] [int] NOT NULL,
    [MetricCode] [varchar](30) NOT NULL,
    [Value] [float] NOT NULL,
    CONSTRAINT [PK_Project_Version_Metric] PRIMARY KEY CLUSTERED ([ProjectVersionId] ASC, [MetricCode] ASC)
) ON [PRIMARY];
PRINT 'Table [dbo].[Project_Version_Metric] créée avec succès.';
END
ELSE BEGIN
PRINT 'Table [dbo].[Project_Version_Metric] déjà existante.';
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
    WHERE fk.parent_object_id = OBJECT_ID(N'[dbo].[Project_Version_Metric]')
      AND fk.referenced_object_id = OBJECT_ID(N'[dbo].[Project_Version]')
      AND fkc.parent_column_id = COLUMNPROPERTY(OBJECT_ID(N'[dbo].[Project_Version_Metric]'), 'ProjectVersionId', 'ColumnId')
) BEGIN
    ALTER TABLE [dbo].[Project_Version_Metric] WITH CHECK ADD CONSTRAINT [FK_ProjectVersionMetric_ProjectVersion]
        FOREIGN KEY ([ProjectVersionId]) REFERENCES [dbo].[Project_Version] ([Id]) ON DELETE CASCADE;
    PRINT 'Contrainte [FK_ProjectVersionMetric_ProjectVersion] ajoutée.';
END
ELSE BEGIN
    PRINT 'Clé étrangère [Project_Version_Metric].[ProjectVersionId] -> [Project_Version] existante.';
END
-- FK recherchée par colonne et table cible (et non par nom) : pas de doublon possible
IF NOT EXISTS (
    SELECT 1
    FROM sys.foreign_keys fk
    JOIN sys.foreign_key_columns fkc ON fkc.constraint_object_id = fk.object_id
    WHERE fk.parent_object_id = OBJECT_ID(N'[dbo].[Project_Version_Metric]')
      AND fk.referenced_object_id = OBJECT_ID(N'[dbo].[Ref_Metric]')
      AND fkc.parent_column_id = COLUMNPROPERTY(OBJECT_ID(N'[dbo].[Project_Version_Metric]'), 'MetricCode', 'ColumnId')
) BEGIN
    ALTER TABLE [dbo].[Project_Version_Metric] WITH CHECK ADD CONSTRAINT [FK_ProjectVersionMetric_Metric]
        FOREIGN KEY ([MetricCode]) REFERENCES [dbo].[Ref_Metric] ([Code]);
    PRINT 'Contrainte [FK_ProjectVersionMetric_Metric] ajoutée.';
END
ELSE BEGIN
    PRINT 'Clé étrangère [Project_Version_Metric].[MetricCode] -> [Ref_Metric] existante.';
END
IF NOT EXISTS (
    SELECT 1 FROM sys.extended_properties
    WHERE major_id = OBJECT_ID(N'[dbo].[Project_Version_Metric]') AND minor_id = 0 AND name = N'MS_Description'
) BEGIN
    EXEC sys.sp_addextendedproperty
        @name = N'MS_Description', @value = N'Métriques de validation d''une version (une ligne par métrique)',
        @level0type = N'SCHEMA', @level0name = N'dbo',
        @level1type = N'TABLE',  @level1name = N'Project_Version_Metric';
    PRINT 'Description de [Project_Version_Metric] ajoutée.';
END
GO
PRINT '=== FIN DE LA MIGRATION [dbo].[Project_Version_Metric] ==='
GO
