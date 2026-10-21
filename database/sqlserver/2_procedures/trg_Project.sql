SET ANSI_NULLS ON
SET QUOTED_IDENTIFIER ON
SET NOCOUNT ON
GO
-- =======================================================
-- TRIGGERS [dbo].[Project] (BATCH SÉPARÉS)
-- [RÉORGANISATION] déplacés depuis le script de table : ils écrivent dans
-- [Project_History] et lisent [User], qui doivent être migrées avant.
-- =======================================================
-- --- TRIGGER DELETE ---
PRINT 'Gestion du trigger [trg_Project_Delete]...';
GO
-- 3.1 Suppression du Trigger existant si besoin (Batch 1)
IF OBJECT_ID(N'[dbo].[trg_Project_Delete]', 'TR') IS NOT NULL
BEGIN
DROP TRIGGER [dbo].[trg_Project_Delete];
PRINT 'Trigger [trg_Project_Delete] supprimé (mise à jour nécessaire).';
END
GO
-- 3.2 Création du Trigger (Batch 2) - DOIT ÊTRE SEUL DANS LE BATCH
CREATE TRIGGER [dbo].[trg_Project_Delete]
ON [dbo].[Project]
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
LEFT JOIN [dbo].[User] u ON @DeleterId = u.Id;

END
GO
-- --- TRIGGER INSERT ---
PRINT 'Gestion du trigger [trg_Project_Insert]...';
GO
-- 3.1 Suppression
IF OBJECT_ID(N'[dbo].[trg_Project_Insert]', 'TR') IS NOT NULL
BEGIN
DROP TRIGGER [dbo].[trg_Project_Insert];
PRINT 'Trigger [trg_Project_Insert] supprimé (mise à jour nécessaire).';
END
GO
-- 3.2 Création
CREATE TRIGGER [dbo].[trg_Project_Insert]
ON [dbo].[Project]
AFTER INSERT
AS
BEGIN
SET NOCOUNT ON;
INSERT INTO Project_History (
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
-- --- TRIGGER UPDATE ---
PRINT 'Gestion du trigger [trg_Project_Update]...';
GO
-- 3.1 Suppression
IF OBJECT_ID(N'[dbo].[trg_Project_Update]', 'TR') IS NOT NULL
BEGIN
DROP TRIGGER [dbo].[trg_Project_Update];
PRINT 'Trigger [trg_Project_Update] supprimé (mise à jour nécessaire).';
END
GO
-- 3.2 Création
CREATE TRIGGER [dbo].[trg_Project_Update]
ON [dbo].[Project]
AFTER UPDATE
AS
BEGIN
SET NOCOUNT ON;
INSERT INTO Project_History (
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
