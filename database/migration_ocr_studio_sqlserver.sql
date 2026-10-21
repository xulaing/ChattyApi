/* =====================================================================
   MIGRATION IDEMPOTENTE - OCR STUDIO
   ---------------------------------------------------------------------
   - Rejouable autant de fois que nécessaire (base vide ou base v1).
   - Ordre respectant les dépendances :
       Team -> User -> Project -> Project_History -> Project_Version
       -> Project_Member -> Evaluation -> Triggers
   - Exécution recommandée : sqlcmd -b (ou SSMS en mode SQLCMD avec
     ":on error exit") pour stopper au premier batch en erreur.
   ===================================================================== */
SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
SET NOCOUNT ON;
SET XACT_ABORT ON;
GO

/* =====================================================================
   0. PROCÉDURES UTILITAIRES TEMPORAIRES (supprimées en fin de script)
   ===================================================================== */
IF OBJECT_ID(N'tempdb..#EnsureDefault', N'P') IS NOT NULL DROP PROCEDURE #EnsureDefault;
IF OBJECT_ID(N'tempdb..#EnsureForeignKey', N'P') IS NOT NULL DROP PROCEDURE #EnsureForeignKey;
IF OBJECT_ID(N'tempdb..#EnsureCheck', N'P') IS NOT NULL DROP PROCEDURE #EnsureCheck;
IF OBJECT_ID(N'tempdb..#EnsureTableDescription', N'P') IS NOT NULL DROP PROCEDURE #EnsureTableDescription;
IF OBJECT_ID(N'tempdb..#DropColumnDependencies', N'P') IS NOT NULL DROP PROCEDURE #DropColumnDependencies;
GO

-- Garantit UN default nommé @Name sur la colonne.
-- La recherche se fait par COLONNE (et non par nom) : un default auto-généré
-- (DF__Project__Creat__XXXX) est remplacé au lieu de provoquer l'erreur 1781.
CREATE PROCEDURE #EnsureDefault
    @Table      sysname,
    @Column     sysname,
    @Name       sysname,
    @Definition nvarchar(4000)
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @FullTable nvarchar(300) = N'[dbo].' + QUOTENAME(@Table);
    DECLARE @sql nvarchar(max);
    DECLARE @Existing sysname = (
        SELECT dc.name
        FROM sys.default_constraints dc
        WHERE dc.parent_object_id = OBJECT_ID(@FullTable)
          AND dc.parent_column_id = COLUMNPROPERTY(OBJECT_ID(@FullTable), @Column, 'ColumnId')
    );

    IF @Existing = @Name
    BEGIN
        PRINT '  - Default [' + @Name + '] déjà présent.';
        RETURN;
    END

    IF @Existing IS NOT NULL
    BEGIN
        SET @sql = N'ALTER TABLE ' + @FullTable + N' DROP CONSTRAINT ' + QUOTENAME(@Existing) + N';';
        EXEC sys.sp_executesql @sql;
        PRINT '  - Default [' + @Existing + '] supprimé (remplacé par [' + @Name + ']).';
    END

    SET @sql = N'ALTER TABLE ' + @FullTable + N' ADD CONSTRAINT ' + QUOTENAME(@Name)
             + N' DEFAULT ' + @Definition + N' FOR ' + QUOTENAME(@Column) + N';';
    EXEC sys.sp_executesql @sql;
    PRINT '  - Default [' + @Name + '] ajouté.';
END
GO

-- Garantit UNE clé étrangère nommée @Name sur @Table(@Column) -> @RefTable(@RefColumn).
-- - une FK équivalente sous un autre nom (ancien nom / nom auto-généré) est renommée ;
-- - les FK en doublon sur la même colonne vers la même table sont supprimées ;
-- - avant création, contrôle des orphelins pour un message d'erreur explicite.
CREATE PROCEDURE #EnsureForeignKey
    @Table     sysname,
    @Column    sysname,
    @RefTable  sysname,
    @RefColumn sysname,
    @Name      sysname
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @FullTable nvarchar(300) = N'[dbo].' + QUOTENAME(@Table);
    DECLARE @FullRef   nvarchar(300) = N'[dbo].' + QUOTENAME(@RefTable);
    DECLARE @sql nvarchar(max);
    DECLARE @Existing TABLE (name sysname NOT NULL);

    INSERT INTO @Existing (name)
    SELECT DISTINCT fk.name
    FROM sys.foreign_keys fk
    JOIN sys.foreign_key_columns fkc ON fkc.constraint_object_id = fk.object_id
    WHERE fk.parent_object_id = OBJECT_ID(@FullTable)
      AND fk.referenced_object_id = OBJECT_ID(@FullRef)
      AND fkc.parent_column_id = COLUMNPROPERTY(OBJECT_ID(@FullTable), @Column, 'ColumnId');

    DECLARE @Keep sysname = (SELECT name FROM @Existing WHERE name = @Name);

    -- Le nom cible est déjà pris par une FK ayant une autre définition : on la supprime
    IF @Keep IS NULL AND OBJECT_ID(N'[dbo].' + QUOTENAME(@Name), N'F') IS NOT NULL
    BEGIN
        SELECT @sql = N'ALTER TABLE [dbo].' + QUOTENAME(OBJECT_NAME(parent_object_id))
                    + N' DROP CONSTRAINT ' + QUOTENAME(@Name) + N';'
        FROM sys.foreign_keys
        WHERE object_id = OBJECT_ID(N'[dbo].' + QUOTENAME(@Name));
        EXEC sys.sp_executesql @sql;
        PRINT '  - FK [' + @Name + '] mal définie supprimée.';
    END

    -- Renommage d'une FK équivalente (ex. FK_Project_Evaluation -> FK_Evaluation_Project)
    IF @Keep IS NULL
    BEGIN
        SELECT TOP (1) @Keep = name FROM @Existing ORDER BY name;
        IF @Keep IS NOT NULL
        BEGIN
            DECLARE @OldName nvarchar(300) = N'[dbo].' + QUOTENAME(@Keep);
            EXEC sys.sp_rename @OldName, @Name, N'OBJECT';
            PRINT '  - FK [' + @Keep + '] renommée en [' + @Name + '].';
            UPDATE @Existing SET name = @Name WHERE name = @Keep;
            SET @Keep = @Name;
        END
    END

    -- Suppression des doublons
    SET @sql = N'';
    SELECT @sql += N'ALTER TABLE ' + @FullTable + N' DROP CONSTRAINT ' + QUOTENAME(name) + N';'
    FROM @Existing
    WHERE name <> @Name;
    IF @sql <> N''
    BEGIN
        EXEC sys.sp_executesql @sql;
        PRINT '  - FK en doublon supprimée(s) sur [' + @Table + '].[' + @Column + '].';
    END

    IF @Keep IS NOT NULL
    BEGIN
        PRINT '  - FK [' + @Name + '] présente.';
        RETURN;
    END

    DECLARE @Orphans int;
    SET @sql = N'SELECT @n = COUNT(*) FROM ' + @FullTable + N' t WHERE t.' + QUOTENAME(@Column)
             + N' IS NOT NULL AND NOT EXISTS (SELECT 1 FROM ' + @FullRef + N' r WHERE r.'
             + QUOTENAME(@RefColumn) + N' = t.' + QUOTENAME(@Column) + N');';
    EXEC sys.sp_executesql @sql, N'@n int OUTPUT', @n = @Orphans OUTPUT;
    IF @Orphans > 0
    BEGIN
        RAISERROR(N'Impossible de créer [%s] : %d ligne(s) de [%s].[%s] sans correspondance dans [%s].',
                  16, 1, @Name, @Orphans, @Table, @Column, @RefTable);
        RETURN;
    END

    SET @sql = N'ALTER TABLE ' + @FullTable + N' WITH CHECK ADD CONSTRAINT ' + QUOTENAME(@Name)
             + N' FOREIGN KEY (' + QUOTENAME(@Column) + N') REFERENCES ' + @FullRef
             + N' (' + QUOTENAME(@RefColumn) + N');';
    EXEC sys.sp_executesql @sql;
    PRINT '  - FK [' + @Name + '] créée.';
END
GO

CREATE PROCEDURE #EnsureCheck
    @Table      sysname,
    @Name       sysname,
    @Expression nvarchar(4000)
AS
BEGIN
    SET NOCOUNT ON;
    IF OBJECT_ID(N'[dbo].' + QUOTENAME(@Name), N'C') IS NOT NULL
    BEGIN
        PRINT '  - Check [' + @Name + '] déjà présent.';
        RETURN;
    END
    DECLARE @sql nvarchar(max) = N'ALTER TABLE [dbo].' + QUOTENAME(@Table)
        + N' WITH CHECK ADD CONSTRAINT ' + QUOTENAME(@Name) + N' CHECK (' + @Expression + N');';
    EXEC sys.sp_executesql @sql;
    PRINT '  - Check [' + @Name + '] ajouté.';
END
GO

CREATE PROCEDURE #EnsureTableDescription
    @Table       sysname,
    @Description nvarchar(4000)
AS
BEGIN
    SET NOCOUNT ON;
    IF EXISTS (
        SELECT 1 FROM sys.extended_properties
        WHERE class = 1
          AND major_id = OBJECT_ID(N'[dbo].' + QUOTENAME(@Table))
          AND minor_id = 0
          AND name = N'MS_Description'
    )
    BEGIN
        PRINT '  - Description de [' + @Table + '] déjà présente.';
        RETURN;
    END
    EXEC sys.sp_addextendedproperty
        @name = N'MS_Description', @value = @Description,
        @level0type = N'SCHEMA', @level0name = N'dbo',
        @level1type = N'TABLE',  @level1name = @Table;
    PRINT '  - Description de [' + @Table + '] ajoutée.';
END
GO

-- Supprime les FK et le default qui portent sur une colonne (nécessaire avant un ALTER COLUMN).
-- Ils sont recréés ensuite par #EnsureForeignKey / #EnsureDefault.
CREATE PROCEDURE #DropColumnDependencies
    @Table  sysname,
    @Column sysname
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @FullTable nvarchar(300) = N'[dbo].' + QUOTENAME(@Table);
    DECLARE @ObjectId int = OBJECT_ID(@FullTable);
    DECLARE @ColumnId int = COLUMNPROPERTY(@ObjectId, @Column, 'ColumnId');
    DECLARE @sql nvarchar(max) = N'';

    SELECT @sql += N'ALTER TABLE ' + @FullTable + N' DROP CONSTRAINT ' + QUOTENAME(fk.name) + N';'
    FROM sys.foreign_keys fk
    WHERE fk.parent_object_id = @ObjectId
      AND EXISTS (SELECT 1 FROM sys.foreign_key_columns fkc
                  WHERE fkc.constraint_object_id = fk.object_id AND fkc.parent_column_id = @ColumnId);

    SELECT @sql += N'ALTER TABLE ' + @FullTable + N' DROP CONSTRAINT ' + QUOTENAME(dc.name) + N';'
    FROM sys.default_constraints dc
    WHERE dc.parent_object_id = @ObjectId AND dc.parent_column_id = @ColumnId;

    IF @sql <> N''
    BEGIN
        EXEC sys.sp_executesql @sql;
        PRINT '  - Dépendances de [' + @Table + '].[' + @Column + '] supprimées temporairement.';
    END
END
GO


/* =====================================================================
   1. [dbo].[Team]
   ===================================================================== */
PRINT '=== DÉBUT DE LA MIGRATION [dbo].[Team] ===';
IF OBJECT_ID(N'[dbo].[Team]', N'U') IS NULL
BEGIN
    CREATE TABLE [dbo].[Team](
        [Id]         [bigint] IDENTITY(1, 1) NOT NULL,
        [Code]       [varchar](6) NOT NULL,
        [CanViewAll] [bit] NOT NULL,
        CONSTRAINT [PK_Team] PRIMARY KEY CLUSTERED ([Id] ASC)
    ) ON [PRIMARY];
    PRINT '  - Table [dbo].[Team] créée.';
END
ELSE
    PRINT '  - Table [dbo].[Team] déjà existante.';
GO
EXEC #EnsureTableDescription N'Team', N'Equipe';
GO
INSERT INTO [dbo].[Team] ([Code], [CanViewAll])
SELECT v.[Code], v.[CanViewAll]
FROM (VALUES ('H620', CAST(1 AS bit)),
             ('H600', CAST(1 AS bit)),
             ('H500', CAST(1 AS bit))) v ([Code], [CanViewAll])
WHERE NOT EXISTS (SELECT 1 FROM [dbo].[Team] t WHERE t.[Code] = v.[Code]);
PRINT '  - Équipes de référence insérées : ' + CAST(@@ROWCOUNT AS varchar(10));
GO
PRINT '=== FIN DE LA MIGRATION [dbo].[Team] ===';
GO


/* =====================================================================
   2. [dbo].[User]
   ===================================================================== */
PRINT '=== DÉBUT DE LA MIGRATION [dbo].[User] ===';
IF OBJECT_ID(N'[dbo].[User]', N'U') IS NULL
BEGIN
    CREATE TABLE [dbo].[User](
        [Id]        [int] IDENTITY(1, 1) NOT NULL,
        [Lastname]  [nvarchar](max) NOT NULL,
        [Firstname] [nvarchar](max) NOT NULL,
        [PersoId]   [nvarchar](8) NOT NULL,
        [Email]     [nvarchar](max) NULL,
        [Gender]    [bit] NULL,
        [TeamId]    [bigint] NOT NULL,
        [IsAdmin]   [bit] NOT NULL,
        CONSTRAINT [PK_User] PRIMARY KEY CLUSTERED ([Id] ASC)
    ) ON [PRIMARY] TEXTIMAGE_ON [PRIMARY];
    PRINT '  - Table [dbo].[User] créée.';
END
ELSE
    PRINT '  - Table [dbo].[User] déjà existante.';
GO
EXEC #EnsureTableDescription N'User', N'Utilisateur de l''OCR STUDIO';
GO
IF NOT EXISTS (
    SELECT 1 FROM sys.indexes
    WHERE object_id = OBJECT_ID(N'[dbo].[User]') AND name = N'UQ_User_PersoId'
)
BEGIN
    ALTER TABLE [dbo].[User] ADD CONSTRAINT [UQ_User_PersoId] UNIQUE NONCLUSTERED ([PersoId] ASC);
    PRINT '  - Contrainte d''unicité [UQ_User_PersoId] ajoutée.';
END
ELSE
    PRINT '  - Contrainte d''unicité [UQ_User_PersoId] déjà présente.';
GO
PRINT '=== FIN DE LA MIGRATION [dbo].[User] ===';
GO


/* =====================================================================
   3. [dbo].[Project]
   ===================================================================== */
PRINT '=== DÉBUT DE LA MIGRATION [dbo].[Project] ===';
IF OBJECT_ID(N'[dbo].[Project]', N'U') IS NULL
BEGIN
    -- Pas de DEFAULT inline : il créerait une contrainte au nom auto-généré.
    -- Les defaults sont posés plus bas avec un nom fixe.
    CREATE TABLE [dbo].[Project](
        [Id]          [int] IDENTITY(1, 1) NOT NULL,
        [Name]        [nvarchar](max) NOT NULL,
        [ProjectType] [nvarchar](max) NULL,
        [Description] [nvarchar](max) NULL,
        [IsActive]    [bit] NOT NULL,
        [CreatedAt]   [datetime2](7) NOT NULL,
        [CreatedBy]   [nvarchar](max) NULL,
        [UpdatedBy]   [nvarchar](max) NULL,
        CONSTRAINT [PK_Project] PRIMARY KEY CLUSTERED ([Id] ASC)
    ) ON [PRIMARY] TEXTIMAGE_ON [PRIMARY];
    PRINT '  - Table [dbo].[Project] créée.';
END
ELSE
    PRINT '  - Table [dbo].[Project] déjà existante.';
GO
IF COL_LENGTH(N'dbo.Project', N'UpdatedBy') IS NULL
BEGIN
    ALTER TABLE [dbo].[Project] ADD [UpdatedBy] [nvarchar](max) NULL;
    PRINT '  - Colonne [UpdatedBy] ajoutée.';
END
GO
EXEC #EnsureDefault N'Project', N'IsActive',  N'DF_Project_IsActive',  N'(1)';
EXEC #EnsureDefault N'Project', N'CreatedAt', N'DF_Project_CreatedAt', N'(getdate())';
EXEC #EnsureTableDescription N'Project', N'Projets (Entité principale)';
GO
PRINT '=== FIN DE LA MIGRATION [dbo].[Project] ===';
GO


/* =====================================================================
   4. [dbo].[Project_History]
   ===================================================================== */
PRINT '=== DÉBUT DE LA MIGRATION [dbo].[Project_History] ===';
IF OBJECT_ID(N'[dbo].[Project_History]', N'U') IS NULL
BEGIN
    CREATE TABLE [dbo].[Project_History](
        [Id]         [uniqueidentifier] NOT NULL,
        [ProjectId]  [int] NOT NULL,
        [Entity]     [varchar](25) NOT NULL,
        [EntityId]   [int] NULL,
        [Action]     [varchar](10) NOT NULL,
        [EntityName] [varchar](25) NOT NULL,
        [Message]    [nvarchar](max) NULL,
        [OldValues]  [nvarchar](max) NULL,
        [NewValues]  [nvarchar](max) NULL,
        [UpdatedBy]  [int] NULL,
        [UpdatedAt]  [datetime2](7) NOT NULL,
        CONSTRAINT [PK_Project_History] PRIMARY KEY CLUSTERED ([Id] ASC)
    ) ON [PRIMARY] TEXTIMAGE_ON [PRIMARY];
    PRINT '  - Table [dbo].[Project_History] créée.';
END
ELSE
    PRINT '  - Table [dbo].[Project_History] déjà existante.';
GO
-- 4.1 Ancien schéma (v1) : [EntityName] contenait le type d'entité -> renommé en [Entity]
IF COL_LENGTH(N'dbo.Project_History', N'Entity') IS NULL
   AND COL_LENGTH(N'dbo.Project_History', N'EntityName') IS NOT NULL
BEGIN
    EXEC sys.sp_rename N'dbo.Project_History.EntityName', N'Entity', N'COLUMN';
    PRINT '  - Colonne [EntityName] renommée en [Entity].';
END
-- 4.2 Nouvelle colonne [EntityName] (libellé affiché), ajoutée nullable puis alimentée
IF COL_LENGTH(N'dbo.Project_History', N'EntityName') IS NULL
BEGIN
    ALTER TABLE [dbo].[Project_History] ADD [EntityName] [varchar](25) NULL;
    PRINT '  - Colonne [EntityName] ajoutée.';
END
GO
-- Batch séparé : la colonne [EntityName] existe forcément à la compilation
UPDATE [dbo].[Project_History]
SET [EntityName] = CASE [Entity]
                       WHEN 'Project'         THEN 'Projet'
                       WHEN 'Project_Version' THEN 'Version'
                       WHEN 'Project_Member'  THEN 'Utilisateur'
                       ELSE LEFT([Entity], 25)
                   END
WHERE [EntityName] IS NULL;

IF EXISTS (
    SELECT 1 FROM sys.columns
    WHERE object_id = OBJECT_ID(N'[dbo].[Project_History]')
      AND name = N'EntityName'
      AND (is_nullable = 1 OR TYPE_NAME(system_type_id) <> N'varchar' OR max_length <> 25)
)
BEGIN
    ALTER TABLE [dbo].[Project_History] ALTER COLUMN [EntityName] [varchar](25) NOT NULL;
    PRINT '  - Colonne [EntityName] alignée en varchar(25) NOT NULL.';
END
GO
-- 4.3 Defaults
EXEC #EnsureDefault N'Project_History', N'Id',        N'DF_Project_History_Id',        N'(newid())';
EXEC #EnsureDefault N'Project_History', N'UpdatedAt', N'DF_Project_History_UpdatedAt', N'(getdate())';
GO
-- 4.4 Pas de FK vers [Project] sur une table d'historique : le trigger AFTER DELETE
--     de [Project] y insère une ligne pour un projet qui n'existe plus, et les lignes
--     d'historique existantes empêcheraient toute suppression de projet.
DECLARE @sql nvarchar(max) = N'';
SELECT @sql += N'ALTER TABLE [dbo].[Project_History] DROP CONSTRAINT ' + QUOTENAME(name) + N';'
FROM sys.foreign_keys
WHERE parent_object_id = OBJECT_ID(N'[dbo].[Project_History]')
  AND referenced_object_id = OBJECT_ID(N'[dbo].[Project]');
IF @sql <> N''
BEGIN
    EXEC sys.sp_executesql @sql;
    PRINT '  - FK [Project_History] -> [Project] supprimée.';
END
GO
-- 4.5 FK vers User
EXEC #EnsureForeignKey N'Project_History', N'UpdatedBy', N'User', N'Id', N'FK_ProjectHistory_User';
GO
-- 4.6 Check constraints
EXEC #EnsureCheck N'Project_History', N'CHK_ProjectHistory_Action',
     N'[Action]=''DELETE'' OR [Action]=''UPDATE'' OR [Action]=''INSERT''';
EXEC #EnsureCheck N'Project_History', N'CHK_ProjectHistory_Delete_NewValues',
     N'NOT ([Action]=''DELETE'' AND [NewValues] IS NOT NULL)';
EXEC #EnsureCheck N'Project_History', N'CHK_ProjectHistory_Insert_OldValues',
     N'NOT ([Action]=''INSERT'' AND [OldValues] IS NOT NULL)';
EXEC #EnsureCheck N'Project_History', N'CHK_ProjectHistory_Update_Values',
     N'NOT ([Action]=''UPDATE'' AND ([OldValues] IS NULL OR [NewValues] IS NULL))';
EXEC #EnsureCheck N'Project_History', N'CHK_ProjectHistory_NewValues_JSON',
     N'ISJSON([NewValues])=(1) OR [NewValues] IS NULL';
EXEC #EnsureCheck N'Project_History', N'CHK_ProjectHistory_OldValues_JSON',
     N'ISJSON([OldValues])=(1) OR [OldValues] IS NULL';
EXEC #EnsureTableDescription N'Project_History', N'Histoire des modifications des projets';
GO
PRINT '=== FIN DE LA MIGRATION [dbo].[Project_History] ===';
GO


/* =====================================================================
   5. [dbo].[Project_Version]
   ===================================================================== */
PRINT '=== DÉBUT DE LA MIGRATION [dbo].[Project_Version] ===';
IF OBJECT_ID(N'[dbo].[Project_Version]', N'U') IS NULL
BEGIN
    CREATE TABLE [dbo].[Project_Version](
        [Id]                    [int] IDENTITY(1, 1) NOT NULL,
        [ProjectId]             [int] NOT NULL,
        [VersionNumber]         [int] NOT NULL,
        [Description]           [nvarchar](max) NULL,
        [ConfigLLMPath]         [nvarchar](max) NULL,
        [SdaConfigPath]         [nvarchar](max) NULL,
        [CreatedAt]             [datetime2](7) NULL,
        [CreatedBy]             [nvarchar](max) NULL,
        [UpdatedBy]             [nvarchar](max) NULL,
        [Title]                 [nvarchar](50) NULL,
        [DeliveredToProduction] [bit] NOT NULL,
        [State]                 [nvarchar](max) NOT NULL,
        CONSTRAINT [PK_Project_Version] PRIMARY KEY CLUSTERED ([Id] ASC)
    ) ON [PRIMARY] TEXTIMAGE_ON [PRIMARY];
    PRINT '  - Table [dbo].[Project_Version] créée.';
END
ELSE
    PRINT '  - Table [dbo].[Project_Version] déjà existante.';
GO
-- 5.1 Colonnes manquantes (le DEFAULT nommé remplit les lignes existantes)
IF COL_LENGTH(N'dbo.Project_Version', N'State') IS NULL
BEGIN
    ALTER TABLE [dbo].[Project_Version]
        ADD [State] [nvarchar](max) NOT NULL
        CONSTRAINT [DF_ProjectVersion_State] DEFAULT ('ONGOING');
    PRINT '  - Colonne [State] ajoutée.';
END
IF COL_LENGTH(N'dbo.Project_Version', N'DeliveredToProduction') IS NULL
BEGIN
    ALTER TABLE [dbo].[Project_Version]
        ADD [DeliveredToProduction] [bit] NOT NULL
        CONSTRAINT [DF_ProjectVersion_DeliveredToProduction] DEFAULT ((0));
    PRINT '  - Colonne [DeliveredToProduction] ajoutée.';
END
GO
-- 5.2 [CreatedAt] : datetime -> datetime2(7)
IF EXISTS (
    SELECT 1 FROM sys.columns
    WHERE object_id = OBJECT_ID(N'[dbo].[Project_Version]')
      AND name = N'CreatedAt' AND TYPE_NAME(system_type_id) = N'datetime'
)
BEGIN
    ALTER TABLE [dbo].[Project_Version] ALTER COLUMN [CreatedAt] [datetime2](7) NULL;
    PRINT '  - Colonne [CreatedAt] convertie en datetime2(7).';
END
GO
-- 5.3 [DeliveredToProduction] : correction d'une éventuelle création en nvarchar(max)
IF EXISTS (
    SELECT 1 FROM sys.columns
    WHERE object_id = OBJECT_ID(N'[dbo].[Project_Version]')
      AND name = N'DeliveredToProduction' AND TYPE_NAME(system_type_id) <> N'bit'
)
BEGIN
    IF EXISTS (SELECT 1 FROM [dbo].[Project_Version] WHERE TRY_CAST([DeliveredToProduction] AS bit) IS NULL)
    BEGIN
        RAISERROR(N'[Project_Version].[DeliveredToProduction] contient des valeurs non convertibles en bit.', 16, 1);
        RETURN;
    END
    EXEC #DropColumnDependencies N'Project_Version', N'DeliveredToProduction';
    ALTER TABLE [dbo].[Project_Version] ALTER COLUMN [DeliveredToProduction] [bit] NOT NULL;
    PRINT '  - Colonne [DeliveredToProduction] convertie en bit.';
END
GO
-- 5.4 [ProjectId] NOT NULL (uniquement si nécessaire : un ALTER COLUMN sur une
--     colonne portant une FK échoue, il faut d'abord retirer la FK)
IF EXISTS (
    SELECT 1 FROM sys.columns
    WHERE object_id = OBJECT_ID(N'[dbo].[Project_Version]')
      AND name = N'ProjectId' AND is_nullable = 1
)
BEGIN
    IF EXISTS (SELECT 1 FROM [dbo].[Project_Version] WHERE [ProjectId] IS NULL)
    BEGIN
        RAISERROR(N'[Project_Version].[ProjectId] contient des valeurs NULL. Impossible de la passer en NOT NULL.', 16, 1);
        RETURN;
    END
    EXEC #DropColumnDependencies N'Project_Version', N'ProjectId';
    ALTER TABLE [dbo].[Project_Version] ALTER COLUMN [ProjectId] [int] NOT NULL;
    PRINT '  - Colonne [ProjectId] passée en NOT NULL.';
END
GO
-- 5.5 Defaults + FK (renomme FK_Project_ProjectVersion si elle existe encore)
EXEC #EnsureDefault N'Project_Version', N'State',                 N'DF_ProjectVersion_State',                 N'(''ONGOING'')';
EXEC #EnsureDefault N'Project_Version', N'DeliveredToProduction', N'DF_ProjectVersion_DeliveredToProduction', N'((0))';
EXEC #EnsureForeignKey N'Project_Version', N'ProjectId', N'Project', N'Id', N'FK_ProjectVersion_Project';
GO
PRINT '=== FIN DE LA MIGRATION [dbo].[Project_Version] ===';
GO


/* =====================================================================
   6. [dbo].[Project_Member]
   ===================================================================== */
PRINT '=== DÉBUT DE LA MIGRATION [dbo].[Project_Member] ===';
IF OBJECT_ID(N'[dbo].[Project_Member]', N'U') IS NULL
BEGIN
    CREATE TABLE [dbo].[Project_Member](
        [UserId]    [int] NOT NULL,
        [ProjectId] [int] NOT NULL,
        [Role]      [nvarchar](20) NOT NULL,
        [UpdatedBy] [nvarchar](max) NULL,
        CONSTRAINT [PK_Project_Member] PRIMARY KEY CLUSTERED ([UserId] ASC, [ProjectId] ASC)
    ) ON [PRIMARY];
    PRINT '  - Table [dbo].[Project_Member] créée.';
END
ELSE
    PRINT '  - Table [dbo].[Project_Member] déjà existante.';
GO
-- 6.1 [UserId] : bigint -> int (la colonne est dans la PK et une FK : on les retire avant)
IF EXISTS (
    SELECT 1 FROM sys.columns
    WHERE object_id = OBJECT_ID(N'[dbo].[Project_Member]')
      AND name = N'UserId' AND TYPE_NAME(system_type_id) = N'bigint'
)
BEGIN
    IF EXISTS (SELECT 1 FROM [dbo].[Project_Member] WHERE [UserId] > 2147483647)
    BEGIN
        RAISERROR(N'[Project_Member].[UserId] contient des valeurs hors plage int.', 16, 1);
        RETURN;
    END
    EXEC #DropColumnDependencies N'Project_Member', N'UserId';

    DECLARE @sql nvarchar(max) = N'';
    SELECT @sql += N'ALTER TABLE [dbo].[Project_Member] DROP CONSTRAINT ' + QUOTENAME(name) + N';'
    FROM sys.key_constraints
    WHERE parent_object_id = OBJECT_ID(N'[dbo].[Project_Member]') AND type = 'PK';
    IF @sql <> N'' EXEC sys.sp_executesql @sql;

    ALTER TABLE [dbo].[Project_Member] ALTER COLUMN [UserId] [int] NOT NULL;
    PRINT '  - Colonne [UserId] convertie en int.';
END
GO
IF NOT EXISTS (
    SELECT 1 FROM sys.key_constraints
    WHERE parent_object_id = OBJECT_ID(N'[dbo].[Project_Member]') AND type = 'PK'
)
BEGIN
    ALTER TABLE [dbo].[Project_Member]
        ADD CONSTRAINT [PK_Project_Member] PRIMARY KEY CLUSTERED ([UserId] ASC, [ProjectId] ASC);
    PRINT '  - Clé primaire [PK_Project_Member] recréée.';
END
GO
-- 6.2 [UpdatedBy] : ajout, ou correction si créée en nvarchar(1) par l'ancien script
IF COL_LENGTH(N'dbo.Project_Member', N'UpdatedBy') IS NULL
BEGIN
    ALTER TABLE [dbo].[Project_Member] ADD [UpdatedBy] [nvarchar](max) NULL;
    PRINT '  - Colonne [UpdatedBy] ajoutée.';
END
ELSE IF COL_LENGTH(N'dbo.Project_Member', N'UpdatedBy') <> -1
BEGIN
    ALTER TABLE [dbo].[Project_Member] ALTER COLUMN [UpdatedBy] [nvarchar](max) NULL;
    PRINT '  - Colonne [UpdatedBy] élargie en nvarchar(max).';
END
GO
-- 6.3 FK + description
EXEC #EnsureForeignKey N'Project_Member', N'ProjectId', N'Project', N'Id', N'FK_Project_Member_Project';
EXEC #EnsureForeignKey N'Project_Member', N'UserId',    N'User',    N'Id', N'FK_Project_Member_User';
EXEC #EnsureTableDescription N'Project_Member', N'Membres des projets';
GO
PRINT '=== FIN DE LA MIGRATION [dbo].[Project_Member] ===';
GO


/* =====================================================================
   7. [dbo].[Evaluation]
   ===================================================================== */
PRINT '=== DÉBUT DE LA MIGRATION [dbo].[Evaluation] ===';
IF OBJECT_ID(N'[dbo].[Evaluation]', N'U') IS NULL
BEGIN
    CREATE TABLE [dbo].[Evaluation](
        [Id]              [int] IDENTITY(1, 1) NOT NULL,
        [ProjectId]       [int] NOT NULL,
        [VersionNumber]   [int] NOT NULL,
        [Name]            [nvarchar](max) NULL,
        [Timestamp]       [datetime2](7) NULL,
        [EvalPath]        [nvarchar](max) NOT NULL,
        [GroundTruthFile] [nvarchar](max) NOT NULL,
        [PredictionFile]  [nvarchar](max) NOT NULL,
        [TriggeredBy]     [nvarchar](max) NULL,
        CONSTRAINT [PK_Evaluation] PRIMARY KEY CLUSTERED ([Id] ASC)
    ) ON [PRIMARY] TEXTIMAGE_ON [PRIMARY];
    PRINT '  - Table [dbo].[Evaluation] créée.';
END
ELSE
    PRINT '  - Table [dbo].[Evaluation] déjà existante.';
GO
IF EXISTS (
    SELECT 1 FROM sys.columns
    WHERE object_id = OBJECT_ID(N'[dbo].[Evaluation]')
      AND name = N'Timestamp' AND TYPE_NAME(system_type_id) = N'datetime'
)
BEGIN
    ALTER TABLE [dbo].[Evaluation] ALTER COLUMN [Timestamp] [datetime2](7) NULL;
    PRINT '  - Colonne [Timestamp] convertie en datetime2(7).';
END
GO
-- Renomme FK_Project_Evaluation en FK_Evaluation_Project si besoin
EXEC #EnsureForeignKey N'Evaluation', N'ProjectId', N'Project', N'Id', N'FK_Evaluation_Project';
GO
PRINT '=== FIN DE LA MIGRATION [dbo].[Evaluation] ===';
GO


/* =====================================================================
   8. TRIGGERS (CREATE OR ALTER : idempotent, pas de DROP nécessaire)
      Créés en dernier : toutes les tables/colonnes référencées existent.
   ===================================================================== */
PRINT '=== TRIGGERS ===';
GO
-- ---------------------------------------------------------------- Project
CREATE OR ALTER TRIGGER [dbo].[trg_Project_Delete]
ON [dbo].[Project]
AFTER DELETE
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @DeleterId int = TRY_CAST(CAST(SESSION_CONTEXT(N'DeleterId') AS nvarchar(50)) AS int);

    INSERT INTO [dbo].[Project_History] (
        Id, ProjectId, Entity, EntityId, Action, EntityName, Message, OldValues, NewValues, UpdatedBy, UpdatedAt
    )
    SELECT
        NEWID(),
        d.Id,
        'Project',
        d.Id,
        'DELETE',
        'Projet',
        'Le projet "' + d.Name + '" a été supprimé',
        (SELECT d.* FOR JSON PATH, WITHOUT_ARRAY_WRAPPER),
        NULL,
        u.Id,
        GETDATE()
    FROM deleted d
    LEFT JOIN [dbo].[User] u ON u.Id = @DeleterId;
END
GO
CREATE OR ALTER TRIGGER [dbo].[trg_Project_Insert]
ON [dbo].[Project]
AFTER INSERT
AS
BEGIN
    SET NOCOUNT ON;
    INSERT INTO [dbo].[Project_History] (
        Id, ProjectId, Entity, EntityId, Action, EntityName, Message, OldValues, NewValues, UpdatedBy, UpdatedAt
    )
    SELECT
        NEWID(),
        i.Id,
        'Project',
        i.Id,
        'INSERT',
        'Projet',
        'Le projet "' + i.Name + '" a été créé',
        NULL,
        (SELECT i.* FOR JSON PATH, WITHOUT_ARRAY_WRAPPER),
        u.Id,
        GETDATE()
    FROM inserted i
    LEFT JOIN [dbo].[User] u ON i.CreatedBy = u.PersoId;
END
GO
CREATE OR ALTER TRIGGER [dbo].[trg_Project_Update]
ON [dbo].[Project]
AFTER UPDATE
AS
BEGIN
    SET NOCOUNT ON;
    INSERT INTO [dbo].[Project_History] (
        Id, ProjectId, Entity, EntityId, Action, EntityName, Message, OldValues, NewValues, UpdatedBy, UpdatedAt
    )
    SELECT
        NEWID(),
        i.Id,
        'Project',
        i.Id,
        'UPDATE',
        'Projet',
        'Le projet "' + i.Name + '" a été modifié',
        (SELECT d.* FOR JSON PATH, WITHOUT_ARRAY_WRAPPER),
        (SELECT i.* FOR JSON PATH, WITHOUT_ARRAY_WRAPPER),
        u.Id,
        GETDATE()
    FROM inserted i
    JOIN deleted d ON i.Id = d.Id
    LEFT JOIN [dbo].[User] u ON i.UpdatedBy = u.PersoId;
END
GO
-- --------------------------------------------------------- Project_Member
CREATE OR ALTER TRIGGER [dbo].[trg_ProjectMember_Delete]
ON [dbo].[Project_Member]
AFTER DELETE
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @DeleterId int = TRY_CAST(CAST(SESSION_CONTEXT(N'DeleterId') AS nvarchar(50)) AS int);

    INSERT INTO [dbo].[Project_History] (
        Id, ProjectId, Entity, EntityId, Action, EntityName, Message, OldValues, NewValues, UpdatedBy, UpdatedAt
    )
    SELECT
        NEWID(),
        d.ProjectId,
        'Project_Member',
        NULL, -- Pas d'ID unique dans Project_Member (clé composite)
        'DELETE',
        'Utilisateur',
        'L''utilisateur ' + ISNULL(u.Firstname + ' ' + u.Lastname, 'inconnu')
            + ' a été retiré (rôle: "'
            + CASE d.Role WHEN 'VIEWER' THEN 'lecteur' WHEN 'EDITOR' THEN 'éditeur' ELSE d.Role END
            + '")',
        (SELECT d.* FOR JSON PATH, WITHOUT_ARRAY_WRAPPER),
        NULL,
        deleter.Id,
        GETDATE()
    FROM deleted d
    LEFT JOIN [dbo].[User] u ON d.UserId = u.Id
    LEFT JOIN [dbo].[User] deleter ON deleter.Id = @DeleterId;
END
GO
CREATE OR ALTER TRIGGER [dbo].[trg_ProjectMember_Insert]
ON [dbo].[Project_Member]
AFTER INSERT
AS
BEGIN
    SET NOCOUNT ON;
    INSERT INTO [dbo].[Project_History] (
        Id, ProjectId, Entity, EntityId, Action, EntityName, Message, OldValues, NewValues, UpdatedBy, UpdatedAt
    )
    SELECT
        NEWID(),
        i.ProjectId,
        'Project_Member',
        NULL,
        'INSERT',
        'Utilisateur',
        'L''utilisateur ' + ISNULL(u.Firstname + ' ' + u.Lastname, 'inconnu')
            + ' a été ajouté avec le rôle "'
            + CASE i.Role WHEN 'VIEWER' THEN 'lecteur' WHEN 'EDITOR' THEN 'éditeur' ELSE i.Role END
            + '"',
        NULL,
        (SELECT i.* FOR JSON PATH, WITHOUT_ARRAY_WRAPPER),
        updater.Id,
        GETDATE()
    FROM inserted i
    LEFT JOIN [dbo].[User] u ON i.UserId = u.Id
    LEFT JOIN [dbo].[User] updater ON i.UpdatedBy = updater.PersoId;
END
GO
CREATE OR ALTER TRIGGER [dbo].[trg_ProjectMember_Update]
ON [dbo].[Project_Member]
AFTER UPDATE
AS
BEGIN
    SET NOCOUNT ON;
    INSERT INTO [dbo].[Project_History] (
        Id, ProjectId, Entity, EntityId, Action, EntityName, Message, OldValues, NewValues, UpdatedBy, UpdatedAt
    )
    SELECT
        NEWID(),
        i.ProjectId,
        'Project_Member',
        NULL,
        'UPDATE',
        'Utilisateur',
        'Le rôle de l''utilisateur ' + ISNULL(u.Firstname + ' ' + u.Lastname, 'inconnu')
            + ' a été modifié de "'
            + CASE d.Role WHEN 'VIEWER' THEN 'lecteur' WHEN 'EDITOR' THEN 'éditeur' ELSE d.Role END
            + '" à "'
            + CASE i.Role WHEN 'VIEWER' THEN 'lecteur' WHEN 'EDITOR' THEN 'éditeur' ELSE i.Role END
            + '"',
        (SELECT d.* FOR JSON PATH, WITHOUT_ARRAY_WRAPPER),
        (SELECT i.* FOR JSON PATH, WITHOUT_ARRAY_WRAPPER),
        updater.Id,
        GETDATE()
    FROM inserted i
    JOIN deleted d ON i.ProjectId = d.ProjectId AND i.UserId = d.UserId
    LEFT JOIN [dbo].[User] u ON i.UserId = u.Id
    LEFT JOIN [dbo].[User] updater ON i.UpdatedBy = updater.PersoId;
END
GO
-- -------------------------------------------------------- Project_Version
CREATE OR ALTER TRIGGER [dbo].[trg_ProjectVersion_Delete]
ON [dbo].[Project_Version]
AFTER DELETE
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @DeleterId int = TRY_CAST(CAST(SESSION_CONTEXT(N'DeleterId') AS nvarchar(50)) AS int);

    INSERT INTO [dbo].[Project_History] (
        Id, ProjectId, Entity, EntityId, Action, EntityName, Message, OldValues, NewValues, UpdatedBy, UpdatedAt
    )
    SELECT
        NEWID(),
        d.ProjectId,
        'Project_Version',
        d.Id,
        'DELETE',
        'Version',
        'La version "' + ISNULL(d.Title, 'Sans titre') + '" (v' + CAST(d.VersionNumber AS nvarchar(10)) + ') a été supprimée',
        (SELECT d.* FOR JSON PATH, WITHOUT_ARRAY_WRAPPER),
        NULL,
        u.Id,
        GETDATE()
    FROM deleted d
    LEFT JOIN [dbo].[User] u ON u.Id = @DeleterId;
END
GO
CREATE OR ALTER TRIGGER [dbo].[trg_ProjectVersion_Insert]
ON [dbo].[Project_Version]
AFTER INSERT
AS
BEGIN
    SET NOCOUNT ON;
    INSERT INTO [dbo].[Project_History] (
        Id, ProjectId, Entity, EntityId, Action, EntityName, Message, OldValues, NewValues, UpdatedBy, UpdatedAt
    )
    SELECT
        NEWID(),
        i.ProjectId,
        'Project_Version',
        i.Id,
        'INSERT',
        'Version',
        'La version "' + ISNULL(i.Title, 'Sans titre') + '" (v' + CAST(i.VersionNumber AS nvarchar(10)) + ') a été créée',
        NULL,
        (SELECT i.* FOR JSON PATH, WITHOUT_ARRAY_WRAPPER),
        u.Id,
        GETDATE()
    FROM inserted i
    LEFT JOIN [dbo].[User] u ON i.CreatedBy = u.PersoId;
END
GO
CREATE OR ALTER TRIGGER [dbo].[trg_ProjectVersion_Update]
ON [dbo].[Project_Version]
AFTER UPDATE
AS
BEGIN
    SET NOCOUNT ON;

    -- 1. Une seule version en production par projet : on déflague les autres
    UPDATE pv
    SET [DeliveredToProduction] = 0
    FROM [dbo].[Project_Version] pv
    JOIN inserted i ON pv.ProjectId = i.ProjectId AND pv.Id <> i.Id
    WHERE i.DeliveredToProduction = 1
      AND pv.DeliveredToProduction = 1;

    -- 2. Historique
    INSERT INTO [dbo].[Project_History] (
        Id, ProjectId, Entity, EntityId, Action, EntityName, Message, OldValues, NewValues, UpdatedBy, UpdatedAt
    )
    SELECT
        NEWID(),
        i.ProjectId,
        'Project_Version',
        i.Id,
        'UPDATE',
        'Version',
        'La version "' + ISNULL(i.Title, 'Sans titre') + '" (v' + CAST(i.VersionNumber AS nvarchar(10)) + ') '
        + CASE
              WHEN i.DeliveredToProduction = 1 AND d.DeliveredToProduction = 0 THEN 'a été flaguée en production'
              WHEN i.DeliveredToProduction = 0 AND d.DeliveredToProduction = 1 THEN 'a été déflaguée en production'
              WHEN i.State <> d.State THEN
                  CASE
                      WHEN i.State = 'BLOCKED'                           THEN 'a été verrouillée'
                      WHEN i.State = 'ARCHIVED'                          THEN 'a été archivée'
                      WHEN i.State = 'ONGOING' AND d.State = 'BLOCKED'   THEN 'a été déverrouillée'
                      WHEN i.State = 'ONGOING' AND d.State = 'ARCHIVED'  THEN 'a été désarchivée'
                      ELSE 'a changé d''état : ' + i.State
                  END
              ELSE 'a été modifiée'
          END,
        (SELECT d.* FOR JSON PATH, WITHOUT_ARRAY_WRAPPER),
        (SELECT i.* FOR JSON PATH, WITHOUT_ARRAY_WRAPPER),
        u.Id,
        GETDATE()
    FROM inserted i
    JOIN deleted d ON i.Id = d.Id
    LEFT JOIN [dbo].[User] u ON i.UpdatedBy = u.PersoId;
END
GO
PRINT '=== FIN DES TRIGGERS ===';
GO


/* =====================================================================
   9. NETTOYAGE
   ===================================================================== */
DROP PROCEDURE #EnsureDefault;
DROP PROCEDURE #EnsureForeignKey;
DROP PROCEDURE #EnsureCheck;
DROP PROCEDURE #EnsureTableDescription;
DROP PROCEDURE #DropColumnDependencies;
GO
PRINT '=== MIGRATION TERMINÉE ===';
GO
