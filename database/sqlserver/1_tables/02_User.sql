SET ANSI_NULLS ON
SET QUOTED_IDENTIFIER ON
SET NOCOUNT ON
GO
PRINT '=== DÉBUT DE LA MIGRATION [dbo].[User] ==='
GO
-- =======================================================
-- 1. CRÉATION DE LA TABLE (Si elle n'existe pas)
-- =======================================================
IF NOT EXISTS (
SELECT
*
FROM
sys.objects
WHERE
object_id = OBJECT_ID(N'[dbo].[User]')
AND type in (N'U')
) BEGIN
PRINT 'Création de la table [dbo].[User]...';
CREATE TABLE [dbo].[User](
    [Id] [int] IDENTITY(1, 1) NOT NULL,
    [Lastname] [nvarchar](max) NOT NULL,
    [Firstname] [nvarchar](max) NOT NULL,
    [PersoId] [nvarchar](8) NOT NULL,
    [Email] [nvarchar](max) NULL,
    [Gender] [bit] NULL,
    [TeamId] [bigint] NOT NULL,
    [IsAdmin] [bit] NOT NULL,
    CONSTRAINT [PK_User] PRIMARY KEY CLUSTERED ([Id] ASC) WITH (
        PAD_INDEX = OFF,
        STATISTICS_NORECOMPUTE = OFF,
        IGNORE_DUP_KEY = OFF,
        ALLOW_ROW_LOCKS = ON,
        ALLOW_PAGE_LOCKS = ON,
        OPTIMIZE_FOR_SEQUENTIAL_KEY = OFF
    ) ON [PRIMARY]
) ON [PRIMARY] TEXTIMAGE_ON [PRIMARY];

 IF NOT EXISTS (
 SELECT 1
 FROM sys.extended_properties
 WHERE major_id = OBJECT_ID(N'[dbo].[User]')
 AND minor_id = 0
 AND name = N'MS_Description'

)
BEGIN
-- Propriété Description
EXEC sys.sp_addextendedproperty
@name = N'MS_Description',
@value = N'Utilisateur de l''OCR STUDIO',
@level0type = N'SCHEMA',
@level0name = N'dbo',
@level1type = N'TABLE',
@level1name = N'User';
END
PRINT 'Table [dbo].[User] créée avec succès.';

END
ELSE BEGIN
PRINT 'La table [dbo].[User] existe déjà. Aucune action requise.';
END
GO
-- =======================================================
-- 2. AJOUT DE CONTRAINTES (Si la table existe déjà)
-- =======================================================
PRINT 'Vérification et application des contraintes...'
GO
IF EXISTS (
SELECT 1 FROM sys.tables WHERE name = N'User' AND schema_id = SCHEMA_ID('dbo')
) BEGIN
---- 2.1. Ajout de la contrainte par défaut pour [IsAdmin]
--IF NOT EXISTS (
--    SELECT 1
--    FROM sys.default_constraints
--    WHERE parent_object_id = OBJECT_ID(N'[dbo].[User]')
--      AND name = 'DF_User_IsAdmin'
--) BEGIN
--    PRINT 'Ajout de la contrainte par défaut (IsAdmin = 0)...';
--    ALTER TABLE [dbo].[User] ADD CONSTRAINT [DF_User_IsAdmin] DEFAULT ((0)) FOR [IsAdmin];
--    PRINT 'Contrainte [DF_User_IsAdmin] ajoutée.';
--END
--ELSE BEGIN
--    PRINT 'Contrainte par défaut [DF_User_IsAdmin] existante.';
--END

-- 2.2. Ajout de la contrainte d'unicité sur PersoId
IF NOT EXISTS (
    SELECT 1
    FROM sys.indexes
    WHERE object_id = OBJECT_ID(N'[dbo].[User]')
      AND name = 'UQ_User_PersoId'
) BEGIN
    PRINT 'Ajout de la contrainte d''unicité (PersoId)...';
    ALTER TABLE [dbo].[User]
    ADD CONSTRAINT [UQ_User_PersoId] UNIQUE NONCLUSTERED ([PersoId] ASC);
    PRINT 'Contrainte d''unicité [UQ_User_PersoId] ajoutée.';
END
ELSE BEGIN
    PRINT 'Contrainte d''unicité [UQ_User_PersoId] existante.';
END

END
GO
PRINT '=== FIN DE LA MIGRATION [dbo].[User] ==='
GO
