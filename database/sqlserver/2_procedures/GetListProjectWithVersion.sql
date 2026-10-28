SET ANSI_NULLS ON
SET QUOTED_IDENTIFIER ON
GO
-- [CORRECTIF] CREATE OR ALTER au lieu de DROP + CREATE : idempotent et conserve les droits
--             (GRANT EXECUTE) accordés sur la procédure, qu'un DROP supprimerait.
CREATE OR ALTER PROCEDURE [dbo].[GetListProjectWithVersion]
 -- ==========================================================================================================================
    -- Author        : KHAUVCE
    -- Create date   : 24/07/2026
    -- Description   : Récupérer la liste des projets avec les infos des utilisateurs (Créateur, Membre, Updater)
    -- ==========================================================================================================================
    @PersoId nvarchar(8), -- [CORRECTIF] même type que [User].[PersoId]
    -- [FUSION ML] la table Project contient désormais aussi les modèles entraînés.
    -- Défaut 'LLM' : les appels existants (@PersoId seul) renvoient exactement la même
    -- liste qu'avant. 'MODEL' = modèles entraînés, NULL = toutes les catégories.
    @Category varchar(10) = 'LLM'
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @UserId INT = NULL;
    DECLARE @UserTeamId BIGINT = NULL; -- [CORRECTIF] [User].[TeamId] / [Team].[Id] sont en bigint
    DECLARE @CanViewAll BIT = 0;

    BEGIN TRY
        BEGIN TRANSACTION;

        -- Récupération de l'utilisateur actuel et de son équipe
        SELECT @UserId = [Id], @UserTeamId = [TeamId] 
        FROM [dbo].[User] 
        WHERE [PersoId] = @PersoId;

        -- [CORRECTIF] dans un TRY, RAISERROR (sévérité 16) passe directement au CATCH :
        --             le ROLLBACK et le RETURN -1 qui suivaient n'étaient jamais exécutés.
        --             Le CATCH s'en charge (rollback, renvoi de l'erreur, RETURN -1).
        IF @UserId IS NULL
        BEGIN
            RAISERROR('Utilisateur introuvable', 16, 1);
        END

        -- Récupération des permissions de l'équipe de l'utilisateur
        SELECT @CanViewAll = [CanViewAll] 
        FROM [dbo].[Team] 
        WHERE [Id] = @UserTeamId;

        -- ==========================================================================================================================
        -- Récupération des projets
        -- ==========================================================================================================================
        SELECT
    [p].[Id] AS [ProjectId],
    [p].[Name] AS [ProjectName],
    [p].[Description],
    [p].[ProjectType],
    [p].[Category],  -- [FUSION ML]
    [p].[CreatedAt],
    [p].[CreatedBy],
    [u_creator].[Lastname] AS [CreatorName],
    [u_creator].[Firstname] AS [CreatorFirstname],
    [u_creator].[Gender] AS [CreatorGender],
    [u_creator].[Email] AS [CreatorEmail],
    [t_creator].[Code] AS [CreatorTeam],

    -- 1. Liste complète des membres du projet regroupée en JSON
    (
        SELECT
            [pm].[Role] AS [UserProjectRole],
            [u_member].[Id] AS [MemberId],
            [u_member].[Lastname] AS [MemberName],
            [u_member].[Firstname] AS [MemberFirstname],
            [u_member].[Email] AS [MemberEmail],
            [u_member].[PersoId] AS [MemberPersoId]
        FROM [dbo].[Project_Member] [pm]
        INNER JOIN [dbo].[User] [u_member] ON [pm].[UserId] = [u_member].[Id]
        WHERE [pm].[ProjectId] = [p].[Id]
        FOR JSON PATH, INCLUDE_NULL_VALUES
    ) AS [Members],

    -- 2. Liste complète des versions regroupée en JSON
    (
        SELECT
            [v].[ProjectId] AS [VersionProjectId],
            [v].[Title] AS [VersionTitle],
            [v].[Description] AS [VersionDescription],
            [v].[ConfigLLMPath],
            [v].[SdaConfigPath],
            [v].[VersionNumber],
            [v].[CreatedBy] AS [VersionCreatedBy],
            [v].[UpdatedBy] AS [VersionUpdatedBy],
            [v].[State],
            [v].[DeliveredToProduction],
            [u_version].[Lastname] AS [VersionUpdatedByName],
            [u_version].[Firstname] AS [VersionUpdatedByFirstname],
            [u_version].[Gender] AS [VersionUpdatedByGender],
            [u_version].[Email] AS [VersionUpdatedByEmail]
        FROM [dbo].[Project_Version] [v]
        LEFT JOIN [dbo].[User] [u_version] ON [v].[UpdatedBy] = [u_version].[PersoId]
        WHERE [v].[ProjectId] = [p].[Id]
        FOR JSON PATH, INCLUDE_NULL_VALUES 
    ) AS [Versions]

FROM [dbo].[Project] [p]
LEFT JOIN [dbo].[User] [u_creator] ON [p].[CreatedBy] = [u_creator].[PersoId]
LEFT JOIN [dbo].[Team] [t_creator] ON [u_creator].[TeamId] = [t_creator].[Id]
WHERE
    ((@CanViewAll = 1) OR
    ([u_creator].[TeamId] = @UserTeamId) OR
    EXISTS (
        SELECT 1 
        FROM [dbo].[Project_Member] [pm_check] 
        WHERE [pm_check].[ProjectId] = [p].[Id] AND [pm_check].[UserId] = @UserId
    )) AND [p].[IsActive] = 1
    AND (@Category IS NULL OR [p].[Category] = @Category) -- [FUSION ML]
ORDER BY [p].[Name];

        COMMIT TRANSACTION;
        RETURN 0;

    END TRY
    BEGIN CATCH
        -- Annuler la transaction en cas d'erreur
        IF @@TRANCOUNT > 0
            ROLLBACK TRANSACTION;

        DECLARE @ErrorMessage NVARCHAR(4000) = ERROR_MESSAGE();
        DECLARE @ErrorSeverity INT = ERROR_SEVERITY();
        DECLARE @ErrorState INT = ERROR_STATE();

        -- [CORRECTIF] message passé en paramètre : un '%' dans le message ne casse plus le RAISERROR
        RAISERROR('%s', @ErrorSeverity, @ErrorState, @ErrorMessage);
        RETURN -1;
    END CATCH
END


