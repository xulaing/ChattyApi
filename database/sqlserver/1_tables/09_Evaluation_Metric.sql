SET ANSI_NULLS ON
SET QUOTED_IDENTIFIER ON
SET NOCOUNT ON
GO
PRINT '=== DÉBUT DE LA MIGRATION [dbo].[Evaluation_Metric] ==='
GO
-- =======================================================
-- [FUSION ML] Remplace : les colonnes de métriques des 5 tables Model*_Version_Test
-- Une ligne par (évaluation, métrique). Utilisable aussi pour les évaluations LLM.
-- La version testée est connue via [Evaluation] : elle n'est pas recopiée ici
-- (dans le schéma PostgreSQL, metric portait à la fois la version et le test_run,
-- ce qui permettait une incohérence entre les deux).
-- [EvaluationId] en uniqueidentifier : même type que [Evaluation].[Id].
-- =======================================================
-- 0. TABLE CRÉÉE PAR UNE VERSION PRÉCÉDENTE AVEC UN [EvaluationId] int
--    Vide : supprimée puis recréée en section 1 ; non vide : arrêt.
-- =======================================================
IF EXISTS (
    SELECT 1 FROM sys.columns
    WHERE object_id = OBJECT_ID(N'[dbo].[Evaluation_Metric]') AND name = N'EvaluationId'
      AND TYPE_NAME(system_type_id) <> N'uniqueidentifier'
) BEGIN
    IF EXISTS (SELECT 1 FROM [dbo].[Evaluation_Metric]) BEGIN
        RAISERROR ('ERREUR CRITIQUE : [Evaluation_Metric] contient des données avec un [EvaluationId] non uniqueidentifier. Conversion à traiter manuellement.', 16, 1);
        RETURN;
    END
    DROP TABLE [dbo].[Evaluation_Metric];
    PRINT 'Table [dbo].[Evaluation_Metric] (EvaluationId int, vide) supprimée pour être recréée.';
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
WHERE object_id = OBJECT_ID(N'[dbo].[Evaluation_Metric]')
AND type in (N'U')
) BEGIN
PRINT 'Création de la table [dbo].[Evaluation_Metric]...';
CREATE TABLE [dbo].[Evaluation_Metric](
    [EvaluationId] [uniqueidentifier] NOT NULL,
    [MetricCode] [varchar](30) NOT NULL,
    [Value] [float] NOT NULL,
    CONSTRAINT [PK_Evaluation_Metric] PRIMARY KEY CLUSTERED ([EvaluationId] ASC, [MetricCode] ASC)
) ON [PRIMARY];
PRINT 'Table [dbo].[Evaluation_Metric] créée avec succès.';
END
ELSE BEGIN
PRINT 'Table [dbo].[Evaluation_Metric] déjà existante.';
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
    WHERE fk.parent_object_id = OBJECT_ID(N'[dbo].[Evaluation_Metric]')
      AND fk.referenced_object_id = OBJECT_ID(N'[dbo].[Evaluation]')
      AND fkc.parent_column_id = COLUMNPROPERTY(OBJECT_ID(N'[dbo].[Evaluation_Metric]'), 'EvaluationId', 'ColumnId')
) BEGIN
    ALTER TABLE [dbo].[Evaluation_Metric] WITH CHECK ADD CONSTRAINT [FK_EvaluationMetric_Evaluation]
        FOREIGN KEY ([EvaluationId]) REFERENCES [dbo].[Evaluation] ([Id]) ON DELETE CASCADE;
    PRINT 'Contrainte [FK_EvaluationMetric_Evaluation] ajoutée.';
END
ELSE BEGIN
    PRINT 'Clé étrangère [Evaluation_Metric].[EvaluationId] -> [Evaluation] existante.';
END
-- FK recherchée par colonne et table cible (et non par nom) : pas de doublon possible
IF NOT EXISTS (
    SELECT 1
    FROM sys.foreign_keys fk
    JOIN sys.foreign_key_columns fkc ON fkc.constraint_object_id = fk.object_id
    WHERE fk.parent_object_id = OBJECT_ID(N'[dbo].[Evaluation_Metric]')
      AND fk.referenced_object_id = OBJECT_ID(N'[dbo].[Ref_Metric]')
      AND fkc.parent_column_id = COLUMNPROPERTY(OBJECT_ID(N'[dbo].[Evaluation_Metric]'), 'MetricCode', 'ColumnId')
) BEGIN
    ALTER TABLE [dbo].[Evaluation_Metric] WITH CHECK ADD CONSTRAINT [FK_EvaluationMetric_Metric]
        FOREIGN KEY ([MetricCode]) REFERENCES [dbo].[Ref_Metric] ([Code]);
    PRINT 'Contrainte [FK_EvaluationMetric_Metric] ajoutée.';
END
ELSE BEGIN
    PRINT 'Clé étrangère [Evaluation_Metric].[MetricCode] -> [Ref_Metric] existante.';
END
IF NOT EXISTS (
    SELECT 1 FROM sys.extended_properties
    WHERE major_id = OBJECT_ID(N'[dbo].[Evaluation_Metric]') AND minor_id = 0 AND name = N'MS_Description'
) BEGIN
    EXEC sys.sp_addextendedproperty
        @name = N'MS_Description', @value = N'Métriques d''une évaluation / d''un test de modèle (une ligne par métrique)',
        @level0type = N'SCHEMA', @level0name = N'dbo',
        @level1type = N'TABLE',  @level1name = N'Evaluation_Metric';
    PRINT 'Description de [Evaluation_Metric] ajoutée.';
END
GO
PRINT '=== FIN DE LA MIGRATION [dbo].[Evaluation_Metric] ==='
GO
