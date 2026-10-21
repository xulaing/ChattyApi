SET ANSI_NULLS ON
SET QUOTED_IDENTIFIER ON
SET NOCOUNT ON
GO
-- =======================================================
-- INSÉRITION DES DONNÉES [dbo].[Team] (Idempotence)
-- [RÉORGANISATION] déplacé depuis le script de table [Team]
-- =======================================================
PRINT 'Vérification et insertion de l''équipe H620...'
GO
IF EXISTS (
SELECT 1 FROM sys.tables WHERE name = N'Team' AND schema_id = SCHEMA_ID('dbo')
) BEGIN
IF NOT EXISTS (
SELECT 1 FROM [dbo].[Team] WHERE [Code] = 'H620'
)
BEGIN
PRINT 'Équipe H620 manquante. Insertion...';
INSERT INTO [dbo].[Team] ([Code], [CanViewAll])
VALUES ('H620', 1);
PRINT 'Équipe H620 insérée avec succès.';
END
ELSE
BEGIN
PRINT 'Équipe H620 présente. Aucune modification de données requise.';
END
IF NOT EXISTS (
SELECT 1 FROM [dbo].[Team] WHERE [Code] = 'H600'
)
BEGIN
PRINT 'Équipe H600 manquante. Insertion...';
INSERT INTO [dbo].[Team] ([Code], [CanViewAll])
VALUES ('H600', 1);
PRINT 'Équipe H600 insérée avec succès.';
END
ELSE
BEGIN
PRINT 'Équipe H600 présente. Aucune modification de données requise.';
END
IF NOT EXISTS (
SELECT 1 FROM [dbo].[Team] WHERE [Code] = 'H500'
)
BEGIN
PRINT 'Équipe H500 manquante. Insertion...';
INSERT INTO [dbo].[Team] ([Code], [CanViewAll])
VALUES ('H500', 1);
PRINT 'Équipe H500 insérée avec succès.';
END
ELSE
BEGIN
PRINT 'Équipe H500 présente. Aucune modification de données requise.';
END
END
GO
