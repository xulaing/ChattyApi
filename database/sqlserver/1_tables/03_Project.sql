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
    -- [CORRECTIF] pas de DEFAULT inline (il créerait une contrainte anonyme DF__Project__Creat__XXXX) :
    --             le default [DF_Project_CreatedAt] est posé à l'étape 2.3, comme celui de [IsActive]
    [CreatedAt] [datetime2](7) NOT NULL,
    [CreatedBy] [nvarchar](max) NULL,
    [UpdatedBy] [nvarchar](max) NULL,
    -- [FUSION ML] colonnes issues de l'ancienne table model (voir section 3)
    [Category] [varchar](10) NOT NULL,
    [AssociatedSolutionId] [uniqueidentifier] NULL,
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
DECLARE @df SYSNAME, @dfDef NVARCHAR(MAX), @dfOld NVARCHAR(300);

-- Pour IsActive
SET @df = NULL; SET @dfDef = NULL;
SELECT @df = name, @dfDef = definition
FROM sys.default_constraints
WHERE parent_object_id = OBJECT_ID(N'[dbo].[Project]')
  AND parent_column_id = COLUMNPROPERTY(OBJECT_ID(N'[dbo].[Project]'), 'IsActive', 'ColumnId');
IF COL_LENGTH(N'[dbo].[Project]', N'IsActive') IS NULL BEGIN
    PRINT 'ATTENTION : colonne [Project].[IsActive] absente, default [DF_Project_IsActive] non traité.';
END
-- Aucun default sur la colonne (ni nommé, ni anonyme) : création
ELSE IF @df IS NULL BEGIN
    IF OBJECT_ID(N'[dbo].[DF_Project_IsActive]') IS NOT NULL BEGIN
        PRINT 'ATTENTION : le nom [DF_Project_IsActive] est déjà utilisé par un autre objet, default non créé.';
    END
    ELSE BEGIN
        ALTER TABLE [dbo].[Project] ADD CONSTRAINT [DF_Project_IsActive] DEFAULT ((1)) FOR [IsActive];
        PRINT 'Default [DF_Project_IsActive] ajouté.';
    END
END
-- Un default existe déjà (éventuellement anonyme) : on n'en crée JAMAIS un second
ELSE BEGIN
    IF @df <> N'DF_Project_IsActive' BEGIN
        IF OBJECT_ID(N'[dbo].[DF_Project_IsActive]') IS NOT NULL BEGIN
            PRINT 'ATTENTION : default ' + @df + ' conservé, le nom [DF_Project_IsActive] est déjà utilisé par un autre objet.';
        END
        ELSE BEGIN
            SET @dfOld = N'[dbo].' + QUOTENAME(@df);
            EXEC sp_rename @dfOld, N'DF_Project_IsActive', N'OBJECT';
            PRINT 'Default ' + @df + ' renommé en [DF_Project_IsActive].';
        END
    END
    ELSE BEGIN
        PRINT 'Default [DF_Project_IsActive] existant.';
    END
    IF @dfDef <> N'((1))' BEGIN
        PRINT 'ATTENTION : le default de [Project].[IsActive] vaut ' + @dfDef + ' au lieu de ((1)) (conservé, à vérifier).';
    END
END

-- Pour CreatedAt
SET @df = NULL; SET @dfDef = NULL;
SELECT @df = name, @dfDef = definition
FROM sys.default_constraints
WHERE parent_object_id = OBJECT_ID(N'[dbo].[Project]')
  AND parent_column_id = COLUMNPROPERTY(OBJECT_ID(N'[dbo].[Project]'), 'CreatedAt', 'ColumnId');
IF COL_LENGTH(N'[dbo].[Project]', N'CreatedAt') IS NULL BEGIN
    PRINT 'ATTENTION : colonne [Project].[CreatedAt] absente, default [DF_Project_CreatedAt] non traité.';
END
-- Aucun default sur la colonne (ni nommé, ni anonyme) : création
ELSE IF @df IS NULL BEGIN
    IF OBJECT_ID(N'[dbo].[DF_Project_CreatedAt]') IS NOT NULL BEGIN
        PRINT 'ATTENTION : le nom [DF_Project_CreatedAt] est déjà utilisé par un autre objet, default non créé.';
    END
    ELSE BEGIN
        ALTER TABLE [dbo].[Project] ADD CONSTRAINT [DF_Project_CreatedAt] DEFAULT (getdate()) FOR [CreatedAt];
        PRINT 'Default [DF_Project_CreatedAt] ajouté.';
    END
END
-- Un default existe déjà (éventuellement anonyme) : on n'en crée JAMAIS un second
ELSE BEGIN
    IF @df <> N'DF_Project_CreatedAt' BEGIN
        IF OBJECT_ID(N'[dbo].[DF_Project_CreatedAt]') IS NOT NULL BEGIN
            PRINT 'ATTENTION : default ' + @df + ' conservé, le nom [DF_Project_CreatedAt] est déjà utilisé par un autre objet.';
        END
        ELSE BEGIN
            SET @dfOld = N'[dbo].' + QUOTENAME(@df);
            EXEC sp_rename @dfOld, N'DF_Project_CreatedAt', N'OBJECT';
            PRINT 'Default ' + @df + ' renommé en [DF_Project_CreatedAt].';
        END
    END
    ELSE BEGIN
        PRINT 'Default [DF_Project_CreatedAt] existant.';
    END
    IF @dfDef <> N'(getdate())' BEGIN
        PRINT 'ATTENTION : le default de [Project].[CreatedAt] vaut ' + @dfDef + ' au lieu de (getdate()) (conservé, à vérifier).';
    END
END

END
GO
-- =======================================================
-- 3. [FUSION ML] PROJETS LLM ET MODÈLES ENTRAÎNÉS DANS LA MÊME TABLE
--    L'ancienne table model est absorbée par [Project] :
--    - [Category]             : 'LLM' (projets existants) ou 'MODEL' (modèle entraîné)
--                               -> [Ref_ProjectCategory]. Les lignes existantes
--                               reçoivent 'LLM' via le default.
--    - Type de tâche d'un MODEL : porté par [ProjectType] (« Classification »,
--                               « Découpage »...), le libellé de [Ref_TaskType].
--                               Obligatoire pour un MODEL. Plus de colonne [TaskType] :
--                               elle répétait [ProjectType] en majuscules.
--    - [AssociatedSolutionId] : ex-model.AssociatedSolutionId, un GUID (aucune table
--                               cible connue dans cette base : pas de FK).
--    [ProjectType] (colonne existante) n'est pas modifiée.
-- =======================================================
PRINT 'Vérification des colonnes de fusion ML...'
GO
IF COL_LENGTH(N'[dbo].[Project]', N'Category') IS NULL BEGIN
    -- Colonne NOT NULL ajoutée avec son default nommé : les lignes existantes valent 'LLM'
    ALTER TABLE [dbo].[Project] ADD [Category] [varchar](10) NOT NULL
        CONSTRAINT [DF_Project_Category] DEFAULT ('LLM');
    PRINT 'Colonne [Category] ajoutée (projets existants = LLM).';
END
ELSE BEGIN
    PRINT 'Colonne [Category] déjà présente.';
END
-- [FUSION ML] Colonne [TaskType] créée par une version précédente de ce script :
-- doublon de [ProjectType] (même valeur, en majuscules). Supprimée après report de
-- sa valeur dans [ProjectType] quand celui-ci est vide.
-- (SQL dynamique : la colonne peut ne pas exister à la compilation du batch)
IF COL_LENGTH(N'[dbo].[Project]', N'TaskType') IS NOT NULL BEGIN
    DECLARE @Conflits NVARCHAR(MAX), @sql NVARCHAR(MAX), @obj SYSNAME, @colId INT;
    -- 1. [ProjectType] vide : reçoit le libellé du type de tâche
    EXEC sys.sp_executesql N'
        UPDATE p SET p.[ProjectType] = r.[Label]
        FROM [dbo].[Project] p
        JOIN [dbo].[Ref_TaskType] r ON r.[Code] = p.[TaskType]
        WHERE NULLIF(LTRIM(RTRIM(p.[ProjectType])), N'''') IS NULL;
        DECLARE @n INT = @@ROWCOUNT;
        IF @n > 0 PRINT ''[ProjectType] renseigné depuis [TaskType] : '' + CAST(@n AS varchar(10)) + '' ligne(s).'';';
    -- 2. Valeurs contradictoires (ni le code ni le libellé, sans casse ni accents) :
    --    la colonne est conservée pour ne rien perdre
    EXEC sys.sp_executesql N'
        SELECT @c = STRING_AGG(CONVERT(nvarchar(max), CONCAT(N''Id '', p.[Id], N'' : ProjectType = '', p.[ProjectType], N'', TaskType = '', p.[TaskType])), N''; '')
        FROM [dbo].[Project] p
        LEFT JOIN [dbo].[Ref_TaskType] r ON r.[Code] = p.[TaskType]
        WHERE p.[TaskType] IS NOT NULL
          AND LTRIM(RTRIM(p.[ProjectType])) COLLATE Latin1_General_CI_AI NOT IN
              (p.[TaskType] COLLATE Latin1_General_CI_AI, ISNULL(r.[Label], N'''') COLLATE Latin1_General_CI_AI);',
        N'@c NVARCHAR(MAX) OUTPUT', @c = @Conflits OUTPUT;
    IF @Conflits IS NOT NULL BEGIN
        PRINT 'ATTENTION : [Project].[TaskType] conservée, valeurs différentes de [ProjectType] à corriger puis relancer ce script : ' + LEFT(@Conflits, 3500);
    END
    ELSE BEGIN
        SET @colId = COLUMNPROPERTY(OBJECT_ID(N'[dbo].[Project]'), 'TaskType', 'ColumnId');
        -- 3. Contraintes et index qui utilisent la colonne (recherchés par colonne)
        WHILE 1 = 1 BEGIN
            SET @obj = NULL;
            SELECT TOP (1) @obj = fk.name FROM sys.foreign_keys fk
            JOIN sys.foreign_key_columns fkc ON fkc.constraint_object_id = fk.object_id
            WHERE fk.parent_object_id = OBJECT_ID(N'[dbo].[Project]') AND fkc.parent_column_id = @colId;
            IF @obj IS NULL
                SELECT TOP (1) @obj = name FROM sys.check_constraints
                WHERE parent_object_id = OBJECT_ID(N'[dbo].[Project]')
                  AND (parent_column_id = @colId OR definition LIKE N'%\[TaskType\]%' ESCAPE N'\');
            IF @obj IS NULL
                SELECT TOP (1) @obj = name FROM sys.default_constraints
                WHERE parent_object_id = OBJECT_ID(N'[dbo].[Project]') AND parent_column_id = @colId;
            IF @obj IS NULL BREAK;
            SET @sql = N'ALTER TABLE [dbo].[Project] DROP CONSTRAINT ' + QUOTENAME(@obj) + N';';
            EXEC sys.sp_executesql @sql;
            PRINT 'Contrainte ' + QUOTENAME(@obj) + ' (sur [TaskType]) supprimée.';
        END
        WHILE 1 = 1 BEGIN
            SET @obj = NULL;
            SELECT TOP (1) @obj = i.name FROM sys.indexes i
            JOIN sys.index_columns ic ON ic.object_id = i.object_id AND ic.index_id = i.index_id
            WHERE i.object_id = OBJECT_ID(N'[dbo].[Project]') AND ic.column_id = @colId AND i.is_primary_key = 0;
            IF @obj IS NULL BREAK;
            SET @sql = N'DROP INDEX ' + QUOTENAME(@obj) + N' ON [dbo].[Project];';
            EXEC sys.sp_executesql @sql;
            PRINT 'Index ' + QUOTENAME(@obj) + ' (sur [TaskType]) supprimé.';
        END
        -- 4. Suppression de la colonne
        EXEC sys.sp_executesql N'ALTER TABLE [dbo].[Project] DROP COLUMN [TaskType];';
        PRINT 'Colonne [TaskType] supprimée (doublon de [ProjectType]).';
    END
END
-- Colonne créée en bigint par une version précédente de ce script : la donnée source est
-- un GUID. Vide : la colonne est supprimée puis recréée ; sinon arrêt.
-- (SQL dynamique : la colonne peut ne pas exister à la compilation du batch)
IF EXISTS (
    SELECT 1 FROM sys.columns
    WHERE object_id = OBJECT_ID(N'[dbo].[Project]') AND name = N'AssociatedSolutionId'
      AND TYPE_NAME(system_type_id) <> N'uniqueidentifier'
) BEGIN
    DECLARE @NonVide INT;
    EXEC sys.sp_executesql
        N'SELECT @n = COUNT(*) FROM [dbo].[Project] WHERE [AssociatedSolutionId] IS NOT NULL',
        N'@n INT OUTPUT', @n = @NonVide OUTPUT;
    IF @NonVide > 0 BEGIN
        RAISERROR ('ERREUR CRITIQUE : [Project].[AssociatedSolutionId] contient des valeurs non GUID. Conversion à traiter manuellement.', 16, 1);
        RETURN;
    END
    ALTER TABLE [dbo].[Project] DROP COLUMN [AssociatedSolutionId];
    PRINT 'Colonne [AssociatedSolutionId] (bigint, vide) supprimée pour être recréée en uniqueidentifier.';
END
IF COL_LENGTH(N'[dbo].[Project]', N'AssociatedSolutionId') IS NULL BEGIN
    ALTER TABLE [dbo].[Project] ADD [AssociatedSolutionId] [uniqueidentifier] NULL;
    PRINT 'Colonne [AssociatedSolutionId] ajoutée.';
END
ELSE BEGIN
    PRINT 'Colonne [AssociatedSolutionId] déjà présente.';
END
GO
-- Batch séparé : les colonnes ajoutées ci-dessus existent à la compilation
DECLARE @df SYSNAME, @dfDef NVARCHAR(MAX), @dfOld NVARCHAR(300);
SET @df = NULL; SET @dfDef = NULL;
SELECT @df = name, @dfDef = definition
FROM sys.default_constraints
WHERE parent_object_id = OBJECT_ID(N'[dbo].[Project]')
  AND parent_column_id = COLUMNPROPERTY(OBJECT_ID(N'[dbo].[Project]'), 'Category', 'ColumnId');
IF COL_LENGTH(N'[dbo].[Project]', N'Category') IS NULL BEGIN
    PRINT 'ATTENTION : colonne [Project].[Category] absente, default [DF_Project_Category] non traité.';
END
-- Aucun default sur la colonne (ni nommé, ni anonyme) : création
ELSE IF @df IS NULL BEGIN
    IF OBJECT_ID(N'[dbo].[DF_Project_Category]') IS NOT NULL BEGIN
        PRINT 'ATTENTION : le nom [DF_Project_Category] est déjà utilisé par un autre objet, default non créé.';
    END
    ELSE BEGIN
        ALTER TABLE [dbo].[Project] ADD CONSTRAINT [DF_Project_Category] DEFAULT ('LLM') FOR [Category];
        PRINT 'Default [DF_Project_Category] ajouté.';
    END
END
-- Un default existe déjà (éventuellement anonyme) : on n'en crée JAMAIS un second
ELSE BEGIN
    IF @df <> N'DF_Project_Category' BEGIN
        IF OBJECT_ID(N'[dbo].[DF_Project_Category]') IS NOT NULL BEGIN
            PRINT 'ATTENTION : default ' + @df + ' conservé, le nom [DF_Project_Category] est déjà utilisé par un autre objet.';
        END
        ELSE BEGIN
            SET @dfOld = N'[dbo].' + QUOTENAME(@df);
            EXEC sp_rename @dfOld, N'DF_Project_Category', N'OBJECT';
            PRINT 'Default ' + @df + ' renommé en [DF_Project_Category].';
        END
    END
    ELSE BEGIN
        PRINT 'Default [DF_Project_Category] existant.';
    END
    IF @dfDef <> N'(''LLM'')' BEGIN
        PRINT 'ATTENTION : le default de [Project].[Category] vaut ' + @dfDef + ' au lieu de (''LLM'') (conservé, à vérifier).';
    END
END
-- FK recherchée par colonne et table cible (et non par nom) : pas de doublon possible
IF NOT EXISTS (
    SELECT 1
    FROM sys.foreign_keys fk
    JOIN sys.foreign_key_columns fkc ON fkc.constraint_object_id = fk.object_id
    WHERE fk.parent_object_id = OBJECT_ID(N'[dbo].[Project]')
      AND fk.referenced_object_id = OBJECT_ID(N'[dbo].[Ref_ProjectCategory]')
      AND fkc.parent_column_id = COLUMNPROPERTY(OBJECT_ID(N'[dbo].[Project]'), 'Category', 'ColumnId')
) BEGIN
    ALTER TABLE [dbo].[Project] WITH CHECK ADD CONSTRAINT [FK_Project_Category]
        FOREIGN KEY ([Category]) REFERENCES [dbo].[Ref_ProjectCategory] ([Code]);
    PRINT 'Contrainte [FK_Project_Category] ajoutée.';
END
ELSE BEGIN
    PRINT 'Clé étrangère [Project].[Category] -> [Ref_ProjectCategory] existante.';
END
-- Un modèle entraîné a forcément un type de tâche ([ProjectType])
IF NOT EXISTS (
    SELECT 1 FROM sys.check_constraints
    WHERE name = N'CK_Project_ProjectType_Model' AND parent_object_id = OBJECT_ID(N'[dbo].[Project]')
) BEGIN
    IF EXISTS (SELECT 1 FROM [dbo].[Project] WHERE [Category] = 'MODEL' AND NULLIF(LTRIM(RTRIM([ProjectType])), N'') IS NULL) BEGIN
        PRINT 'ATTENTION : des projets MODEL n''ont pas de [ProjectType] : contrainte [CK_Project_ProjectType_Model] non créée.';
    END
    ELSE BEGIN
        ALTER TABLE [dbo].[Project] WITH CHECK ADD CONSTRAINT [CK_Project_ProjectType_Model]
            CHECK ([Category] <> 'MODEL' OR NULLIF(LTRIM(RTRIM([ProjectType])), N'') IS NOT NULL);
        PRINT 'Contrainte [CK_Project_ProjectType_Model] ajoutée.';
    END
END
ELSE BEGIN
    PRINT 'Contrainte [CK_Project_ProjectType_Model] existante.';
END
IF NOT EXISTS (
    SELECT 1 FROM sys.indexes
    WHERE name = N'IX_Project_Category' AND object_id = OBJECT_ID(N'[dbo].[Project]')
) BEGIN
    CREATE NONCLUSTERED INDEX [IX_Project_Category] ON [dbo].[Project] ([Category], [IsActive]);
    PRINT 'Index [IX_Project_Category] créé.';
END
ELSE BEGIN
    PRINT 'Index [IX_Project_Category] existant.';
END
GO
-- [RÉORGANISATION] Les triggers de [Project] sont dans 2_procedures/trg_Project.sql
PRINT '=== FIN DE LA MIGRATION [dbo].[Project] ==='
GO
