SET ANSI_NULLS ON
SET QUOTED_IDENTIFIER ON
SET NOCOUNT ON
GO
-- =======================================================
-- TRIGGERS [dbo].[Project_Version] (BATCH SÉPARÉS)
-- [RÉORGANISATION] déplacés depuis le script de table : ils écrivent dans
-- [Project_History] et lisent [User], qui doivent être migrées avant.
-- =======================================================
-- --- TRIGGER DELETE ---
PRINT 'Gestion du trigger [trg_ProjectVersion_Delete]...';
GO
IF OBJECT_ID(N'[dbo].[trg_ProjectVersion_Delete]', 'TR') IS NOT NULL
BEGIN
DROP TRIGGER [dbo].[trg_ProjectVersion_Delete];
PRINT 'Trigger [trg_ProjectVersion_Delete] supprimé (mise à jour nécessaire).';
END
GO
CREATE TRIGGER [dbo].[trg_ProjectVersion_Delete]
ON [dbo].[Project_Version]
AFTER DELETE
AS
BEGIN
SET NOCOUNT ON;
DECLARE @DeleterId NVARCHAR(MAX) = CAST(SESSION_CONTEXT(N'DeleterId') AS NVARCHAR(MAX));
INSERT INTO Project_History (
   Id, ProjectId, Entity, EntityId, Action, EntityName, Message, OldValues, NewValues, UpdatedBy, UpdatedAt
)
SELECT
    NEWID(),
    d.ProjectId,
    'Project_Version',
    d.Id,
    'DELETE',
    'Version',
    'La version "' + ISNULL(d.Title, 'Sans titre') + '" (v' + CAST(d.VersionNumber AS NVARCHAR(10)) + ') a été supprimée',
    (SELECT d.* FOR JSON PATH, WITHOUT_ARRAY_WRAPPER),
    NULL,
    u.Id,
    GETDATE()
FROM deleted d
LEFT JOIN [dbo].[User] u ON @DeleterId = u.Id;

END
GO
-- --- TRIGGER INSERT ---
PRINT 'Gestion du trigger [trg_ProjectVersion_Insert]...';
GO
IF OBJECT_ID(N'[dbo].[trg_ProjectVersion_Insert]', 'TR') IS NOT NULL
BEGIN
DROP TRIGGER [dbo].[trg_ProjectVersion_Insert];
PRINT 'Trigger [trg_ProjectVersion_Insert] supprimé (mise à jour nécessaire).';
END
GO
CREATE TRIGGER [dbo].[trg_ProjectVersion_Insert]
ON [dbo].[Project_Version]
AFTER INSERT
AS
BEGIN
SET NOCOUNT ON;
INSERT INTO Project_History (
Id, ProjectId, Entity, EntityId, Action, EntityName, Message, OldValues, NewValues, UpdatedBy, UpdatedAt
)
SELECT
NEWID(),
i.ProjectId,
'Project_Version',
i.Id,
'INSERT',
'Version',
'La version "' + ISNULL(i.Title, 'Sans titre') + '" (v' + CAST(i.VersionNumber AS NVARCHAR(10)) + ') a été créée',
NULL,
(SELECT i.* FOR JSON PATH, WITHOUT_ARRAY_WRAPPER),
u.Id,
GETDATE()
FROM inserted i
LEFT JOIN [dbo].[User] u ON i.CreatedBy = u.PersoId;
END
GO
-- --- TRIGGER UPDATE ---
PRINT 'Gestion du trigger [trg_ProjectVersion_Update]...';
GO
IF OBJECT_ID(N'[dbo].[trg_ProjectVersion_Update]', 'TR') IS NOT NULL
BEGIN
DROP TRIGGER [dbo].[trg_ProjectVersion_Update];
PRINT 'Trigger [trg_ProjectVersion_Update] supprimé (mise à jour nécessaire).';
END
GO
CREATE TRIGGER [dbo].[trg_ProjectVersion_Update]
ON [dbo].[Project_Version]
AFTER UPDATE
AS
BEGIN
SET NOCOUNT ON;
-- 1. Désactiver les autres versions du projet si la version mise à jour est toppée en production
IF EXISTS (SELECT 1 FROM inserted i WHERE i.DeliveredToProduction = 1)
BEGIN
    UPDATE pv
    SET [DeliveredToProduction] = 0
    FROM [dbo].[Project_Version] pv
    JOIN inserted i ON pv.ProjectId = i.ProjectId
    WHERE pv.Id <> i.Id;
END

-- 2. Historique
INSERT INTO Project_History (
    Id, ProjectId, Entity, EntityId, Action, EntityName, Message, OldValues, NewValues, UpdatedBy, UpdatedAt
)
SELECT
    NEWID(),
    i.ProjectId,
    'Project_Version',
    i.Id,
    'UPDATE',
    'Version',
    CASE
        -- Cas 1 : DeliveredToProduction passe à 1 (ou TRUE)
        WHEN i.DeliveredToProduction = 1 AND (d.DeliveredToProduction = 0 OR d.DeliveredToProduction IS NULL)
            THEN 'La version "' + ISNULL(i.Title, 'Sans titre') + '" (v' + CAST(i.VersionNumber AS NVARCHAR(10)) + ') a été flaguée en production'
        -- Cas 1 : DeliveredToProduction passe à 1 (ou TRUE)
        WHEN i.DeliveredToProduction = 0 AND (d.DeliveredToProduction = 1)
            THEN 'La version "' + ISNULL(i.Title, 'Sans titre') + '" (v' + CAST(i.VersionNumber AS NVARCHAR(10)) + ') a été déflaguée en production'

        -- Cas 2 : State a changé
        WHEN i.State <> d.State OR (i.State IS NULL AND d.State IS NOT NULL) OR (i.State IS NOT NULL AND d.State IS NULL)
            THEN
                CASE
                    WHEN i.State = 'BLOCKED' AND d.State <> 'BLOCKED'
                        THEN 'La version "' + ISNULL(i.Title, 'Sans titre') + '" (v' + CAST(i.VersionNumber AS NVARCHAR(10)) + ') a été verrouillée'
                    WHEN i.State = 'ARCHIVED' AND d.State <> 'ARCHIVED'
                        THEN 'La version "' + ISNULL(i.Title, 'Sans titre') + '" (v' + CAST(i.VersionNumber AS NVARCHAR(10)) + ') a été archivée**'
                    WHEN i.State = 'ONGOING' AND d.State = 'BLOCKED'
                        THEN 'La version "' + ISNULL(i.Title, 'Sans titre') + '" (v' + CAST(i.VersionNumber AS NVARCHAR(10)) + ') a été déverrouillée'
                    WHEN i.State = 'ONGOING' AND d.State = 'ARCHIVED'
                        THEN 'La version "' + ISNULL(i.Title, 'Sans titre') + '" (v' + CAST(i.VersionNumber AS NVARCHAR(10)) + ') a été désarchivée'
                    ELSE 'La version "' + ISNULL(i.Title, 'Sans titre') + '" (v' + CAST(i.VersionNumber AS NVARCHAR(10)) + ') a changé d''état : ' + ISNULL(i.State, 'NULL') + ''
                END

        -- Cas par défaut (autres modifications)
        ELSE 'La version "' + ISNULL(i.Title, 'Sans titre') + '" (v' + CAST(i.VersionNumber AS NVARCHAR(10)) + ') a été modifiée'
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
