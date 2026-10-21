SET ANSI_NULLS ON
SET QUOTED_IDENTIFIER ON
SET NOCOUNT ON
SET XACT_ABORT ON
GO
PRINT '=== DÉBUT DE LA MIGRATION [dbo].[Project_History] ==='
GO
-- =======================================================
-- 1. CRÉATION DE LA TABLE (Si elle n'existe pas)
-- =======================================================
IF NOT EXISTS (
SELECT 1
FROM sys.objects
WHERE object_id = OBJECT_ID(N'[dbo].[Project_History]')
AND type in (N'U')
)
BEGIN
PRINT 'Début de la création de la table [dbo].[Project_History]...';
BEGIN TRY
    BEGIN TRANSACTION;

    -- Création de la table
    CREATE TABLE [dbo].[Project_History](
        [Id] [uniqueidentifier] NOT NULL,
        [ProjectId] [int] NOT NULL,
        [Entity] [varchar](25) NOT NULL,
        [EntityId] [int] NULL,
        [Action] [varchar](10) NOT NULL,
        [EntityName] [varchar](25) NOT NULL,
        [Message] [nvarchar](max) NULL,
        [OldValues] [nvarchar](max) NULL,
        [NewValues] [nvarchar](max) NULL,
        [UpdatedBy] [int] NULL,
        [UpdatedAt] [datetime2](7) NOT NULL,
        CONSTRAINT [PK_Project_History] PRIMARY KEY CLUSTERED
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
    ) ON [PRIMARY] TEXTIMAGE_ON [PRIMARY];

    PRINT '  - Table créée.';

    -- On valide la transaction uniquement après la création
    -- Les contraintes seront ajoutées dans le batch suivant pour séparation propre
    COMMIT TRANSACTION;
    PRINT '  - Transaction commitée.';
END TRY

BEGIN CATCH
IF @@TRANCOUNT > 0
ROLLBACK TRANSACTION;
    -- Capture sécurisée des erreurs (Compatible SSDT)
    DECLARE @ErrorMessage NVARCHAR(4000);
    DECLARE @ErrorSeverity INT;
    DECLARE @ErrorState INT;
    DECLARE @ErrorNumber INT;
    DECLARE @ErrorProcedure NVARCHAR(128);

    -- Récupération dans des variables locales (Crucial pour la compatibilité)
    SELECT
        @ErrorMessage = ERROR_MESSAGE(),
        @ErrorSeverity = ERROR_SEVERITY(),
        @ErrorState = ERROR_STATE(),
        @ErrorNumber = ERROR_NUMBER(),
        @ErrorProcedure = ISNULL(ERROR_PROCEDURE(), 'N/A');

    PRINT 'ERREUR : Échec de la création de la table [dbo].[Project_History]';
    PRINT 'Message : ' + ISNULL(@ErrorMessage, 'Erreur inconnue');
    PRINT 'Numéro : ' + ISNULL(CAST(@ErrorNumber AS NVARCHAR(10)), 'N/A');
    PRINT 'Procédure : ' + ISNULL(@ErrorProcedure, 'N/A');

END CATCH

END
GO
-- =======================================================
-- 2. GESTION DES CONTRAINTES (Si la table existe)
-- =======================================================
IF EXISTS (
SELECT 1
FROM sys.objects
WHERE object_id = OBJECT_ID(N'[dbo].[Project_History]')
AND type in (N'U')
)
BEGIN
PRINT 'Vérification et application des contraintes sur [dbo].[Project_History]...';
-- [CORRECTIF] 2.1 / 2.2 : recherche du default par COLONNE et non par nom
--             (une colonne ne peut avoir qu'un seul default, sinon erreur 1781)
-- 2.1. Contrainte par défaut pour Id (NEWID)
IF NOT EXISTS (
    SELECT 1
    FROM sys.default_constraints
    WHERE parent_object_id = OBJECT_ID(N'[dbo].[Project_History]')
    AND parent_column_id = COLUMNPROPERTY(OBJECT_ID(N'[dbo].[Project_History]'), 'Id', 'ColumnId')
)
BEGIN
    ALTER TABLE [dbo].[Project_History]
    ADD CONSTRAINT [DF_Project_History_Id] DEFAULT (NEWID()) FOR [Id];
    PRINT '  - Contrainte DF_Project_History_Id ajoutée.';
END

-- 2.2. Contrainte par défaut pour UpdatedAt (GETDATE)
IF NOT EXISTS (
    SELECT 1
    FROM sys.default_constraints
    WHERE parent_object_id = OBJECT_ID(N'[dbo].[Project_History]')
    AND parent_column_id = COLUMNPROPERTY(OBJECT_ID(N'[dbo].[Project_History]'), 'UpdatedAt', 'ColumnId')
)
BEGIN
    ALTER TABLE [dbo].[Project_History]
    ADD CONSTRAINT [DF_Project_History_UpdatedAt] DEFAULT (GETDATE()) FOR [UpdatedAt];
    PRINT '  - Contrainte DF_Project_History_UpdatedAt ajoutée.';
END

-- 2.3. Clé étrangère vers User
IF NOT EXISTS (
    SELECT 1
    FROM sys.foreign_keys
    WHERE object_id = OBJECT_ID(N'[dbo].[FK_ProjectHistory_User]')
    AND parent_object_id = OBJECT_ID(N'[dbo].[Project_History]')
)
BEGIN
    ALTER TABLE [dbo].[Project_History] WITH CHECK ADD CONSTRAINT [FK_ProjectHistory_User]
        FOREIGN KEY([UpdatedBy]) REFERENCES [dbo].[User] ([Id]);
    ALTER TABLE [dbo].[Project_History] CHECK CONSTRAINT [FK_ProjectHistory_User];
    PRINT '  - Contrainte FK_ProjectHistory_User ajoutée.';
END

-- 2.4. Clé étrangère vers Project (Correction ajoutée pour cohérence)
IF NOT EXISTS (
    SELECT 1
    FROM sys.foreign_keys
    WHERE object_id = OBJECT_ID(N'[dbo].[FK_ProjectHistory_Project]')
    AND parent_object_id = OBJECT_ID(N'[dbo].[Project_History]')
)
BEGIN
    ALTER TABLE [dbo].[Project_History] WITH CHECK ADD CONSTRAINT [FK_ProjectHistory_Project]
        FOREIGN KEY([ProjectId]) REFERENCES [dbo].[Project] ([Id]);
    ALTER TABLE [dbo].[Project_History] CHECK CONSTRAINT [FK_ProjectHistory_Project];
    PRINT '  - Contrainte FK_ProjectHistory_Project ajoutée.';
END

-- 2.5. Check Constraints (Actions)
IF NOT EXISTS (
    SELECT 1
    FROM sys.check_constraints
    WHERE object_id = OBJECT_ID(N'[dbo].[CHK_ProjectHistory_Action]')
    AND parent_object_id = OBJECT_ID(N'[dbo].[Project_History]')
)
BEGIN
    ALTER TABLE [dbo].[Project_History] WITH CHECK ADD CONSTRAINT [CHK_ProjectHistory_Action]
        CHECK (([Action]='DELETE' OR [Action]='UPDATE' OR [Action]='INSERT'));
    ALTER TABLE [dbo].[Project_History] CHECK CONSTRAINT [CHK_ProjectHistory_Action];
    PRINT '  - Contrainte CHK_ProjectHistory_Action ajoutée.';
END

-- 2.6. Check Constraints (Logique Data)
IF NOT EXISTS (
    SELECT 1
    FROM sys.check_constraints
    WHERE object_id = OBJECT_ID(N'[dbo].[CHK_ProjectHistory_Delete_NewValues]')
    AND parent_object_id = OBJECT_ID(N'[dbo].[Project_History]')
)
BEGIN
    ALTER TABLE [dbo].[Project_History] WITH CHECK ADD CONSTRAINT [CHK_ProjectHistory_Delete_NewValues]
        CHECK ((NOT ([Action]='DELETE' AND [NewValues] IS NOT NULL)));
    ALTER TABLE [dbo].[Project_History] CHECK CONSTRAINT [CHK_ProjectHistory_Delete_NewValues];
    PRINT '  - Contrainte CHK_ProjectHistory_Delete_NewValues ajoutée.';
END

IF NOT EXISTS (
    SELECT 1
    FROM sys.check_constraints
    WHERE object_id = OBJECT_ID(N'[dbo].[CHK_ProjectHistory_Insert_OldValues]')
    AND parent_object_id = OBJECT_ID(N'[dbo].[Project_History]')
)
BEGIN
    ALTER TABLE [dbo].[Project_History] WITH CHECK ADD CONSTRAINT [CHK_ProjectHistory_Insert_OldValues]
        CHECK ((NOT ([Action]='INSERT' AND [OldValues] IS NOT NULL)));
    ALTER TABLE [dbo].[Project_History] CHECK CONSTRAINT [CHK_ProjectHistory_Insert_OldValues];
    PRINT '  - Contrainte CHK_ProjectHistory_Insert_OldValues ajoutée.';
END

IF NOT EXISTS (
    SELECT 1
    FROM sys.check_constraints
    WHERE object_id = OBJECT_ID(N'[dbo].[CHK_ProjectHistory_Update_Values]')
    AND parent_object_id = OBJECT_ID(N'[dbo].[Project_History]')
)
BEGIN
    ALTER TABLE [dbo].[Project_History] WITH CHECK ADD CONSTRAINT [CHK_ProjectHistory_Update_Values]
        CHECK ((NOT ([Action]='UPDATE' AND ([OldValues] IS NULL OR [NewValues] IS NULL))));
    ALTER TABLE [dbo].[Project_History] CHECK CONSTRAINT [CHK_ProjectHistory_Update_Values];
    PRINT '  - Contrainte CHK_ProjectHistory_Update_Values ajoutée.';
END

-- 2.7. Check Constraints (JSON Validation)
IF NOT EXISTS (
    SELECT 1
    FROM sys.check_constraints
    WHERE object_id = OBJECT_ID(N'[dbo].[CHK_ProjectHistory_NewValues_JSON]')
    AND parent_object_id = OBJECT_ID(N'[dbo].[Project_History]')
)
BEGIN
    ALTER TABLE [dbo].[Project_History] WITH CHECK ADD CONSTRAINT [CHK_ProjectHistory_NewValues_JSON]
        CHECK ((ISJSON([NewValues])=(1) OR [NewValues] IS NULL));
    ALTER TABLE [dbo].[Project_History] CHECK CONSTRAINT [CHK_ProjectHistory_NewValues_JSON];
    PRINT '  - Contrainte CHK_ProjectHistory_NewValues_JSON ajoutée.';
END

IF NOT EXISTS (
    SELECT 1
    FROM sys.check_constraints
    WHERE object_id = OBJECT_ID(N'[dbo].[CHK_ProjectHistory_OldValues_JSON]')
    AND parent_object_id = OBJECT_ID(N'[dbo].[Project_History]')
)
BEGIN
    ALTER TABLE [dbo].[Project_History] WITH CHECK ADD CONSTRAINT [CHK_ProjectHistory_OldValues_JSON]
        CHECK ((ISJSON([OldValues])=(1) OR [OldValues] IS NULL));
    ALTER TABLE [dbo].[Project_History] CHECK CONSTRAINT [CHK_ProjectHistory_OldValues_JSON];
    PRINT '  - Contrainte CHK_ProjectHistory_OldValues_JSON ajoutée.';
END

-- 2.8. Description de la table
IF NOT EXISTS (
    SELECT 1
    FROM sys.extended_properties
    WHERE major_id = OBJECT_ID(N'[dbo].[Project_History]')
    AND minor_id = 0
    AND name = N'MS_Description'
)
BEGIN
    EXEC sys.sp_addextendedproperty
        @name=N'MS_Description',
        @value=N'Histoire des modifications des projets',
        @level0type=N'SCHEMA', @level0name=N'dbo',
        @level1type=N'TABLE', @level1name=N'Project_History';
    PRINT '  - Description de table ajoutée.';
END

IF EXISTS (SELECT * FROM sys.columns WHERE object_id = OBJECT_ID('dbo.Project_History') AND name = 'EntityName')

AND NOT EXISTS (SELECT * FROM sys.columns WHERE object_id = OBJECT_ID('dbo.Project_History') AND name = 'Entity')
BEGIN
EXEC sp_rename '[dbo].[Project_History].[EntityName]', 'Entity', 'COLUMN';
END
IF EXISTS (SELECT * FROM sys.columns WHERE object_id = OBJECT_ID('dbo.Project_History') AND name = 'Entity')
AND NOT EXISTS (SELECT * FROM sys.columns WHERE object_id = OBJECT_ID('dbo.Project_History') AND name = 'EntityName')
BEGIN
-- Vérifier si le type est déjà nvarchar
DECLARE @currentType NVARCHAR(100);
SELECT @currentType = TYPE_NAME(user_type_id)
FROM sys.columns
WHERE object_id = OBJECT_ID('dbo.Project_History') AND name = 'Entity';
IF @currentType <> 'nvarchar'
BEGIN
    ALTER TABLE [dbo].[Project_History] ADD [EntityName] [nvarchar](25) NULL;
END

END
PRINT 'Table [dbo].[Project_History] vérifiée et mise à jour.';

END
GO
PRINT '=== FIN DE LA MIGRATION [dbo].[Project_History] ==='
GO
