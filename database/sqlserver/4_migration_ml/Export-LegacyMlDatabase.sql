/* =====================================================================
   EXPORT DE L'ANCIENNE BASE DES MODÈLES ENTRAÎNÉS (format lu par Convert-LegacyMlExport.ps1)

   À exécuter sur l'ANCIENNE base (lecture seule : aucun objet créé ni modifié).
   SSMS : Nouvelle requête sur l'ancienne base, exécuter (F5), puis enregistrer le
   contenu de l'onglet Messages dans un fichier .txt.

   Pour chaque table :
       --- Table : <nom>
       Nombre de lignes : <n>
       --- Résultat JSON :          (ou « Table vide : [] »)
       |<JSON en morceaux de 900 caractères, chaque ligne préfixée par |>

   Corrections par rapport à la requête d'origine :
   - [CORRECTIF] CAUSE PRINCIPALE des tables « sans ligne » : le client ODBC (sqlcmd,
     outils basés sur l'ODBC Driver) n'affiche pas un message PRINT qui commence par
     « [ » quand il est court (il le prend pour un préfixe [Microsoft][ODBC...]) ; il
     ajoute ce préfixe quand il est long. Le JSON d'une petite table, qui tient en un
     seul PRINT commençant par « [ », disparaissait donc. Chaque morceau est désormais
     préfixé par « | », retiré par Convert-LegacyMlExport.ps1 (ligne « Format » en tête).
   - [CORRECTIF] le client ODBC coupe aussi chaque message à 1024 caractères, préfixe
     [Microsoft][ODBC...] compris (≈ 970 caractères utiles) : des morceaux de 4000
     caractères perdaient leur fin et le JSON des grosses tables était incomplet.
     Morceaux de 900 caractères.
   - [CORRECTIF] @pos était déclaré DANS la boucle (DECLARE @pos INT = 1) et n'était
     pas remis à 1 d'une table à l'autre : après une table dont le JSON dépassait
     4000 caractères, le JSON des tables plus petites n'était pas affiché
     (« --- Résultat JSON : » suivi de rien, alors que la table n'est pas vide).
   - [CORRECTIF] FOR JSON échoue sur les types CLR (geography, geometry, hierarchyid)
     et l'erreur interrompait tout l'export : ces colonnes sont converties en texte,
     ainsi que xml, sql_variant, text, ntext et image.
   - [CORRECTIF] erreur sur une table : message « Erreur de génération du JSON »
     et passage à la table suivante (TRY / CATCH), au lieu d'arrêter l'export.
   - [CORRECTIF] tables hors du schéma dbo : nom qualifié par le schéma (sinon
     « Invalid object name » ou mauvaise table).
   - @jsonResult remis à NULL pour chaque table (aucun reste de la table précédente).
   ===================================================================== */
SET NOCOUNT ON;

DECLARE @schemaName sysname, @tableName sysname, @displayName nvarchar(300), @fullName nvarchar(300);
DECLARE @objectId int;
DECLARE @columns nvarchar(max);
DECLARE @query nvarchar(max);
DECLARE @jsonResult nvarchar(max);
DECLARE @rowCount bigint;
DECLARE @pos bigint;
DECLARE @len bigint;
DECLARE @chunk int = 900;    -- [CORRECTIF] ODBC coupe chaque message à 1024 caractères, préfixe ODBC compris

-- Lue par Convert-LegacyMlExport.ps1 : retire le | en tête de chaque ligne de JSON
PRINT N'Format : JSON préfixé par |';
PRINT N'';

DECLARE table_cursor CURSOR LOCAL FAST_FORWARD FOR
    SELECT s.name, t.name, t.object_id
    FROM sys.tables t
    JOIN sys.schemas s ON s.schema_id = t.schema_id
    WHERE t.is_ms_shipped = 0
    ORDER BY s.name, t.name;

OPEN table_cursor;
FETCH NEXT FROM table_cursor INTO @schemaName, @tableName, @objectId;

WHILE @@FETCH_STATUS = 0
BEGIN
    SET @fullName = QUOTENAME(@schemaName) + N'.' + QUOTENAME(@tableName);
    SET @displayName = CASE WHEN @schemaName = N'dbo' THEN @tableName ELSE @schemaName + N'.' + @tableName END;
    SET @jsonResult = NULL;
    SET @rowCount = NULL;

    PRINT N'--- Table : ' + @displayName;

    BEGIN TRY
        SET @query = N'SELECT @rowCount = COUNT_BIG(*) FROM ' + @fullName + N';';
        EXEC sys.sp_executesql @query, N'@rowCount bigint OUTPUT', @rowCount = @rowCount OUTPUT;
        PRINT N'Nombre de lignes : ' + CAST(@rowCount AS nvarchar(20));

        IF @rowCount = 0
        BEGIN
            PRINT N'Table vide : []';
        END
        ELSE
        BEGIN
            -- Liste des colonnes, avec conversion des types que FOR JSON ne sait pas sérialiser
            SELECT @columns = STRING_AGG(CONVERT(nvarchar(max),
                       CASE
                           WHEN c.system_type_id = 240                                    -- CLR : geography, geometry, hierarchyid
                               THEN QUOTENAME(c.name) + N'.ToString() AS ' + QUOTENAME(c.name)
                           WHEN TYPE_NAME(c.system_type_id) IN (N'xml', N'ntext')
                               THEN N'CAST(' + QUOTENAME(c.name) + N' AS nvarchar(max)) AS ' + QUOTENAME(c.name)
                           WHEN TYPE_NAME(c.system_type_id) = N'text'
                               THEN N'CAST(' + QUOTENAME(c.name) + N' AS varchar(max)) AS ' + QUOTENAME(c.name)
                           WHEN TYPE_NAME(c.system_type_id) = N'image'
                               THEN N'CAST(' + QUOTENAME(c.name) + N' AS varbinary(max)) AS ' + QUOTENAME(c.name)
                           WHEN TYPE_NAME(c.system_type_id) = N'sql_variant'
                               THEN N'CAST(' + QUOTENAME(c.name) + N' AS nvarchar(4000)) AS ' + QUOTENAME(c.name)
                           ELSE QUOTENAME(c.name)
                       END), N', ') WITHIN GROUP (ORDER BY c.column_id)
            FROM sys.columns c
            WHERE c.object_id = @objectId;

            SET @query = N'SELECT @jsonResult = (SELECT ' + @columns + N' FROM ' + @fullName + N' FOR JSON PATH);';
            EXEC sys.sp_executesql @query, N'@jsonResult nvarchar(max) OUTPUT', @jsonResult = @jsonResult OUTPUT;

            IF @jsonResult IS NULL OR LEN(@jsonResult) = 0
            BEGIN
                PRINT N'Erreur de génération du JSON : résultat vide.';
            END
            ELSE
            BEGIN
                PRINT N'--- Résultat JSON :';
                SET @len = LEN(@jsonResult);
                SET @pos = 1;   -- [CORRECTIF] remis à 1 pour CHAQUE table
                WHILE @pos <= @len
                BEGIN
                    -- [CORRECTIF] préfixe | : un message qui commence par [ est masqué par ODBC
                    PRINT N'|' + SUBSTRING(@jsonResult, @pos, @chunk);
                    SET @pos = @pos + @chunk;
                END
            END
        END
    END TRY
    BEGIN CATCH
        IF @rowCount IS NULL PRINT N'Nombre de lignes : 0';
        PRINT N'Erreur de génération du JSON : ' + ERROR_MESSAGE();
    END CATCH

    PRINT N'';
    PRINT N'';
    FETCH NEXT FROM table_cursor INTO @schemaName, @tableName, @objectId;
END

CLOSE table_cursor;
DEALLOCATE table_cursor;
