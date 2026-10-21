SET ANSI_NULLS ON
SET QUOTED_IDENTIFIER ON
SET NOCOUNT ON
GO
PRINT '=== DÉBUT DE LA MIGRATION [dbo].[Team] ==='
GO
-- =======================================================
-- 1. CRÉATION DE LA TABLE (Si elle n'existe pas)
-- =======================================================
IF NOT EXISTS (
SELECT *
FROM sys.objects
WHERE object_id = OBJECT_ID(N'[dbo].[Team]')
AND type in (N'U')
) BEGIN
PRINT 'Création de la table [dbo].[Team]...';
CREATE TABLE [dbo].[Team](
    [Id] [bigint] IDENTITY(1,1) NOT NULL,
    [Code] [varchar](6) NOT NULL,
    [CanViewAll] [bit] NOT NULL,
    CONSTRAINT [PK_Team] PRIMARY KEY CLUSTERED
    (
        [Id] ASC
    ) WITH (
        PAD_INDEX = OFF,
        STATISTICS_NORECOMPUTE = OFF,
        IGNORE_DUP_KEY = OFF,
        ALLOW_ROW_LOCKS = ON,
        ALLOW_PAGE_LOCKS = ON,
        OPTIMIZE_FOR_SEQUENTIAL_KEY = OFF
    ) ON [PRIMARY]
) ON [PRIMARY];

 IF NOT EXISTS (
 SELECT 1
 FROM sys.extended_properties
 WHERE major_id = OBJECT_ID(N'[dbo].[Team]')
 AND minor_id = 0
 AND name = N'MS_Description'

)
BEGIN
EXEC sys.sp_addextendedproperty
@name=N'MS_Description',
@value=N'Equipe',
@level0type=N'SCHEMA', @level0name=N'dbo',
@level1type=N'TABLE', @level1name=N'Team';
END
PRINT 'Table [dbo].[Team] créée avec succès.';

END
ELSE
BEGIN
PRINT 'Table [dbo].[Team] déjà existante.';
END
GO
-- =======================================================
-- 2. AJOUT DE CONTRAINTES (Si la table existe déjà)
-- =======================================================
PRINT 'Vérification et application des contraintes...'
GO
IF EXISTS (
    SELECT 1 FROM sys.tables WHERE name = N'Team' AND schema_id = SCHEMA_ID('dbo')
) BEGIN
    -- [CORRECTIF] default bit à 0, recherché par colonne ; un default existant au nom
    --             auto-généré est renommé
    DECLARE @df SYSNAME, @dfDef NVARCHAR(MAX), @dfOld NVARCHAR(300);
    SET @df = NULL; SET @dfDef = NULL;
    SELECT @df = name, @dfDef = definition
    FROM sys.default_constraints
    WHERE parent_object_id = OBJECT_ID(N'[dbo].[Team]')
      AND parent_column_id = COLUMNPROPERTY(OBJECT_ID(N'[dbo].[Team]'), 'CanViewAll', 'ColumnId');
    IF COL_LENGTH(N'[dbo].[Team]', N'CanViewAll') IS NULL BEGIN
        PRINT 'ATTENTION : colonne [Team].[CanViewAll] absente, default [DF_Team_CanViewAll] non traité.';
    END
    -- Aucun default sur la colonne (ni nommé, ni anonyme) : création
    ELSE IF @df IS NULL BEGIN
        IF OBJECT_ID(N'[dbo].[DF_Team_CanViewAll]') IS NOT NULL BEGIN
            PRINT 'ATTENTION : le nom [DF_Team_CanViewAll] est déjà utilisé par un autre objet, default non créé.';
        END
        ELSE BEGIN
            ALTER TABLE [dbo].[Team] ADD CONSTRAINT [DF_Team_CanViewAll] DEFAULT ((0)) FOR [CanViewAll];
            PRINT 'Default [DF_Team_CanViewAll] ajouté.';
        END
    END
    -- Un default existe déjà (éventuellement anonyme) : on n'en crée JAMAIS un second
    ELSE BEGIN
        IF @df <> N'DF_Team_CanViewAll' BEGIN
            IF OBJECT_ID(N'[dbo].[DF_Team_CanViewAll]') IS NOT NULL BEGIN
                PRINT 'ATTENTION : default ' + @df + ' conservé, le nom [DF_Team_CanViewAll] est déjà utilisé par un autre objet.';
            END
            ELSE BEGIN
                SET @dfOld = N'[dbo].' + QUOTENAME(@df);
                EXEC sp_rename @dfOld, N'DF_Team_CanViewAll', N'OBJECT';
                PRINT 'Default ' + @df + ' renommé en [DF_Team_CanViewAll].';
            END
        END
        ELSE BEGIN
            PRINT 'Default [DF_Team_CanViewAll] existant.';
        END
        IF @dfDef <> N'((0))' BEGIN
            PRINT 'ATTENTION : le default de [Team].[CanViewAll] vaut ' + @dfDef + ' au lieu de ((0)) (conservé, à vérifier).';
        END
    END
END
GO
-- [RÉORGANISATION] L'insertion des équipes H620/H600/H500 est déplacée
--                  dans 3_init/init_Team.sql
PRINT '=== FIN DE LA MIGRATION [dbo].[Team] ==='
GO
