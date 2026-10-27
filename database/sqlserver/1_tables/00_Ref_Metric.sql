SET ANSI_NULLS ON
SET QUOTED_IDENTIFIER ON
SET NOCOUNT ON
GO
PRINT '=== DÉBUT DE LA MIGRATION [dbo].[Ref_Metric] ==='
GO
-- =======================================================
-- [FUSION ML] Table de référence : remplace le nom libre metric.name : une métrique inconnue ou mal orthographiée est refusée par la FK.
-- SQL Server n'a pas d'ENUM : une table de référence + clé étrangère
-- garantit les valeurs autorisées, porte un libellé pour l'IHM et
-- permet d'ajouter une valeur sans modifier le schéma.
-- =======================================================
-- 1. CRÉATION DE LA TABLE (Si elle n'existe pas)
-- =======================================================
IF NOT EXISTS (
SELECT 1
FROM sys.objects
WHERE object_id = OBJECT_ID(N'[dbo].[Ref_Metric]')
AND type in (N'U')
) BEGIN
PRINT 'Création de la table [dbo].[Ref_Metric]...';
CREATE TABLE [dbo].[Ref_Metric](
    [Code] [varchar](30) NOT NULL,
    [Label] [nvarchar](100) NOT NULL,
    [LowerIsBetter] [bit] NOT NULL,
    CONSTRAINT [PK_Ref_Metric] PRIMARY KEY CLUSTERED ([Code] ASC)
) ON [PRIMARY];
PRINT 'Table [dbo].[Ref_Metric] créée avec succès.';
END
ELSE BEGIN
PRINT 'Table [dbo].[Ref_Metric] déjà existante.';
END
GO
-- =======================================================
-- 2. CONTRAINTES ET DESCRIPTION
-- =======================================================
DECLARE @df SYSNAME, @dfDef NVARCHAR(MAX), @dfOld NVARCHAR(300);
SET @df = NULL; SET @dfDef = NULL;
SELECT @df = name, @dfDef = definition
FROM sys.default_constraints
WHERE parent_object_id = OBJECT_ID(N'[dbo].[Ref_Metric]')
  AND parent_column_id = COLUMNPROPERTY(OBJECT_ID(N'[dbo].[Ref_Metric]'), 'LowerIsBetter', 'ColumnId');
IF COL_LENGTH(N'[dbo].[Ref_Metric]', N'LowerIsBetter') IS NULL BEGIN
    PRINT 'ATTENTION : colonne [Ref_Metric].[LowerIsBetter] absente, default [DF_Ref_Metric_LowerIsBetter] non traité.';
END
-- Aucun default sur la colonne (ni nommé, ni anonyme) : création
ELSE IF @df IS NULL BEGIN
    IF OBJECT_ID(N'[dbo].[DF_Ref_Metric_LowerIsBetter]') IS NOT NULL BEGIN
        PRINT 'ATTENTION : le nom [DF_Ref_Metric_LowerIsBetter] est déjà utilisé par un autre objet, default non créé.';
    END
    ELSE BEGIN
        ALTER TABLE [dbo].[Ref_Metric] ADD CONSTRAINT [DF_Ref_Metric_LowerIsBetter] DEFAULT ((0)) FOR [LowerIsBetter];
        PRINT 'Default [DF_Ref_Metric_LowerIsBetter] ajouté.';
    END
END
-- Un default existe déjà (éventuellement anonyme) : on n'en crée JAMAIS un second
ELSE BEGIN
    IF @df <> N'DF_Ref_Metric_LowerIsBetter' BEGIN
        IF OBJECT_ID(N'[dbo].[DF_Ref_Metric_LowerIsBetter]') IS NOT NULL BEGIN
            PRINT 'ATTENTION : default ' + @df + ' conservé, le nom [DF_Ref_Metric_LowerIsBetter] est déjà utilisé par un autre objet.';
        END
        ELSE BEGIN
            SET @dfOld = N'[dbo].' + QUOTENAME(@df);
            EXEC sp_rename @dfOld, N'DF_Ref_Metric_LowerIsBetter', N'OBJECT';
            PRINT 'Default ' + @df + ' renommé en [DF_Ref_Metric_LowerIsBetter].';
        END
    END
    ELSE BEGIN
        PRINT 'Default [DF_Ref_Metric_LowerIsBetter] existant.';
    END
    IF @dfDef <> N'((0))' BEGIN
        PRINT 'ATTENTION : le default de [Ref_Metric].[LowerIsBetter] vaut ' + @dfDef + ' au lieu de ((0)) (conservé, à vérifier).';
    END
END
IF NOT EXISTS (
    SELECT 1 FROM sys.extended_properties
    WHERE major_id = OBJECT_ID(N'[dbo].[Ref_Metric]') AND minor_id = 0 AND name = N'MS_Description'
) BEGIN
    EXEC sys.sp_addextendedproperty
        @name = N'MS_Description', @value = N'Catalogue des métriques (évite les noms libres dans les tables de métriques)',
        @level0type = N'SCHEMA', @level0name = N'dbo',
        @level1type = N'TABLE',  @level1name = N'Ref_Metric';
    PRINT 'Description de [Ref_Metric] ajoutée.';
END
GO
-- =======================================================
-- 3. VALEURS DE RÉFÉRENCE
-- Insérées ici (et non dans 3_init) : les contraintes des tables
-- suivantes (FK, defaults) en dépendent dès la phase 1_tables.
-- Idempotent : ajout des codes manquants, mise à jour des libellés.
-- =======================================================
DECLARE @Ref TABLE ([Code] [varchar](30) NOT NULL, [Label] [nvarchar](100) NOT NULL, [LowerIsBetter] [bit] NOT NULL);
INSERT INTO @Ref ([Code], [Label], [LowerIsBetter])
VALUES ('ACCURACY', N'Accuracy', CAST(0 AS bit)),
       ('ERROR_RATE', N'Taux d''erreur', CAST(1 AS bit)),
       ('PRECISION', N'Précision', CAST(0 AS bit)),
       ('RECALL', N'Rappel', CAST(0 AS bit)),
       ('F1', N'F1-score', CAST(0 AS bit)),
       ('KAPPA', N'Kappa de Cohen', CAST(0 AS bit)),
       ('AP_BBOX', N'AP (bounding box)', CAST(0 AS bit)),
       ('RECALL_BBOX', N'Rappel (bounding box)', CAST(0 AS bit)),
       ('AP_SEGM', N'AP (segmentation)', CAST(0 AS bit)),
       ('RECALL_SEGM', N'Rappel (segmentation)', CAST(0 AS bit)),
       ('MEAN_ERRORS', N'Nombre moyen d''erreurs', CAST(1 AS bit)),
       ('NB_ERRORS', N'Nombre d''erreurs', CAST(1 AS bit));

UPDATE r SET r.[Label] = v.[Label], r.[LowerIsBetter] = v.[LowerIsBetter]
FROM [dbo].[Ref_Metric] r
JOIN @Ref v ON v.[Code] = r.[Code]
WHERE r.[Label] <> v.[Label] OR r.[LowerIsBetter] <> v.[LowerIsBetter];
IF @@ROWCOUNT > 0 PRINT 'Libellés de [Ref_Metric] mis à jour.';

INSERT INTO [dbo].[Ref_Metric] ([Code], [Label], [LowerIsBetter])
SELECT v.[Code], v.[Label], v.[LowerIsBetter]
FROM @Ref v
WHERE NOT EXISTS (SELECT 1 FROM [dbo].[Ref_Metric] r WHERE r.[Code] = v.[Code]);
PRINT 'Valeurs de référence insérées dans [Ref_Metric] : ' + CAST(@@ROWCOUNT AS varchar(10));
GO
PRINT '=== FIN DE LA MIGRATION [dbo].[Ref_Metric] ==='
GO
