SET ANSI_NULLS ON
SET QUOTED_IDENTIFIER ON
SET NOCOUNT ON
GO
PRINT '=== DÉBUT DE LA MIGRATION [dbo].[Evaluation] ==='
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
object_id = OBJECT_ID(N'[dbo].[Evaluation]')
AND type in (N'U')
) BEGIN
PRINT 'Création de la table [dbo].[Evaluation]...';
CREATE TABLE [dbo].[Evaluation](
    [Id] [int] IDENTITY(1, 1) NOT NULL,
    [ProjectId] [int] NOT NULL,
    [VersionNumber] [int] NOT NULL,
    [Name] [nvarchar](max) NULL,
    [Timestamp] [datetime2](7) NULL,
    [EvalPath] [nvarchar](max) NOT NULL,
    [GroundTruthFile] [nvarchar](max) NOT NULL,
    [PredictionFile] [nvarchar](max) NOT NULL,
    [TriggeredBy] [nvarchar](max) NULL,
    CONSTRAINT [PK_Evaluation] PRIMARY KEY CLUSTERED ([Id] ASC) WITH (
        PAD_INDEX = OFF,
        STATISTICS_NORECOMPUTE = OFF,
        IGNORE_DUP_KEY = OFF,
        ALLOW_ROW_LOCKS = ON,
        ALLOW_PAGE_LOCKS = ON,
        OPTIMIZE_FOR_SEQUENTIAL_KEY = OFF
    ) ON [PRIMARY]
) ON [PRIMARY];

PRINT 'Table [dbo].[Evaluation] créée avec succès.';

END
GO
-- =======================================================
-- 2. AJOUT DE CONTRAINTES (Si la table existe déjà)
-- =======================================================
PRINT 'Vérification et application des contraintes...'
GO
IF EXISTS (
SELECT 1 FROM sys.tables WHERE name = N'Evaluation' AND schema_id = SCHEMA_ID('dbo')
) BEGIN
-- 2.2. Gestion de la Contrainte Étrangère (FK) - Renommage
PRINT 'Gestion de la contrainte étrangère [FK_Evaluation_Project]...';

-- 2.2.A Suppression de l'ancienne contrainte si elle existe
IF EXISTS (
    SELECT 1
    FROM sys.foreign_keys
    WHERE object_id = OBJECT_ID(N'[dbo].[FK_Project_Evaluation]')
      AND parent_object_id = OBJECT_ID(N'[dbo].[Evaluation]')
) BEGIN
    PRINT 'Suppression de l''ancienne contrainte FK_Project_Evaluation...';
    ALTER TABLE [dbo].[Evaluation] DROP CONSTRAINT [FK_Project_Evaluation];
    PRINT 'Ancienne contrainte supprimée.';
END


-- 2.2.B Création de la nouvelle contrainte avec le bon nom
IF NOT EXISTS (
    SELECT 1
    FROM sys.foreign_keys
    WHERE object_id = OBJECT_ID(N'[dbo].[FK_Evaluation_Project]')
      AND parent_object_id = OBJECT_ID(N'[dbo].[Evaluation]')
) BEGIN
    PRINT 'Création de la nouvelle contrainte FK_Evaluation_Project...';
    ALTER TABLE [dbo].[Evaluation] WITH CHECK
    ADD CONSTRAINT [FK_Evaluation_Project] FOREIGN KEY([ProjectId]) REFERENCES [dbo].[Project] ([Id]);

    ALTER TABLE [dbo].[Evaluation] CHECK CONSTRAINT [FK_Evaluation_Project];
    PRINT 'Nouvelle contrainte FK_Evaluation_Project créée et vérifiée.';
END
ELSE BEGIN
    PRINT 'Contrainte FK_Evaluation_Project existante.';
END


-- 2.3. Modification du type datetime vers datetime2
PRINT '=== ÉTAPE 3 : Modernisation du type de date [Timestamp] ==='

IF EXISTS (
    SELECT 1
    FROM sys.columns
    WHERE Name = N'Timestamp' AND Object_ID = OBJECT_ID(N'[dbo].[Evaluation]')
) BEGIN
    DECLARE @CurrentDataType NVARCHAR(50);
    SELECT @CurrentDataType = DATA_TYPE
    FROM INFORMATION_SCHEMA.COLUMNS
    WHERE TABLE_NAME = N'Evaluation'
      AND COLUMN_NAME = N'Timestamp'
      AND TABLE_SCHEMA = N'dbo';

    IF @CurrentDataType = 'datetime' BEGIN
        PRINT 'Conversion du type [Timestamp] de datetime vers datetime2(7)...';
        ALTER TABLE [dbo].[Evaluation] ALTER COLUMN [Timestamp] [datetime2](7) NULL;
        PRINT 'Type modifié avec succès.';
    END
    ELSE IF @CurrentDataType = 'datetime2' BEGIN
        PRINT 'La colonne [Timestamp] est déjà de type datetime2(7).';
    END
    ELSE BEGIN
        PRINT 'Colonne [Timestamp] a un type inattendu : ' + @CurrentDataType;
    END
END
ELSE BEGIN
    PRINT 'Colonne [Timestamp] non trouvée, aucune action.';
END

END
GO
PRINT '=== FIN DE LA MIGRATION [dbo].[Evaluation] ==='
GO
