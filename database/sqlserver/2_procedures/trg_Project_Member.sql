SET ANSI_NULLS ON
SET QUOTED_IDENTIFIER ON
SET NOCOUNT ON
GO
-- =======================================================
-- TRIGGERS [dbo].[Project_Member] (BATCH SÉPARÉS)
-- [RÉORGANISATION] déplacés depuis le script de table : ils écrivent dans
-- [Project_History] et lisent [User], qui doivent être migrées avant.
-- =======================================================
-- --- TRIGGER DELETE ---
PRINT 'Gestion du trigger [trg_ProjectMember_Delete]...';
GO
IF OBJECT_ID(N'[dbo].[trg_ProjectMember_Delete]', 'TR') IS NOT NULL
BEGIN
DROP TRIGGER [dbo].[trg_ProjectMember_Delete];
PRINT 'Trigger [trg_ProjectMember_Delete] supprimé (mise à jour nécessaire).';
END
GO
CREATE TRIGGER [dbo].[trg_ProjectMember_Delete]
ON [dbo].[Project_Member]
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
    'Project_Member',
    NULL,
    'DELETE',
    'Utilisateur',
    'L''utilisateur ' + ISNULL(u.Firstname + ' ' + u.Lastname, 'inconnu') +
    ' a été retiré (rôle: "' + CASE
    WHEN d.Role = 'VIEWER' THEN 'lecteur'
    WHEN d.Role = 'EDITOR' THEN 'éditeur'
    ELSE d.Role
END + '")',
    (SELECT d.* FOR JSON PATH, WITHOUT_ARRAY_WRAPPER),
    NULL,
    deleter.Id,
    GETDATE()
FROM deleted d
LEFT JOIN [dbo].[User] u ON d.UserId = u.Id
LEFT JOIN [dbo].[User] deleter ON @DeleterId = deleter.Id;

END
GO
-- --- TRIGGER INSERT ---
PRINT 'Gestion du trigger [trg_ProjectMember_Insert]...';
GO
IF OBJECT_ID(N'[dbo].[trg_ProjectMember_Insert]', 'TR') IS NOT NULL
BEGIN
DROP TRIGGER [dbo].[trg_ProjectMember_Insert];
PRINT 'Trigger [trg_ProjectMember_Insert] supprimé (mise à jour nécessaire).';
END
GO
CREATE TRIGGER [dbo].[trg_ProjectMember_Insert]
ON [dbo].[Project_Member]
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
'Project_Member',
NULL, -- Pas d'ID unique dans Project_Member (clé composite)
'INSERT',
'Utilisateur',
'L''utilisateur ' + ISNULL(u.Firstname + ' ' + u.Lastname, 'inconnu') +
' a été ajouté avec le rôle "' + CASE
WHEN i.Role = 'VIEWER' THEN 'lecteur'
WHEN i.Role = 'EDITOR' THEN 'éditeur'
ELSE i.Role
END + '"',
NULL,
(SELECT i.* FOR JSON PATH, WITHOUT_ARRAY_WRAPPER),
updater.Id,
GETDATE()
FROM inserted i
LEFT JOIN [dbo].[User] u ON i.UserId = u.Id
LEFT JOIN [dbo].[User] updater ON i.UpdatedBy = updater.PersoId;
END
GO
-- --- TRIGGER UPDATE ---
PRINT 'Gestion du trigger [trg_ProjectMember_Update]...';
GO
IF OBJECT_ID(N'[dbo].[trg_ProjectMember_Update]', 'TR') IS NOT NULL
BEGIN
DROP TRIGGER [dbo].[trg_ProjectMember_Update];
PRINT 'Trigger [trg_ProjectMember_Update] supprimé (mise à jour nécessaire).';
END
GO
CREATE TRIGGER [dbo].[trg_ProjectMember_Update]
ON [dbo].[Project_Member]
AFTER UPDATE
AS
BEGIN
SET NOCOUNT ON;
INSERT INTO Project_History (
     Id, ProjectId, Entity, EntityId, Action, EntityName, Message, OldValues, NewValues, UpdatedBy, UpdatedAt
)
SELECT
    NEWID(),
    i.ProjectId,
    'Project_Member',
    NULL,
    'UPDATE',
    'Utilisateur',
    'Le rôle de l''utilisateur ' + ISNULL(u.Firstname + ' ' + u.Lastname, 'inconnu') +
    ' a été modifié de "' + CASE
    WHEN d.Role = 'VIEWER' THEN 'lecteur'
    WHEN d.Role = 'EDITOR' THEN 'éditeur'
    ELSE d.Role
END + '" à "' + CASE
    WHEN i.Role = 'VIEWER' THEN 'lecteur'
    WHEN i.Role = 'EDITOR' THEN 'éditeur'
    ELSE i.Role
END + '"',
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
