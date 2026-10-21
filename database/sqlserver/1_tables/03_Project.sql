SET ANSI_NULLS ON
SET QUOTED_IDENTIFIER ON
SET NOCOUNT ON
GO
PRINT '=== DÉBUT DE LA MIGRATION [dbo].[Project] ==='
GO
-- =======================================================
-- 1. CRÉATION DE LA TABLE (Si elle n'existe pas)
-- =======================================================
IF NOT EXISTS (
SELECT *
FROM sys.objects
WHERE object_id = OBJECT_ID(N'[dbo].[Project]')
AND type in (N'U')
) BEGIN
PRINT 'Création de la table [dbo].[Project]...';
CREATE TABLE [dbo].[Project](
    [Id] [int] IDENTITY(1, 1) NOT NULL,
    [Name] [nvarchar](max) NOT NULL,
    [ProjectType] [nvarchar](max) NULL,
    [Description] [nvarchar](max) NULL,
    [IsActive] [bit] NOT NULL,
    -- [CORRECTIF] default nommé : un DEFAULT anonyme crée une contrainte DF__Project__Creat__XXXX
    [CreatedAt] [datetime2](7) NOT NULL CONSTRAINT [DF_Project_CreatedAt] DEFAULT GETDATE(),
    [CreatedBy] [nvarchar](max) NULL,
    [UpdatedBy] [nvarchar](max) NULL,
    CONSTRAINT [PK_Project] PRIMARY KEY CLUSTERED ([Id] ASC) WITH (
        PAD_INDEX = OFF,
        STATISTICS_NORECOMPUTE = OFF,
        IGNORE_DUP_KEY = OFF,
        ALLOW_ROW_LOCKS = ON,
        ALLOW_PAGE_LOCKS = ON,
        OPTIMIZE_FOR_SEQUENTIAL_KEY = OFF
    ) ON [PRIMARY]
) ON [PRIMARY] TEXTIMAGE_ON [PRIMARY];

IF NOT EXISTS (
    SELECT
        1
    FROM
        fn_listextendedproperty(NULL, 'SCHEMA', 'dbo', 'TABLE', 'Project', NULL, NULL)
) BEGIN
    EXEC sys.sp_addextendedproperty @name = N'MS_Description',
    @value = N'Projets (Entité principale)',
    @level0type = N'SCHEMA',
    @level0name = N'dbo',
    @level1type = N'TABLE',
    @level1name = N'Project'
    PRINT 'Propriété MS_Description ajoutée avec succès.'
END
ELSE BEGIN
    PRINT 'Propriété MS_Description existe déjà, aucune action nécessaire.'
END

PRINT 'Table [dbo].[Project] créée avec succès.';

END
GO
-- =======================================================
-- 2. MODIFICATIONS DE STRUCTURE (Si la table existe déjà)
-- =======================================================
PRINT 'Vérification et application des modifications de structure...'
GO
IF EXISTS (
SELECT 1 FROM sys.tables WHERE name = N'Project' AND schema_id = SCHEMA_ID('dbo')
) BEGIN
-- 2.1. Ajout de la colonne [UpdatedBy] si manquante
IF NOT EXISTS (
    SELECT 1
    FROM sys.columns
    WHERE Name = N'UpdatedBy' AND Object_ID = OBJECT_ID(N'[dbo].[Project]')
) BEGIN
    ALTER TABLE [dbo].[Project] ADD [UpdatedBy] [nvarchar](max) NULL;
    PRINT 'Colonne [UpdatedBy] ajoutée.';
END
ELSE BEGIN
    PRINT 'Colonne [UpdatedBy] déjà présente.';
END

-- 2.3. Ajout des contraintes par défaut (Defaults)
-- [CORRECTIF] recherche du default par COLONNE et non par nom : une colonne ne peut
--             avoir qu'un seul default, quel que soit son nom (sinon erreur 1781).
--             Un default existant au nom auto-généré (DF__Project__Creat__XXXX) est renommé.
DECLARE @df SYSNAME, @dfOld NVARCHAR(300);

-- Pour IsActive
SET @df = NULL;
SELECT @df = name
FROM sys.default_constraints
WHERE parent_object_id = OBJECT_ID(N'[dbo].[Project]')
  AND parent_column_id = COLUMNPROPERTY(OBJECT_ID(N'[dbo].[Project]'), 'IsActive', 'ColumnId');
IF @df IS NULL BEGIN
    ALTER TABLE [dbo].[Project] ADD CONSTRAINT [DF_Project_IsActive] DEFAULT 1 FOR [IsActive];
    PRINT 'Default [IsActive] ajouté.';
END
ELSE IF @df <> N'DF_Project_IsActive' BEGIN
    SET @dfOld = N'[dbo].' + QUOTENAME(@df);
    EXEC sp_rename @dfOld, N'DF_Project_IsActive', N'OBJECT';
    PRINT 'Default ' + @df + ' renommé en [DF_Project_IsActive].';
END
ELSE BEGIN
    PRINT 'Default [IsActive] existant.';
END

-- Pour CreatedAt
SET @df = NULL;
SELECT @df = name
FROM sys.default_constraints
WHERE parent_object_id = OBJECT_ID(N'[dbo].[Project]')
  AND parent_column_id = COLUMNPROPERTY(OBJECT_ID(N'[dbo].[Project]'), 'CreatedAt', 'ColumnId');
IF @df IS NULL BEGIN
    ALTER TABLE [dbo].[Project] ADD CONSTRAINT [DF_Project_CreatedAt] DEFAULT GETDATE() FOR [CreatedAt];
    PRINT 'Default [CreatedAt] ajouté.';
END
ELSE IF @df <> N'DF_Project_CreatedAt' BEGIN
    SET @dfOld = N'[dbo].' + QUOTENAME(@df);
    EXEC sp_rename @dfOld, N'DF_Project_CreatedAt', N'OBJECT';
    PRINT 'Default ' + @df + ' renommé en [DF_Project_CreatedAt].';
END
ELSE BEGIN
    PRINT 'Default [CreatedAt] existant.';
END

END
GO
-- [RÉORGANISATION] Les triggers de [Project] sont dans 2_procedures/trg_Project.sql
PRINT '=== FIN DE LA MIGRATION [dbo].[Project] ==='
GO
