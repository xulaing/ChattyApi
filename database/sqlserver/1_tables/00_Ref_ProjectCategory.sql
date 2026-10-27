SET ANSI_NULLS ON
SET QUOTED_IDENTIFIER ON
SET NOCOUNT ON
GO
PRINT '=== DÉBUT DE LA MIGRATION [dbo].[Ref_ProjectCategory] ==='
GO
-- =======================================================
-- [FUSION ML] Table de référence : distingue les projets LLM existants des modèles entraînés.
-- SQL Server n'a pas d'ENUM : une table de référence + clé étrangère
-- garantit les valeurs autorisées, porte un libellé pour l'IHM et
-- permet d'ajouter une valeur sans modifier le schéma.
-- =======================================================
-- 1. CRÉATION DE LA TABLE (Si elle n'existe pas)
-- =======================================================
IF NOT EXISTS (
SELECT 1
FROM sys.objects
WHERE object_id = OBJECT_ID(N'[dbo].[Ref_ProjectCategory]')
AND type in (N'U')
) BEGIN
PRINT 'Création de la table [dbo].[Ref_ProjectCategory]...';
CREATE TABLE [dbo].[Ref_ProjectCategory](
    [Code] [varchar](10) NOT NULL,
    [Label] [nvarchar](100) NOT NULL,
    CONSTRAINT [PK_Ref_ProjectCategory] PRIMARY KEY CLUSTERED ([Code] ASC)
) ON [PRIMARY];
PRINT 'Table [dbo].[Ref_ProjectCategory] créée avec succès.';
END
ELSE BEGIN
PRINT 'Table [dbo].[Ref_ProjectCategory] déjà existante.';
END
GO
-- =======================================================
-- 2. CONTRAINTES ET DESCRIPTION
-- =======================================================
IF NOT EXISTS (
    SELECT 1 FROM sys.extended_properties
    WHERE major_id = OBJECT_ID(N'[dbo].[Ref_ProjectCategory]') AND minor_id = 0 AND name = N'MS_Description'
) BEGIN
    EXEC sys.sp_addextendedproperty
        @name = N'MS_Description', @value = N'Catégorie de projet : LLM (projets existants) ou MODEL (modèle entraîné, ex-table model)',
        @level0type = N'SCHEMA', @level0name = N'dbo',
        @level1type = N'TABLE',  @level1name = N'Ref_ProjectCategory';
    PRINT 'Description de [Ref_ProjectCategory] ajoutée.';
END
GO
-- =======================================================
-- 3. VALEURS DE RÉFÉRENCE
-- Insérées ici (et non dans 3_init) : les contraintes des tables
-- suivantes (FK, defaults) en dépendent dès la phase 1_tables.
-- Idempotent : ajout des codes manquants, mise à jour des libellés.
-- =======================================================
DECLARE @Ref TABLE ([Code] [varchar](10) NOT NULL, [Label] [nvarchar](100) NOT NULL);
INSERT INTO @Ref ([Code], [Label])
VALUES ('LLM', N'Projet LLM'),
       ('MODEL', N'Modèle entraîné');

UPDATE r SET r.[Label] = v.[Label]
FROM [dbo].[Ref_ProjectCategory] r
JOIN @Ref v ON v.[Code] = r.[Code]
WHERE r.[Label] <> v.[Label];
IF @@ROWCOUNT > 0 PRINT 'Libellés de [Ref_ProjectCategory] mis à jour.';

INSERT INTO [dbo].[Ref_ProjectCategory] ([Code], [Label])
SELECT v.[Code], v.[Label]
FROM @Ref v
WHERE NOT EXISTS (SELECT 1 FROM [dbo].[Ref_ProjectCategory] r WHERE r.[Code] = v.[Code]);
PRINT 'Valeurs de référence insérées dans [Ref_ProjectCategory] : ' + CAST(@@ROWCOUNT AS varchar(10));
GO
PRINT '=== FIN DE LA MIGRATION [dbo].[Ref_ProjectCategory] ==='
GO
