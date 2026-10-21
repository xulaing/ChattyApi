SET ANSI_NULLS ON
SET QUOTED_IDENTIFIER ON
SET NOCOUNT ON
GO
PRINT '=== DÉBUT DE LA MIGRATION [dbo].[Project_Member] ==='
GO
-- =======================================================
-- 1. CRÉATION DE LA TABLE (Si elle n'existe pas)
-- =======================================================
IF NOT EXISTS (
SELECT 1
FROM sys.tables
WHERE object_id = OBJECT_ID(N'[dbo].[Project_Member]')
)
BEGIN
PRINT 'Début de la création de la table [dbo].[Project_Member]...';
CREATE TABLE [dbo].[Project_Member](
    [UserId] [int] NOT NULL,
    [ProjectId] [int] NOT NULL,
    [Role] [nvarchar](20) NOT NULL,
    [UpdatedBy] [nvarchar](max) NULL,
    CONSTRAINT [PK_Project_Member] PRIMARY KEY CLUSTERED
    (
        [UserId] ASC,
        [ProjectId] ASC
    ) WITH (
        PAD_INDEX = OFF,
        STATISTICS_NORECOMPUTE = OFF,
        IGNORE_DUP_KEY = OFF,
        ALLOW_ROW_LOCKS = ON,
        ALLOW_PAGE_LOCKS = ON,
        OPTIMIZE_FOR_SEQUENTIAL_KEY = OFF
    ) ON [PRIMARY]
) ON [PRIMARY];

-- Propriété Description
 IF NOT EXISTS (
    SELECT 1
    FROM sys.extended_properties
    WHERE major_id = OBJECT_ID(N'[dbo].[Project_Member]')
    AND minor_id = 0
    AND name = N'MS_Description'
)
BEGIN
EXEC sys.sp_addextendedproperty @name=N'MS_Description',
    @value=N'Membres des projets',
    @level0type=N'SCHEMA', @level0name=N'dbo',
    @level1type=N'TABLE', @level1name=N'Project_Member';

PRINT 'Table [dbo].[Project_Member] créée avec succès.';
END

END
GO
-- =======================================================
-- 2. CONVERSION DU TYPE [UserId] (bigint -> int)
--    Si la table existe déjà avec UserId bigint
-- =======================================================
IF EXISTS (
SELECT 1
FROM sys.tables
WHERE object_id = OBJECT_ID(N'[dbo].[Project_Member]')
)
BEGIN
DECLARE @UserIdType NVARCHAR(50);
SELECT @UserIdType = DATA_TYPE
FROM INFORMATION_SCHEMA.COLUMNS
WHERE TABLE_NAME = N'Project_Member'
AND COLUMN_NAME = N'UserId'
AND TABLE_SCHEMA = N'dbo';
IF @UserIdType = 'bigint' BEGIN
    PRINT 'Conversion du type [UserId] de bigint vers int...';
    -- [CORRECTIF] [UserId] fait partie de la PK (et éventuellement d'une FK) : l'ALTER COLUMN
    --             échoue tant qu'elles existent (erreur 5074). On les retire, on convertit,
    --             on recrée la PK. La FK vers [User] est recréée à l'étape 3.
    DECLARE @DropKeys NVARCHAR(MAX) = N'';
    SELECT @DropKeys += N'ALTER TABLE [dbo].[Project_Member] DROP CONSTRAINT ' + QUOTENAME(fk.name) + N';'
    FROM sys.foreign_keys fk
    JOIN sys.foreign_key_columns fkc ON fkc.constraint_object_id = fk.object_id
    WHERE fk.parent_object_id = OBJECT_ID(N'[dbo].[Project_Member]')
      AND fkc.parent_column_id = COLUMNPROPERTY(OBJECT_ID(N'[dbo].[Project_Member]'), 'UserId', 'ColumnId');
    SELECT @DropKeys += N'ALTER TABLE [dbo].[Project_Member] DROP CONSTRAINT ' + QUOTENAME(name) + N';'
    FROM sys.key_constraints
    WHERE parent_object_id = OBJECT_ID(N'[dbo].[Project_Member]') AND type = 'PK';
    IF @DropKeys <> N'' EXEC sys.sp_executesql @DropKeys;

    ALTER TABLE [dbo].[Project_Member] ALTER COLUMN [UserId] [int] NOT NULL;

    ALTER TABLE [dbo].[Project_Member] ADD CONSTRAINT [PK_Project_Member] PRIMARY KEY CLUSTERED
    (
        [UserId] ASC,
        [ProjectId] ASC
    );
    PRINT 'Type [UserId] modifié avec succès en int.';
END
ELSE IF @UserIdType = 'int' BEGIN
    PRINT 'La colonne [UserId] est déjà de type int.';
END
ELSE BEGIN
    PRINT 'Colonne [UserId] a un type inattendu : ' + @UserIdType;
END

END
GO
-- =======================================================
-- 3. CONTRAINTES ÉTRANGÈRES (si la table existe)
-- =======================================================
IF EXISTS (
SELECT 1
FROM sys.tables
WHERE object_id = OBJECT_ID(N'[dbo].[Project_Member]')
)
BEGIN
-- FK Project
IF NOT EXISTS (
SELECT 1
FROM sys.foreign_keys
WHERE name = 'FK_Project_Member_Project'
AND parent_object_id = OBJECT_ID('dbo.Project_Member')
) BEGIN
ALTER TABLE [dbo].[Project_Member]  WITH CHECK ADD CONSTRAINT [FK_Project_Member_Project]
FOREIGN KEY([ProjectId]) REFERENCES [dbo].[Project] ([Id]);
PRINT 'Contrainte étrangère [FK_Project_Member_Project] ajoutée avec succès.';
END
ELSE BEGIN
PRINT 'Contrainte étrangère [FK_Project_Member_Project] existe déjà.';
END
ALTER TABLE [dbo].[Project_Member] CHECK CONSTRAINT [FK_Project_Member_Project];

-- FK User
IF NOT EXISTS (
    SELECT 1
    FROM sys.foreign_keys
    WHERE name = 'FK_Project_Member_User'
    AND parent_object_id = OBJECT_ID('dbo.Project_Member')
) BEGIN
    ALTER TABLE [dbo].[Project_Member]  WITH CHECK ADD CONSTRAINT [FK_Project_Member_User]
        FOREIGN KEY([UserId]) REFERENCES [dbo].[User] ([Id]);
    PRINT 'Contrainte étrangère [FK_Project_Member_User] ajoutée avec succès.';
END
ELSE BEGIN
    PRINT 'Contrainte étrangère [FK_Project_Member_User] existe déjà.';
END

ALTER TABLE [dbo].[Project_Member] CHECK CONSTRAINT [FK_Project_Member_User];

END
GO
-- =======================================================
-- 4. MODIFICATIONS DE STRUCTURE (Colonne UpdatedBy)
-- =======================================================
PRINT 'Vérification de la colonne [UpdatedBy]...'
GO
-- [CORRECTIF] nvarchar(max) au lieu de "nvarchar" (= nvarchar(1)), comme dans le CREATE TABLE.
--             Si la colonne a déjà été créée en nvarchar(1), elle est élargie.
IF NOT EXISTS (
SELECT 1
FROM sys.columns
WHERE object_id = OBJECT_ID('[dbo].[Project_Member]')
AND name = 'UpdatedBy'
)
BEGIN
ALTER TABLE [dbo].[Project_Member]
ADD [UpdatedBy] nvarchar(max) NULL;
PRINT 'Colonne [UpdatedBy] ajoutée avec succès à [dbo].[Project_Member]';
END
ELSE IF COL_LENGTH(N'dbo.Project_Member', N'UpdatedBy') <> -1
BEGIN
ALTER TABLE [dbo].[Project_Member]
ALTER COLUMN [UpdatedBy] nvarchar(max) NULL;
PRINT 'Colonne [UpdatedBy] élargie en nvarchar(max).';
END
ELSE BEGIN
PRINT 'Colonne [UpdatedBy] déjà présente.';
END
GO
-- [RÉORGANISATION] Les triggers de [Project_Member] sont dans 2_procedures/trg_Project_Member.sql
PRINT '=== FIN DE LA MIGRATION [dbo].[Project_Member] ==='
GO
