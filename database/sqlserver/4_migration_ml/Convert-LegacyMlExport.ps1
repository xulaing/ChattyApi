<#
.SYNOPSIS
    Génère le script SQL Server de migration des données de l'ancienne base des
    modèles entraînés vers la base fusionnée (Project / Project_Version / Evaluation...).

.DESCRIPTION
    Lit l'export texte de l'ancienne base (une section par table) :

        --- Table : Model
        Nombre de lignes : 66
        --- Résultat JSON :
        [Microsoft][ODBC Driver 13 for SQL Server][SQL Server][{"IdModel":2,...},...]

    Pour chaque table, le script :
      1. reconstitue le JSON (l'export le coupe en lignes de ~2000 caractères, parfois
         au milieu d'un mot : les lignes sont recollées sans séparateur) ;
      2. compare le nombre de lignes annoncé au nombre d'éléments JSON et affiche le
         nom de la table quand ils ne correspondent pas ;
      3. écarte les logs IHM des tables d'inférence (Classification_Test, *_Test) :
         une ligne sans DocId n'est pas un résultat d'inférence ;
      4. écrit les lignes conservées dans le script SQL de sortie.

    Le script SQL généré :
      - charge les lignes dans une table temporaire, vérifie qu'elles sont toutes
        arrivées, puis migre toutes les tables dans UNE SEULE transaction : si une
        table échoue, rien n'est écrit ;
      - est rejouable : la table dbo.Migration_LegacyMap garde la correspondance
        (table source, ancien Id) -> nouvel Id ; une ligne déjà migrée n'est pas recopiée.

    Compatible Windows PowerShell 5.1 et PowerShell 7.

.PARAMETER InputFile
    Fichier texte de l'export de l'ancienne base.

.PARAMETER OutputFile
    Script SQL à générer. Par défaut : <InputFile>_migration.sql.

.PARAMETER InputEncoding
    Encodage du fichier d'entrée (Auto par défaut : UTF-8 si le fichier est de
    l'UTF-8 valide, sinon Windows-1252).

.PARAMETER TrainStatusMap
    Correspondance StatusTrain (ancienne base) -> code [Ref_RunStatus].
    Par défaut : 0 = RUNNING, 1 = SUCCEEDED, 2 = FAILED (À VALIDER).

.PARAMETER RowsPerBatch
    Nombre d'INSERT de chargement par batch (GO) dans le script généré.

.PARAMETER Strict
    Arrête sans générer de SQL si une table a un écart de nombre de lignes ou un
    JSON invalide. Recommandé pour la migration de production.

.EXAMPLE
    .\Convert-LegacyMlExport.ps1 -InputFile .\export_ancienne_base.txt -Strict
    Puis, dans SSMS : Nouvelle requête sur la base cible, ouvrir
    .\export_ancienne_base_migration.sql et l'exécuter (F5).
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$InputFile,

    [string]$OutputFile,

    [ValidateSet('Auto', 'UTF8', 'Windows1252', 'Unicode')]
    [string]$InputEncoding = 'Auto',

    [hashtable]$TrainStatusMap = @{ 0 = 'RUNNING'; 1 = 'SUCCEEDED'; 2 = 'FAILED' },

    [ValidateRange(1, 1000)]
    [int]$RowsPerBatch = 200,

    [switch]$Strict
)

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

# ---------------------------------------------------------------------------
# Catalogue des tables de l'ancienne base
# ---------------------------------------------------------------------------
# Tables migrées (le nom exact est utilisé par le script SQL pour la correspondance).
$MigratedTables = @(
    'Model',
    'Model_Version', 'ModelDecoupage_Version', 'ModelExtraction_Version', 'ModelDetection_Version', 'ModelSegmentation_Version',
    'Model_Version_Test', 'ModelDecoupage_Version_Test', 'ModelExtraction_Version_Test', 'ModelDetection_Version_Test', 'ModelSegmentation_Version_Test',
    'TrainTrack', 'ExtractionTrainTrack', 'DetectionTrainTrack', 'SegmentationTrainTrack',
    'Classification_Test', 'Decoupage_Test', 'Extraction_Test', 'Detection_Test', 'Segmentation_Test',
    'DocumentClass', 'DocumentField', 'DocumentProperty',
    'DocumentClassProjects', 'DocumentFieldProjects', 'DocumentPropertyProjects',
    'DocumentRequest'
)
# Tables d'inférence : contiennent aussi des logs IHM à écarter (ligne sans DocId).
$InferenceTables = @('Classification_Test', 'Decoupage_Test', 'Extraction_Test', 'Detection_Test', 'Segmentation_Test')
# Tables sans équivalent dans la nouvelle base : non migrées.
$IgnoredTables = @(
    'Logs_IHM', 'Parameters', 'Processor', 'PipelineTest',
    'PipelineInstance', 'PipelineModule', 'PipelineModuleParameter', 'PipelineStepInstance', 'PipelineParameterInstance'
)

# ---------------------------------------------------------------------------
# Colonnes reprises par le script SQL, par type de table.
# Une table vide dans cet environnement peut être remplie dans un autre : chaque
# colonne présente dans l'export mais absente de ces listes est signalée, car elle
# ne serait pas migrée. Les noms sont sensibles à la casse, comme OPENJSON.
# DOIT rester aligné avec les OPENJSON ... WITH du script SQL généré (plus bas).
#   Required : groupes de colonnes obligatoires ('A|B' = A ou B)
#   Known    : colonnes reprises
#   Skipped  : colonnes volontairement non reprises (redondantes)
# ---------------------------------------------------------------------------
# Colonnes de métriques -> code [Ref_Metric] (alimente aussi #MetricKey du script SQL)
$MetricKeys = [ordered]@{
    'Accuracy' = 'ACCURACY'; 'ErrorRate' = 'ERROR_RATE'; 'PrecisionScore' = 'PRECISION'; 'RecallScore' = 'RECALL'
    'f1_score' = 'F1'; 'kappa' = 'KAPPA'; 'AP_bbox' = 'AP_BBOX'; 'Recall_bbox' = 'RECALL_BBOX'
    'AP_segm' = 'AP_SEGM'; 'Recall_segm' = 'RECALL_SEGM'; 'MeanErrors' = 'MEAN_ERRORS'; 'NbErrors' = 'NB_ERRORS'
}
$VersionIds = @('IdModelVersion', 'IdModelExtractionVersion', 'IdModelDetectionVersion', 'IdModelSegmentationVersion', 'IdModelDecoupageVersion')
$ModelIds = @('IdModel', 'IdModelExtraction', 'IdModelDetection', 'IdModelSegmentation', 'IdModelDecoupage')
$TestIds = @('IdModelVersionTest', 'IdModelExtractionVersionTest', 'IdModelDetectionVersionTest', 'IdModelSegmentationVersionTest', 'IdModelDecoupageVersionTest')
$TrainIds = @('IdTrainTrack', 'IdExtractionTrainTrack', 'IdDetectionTrainTrack', 'IdSegmentationTrainTrack')
$InferenceIds = @('IdClassification', 'IdDecoupage', 'IdExtraction', 'IdDetection', 'IdSegmentation')
$Metrics = @($MetricKeys.Keys)

$KindSpecs = @{
    Model            = @{ Required = @('IdModel', 'Name')
                          Known    = @('IdModel', 'Name', 'ProjectType', 'Creator', 'DateCreate', 'AssociatedSolutionId'); Skipped = @() }
    Version          = @{ Required = @(($VersionIds -join '|'), ($ModelIds -join '|'), 'VersionNb')
                          Known    = $VersionIds + $ModelIds + @('VersionNb', 'DateCreate', 'Creator', 'TrainDataCount', 'ValidDataCount', 'TrainDataPath', 'ModelPath', 'AnnotationFile', 'InProd', 'IsITC', 'Algo', 'Comment') + $Metrics
                          Skipped  = @() }
    Test             = @{ Required = @(($TestIds -join '|'), ($VersionIds -join '|'), 'TestDataPath')
                          Known    = $TestIds + $VersionIds + @('VersionNb', 'DateCreate', 'Creator', 'TestDataCount', 'TestDataPath', 'TestResultsPath', 'AnnotationFile', 'IsITC', 'Comment') + $Metrics
                          Skipped  = @('Algo') }   # algorithme de la version testée : déjà porté par la version
    Train            = @{ Required = @(($TrainIds -join '|'), (($ModelIds | Where-Object { $_ -ne 'IdModelDecoupage' }) -join '|'), 'VersionNb', 'StatusTrain')
                          Known    = $TrainIds + $ModelIds + @('VersionNb', 'DateStart', 'DateEnd', 'StatusTrain', 'DatasetPath', 'AnnotationFile', 'ModelPath', 'Creator', 'CurrentStep', 'Step', 'Epoch', 'CurrentPhase', 'IsITC')
                          Skipped  = @() }
    Inference        = @{ Required = @(($InferenceIds -join '|'), 'DocId')
                          Known    = $InferenceIds + @('DocId', 'ResMessage', 'DateCreate', 'EndStatus'); Skipped = @() }
    DocumentClass    = @{ Required = @('IdClass|IdDocumentClass', 'NameClass|Name')
                          Known    = @('IdClass', 'IdDocumentClass', 'NameClass', 'Name', 'DescriptionClass', 'Description', 'CreatorClass', 'Creator', 'DateCreateClass', 'DateCreate', 'UpdaterClass', 'Updater', 'DateUpdateClass', 'DateUpdate'); Skipped = @() }
    DocumentField    = @{ Required = @('IdField|IdDocumentField', 'IdClass|IdDocumentClass', 'NameField|Name')
                          Known    = @('IdField', 'IdDocumentField', 'IdClass', 'IdDocumentClass', 'NameField', 'Name', 'DescriptionField', 'Description', 'CreatorField', 'Creator', 'DateCreateField', 'DateCreate', 'UpdaterField', 'Updater', 'DateUpdateField', 'DateUpdate'); Skipped = @() }
    DocumentProperty = @{ Required = @('IdProperty|IdDocumentProperty', 'NameProperty|Name')
                          Known    = @('IdProperty', 'IdDocumentProperty', 'NameProperty', 'Name', 'DescriptionProperty', 'Description', 'CreatorProperty', 'Creator', 'DateCreateProperty', 'DateCreate', 'UpdaterProperty', 'Updater', 'DateUpdateProperty', 'DateUpdate'); Skipped = @() }
    ClassAssoc       = @{ Required = @('IdClass|IdDocumentClass', 'IdModel', 'IdModelVersion')
                          Known    = @('IdClass', 'IdDocumentClass', 'IdModel', 'IdModelVersion'); Skipped = @('IdAssociation') }
    FieldAssoc       = @{ Required = @('IdField|IdDocumentField', 'IdModel', 'IdModelVersion')
                          Known    = @('IdField', 'IdDocumentField', 'IdModel', 'IdModelVersion'); Skipped = @('IdAssociation') }
    PropertyAssoc    = @{ Required = @('IdProperty|IdDocumentProperty', 'IdModel', 'IdModelVersion')
                          Known    = @('IdProperty', 'IdDocumentProperty', 'IdModel', 'IdModelVersion'); Skipped = @('IdAssociation') }
    DocumentRequest  = @{ Required = @('IdDocumentRequest', 'TypeDocumentRequest', 'NameDocumentRequest')
                          Known    = @('IdDocumentRequest', 'TypeDocumentRequest', 'NameDocumentRequest', 'DescriptionDocumentRequest', 'StatusDocumentRequest', 'CreatorDocumentRequest', 'DateCreateDocumentRequest', 'UpdaterDocumentRequest', 'DateUpdateDocumentRequest', 'CommentDocumentRequest', 'ResponseDocumentRequest'); Skipped = @() }
}

function Get-TableKind([string]$Name) {
    if ($Name -eq 'Model') { return 'Model' }
    if ($Name -like 'Model*_Version_Test') { return 'Test' }
    if ($Name -like 'Model*_Version') { return 'Version' }
    if ($Name -like '*TrainTrack') { return 'Train' }
    if ($InferenceTables -contains $Name) { return 'Inference' }
    switch ($Name) {
        'DocumentClassProjects' { return 'ClassAssoc' }
        'DocumentFieldProjects' { return 'FieldAssoc' }
        'DocumentPropertyProjects' { return 'PropertyAssoc' }
        default { return $Name }   # DocumentClass, DocumentField, DocumentProperty, DocumentRequest
    }
}

# ---------------------------------------------------------------------------
# Lecture du fichier
# ---------------------------------------------------------------------------
function Read-ExportFile([string]$Path, [string]$Encoding) {
    $bytes = [System.IO.File]::ReadAllBytes((Resolve-Path -LiteralPath $Path).ProviderPath)
    switch ($Encoding) {
        'UTF8' { return [System.Text.Encoding]::UTF8.GetString($bytes) }
        'Unicode' { return [System.Text.Encoding]::Unicode.GetString($bytes) }
        'Windows1252' { return (Get-Windows1252).GetString($bytes) }
    }
    # Auto : BOM, puis UTF-8 strict, sinon Windows-1252
    if ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF) {
        return [System.Text.Encoding]::UTF8.GetString($bytes, 3, $bytes.Length - 3)
    }
    if ($bytes.Length -ge 2 -and $bytes[0] -eq 0xFF -and $bytes[1] -eq 0xFE) {
        return [System.Text.Encoding]::Unicode.GetString($bytes, 2, $bytes.Length - 2)
    }
    try {
        return (New-Object System.Text.UTF8Encoding($false, $true)).GetString($bytes)
    }
    catch {
        Write-Verbose 'Fichier non UTF-8 : lecture en Windows-1252.'
        return (Get-Windows1252).GetString($bytes)
    }
}

function Get-Windows1252 {
    try {
        # .NET Core / PowerShell 7 : les pages de code doivent être enregistrées
        [System.Text.Encoding]::RegisterProvider([System.Text.CodePagesEncodingProvider]::Instance)
    }
    catch { }
    return [System.Text.Encoding]::GetEncoding(1252)
}

# ---------------------------------------------------------------------------
# Découpage d'un tableau JSON en éléments, SANS les réécrire (aucune perte de
# précision sur les nombres ni de format sur les dates).
# En cas de texte invalide (export coupé), resynchronisation sur le prochain
# début d'objet ',{"' ; les morceaux récupérés sont ensuite validés un par un.
# ---------------------------------------------------------------------------
function Split-JsonArray([string]$Text) {
    $result = @{ Elements = New-Object System.Collections.Generic.List[string]; Errors = New-Object System.Collections.Generic.List[string] }
    $s = $Text.Trim()
    if ($s.Length -eq 0) { return $result }
    if ($s[0] -ne '[') {
        $result.Errors.Add('le texte ne commence pas par [ : ' + $s.Substring(0, [Math]::Min(80, $s.Length)))
        return $result
    }
    $depth = 0; $inString = $false; $start = -1; $closed = $false
    $stringStops = [char[]]@('"', '\')
    $i = 1
    while ($i -lt $s.Length) {
        if ($inString) {
            # Saut direct au prochain guillemet ou antislash : les chaînes sont l'essentiel du volume
            $j = $s.IndexOfAny($stringStops, $i)
            if ($j -lt 0) { $i = $s.Length; break }
            if ($s[$j] -eq '\') { $i = $j + 2; continue }   # caractère échappé
            $inString = $false; $i = $j + 1; continue
        }
        $c = $s[$i]
        if ($c -eq '"') {
            if ($depth -eq 0) { $result.Errors.Add("texte inattendu en position $i"); $i = Resync $s $i $result; continue }
            $inString = $true
        }
        elseif ($c -eq '{' -or $c -eq '[') {
            if ($depth -eq 0) { $start = $i }
            $depth++
        }
        elseif ($c -eq '}' -or $c -eq ']') {
            if ($depth -eq 0) {
                if ($c -eq ']') { $closed = $true; $i++; break }
                $result.Errors.Add("accolade fermante inattendue en position $i"); $i = Resync $s $i $result; continue
            }
            $depth--
            if ($depth -eq 0) { $result.Elements.Add($s.Substring($start, $i - $start + 1)); $start = -1 }
        }
        elseif ($depth -eq 0 -and $c -ne ',' -and -not [char]::IsWhiteSpace($c)) {
            $result.Errors.Add("texte inattendu en position $i"); $i = Resync $s $i $result; continue
        }
        $i++
    }
    if (-not $closed) { $result.Errors.Add('tableau JSON non terminé (export tronqué ?)') }
    elseif ($s.Substring($i).Trim().Length -gt 0) { $result.Errors.Add('texte après la fin du tableau JSON') }
    return $result
}

# Met à jour l'état de lecture JSON (dans une chaîne ? caractère échappé en attente ?)
# après une ligne : un saut de ligne peut tomber au milieu d'une chaîne, voire juste
# après un antislash.
function Update-JsonStringState($State, [string]$Line) {
    $stops = [char[]]@('"', '\')
    $i = 0
    if ($State.Escape) { $State.Escape = $false; $i = 1 }
    while ($i -lt $Line.Length) {
        $j = $Line.IndexOfAny($stops, $i)
        if ($j -lt 0) { break }
        if ($Line[$j] -eq '\') {
            if ($State.InString) {
                if ($j + 1 -ge $Line.Length) { $State.Escape = $true; break }
                $i = $j + 2; continue
            }
            $i = $j + 1; continue
        }
        $State.InString = -not $State.InString
        $i = $j + 1
    }
}

function Resync([string]$s, [int]$from, $result) {
    $next = $s.IndexOf(',{"', $from)
    if ($next -lt 0) { return $s.Length }
    return $next + 1   # repart sur le '{'
}

# ---------------------------------------------------------------------------
# Analyse de l'export
# ---------------------------------------------------------------------------
$text = Read-ExportFile $InputFile $InputEncoding
# Sauts de ligne CR LF, LF ou CR seul
$lines = $text -split "`r`n|`n|`r"

# Le JSON d'une table s'étend de « --- Résultat JSON : » jusqu'à la section suivante.
# Il peut être coupé par des sauts de ligne n'importe où (découpage FOR JSON, retours
# à la ligne parasites, lignes vides intercalées) : toutes les lignes sont recollées
# SANS séparateur. Une ligne vide est ignorée, sauf au milieu d'une chaîne JSON où
# ses espaces font partie de la valeur.
$tables = New-Object System.Collections.Generic.List[object]
$current = $null
$inJson = $false
foreach ($line in $lines) {
    if ($line -match '^\s*---\s*Table\s*:\s*(.+?)\s*$') {
        $current = [pscustomobject]@{
            Name = $Matches[1]; Declared = $null; Json = New-Object System.Text.StringBuilder
            JsonLines = 0; InString = $false; Escape = $false
        }
        $tables.Add($current)
        $inJson = $false
        continue
    }
    if ($null -eq $current) { continue }
    if ($inJson) {
        if ($line.Trim().Length -eq 0 -and -not $current.InString) { continue }
        [void]$current.Json.Append($line)
        $current.JsonLines++
        Update-JsonStringState $current $line
        continue
    }
    if ($line -match '^\s*Nombre de lignes\s*:\s*(\d+)') { $current.Declared = [int]$Matches[1]; continue }
    if ($line -match '^\s*Table vide\s*:') { continue }
    if ($line -match '^\s*---\s*R.{1,3}sultat JSON\s*:') { $inJson = $true; continue }
}
if ($tables.Count -eq 0) { throw "Aucune section '--- Table :' trouvée dans $InputFile." }

# ---------------------------------------------------------------------------
# Contrôle et préparation de chaque table
# ---------------------------------------------------------------------------
$report = New-Object System.Collections.Generic.List[object]
$rowsToLoad = New-Object System.Collections.Generic.List[object]
$problems = 0

foreach ($t in $tables) {
    $raw = $t.Json.ToString()
    # Préfixe ODBC éventuel : [Microsoft][ODBC Driver 13 for SQL Server][SQL Server]
    $raw = [regex]::Replace($raw, '^\s*(?:\[[^\[\]{}"]*\])+(?=\[)', '')

    $split = Split-JsonArray $raw
    $valid = New-Object System.Collections.Generic.List[string]
    $invalid = 0
    $logs = 0
    $columns = New-Object 'System.Collections.Generic.HashSet[string]' ([System.StringComparer]::Ordinal)
    $missing = @{}   # groupe obligatoire -> nombre de lignes où il manque
    $spec = $null
    if ($MigratedTables -contains $t.Name) { $spec = $KindSpecs[(Get-TableKind $t.Name)] }
    foreach ($el in $split.Elements) {
        $obj = $null
        try { $obj = ConvertFrom-Json -InputObject $el } catch { $obj = $null }
        if ($null -eq $obj -or -not ($obj -is [System.Management.Automation.PSCustomObject])) { $invalid++; continue }
        # Colonnes présentes avec une valeur (noms sensibles à la casse)
        $present = New-Object 'System.Collections.Generic.HashSet[string]' ([System.StringComparer]::Ordinal)
        foreach ($p in $obj.PSObject.Properties) {
            if ($null -ne $p.Value -and -not ($p.Value -is [string] -and $p.Value.Trim().Length -eq 0)) { [void]$present.Add($p.Name) }
            [void]$columns.Add($p.Name)
        }
        if ($InferenceTables -contains $t.Name -and -not $present.Contains('DocId')) { $logs++; continue }
        if ($null -ne $spec) {
            foreach ($group in $spec.Required) {
                $ok = $false
                foreach ($alt in ($group -split '\|')) { if ($present.Contains($alt)) { $ok = $true; break } }
                if (-not $ok) { $missing[$group] = 1 + [int]$missing[$group] }
            }
        }
        $valid.Add($el)
    }
    # Colonnes présentes dans l'export mais non reprises par le script SQL
    $unknown = @()
    if ($null -ne $spec) {
        $unknown = @($columns | Where-Object { ($spec.Known -cnotcontains $_) -and ($spec.Skipped -cnotcontains $_) } | Sort-Object)
    }
    $jsonCount = $split.Elements.Count
    $declared = $t.Declared

    $status = 'OK'
    if ($IgnoredTables -contains $t.Name) { $status = 'IGNORÉE (pas de table cible)' }
    elseif (-not ($MigratedTables -contains $t.Name)) { $status = 'INCONNUE (non migrée)' }

    $mismatch = ($null -eq $declared) -or ($declared -ne $jsonCount) -or ($split.Errors.Count -gt 0) -or ($invalid -gt 0)
    if ($mismatch) {
        # Affiché pour toutes les tables ; seules les tables migrées comptent pour -Strict
        if ($MigratedTables -contains $t.Name) { $problems++ }
        $detail = "annoncé : $declared, éléments JSON : $jsonCount"
        if ($invalid -gt 0) { $detail += ", invalides : $invalid" }
        if ($split.Errors.Count -gt 0) { $detail += ', JSON : ' + ($split.Errors -join ' ; ') }
        Write-Host ("ÉCART  {0}  ({1})" -f $t.Name, $detail) -ForegroundColor Yellow
    }
    if ($logs -gt 0) {
        Write-Host ("LOGS   {0}  : {1} ligne(s) de logs IHM écartée(s) (sans DocId)" -f $t.Name, $logs) -ForegroundColor Cyan
    }
    $structure = ''
    if ($unknown.Count -gt 0) {
        $problems++
        $structure = 'colonnes non reprises'
        Write-Host ("COLONNES {0}  : colonne(s) présente(s) dans l'export mais non reprise(s) par la migration : {1}" -f $t.Name, ($unknown -join ', ')) -ForegroundColor Red
    }
    foreach ($group in $missing.Keys) {
        $problems++
        $structure = 'colonnes obligatoires absentes'
        Write-Host ("STRUCTURE {0}  : {1} ligne(s) sans [{2}]" -f $t.Name, $missing[$group], $group) -ForegroundColor Red
    }

    $staged = 0
    if ($MigratedTables -contains $t.Name) {
        foreach ($el in $valid) { $rowsToLoad.Add([pscustomobject]@{ Table = $t.Name; Json = $el }) }
        $staged = $valid.Count
    }
    $report.Add([pscustomobject]@{
            Table     = $t.Name
            Annonce   = $declared
            JSON      = $jsonCount
            Invalides = $invalid
            LignesTxt = $t.JsonLines
            LogsIHM   = $logs
            AMigrer   = $staged
            Ecart     = $(if ($mismatch) { 'OUI' } else { '' })
            Structure = $structure
            Statut    = $status
        })
}

$report | Format-Table -AutoSize | Out-String -Width 200 | Write-Host

if ($problems -gt 0) {
    Write-Warning "$problems problème(s) sur les tables migrées (voir les lignes ÉCART, COLONNES et STRUCTURE)."
    if ($Strict) {
        Write-Error 'Mode -Strict : aucun script SQL généré.'
        exit 1
    }
}

# ---------------------------------------------------------------------------
# Génération du script SQL
# ---------------------------------------------------------------------------
if (-not $OutputFile) {
    $OutputFile = [System.IO.Path]::Combine(
        [System.IO.Path]::GetDirectoryName((Resolve-Path -LiteralPath $InputFile).ProviderPath),
        [System.IO.Path]::GetFileNameWithoutExtension($InputFile) + '_migration.sql')
}

function ConvertTo-SqlLiteral([string]$Value) {
    $v = $Value.Replace("'", "''")
    if ($v.Contains('$(')) {
        # sqlcmd (et SSMS en mode SQLCMD) interprète $(...) comme une variable : on coupe la séquence.
        # CONVERT(nvarchar(max)) évite la troncature à 4000 caractères de la concaténation.
        $parts = $v -split [regex]::Escape('$(')
        # Résultat : CONVERT(nvarchar(max), N'...$') + N'(...'
        return "CONVERT(nvarchar(max), N'" + $parts[0] + "$')" + (($parts[1..($parts.Count - 1)] | ForEach-Object { " + N'(" + $_ + "'" }) -join '')
    }
    return "N'" + $v + "'"
}

$sb = New-Object System.Text.StringBuilder
$nl = "`r`n"
[void]$sb.Append(@"
/* =====================================================================
   MIGRATION DES MODÈLES ENTRAÎNÉS (ancienne base -> base fusionnée)
   Généré le $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') par Convert-LegacyMlExport.ps1
   Source : $([System.IO.Path]::GetFileName($InputFile))

   EXÉCUTION DANS SSMS
     1. Nouvelle requête, connectée à la BASE CIBLE (vérifier la liste déroulante
        des bases : le script n'a pas de USE).
     2. Ouvrir ce fichier (ou le coller) et exécuter tout le script (F5).
     3. Lire l'onglet Messages : contrôles, lignes insérées par table, puis
        « MIGRATION TERMINÉE » ou « MIGRATION ANNULÉE ».
     Le mode SQLCMD n'est pas nécessaire (sqlcmd -b -i fonctionne aussi).

   DROITS NÉCESSAIRES (vérifiés avant toute écriture)
     - SELECT et INSERT sur les tables cibles et dbo.Migration_LegacyMap,
       SELECT sur dbo.[User] et dbo.Ref_TaskType ;
     - facultatif : ALTER sur dbo.Project et dbo.Project_Version, pour suspendre
       les triggers d'historique pendant la migration. Sans ce droit, la migration
       a lieu quand même, et chaque projet / version migré apparaît dans
       Project_History (« a été créé »).
     Aucun droit de création d'objet n'est nécessaire : seules des tables
     temporaires (#) sont créées. Les scripts 1_tables (dont 19_Migration_LegacyMap)
     doivent avoir été déployés au préalable.

   SÉCURITÉ
     - Contrôle préalable : s'il manque un droit, une table ou une colonne, le
       script s'arrête avant d'écrire quoi que ce soit (SET NOEXEC ON).
     - Transaction unique : si une table échoue, aucune donnée n'est écrite.
     - Rejouable : les lignes déjà migrées (dbo.Migration_LegacyMap) ne sont pas recopiées.

   Contrôle de l'export :
"@ + $nl)
foreach ($r in $report) {
    [void]$sb.Append(('     {0,-32} annoncé {1,5}  JSON {2,5}  logs IHM {3,4}  à migrer {4,5}  {5} {6} {7}' -f $r.Table, $r.Annonce, $r.JSON, $r.LogsIHM, $r.AMigrer, $(if ($r.Ecart) { 'ÉCART' } else { '' }), $r.Structure, $r.Statut) + $nl)
}
[void]$sb.Append("   ===================================================================== */$nl")

# --- Préambule : vérifications, table de correspondance, tables de chargement
[void]$sb.Append(@'
SET NOEXEC OFF;   -- au cas où une exécution précédente dans la même fenêtre SSMS l'aurait laissé à ON
SET NOCOUNT ON;
SET XACT_ABORT ON;
SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
GO
/* ---------------------------------------------------------------------
   CONTRÔLE PRÉALABLE : rien n'est écrit tant que tout n'est pas vérifié.
   Dans SSMS, une erreur n'arrête pas les batches suivants : en cas de
   problème, SET NOEXEC ON désactive l'exécution de tout le reste du script.
   --------------------------------------------------------------------- */
DECLARE @nl nchar(2) = NCHAR(13) + NCHAR(10);
DECLARE @Err nvarchar(4000) = N'';

PRINT CONCAT(N'Base cible : ', DB_NAME(), N'   -   Serveur : ', @@SERVERNAME, N'   -   Connecté en tant que : ', SUSER_SNAME());

-- Version et niveau de compatibilité (OPENJSON exige le niveau 130, STRING_AGG SQL Server 2017)
IF CONVERT(int, SERVERPROPERTY('ProductMajorVersion')) < 14
    SET @Err += N'  - SQL Server 2017 ou plus récent requis.' + @nl;
IF (SELECT compatibility_level FROM sys.databases WHERE database_id = DB_ID()) < 130
    SET @Err += CONCAT(N'  - Niveau de compatibilité de la base trop bas (',
                       (SELECT compatibility_level FROM sys.databases WHERE database_id = DB_ID()),
                       N') : 130 minimum pour OPENJSON. À modifier par un administrateur.', @nl,
                       N'    (Les erreurs « Incorrect syntax » affichées ensuite en découlent : SQL Server analyse', @nl,
                       N'     les batches suivants sans les exécuter. Aucune donnée n''est écrite.)', @nl);

-- Schéma cible (scripts 1_tables)
IF COL_LENGTH(N'dbo.Project', N'Category') IS NULL
   OR COL_LENGTH(N'dbo.Training_Run', N'ProjectId') IS NULL
   OR COL_LENGTH(N'dbo.Evaluation', N'IsItc') IS NULL
   OR OBJECT_ID(N'dbo.Inference_Request', N'U') IS NULL
   OR OBJECT_ID(N'dbo.Document_Request', N'U') IS NULL
   OR OBJECT_ID(N'dbo.Migration_LegacyMap', N'U') IS NULL
    SET @Err += N'  - Schéma cible incomplet (ou mauvaise base sélectionnée) : déployer d''abord les scripts 1_tables, dont 19_Migration_LegacyMap.' + @nl;

-- Droits
SELECT @Err += CONCAT(N'  - Droit ', p.Perm, N' manquant sur ', p.Obj, @nl)
FROM (VALUES
    (N'dbo.Project', N'SELECT'), (N'dbo.Project', N'INSERT'),
    (N'dbo.Project_Version', N'SELECT'), (N'dbo.Project_Version', N'INSERT'),
    (N'dbo.Project_Version_Metric', N'SELECT'), (N'dbo.Project_Version_Metric', N'INSERT'),
    (N'dbo.Evaluation', N'SELECT'), (N'dbo.Evaluation', N'INSERT'),
    (N'dbo.Evaluation_Metric', N'SELECT'), (N'dbo.Evaluation_Metric', N'INSERT'),
    (N'dbo.Training_Run', N'SELECT'), (N'dbo.Training_Run', N'INSERT'),
    (N'dbo.Inference_Request', N'SELECT'), (N'dbo.Inference_Request', N'INSERT'),
    (N'dbo.Document_Class', N'SELECT'), (N'dbo.Document_Class', N'INSERT'),
    (N'dbo.Document_Field', N'SELECT'), (N'dbo.Document_Field', N'INSERT'),
    (N'dbo.Document_Property', N'SELECT'), (N'dbo.Document_Property', N'INSERT'),
    (N'dbo.Project_Version_Document_Class', N'SELECT'), (N'dbo.Project_Version_Document_Class', N'INSERT'),
    (N'dbo.Project_Version_Document_Field', N'SELECT'), (N'dbo.Project_Version_Document_Field', N'INSERT'),
    (N'dbo.Project_Version_Document_Property', N'SELECT'), (N'dbo.Project_Version_Document_Property', N'INSERT'),
    (N'dbo.Document_Request', N'SELECT'), (N'dbo.Document_Request', N'INSERT'),
    (N'dbo.Migration_LegacyMap', N'SELECT'), (N'dbo.Migration_LegacyMap', N'INSERT'),
    (N'dbo.[User]', N'SELECT'), (N'dbo.Ref_TaskType', N'SELECT')
) p (Obj, Perm)
WHERE OBJECT_ID(p.Obj) IS NOT NULL
  AND ISNULL(HAS_PERMS_BY_NAME(p.Obj, N'OBJECT', p.Perm), 0) = 0;

IF @Err <> N''
BEGIN
    PRINT N'=== MIGRATION IMPOSSIBLE : aucune donnée écrite ===';
    PRINT @Err;
    RAISERROR (N'Contrôle préalable en échec (voir les messages ci-dessus). Le reste du script n''est pas exécuté.', 16, 1);
    SET NOEXEC ON;
END
ELSE IF ISNULL(HAS_PERMS_BY_NAME(N'dbo.Project', N'OBJECT', N'ALTER'), 0) = 0
     OR ISNULL(HAS_PERMS_BY_NAME(N'dbo.Project_Version', N'OBJECT', N'ALTER'), 0) = 0
    PRINT N'Information : pas de droit ALTER sur dbo.Project / dbo.Project_Version : les triggers d''historique restent actifs, chaque projet / version migré sera tracé dans Project_History.';
ELSE
    PRINT N'Contrôle préalable OK.';
GO
IF OBJECT_ID(N'tempdb..#Src') IS NOT NULL DROP TABLE #Src;
CREATE TABLE #Src (Seq int IDENTITY(1, 1) PRIMARY KEY, SourceTable nvarchar(128) NOT NULL, RowJson nvarchar(max) NOT NULL);
IF OBJECT_ID(N'tempdb..#Expected') IS NOT NULL DROP TABLE #Expected;
CREATE TABLE #Expected (SourceTable nvarchar(128) NOT NULL PRIMARY KEY, NbRows int NOT NULL);
IF OBJECT_ID(N'tempdb..#StatusMap') IS NOT NULL DROP TABLE #StatusMap;
CREATE TABLE #StatusMap (StatusTrain int NOT NULL PRIMARY KEY, StatusCode varchar(20) NOT NULL);
IF OBJECT_ID(N'tempdb..#MetricKey') IS NOT NULL DROP TABLE #MetricKey;
CREATE TABLE #MetricKey (JsonKey nvarchar(50) COLLATE Latin1_General_CS_AS NOT NULL PRIMARY KEY, MetricCode varchar(30) NOT NULL);

'@)
foreach ($k in ($TrainStatusMap.Keys | Sort-Object { [int]$_ })) {
    [void]$sb.Append(("INSERT INTO #StatusMap (StatusTrain, StatusCode) VALUES ({0}, '{1}');" -f [int]$k, ([string]$TrainStatusMap[$k]).Replace("'", "''")) + $nl)
}
foreach ($k in $MetricKeys.Keys) {
    [void]$sb.Append(("INSERT INTO #MetricKey (JsonKey, MetricCode) VALUES (N'{0}', '{1}');" -f $k, $MetricKeys[$k]) + $nl)
}
foreach ($g in ($rowsToLoad | Group-Object Table)) {
    [void]$sb.Append(("INSERT INTO #Expected (SourceTable, NbRows) VALUES (N'{0}', {1});" -f $g.Name, $g.Count) + $nl)
}
[void]$sb.Append("GO$nl")

# --- Chargement des lignes (une ligne JSON par INSERT, batches de $RowsPerBatch)
$n = 0
foreach ($row in $rowsToLoad) {
    [void]$sb.Append("INSERT INTO #Src (SourceTable, RowJson) VALUES (N'" + $row.Table + "', " + (ConvertTo-SqlLiteral $row.Json) + ");$nl")
    $n++
    if ($n % $RowsPerBatch -eq 0) { [void]$sb.Append("GO$nl") }
}
[void]$sb.Append("GO$nl")

# --- Migration (script SQL statique)
[void]$sb.Append(@'
/* =====================================================================
   MIGRATION : un seul batch, une seule transaction
   ===================================================================== */
SET NOCOUNT ON;
SET XACT_ABORT ON;
DECLARE @Step nvarchar(200) = N'Contrôle du chargement';
DECLARE @Msg nvarchar(2000);  -- RAISERROR n'accepte pas de paramètre nvarchar(max)
DECLARE @n int;

BEGIN TRY
    -- -----------------------------------------------------------------
    -- 0. Contrôles avant écriture
    -- -----------------------------------------------------------------
    -- Toutes les lignes générées ont-elles été chargées ?
    SELECT @Msg = STRING_AGG(CONCAT(e.SourceTable, N' (attendu ', e.NbRows, N', chargé ', ISNULL(c.NbRows, 0), N')'), N', ')
    FROM #Expected e
    LEFT JOIN (SELECT SourceTable, COUNT(*) AS NbRows FROM #Src GROUP BY SourceTable) c ON c.SourceTable = e.SourceTable
    WHERE ISNULL(c.NbRows, 0) <> e.NbRows;
    IF @Msg IS NOT NULL RAISERROR (N'Chargement incomplet : %s', 16, 1, @Msg);

    SELECT @Msg = STRING_AGG(CONCAT(SourceTable, N' #', Seq), N', ') FROM #Src WHERE ISJSON(RowJson) = 0;
    IF @Msg IS NOT NULL RAISERROR (N'Lignes JSON invalides : %s', 16, 1, @Msg);

    -- Famille de chaque table source
    SET @Step = N'Préparation';
    CREATE TABLE #Family (SourceTable nvarchar(128) NOT NULL PRIMARY KEY, Kind varchar(10) NOT NULL, TaskType varchar(20) NULL, VersionTable nvarchar(128) NULL);
    INSERT INTO #Family VALUES
        (N'Model_Version',                 'VERSION',   'CLASSIFICATION', NULL),
        (N'ModelDecoupage_Version',        'VERSION',   'DECOUPAGE',      NULL),
        (N'ModelExtraction_Version',       'VERSION',   'EXTRACTION',     NULL),
        (N'ModelDetection_Version',        'VERSION',   'DETECTION',      NULL),
        (N'ModelSegmentation_Version',     'VERSION',   'SEGMENTATION',   NULL),
        (N'Model_Version_Test',            'TEST',      NULL, N'Model_Version'),
        (N'ModelDecoupage_Version_Test',   'TEST',      NULL, N'ModelDecoupage_Version'),
        (N'ModelExtraction_Version_Test',  'TEST',      NULL, N'ModelExtraction_Version'),
        (N'ModelDetection_Version_Test',   'TEST',      NULL, N'ModelDetection_Version'),
        (N'ModelSegmentation_Version_Test','TEST',      NULL, N'ModelSegmentation_Version'),
        (N'TrainTrack',                    'TRAIN',     NULL, NULL),
        (N'ExtractionTrainTrack',          'TRAIN',     NULL, NULL),
        (N'DetectionTrainTrack',           'TRAIN',     NULL, NULL),
        (N'SegmentationTrainTrack',        'TRAIN',     NULL, NULL),
        (N'Classification_Test',           'INFERENCE', 'CLASSIFICATION', NULL),
        (N'Decoupage_Test',                'INFERENCE', 'DECOUPAGE',      NULL),
        (N'Extraction_Test',               'INFERENCE', 'EXTRACTION',     NULL),
        (N'Detection_Test',                'INFERENCE', 'DETECTION',      NULL),
        (N'Segmentation_Test',             'INFERENCE', 'SEGMENTATION',   NULL);

    -- #MetricKey (colonnes de métriques -> [Ref_Metric]) est alimentée dans le préambule
    -- à partir de $MetricKeys du script PowerShell.

    -- -----------------------------------------------------------------
    -- 0.1 Mise en forme typée des lignes sources (tables temporaires)
    --     Les variantes de noms de colonnes des tables par type de modèle
    --     (IdModelVersion / IdModelExtractionVersion...) sont unifiées.
    -- -----------------------------------------------------------------
    SET @Step = N'Lecture : Model';
    SELECT s.Seq, s.SourceTable, j.IdModel AS LegacyId, j.Name, j.ProjectType, j.Creator,
           j.DateCreate, j.AssociatedSolutionId
    INTO #Model
    FROM #Src s
    CROSS APPLY OPENJSON(s.RowJson) WITH (
        IdModel bigint '$.IdModel', Name nvarchar(max) '$.Name', ProjectType nvarchar(max) '$.ProjectType',
        Creator nvarchar(200) '$.Creator', DateCreate datetime2(7) '$.DateCreate',
        AssociatedSolutionId uniqueidentifier '$.AssociatedSolutionId') j
    WHERE s.SourceTable = N'Model';

    SET @Step = N'Lecture : versions';
    SELECT s.Seq, s.SourceTable, f.TaskType, s.RowJson,
           COALESCE(j.IdModelVersion, j.IdModelExtractionVersion, j.IdModelDetectionVersion, j.IdModelSegmentationVersion, j.IdModelDecoupageVersion) AS LegacyId,
           COALESCE(j.IdModel, j.IdModelExtraction, j.IdModelDetection, j.IdModelSegmentation, j.IdModelDecoupage) AS LegacyModelId,
           j.VersionNb, j.DateCreate, j.Creator, j.TrainDataCount, j.ValidDataCount, j.TrainDataPath, j.ModelPath,
           j.AnnotationFile, j.InProd, j.IsITC, j.Algo, j.Comment
    INTO #Version
    FROM #Src s
    JOIN #Family f ON f.SourceTable = s.SourceTable AND f.Kind = 'VERSION'
    CROSS APPLY OPENJSON(s.RowJson) WITH (
        IdModelVersion bigint, IdModelExtractionVersion bigint, IdModelDetectionVersion bigint,
        IdModelSegmentationVersion bigint, IdModelDecoupageVersion bigint,
        IdModel bigint, IdModelExtraction bigint, IdModelDetection bigint, IdModelSegmentation bigint, IdModelDecoupage bigint,
        VersionNb int, DateCreate datetime2(7), Creator nvarchar(200), TrainDataCount int, ValidDataCount int,
        TrainDataPath nvarchar(max), ModelPath nvarchar(max), AnnotationFile nvarchar(max),
        InProd bit, IsITC bit, Algo nvarchar(100), Comment nvarchar(max)) j;

    SET @Step = N'Lecture : tests de versions';
    SELECT s.Seq, s.SourceTable, f.VersionTable, s.RowJson,
           COALESCE(j.IdModelVersionTest, j.IdModelExtractionVersionTest, j.IdModelDetectionVersionTest, j.IdModelSegmentationVersionTest, j.IdModelDecoupageVersionTest) AS LegacyId,
           COALESCE(j.IdModelVersion, j.IdModelExtractionVersion, j.IdModelDetectionVersion, j.IdModelSegmentationVersion, j.IdModelDecoupageVersion) AS LegacyVersionId,
           j.VersionNb AS TestNb, j.DateCreate, j.Creator, j.TestDataCount, j.TestDataPath, j.TestResultsPath,
           j.AnnotationFile, j.IsITC, j.Comment
    INTO #Test
    FROM #Src s
    JOIN #Family f ON f.SourceTable = s.SourceTable AND f.Kind = 'TEST'
    CROSS APPLY OPENJSON(s.RowJson) WITH (
        IdModelVersionTest bigint, IdModelExtractionVersionTest bigint, IdModelDetectionVersionTest bigint,
        IdModelSegmentationVersionTest bigint, IdModelDecoupageVersionTest bigint,
        IdModelVersion bigint, IdModelExtractionVersion bigint, IdModelDetectionVersion bigint,
        IdModelSegmentationVersion bigint, IdModelDecoupageVersion bigint,
        VersionNb int, DateCreate datetime2(7), Creator nvarchar(200), TestDataCount int,
        TestDataPath nvarchar(max), TestResultsPath nvarchar(max), AnnotationFile nvarchar(max),
        IsITC bit, Comment nvarchar(max)) j;

    SET @Step = N'Lecture : suivis d''entraînement';
    SELECT s.Seq, s.SourceTable,
           COALESCE(j.IdTrainTrack, j.IdExtractionTrainTrack, j.IdDetectionTrainTrack, j.IdSegmentationTrainTrack) AS LegacyId,
           COALESCE(j.IdModel, j.IdModelExtraction, j.IdModelDetection, j.IdModelSegmentation) AS LegacyModelId,
           j.VersionNb, j.DateStart, j.DateEnd, j.StatusTrain, j.DatasetPath, j.AnnotationFile, j.ModelPath,
           j.Creator, j.CurrentStep, j.Step, j.Epoch, j.CurrentPhase, j.IsITC
    INTO #Train
    FROM #Src s
    JOIN #Family f ON f.SourceTable = s.SourceTable AND f.Kind = 'TRAIN'
    CROSS APPLY OPENJSON(s.RowJson) WITH (
        IdTrainTrack bigint, IdExtractionTrainTrack bigint, IdDetectionTrainTrack bigint, IdSegmentationTrainTrack bigint,
        IdModel bigint, IdModelExtraction bigint, IdModelDetection bigint, IdModelSegmentation bigint,
        VersionNb int, DateStart datetime2(7), DateEnd datetime2(7), StatusTrain int,
        DatasetPath nvarchar(max), AnnotationFile nvarchar(max), ModelPath nvarchar(max), Creator nvarchar(200),
        CurrentStep nvarchar(200), Step nvarchar(200), Epoch nvarchar(50), CurrentPhase nvarchar(200), IsITC bit) j;

    SET @Step = N'Lecture : inférences';
    SELECT s.Seq, s.SourceTable, f.TaskType,
           COALESCE(j.IdClassification, j.IdDecoupage, j.IdExtraction, j.IdDetection, j.IdSegmentation) AS LegacyId,
           NULLIF(LTRIM(RTRIM(j.DocId)), N'') AS DocId, j.ResMessage, j.DateCreate, j.EndStatus
    INTO #Inference
    FROM #Src s
    JOIN #Family f ON f.SourceTable = s.SourceTable AND f.Kind = 'INFERENCE'
    CROSS APPLY OPENJSON(s.RowJson) WITH (
        IdClassification bigint, IdDecoupage bigint, IdExtraction bigint, IdDetection bigint, IdSegmentation bigint,
        DocId nvarchar(400), ResMessage nvarchar(max), DateCreate datetime2(7), EndStatus nvarchar(50)) j;

    SET @Step = N'Lecture : référentiel documentaire';
    SELECT s.Seq, s.SourceTable, COALESCE(j.IdClass, j.IdDocumentClass) AS LegacyId,
           COALESCE(j.NameClass, j.Name) AS Name, COALESCE(j.DescriptionClass, j.Description) AS Description,
           COALESCE(j.CreatorClass, j.Creator) AS Creator, COALESCE(j.DateCreateClass, j.DateCreate) AS DateCreate,
           COALESCE(j.UpdaterClass, j.Updater) AS Updater, COALESCE(j.DateUpdateClass, j.DateUpdate) AS DateUpdate
    INTO #DocClass
    FROM #Src s
    CROSS APPLY OPENJSON(s.RowJson) WITH (
        IdClass bigint, IdDocumentClass bigint, NameClass nvarchar(400), Name nvarchar(400),
        DescriptionClass nvarchar(max), Description nvarchar(max), CreatorClass nvarchar(200), Creator nvarchar(200),
        DateCreateClass datetime2(7), DateCreate datetime2(7), UpdaterClass nvarchar(200), Updater nvarchar(200),
        DateUpdateClass datetime2(7), DateUpdate datetime2(7)) j
    WHERE s.SourceTable = N'DocumentClass';

    SELECT s.Seq, s.SourceTable, COALESCE(j.IdField, j.IdDocumentField) AS LegacyId,
           COALESCE(j.IdClass, j.IdDocumentClass) AS LegacyClassId,
           COALESCE(j.NameField, j.Name) AS Name, COALESCE(j.DescriptionField, j.Description) AS Description,
           COALESCE(j.CreatorField, j.Creator) AS Creator, COALESCE(j.DateCreateField, j.DateCreate) AS DateCreate,
           COALESCE(j.UpdaterField, j.Updater) AS Updater, COALESCE(j.DateUpdateField, j.DateUpdate) AS DateUpdate
    INTO #DocField
    FROM #Src s
    CROSS APPLY OPENJSON(s.RowJson) WITH (
        IdField bigint, IdDocumentField bigint, IdClass bigint, IdDocumentClass bigint,
        NameField nvarchar(400), Name nvarchar(400), DescriptionField nvarchar(max), Description nvarchar(max),
        CreatorField nvarchar(200), Creator nvarchar(200), DateCreateField datetime2(7), DateCreate datetime2(7),
        UpdaterField nvarchar(200), Updater nvarchar(200), DateUpdateField datetime2(7), DateUpdate datetime2(7)) j
    WHERE s.SourceTable = N'DocumentField';

    SELECT s.Seq, s.SourceTable, COALESCE(j.IdProperty, j.IdDocumentProperty) AS LegacyId,
           COALESCE(j.NameProperty, j.Name) AS Name, COALESCE(j.DescriptionProperty, j.Description) AS Description,
           COALESCE(j.CreatorProperty, j.Creator) AS Creator, COALESCE(j.DateCreateProperty, j.DateCreate) AS DateCreate,
           COALESCE(j.UpdaterProperty, j.Updater) AS Updater, COALESCE(j.DateUpdateProperty, j.DateUpdate) AS DateUpdate
    INTO #DocProperty
    FROM #Src s
    CROSS APPLY OPENJSON(s.RowJson) WITH (
        IdProperty bigint, IdDocumentProperty bigint, NameProperty nvarchar(400), Name nvarchar(400),
        DescriptionProperty nvarchar(max), Description nvarchar(max), CreatorProperty nvarchar(200), Creator nvarchar(200),
        DateCreateProperty datetime2(7), DateCreate datetime2(7), UpdaterProperty nvarchar(200), Updater nvarchar(200),
        DateUpdateProperty datetime2(7), DateUpdate datetime2(7)) j
    WHERE s.SourceTable = N'DocumentProperty';

    SELECT s.Seq, s.SourceTable,
           COALESCE(j.IdClass, j.IdDocumentClass, j.IdField, j.IdDocumentField, j.IdProperty, j.IdDocumentProperty) AS LegacyItemId,
           j.IdModel AS LegacyModelId, j.IdModelVersion AS LegacyVersionRef
    INTO #DocAssoc
    FROM #Src s
    CROSS APPLY OPENJSON(s.RowJson) WITH (
        IdClass bigint, IdDocumentClass bigint, IdField bigint, IdDocumentField bigint,
        IdProperty bigint, IdDocumentProperty bigint, IdModel bigint, IdModelVersion bigint) j
    WHERE s.SourceTable IN (N'DocumentClassProjects', N'DocumentFieldProjects', N'DocumentPropertyProjects');

    SELECT s.Seq, s.SourceTable, j.IdDocumentRequest AS LegacyId, j.TypeDocumentRequest AS [Type],
           j.NameDocumentRequest AS Name, j.DescriptionDocumentRequest AS Description,
           j.StatusDocumentRequest AS [Status], j.CreatorDocumentRequest AS Creator,
           j.DateCreateDocumentRequest AS DateCreate, j.UpdaterDocumentRequest AS Updater,
           j.DateUpdateDocumentRequest AS DateUpdate, j.CommentDocumentRequest AS Comment,
           j.ResponseDocumentRequest AS Response
    INTO #DocRequest
    FROM #Src s
    CROSS APPLY OPENJSON(s.RowJson) WITH (
        IdDocumentRequest bigint, TypeDocumentRequest nvarchar(200), NameDocumentRequest nvarchar(400),
        DescriptionDocumentRequest nvarchar(max), StatusDocumentRequest nvarchar(100),
        CreatorDocumentRequest nvarchar(200), DateCreateDocumentRequest datetime2(7),
        UpdaterDocumentRequest nvarchar(200), DateUpdateDocumentRequest datetime2(7),
        CommentDocumentRequest nvarchar(max), ResponseDocumentRequest nvarchar(max)) j
    WHERE s.SourceTable = N'DocumentRequest';

    -- -----------------------------------------------------------------
    -- 0.2 Contrôles de cohérence des sources
    -- -----------------------------------------------------------------
    SET @Step = N'Contrôle des identifiants sources';
    ;WITH AllIds AS (
        SELECT SourceTable, Seq, LegacyId FROM #Model     UNION ALL
        SELECT SourceTable, Seq, LegacyId FROM #Version   UNION ALL
        SELECT SourceTable, Seq, LegacyId FROM #Test      UNION ALL
        SELECT SourceTable, Seq, LegacyId FROM #Train     UNION ALL
        SELECT SourceTable, Seq, LegacyId FROM #Inference UNION ALL
        SELECT SourceTable, Seq, LegacyId FROM #DocClass  UNION ALL
        SELECT SourceTable, Seq, LegacyId FROM #DocField  UNION ALL
        SELECT SourceTable, Seq, LegacyId FROM #DocProperty UNION ALL
        SELECT SourceTable, Seq, LegacyId FROM #DocRequest
    )
    SELECT @Msg = STRING_AGG(CONVERT(nvarchar(max), CONCAT(SourceTable, N' #', Seq)), N', ') FROM AllIds WHERE LegacyId IS NULL;
    IF @Msg IS NOT NULL RAISERROR (N'Identifiant source introuvable (nom de colonne inattendu ?) : %s', 16, 1, @Msg);

    ;WITH AllIds AS (
        SELECT SourceTable, LegacyId FROM #Model     UNION ALL
        SELECT SourceTable, LegacyId FROM #Version   UNION ALL
        SELECT SourceTable, LegacyId FROM #Test      UNION ALL
        SELECT SourceTable, LegacyId FROM #Train     UNION ALL
        SELECT SourceTable, LegacyId FROM #Inference UNION ALL
        SELECT SourceTable, LegacyId FROM #DocClass  UNION ALL
        SELECT SourceTable, LegacyId FROM #DocField  UNION ALL
        SELECT SourceTable, LegacyId FROM #DocProperty UNION ALL
        SELECT SourceTable, LegacyId FROM #DocRequest
    )
    SELECT @Msg = STRING_AGG(CONVERT(nvarchar(max), CONCAT(SourceTable, N' Id ', LegacyId)), N', ')
    FROM (SELECT SourceTable, LegacyId FROM AllIds GROUP BY SourceTable, LegacyId HAVING COUNT(*) > 1) d;
    IF @Msg IS NOT NULL RAISERROR (N'Identifiants sources en double : %s', 16, 1, @Msg);

    -- Type de tâche du modèle : ProjectType (« Classification », « Découpage »...),
    -- comparé sans casse ni accents au code et au libellé de [Ref_TaskType] ;
    -- à défaut, famille des tables de versions qui référencent le modèle.
    SET @Step = N'Contrôle : type de tâche des modèles';
    ALTER TABLE #Model ADD TaskType varchar(20) NULL;
    UPDATE m SET TaskType = COALESCE(
        (SELECT TOP (1) r.Code FROM dbo.Ref_TaskType r
         WHERE LTRIM(RTRIM(m.ProjectType)) COLLATE Latin1_General_CI_AI IN (r.Code COLLATE Latin1_General_CI_AI, r.Label COLLATE Latin1_General_CI_AI)),
        (SELECT MIN(v.TaskType) FROM #Version v WHERE v.LegacyModelId = m.LegacyId))
    FROM #Model m;
    SELECT @Msg = STRING_AGG(CONVERT(nvarchar(max), CONCAT(N'IdModel ', LegacyId, N' (', ProjectType, N')')), N', ') FROM #Model WHERE TaskType IS NULL;
    IF @Msg IS NOT NULL RAISERROR (N'Type de tâche non reconnu : %s', 16, 1, @Msg);

    -- Auteurs : nom complet (« DUPREZ Julien ») ou identifiant (« CRETYSE ») -> PersoId
    -- quand l'utilisateur existe dans [User] ; sinon la valeur source est conservée.
    SET @Step = N'Résolution des auteurs';
    CREATE TABLE #Who (Raw nvarchar(200) NOT NULL PRIMARY KEY, Resolved nvarchar(200) NOT NULL);
    INSERT INTO #Who (Raw, Resolved)
    SELECT x.Raw, COALESCE(u.PersoId, x.Raw)
    FROM (
        SELECT Creator FROM #Model UNION SELECT Creator FROM #Version UNION SELECT Creator FROM #Test
        UNION SELECT Creator FROM #Train UNION SELECT Creator FROM #DocClass UNION SELECT Updater FROM #DocClass
        UNION SELECT Creator FROM #DocField UNION SELECT Updater FROM #DocField
        UNION SELECT Creator FROM #DocProperty UNION SELECT Updater FROM #DocProperty
        UNION SELECT Creator FROM #DocRequest UNION SELECT Updater FROM #DocRequest
    ) c (Raw)
    CROSS APPLY (SELECT LTRIM(RTRIM(c.Raw)) AS Raw) x
    OUTER APPLY (
        SELECT TOP (1) us.PersoId FROM dbo.[User] us
        WHERE us.PersoId = x.Raw
           OR us.Lastname + N' ' + us.Firstname = x.Raw
           OR us.Firstname + N' ' + us.Lastname = x.Raw
        ORDER BY us.Id
    ) u
    WHERE x.Raw IS NOT NULL AND x.Raw <> N''
    GROUP BY x.Raw, u.PersoId;

    -- -----------------------------------------------------------------
    -- ÉCRITURE : une seule transaction pour toutes les tables
    -- -----------------------------------------------------------------
    BEGIN TRANSACTION;

    -- Les triggers d'historique d'insertion sont suspendus : chaque projet / version migré
    -- créerait sinon une entrée « a été créé(e) » datée du jour de la migration.
    -- Réactivés avant le COMMIT ; en cas d'erreur, le ROLLBACK annule aussi leur désactivation.
    -- Nécessite le droit ALTER sur les tables : sans ce droit, les triggers restent actifs.
    SET @Step = N'Suspension des triggers d''insertion';
    DECLARE @CanAlter bit = CASE WHEN ISNULL(HAS_PERMS_BY_NAME(N'dbo.Project', N'OBJECT', N'ALTER'), 0) = 1
                                  AND ISNULL(HAS_PERMS_BY_NAME(N'dbo.Project_Version', N'OBJECT', N'ALTER'), 0) = 1
                                 THEN 1 ELSE 0 END;
    IF @CanAlter = 1
    BEGIN
        IF OBJECT_ID(N'dbo.trg_Project_Insert', N'TR') IS NOT NULL ALTER TABLE dbo.Project DISABLE TRIGGER trg_Project_Insert;
        IF OBJECT_ID(N'dbo.trg_ProjectVersion_Insert', N'TR') IS NOT NULL ALTER TABLE dbo.Project_Version DISABLE TRIGGER trg_ProjectVersion_Insert;
    END

    -- 1. Model -> Project ----------------------------------------------
    SET @Step = N'Model -> Project';
    MERGE dbo.Project AS t
    USING (
        SELECT m.*, w.Resolved AS CreatedBy
        FROM #Model m
        LEFT JOIN #Who w ON w.Raw = LTRIM(RTRIM(m.Creator))
        WHERE NOT EXISTS (SELECT 1 FROM dbo.Migration_LegacyMap mp WHERE mp.SourceTable = m.SourceTable AND mp.SourceId = m.LegacyId)
    ) AS s
    ON 1 = 0
    WHEN NOT MATCHED THEN
        INSERT (Name, ProjectType, IsActive, CreatedAt, CreatedBy, Category, TaskType, AssociatedSolutionId)
        VALUES (s.Name, s.ProjectType, 1, COALESCE(s.DateCreate, SYSDATETIME()), s.CreatedBy, 'MODEL', s.TaskType, s.AssociatedSolutionId)
    OUTPUT s.SourceTable, s.LegacyId, NULL, N'Project', inserted.Id, NULL
    INTO dbo.Migration_LegacyMap (SourceTable, SourceId, SourceParentId, TargetTable, TargetId, TargetGuid);
    SET @n = @@ROWCOUNT; PRINT CONCAT(N'Project                          : ', @n, N' ligne(s) insérée(s)');

    -- 2. Model*_Version -> Project_Version -----------------------------
    SET @Step = N'Model*_Version -> Project_Version';
    ALTER TABLE #Version ADD ProjectId int NULL;
    UPDATE v SET ProjectId = mp.TargetId
    FROM #Version v
    JOIN dbo.Migration_LegacyMap mp ON mp.SourceTable = N'Model' AND mp.SourceId = v.LegacyModelId;

    SELECT @Msg = STRING_AGG(CONVERT(nvarchar(max), CONCAT(SourceTable, N' Id ', LegacyId, N' (IdModel ', LegacyModelId, N')')), N', ')
    FROM #Version WHERE ProjectId IS NULL;
    IF @Msg IS NOT NULL RAISERROR (N'Versions dont le modèle est introuvable : %s', 16, 1, @Msg);

    SELECT @Msg = STRING_AGG(CONVERT(nvarchar(max), CONCAT(N'IdModel ', v.LegacyModelId, N' VersionNb ', v.VersionNb)), N', ')
    FROM #Version v
    WHERE NOT EXISTS (SELECT 1 FROM dbo.Migration_LegacyMap mp WHERE mp.SourceTable = v.SourceTable AND mp.SourceId = v.LegacyId)
      AND (   EXISTS (SELECT 1 FROM dbo.Project_Version pv WHERE pv.ProjectId = v.ProjectId AND pv.VersionNumber = v.VersionNb)
           OR EXISTS (SELECT 1 FROM #Version v2 WHERE v2.ProjectId = v.ProjectId AND v2.VersionNb = v.VersionNb
                      AND NOT (v2.SourceTable = v.SourceTable AND v2.LegacyId = v.LegacyId)));
    IF @Msg IS NOT NULL RAISERROR (N'Numéros de version en double pour un même modèle : %s', 16, 1, @Msg);

    MERGE dbo.Project_Version AS t
    USING (
        SELECT v.*, w.Resolved AS CreatedBy
        FROM #Version v
        LEFT JOIN #Who w ON w.Raw = LTRIM(RTRIM(v.Creator))
        WHERE NOT EXISTS (SELECT 1 FROM dbo.Migration_LegacyMap mp WHERE mp.SourceTable = v.SourceTable AND mp.SourceId = v.LegacyId)
    ) AS s
    ON 1 = 0
    WHEN NOT MATCHED THEN
        INSERT (ProjectId, VersionNumber, Description, CreatedAt, CreatedBy, DeliveredToProduction, [State],
                Algo, ModelPath, AnnotationFile, TrainDataPath, TrainDataCount, ValidDataCount, IsItc)
        VALUES (s.ProjectId, s.VersionNb, s.Comment, s.DateCreate, s.CreatedBy, ISNULL(s.InProd, 0), 'ONGOING',
                s.Algo, s.ModelPath, s.AnnotationFile, s.TrainDataPath, s.TrainDataCount, s.ValidDataCount, ISNULL(s.IsITC, 0))
    OUTPUT s.SourceTable, s.LegacyId, s.LegacyModelId, N'Project_Version', inserted.Id, NULL
    INTO dbo.Migration_LegacyMap (SourceTable, SourceId, SourceParentId, TargetTable, TargetId, TargetGuid);
    SET @n = @@ROWCOUNT; PRINT CONCAT(N'Project_Version                  : ', @n, N' ligne(s) insérée(s)');

    SELECT @Msg = STRING_AGG(CONVERT(nvarchar(max), CONCAT(N'ProjectId ', ProjectId)), N', ')
    FROM (SELECT ProjectId FROM dbo.Project_Version
          WHERE DeliveredToProduction = 1 AND ProjectId IN (SELECT ProjectId FROM #Version)
          GROUP BY ProjectId HAVING COUNT(*) > 1) x;
    IF @Msg IS NOT NULL PRINT N'ATTENTION : plusieurs versions en production (InProd) pour : ' + @Msg;

    -- 3. Métriques de validation -> Project_Version_Metric --------------
    SET @Step = N'Métriques de versions -> Project_Version_Metric';
    INSERT INTO dbo.Project_Version_Metric (ProjectVersionId, MetricCode, Value)
    SELECT mp.TargetId, mk.MetricCode, CONVERT(float, j.[value])
    FROM #Version v
    JOIN dbo.Migration_LegacyMap mp ON mp.SourceTable = v.SourceTable AND mp.SourceId = v.LegacyId
    CROSS APPLY OPENJSON(v.RowJson) j
    JOIN #MetricKey mk ON mk.JsonKey = j.[key] COLLATE Latin1_General_CS_AS
    WHERE j.[type] = 2
      AND NOT EXISTS (SELECT 1 FROM dbo.Project_Version_Metric x WHERE x.ProjectVersionId = mp.TargetId AND x.MetricCode = mk.MetricCode);
    SET @n = @@ROWCOUNT; PRINT CONCAT(N'Project_Version_Metric           : ', @n, N' ligne(s) insérée(s)');

    -- 4. Model*_Version_Test -> Evaluation ------------------------------
    SET @Step = N'Model*_Version_Test -> Evaluation';
    ALTER TABLE #Test ADD ProjectId int NULL, VersionNumber int NULL;
    UPDATE t SET ProjectId = pv.ProjectId, VersionNumber = pv.VersionNumber
    FROM #Test t
    JOIN dbo.Migration_LegacyMap mp ON mp.SourceTable = t.VersionTable AND mp.SourceId = t.LegacyVersionId
    JOIN dbo.Project_Version pv ON pv.Id = mp.TargetId;

    SELECT @Msg = STRING_AGG(CONVERT(nvarchar(max), CONCAT(SourceTable, N' Id ', LegacyId, N' (version ', LegacyVersionId, N')')), N', ')
    FROM #Test WHERE ProjectId IS NULL;
    IF @Msg IS NOT NULL RAISERROR (N'Tests dont la version est introuvable : %s', 16, 1, @Msg);

    SELECT @Msg = STRING_AGG(CONVERT(nvarchar(max), CONCAT(SourceTable, N' Id ', LegacyId)), N', ')
    FROM #Test WHERE TestDataPath IS NULL OR LTRIM(RTRIM(TestDataPath)) = N'';
    IF @Msg IS NOT NULL RAISERROR (N'Tests sans TestDataPath (EvalPath obligatoire) : %s', 16, 1, @Msg);

    MERGE dbo.Evaluation AS t
    USING (
        SELECT x.*, w.Resolved AS TriggeredBy
        FROM #Test x
        LEFT JOIN #Who w ON w.Raw = LTRIM(RTRIM(x.Creator))
        WHERE NOT EXISTS (SELECT 1 FROM dbo.Migration_LegacyMap mp WHERE mp.SourceTable = x.SourceTable AND mp.SourceId = x.LegacyId)
    ) AS s
    ON 1 = 0
    WHEN NOT MATCHED THEN
        INSERT (ProjectId, VersionNumber, Name, [Timestamp], EvalPath, GroundTruthFile, PredictionFile,
                TriggeredBy, TestDataCount, IsItc, Comment)
        VALUES (s.ProjectId, s.VersionNumber, CASE WHEN s.TestNb IS NOT NULL THEN CONCAT(N'Test ', s.TestNb) END, s.DateCreate,
                s.TestDataPath, s.AnnotationFile, s.TestResultsPath, s.TriggeredBy, s.TestDataCount, ISNULL(s.IsITC, 0), s.Comment)
    OUTPUT s.SourceTable, s.LegacyId, s.LegacyVersionId, N'Evaluation', NULL, inserted.Id   -- [Evaluation].[Id] : uniqueidentifier
    INTO dbo.Migration_LegacyMap (SourceTable, SourceId, SourceParentId, TargetTable, TargetId, TargetGuid);
    SET @n = @@ROWCOUNT; PRINT CONCAT(N'Evaluation                       : ', @n, N' ligne(s) insérée(s)');

    -- 5. Métriques de test -> Evaluation_Metric -------------------------
    SET @Step = N'Métriques de tests -> Evaluation_Metric';
    INSERT INTO dbo.Evaluation_Metric (EvaluationId, MetricCode, Value)
    SELECT mp.TargetGuid, mk.MetricCode, CONVERT(float, j.[value])
    FROM #Test x
    JOIN dbo.Migration_LegacyMap mp ON mp.SourceTable = x.SourceTable AND mp.SourceId = x.LegacyId
    CROSS APPLY OPENJSON(x.RowJson) j
    JOIN #MetricKey mk ON mk.JsonKey = j.[key] COLLATE Latin1_General_CS_AS
    WHERE j.[type] = 2
      AND NOT EXISTS (SELECT 1 FROM dbo.Evaluation_Metric e WHERE e.EvaluationId = mp.TargetGuid AND e.MetricCode = mk.MetricCode);
    SET @n = @@ROWCOUNT; PRINT CONCAT(N'Evaluation_Metric                : ', @n, N' ligne(s) insérée(s)');

    -- 6. *TrainTrack -> Training_Run -----------------------------------
    SET @Step = N'*TrainTrack -> Training_Run';
    ALTER TABLE #Train ADD ProjectId int NULL, StatusCode varchar(20) NULL;
    UPDATE r SET ProjectId = mp.TargetId
    FROM #Train r
    JOIN dbo.Migration_LegacyMap mp ON mp.SourceTable = N'Model' AND mp.SourceId = r.LegacyModelId;
    UPDATE r SET StatusCode = sm.StatusCode FROM #Train r JOIN #StatusMap sm ON sm.StatusTrain = r.StatusTrain;

    SELECT @Msg = STRING_AGG(CONVERT(nvarchar(max), CONCAT(SourceTable, N' Id ', LegacyId, N' (IdModel ', LegacyModelId, N')')), N', ')
    FROM #Train WHERE ProjectId IS NULL;
    IF @Msg IS NOT NULL RAISERROR (N'Entraînements dont le modèle est introuvable : %s', 16, 1, @Msg);

    SELECT @Msg = STRING_AGG(CONVERT(nvarchar(max), CONCAT(SourceTable, N' Id ', LegacyId, N' (StatusTrain ', ISNULL(CONVERT(nvarchar(20), StatusTrain), N'NULL'), N')')), N', ')
    FROM #Train WHERE StatusCode IS NULL;
    IF @Msg IS NOT NULL RAISERROR (N'StatusTrain sans correspondance (paramètre -TrainStatusMap) : %s', 16, 1, @Msg);

    SELECT @Msg = STRING_AGG(CONVERT(nvarchar(max), CONCAT(SourceTable, N' Id ', LegacyId)), N', ')
    FROM #Train WHERE VersionNb IS NULL;
    IF @Msg IS NOT NULL RAISERROR (N'Entraînements sans VersionNb : %s', 16, 1, @Msg);

    MERGE dbo.Training_Run AS t
    USING (
        SELECT r.*, COALESCE(w.Resolved, N'MIGRATION') AS CreatedBy,
               TRY_CONVERT(int, NULLIF(LTRIM(RTRIM(r.Epoch)), N'')) AS EpochInt,
               COALESCE(TRY_CONVERT(int, NULLIF(LTRIM(RTRIM(r.Step)), N'')), TRY_CONVERT(int, NULLIF(LTRIM(RTRIM(r.CurrentStep)), N''))) AS StepInt,
               LEFT(COALESCE(NULLIF(LTRIM(RTRIM(r.CurrentPhase)), N''),
                             CASE WHEN TRY_CONVERT(int, r.CurrentStep) IS NULL THEN NULLIF(LTRIM(RTRIM(r.CurrentStep)), N'') END,
                             CASE WHEN TRY_CONVERT(int, r.Step) IS NULL THEN NULLIF(LTRIM(RTRIM(r.Step)), N'') END), 100) AS Phase
        FROM #Train r
        LEFT JOIN #Who w ON w.Raw = LTRIM(RTRIM(r.Creator))
        WHERE NOT EXISTS (SELECT 1 FROM dbo.Migration_LegacyMap mp WHERE mp.SourceTable = r.SourceTable AND mp.SourceId = r.LegacyId)
    ) AS s
    ON 1 = 0
    WHEN NOT MATCHED THEN
        INSERT (ProjectId, VersionNumber, StatusCode, StartedAt, EndedAt, Epoch, CurrentStep, CurrentPhase,
                DatasetPath, AnnotationFile, OutputPath, IsItc, CreatedBy, CreatedAt)
        VALUES (s.ProjectId, s.VersionNb, s.StatusCode, s.DateStart, s.DateEnd, s.EpochInt, s.StepInt, s.Phase,
                s.DatasetPath, s.AnnotationFile, s.ModelPath, ISNULL(s.IsITC, 0), s.CreatedBy,
                COALESCE(s.DateStart, s.DateEnd, SYSDATETIME()))
    OUTPUT s.SourceTable, s.LegacyId, s.LegacyModelId, N'Training_Run', NULL, inserted.Id
    INTO dbo.Migration_LegacyMap (SourceTable, SourceId, SourceParentId, TargetTable, TargetId, TargetGuid);
    SET @n = @@ROWCOUNT; PRINT CONCAT(N'Training_Run                     : ', @n, N' ligne(s) insérée(s)');

    -- 7. *_Test (inférences) -> Inference_Request ------------------------
    --    Les logs IHM (lignes sans DocId) sont déjà écartés par le script PowerShell ;
    --    ils sont de nouveau exclus ici par sécurité.
    --    ResMessage contient la réponse du service encodée comme une chaîne JSON :
    --    elle est décodée vers [ResContent] ; [StatusCode] et [ResMessage] en sont extraits.
    SET @Step = N'*_Test -> Inference_Request';
    SELECT @n = COUNT(*) FROM #Inference WHERE DocId IS NULL;
    IF @n > 0 PRINT CONCAT(N'Inference_Request                : ', @n, N' log(s) IHM exclu(s)');

    MERGE dbo.Inference_Request AS t
    USING (
        SELECT i.*, c.Content,
               CASE WHEN c.Content IS NOT NULL THEN TRY_CONVERT(int, JSON_VALUE(c.Content, '$.status_code')) END AS HttpStatus,
               CASE WHEN c.Content IS NOT NULL THEN JSON_VALUE(c.Content, '$.message') ELSE i.ResMessage END AS Message
        FROM #Inference i
        CROSS APPLY (SELECT CASE
            WHEN ISJSON(i.ResMessage) = 1 AND LEFT(LTRIM(i.ResMessage), 1) = N'{' THEN i.ResMessage
            WHEN ISJSON(N'[' + i.ResMessage + N']') = 1
                THEN (SELECT TOP (1) d.[value] FROM OPENJSON(N'[' + i.ResMessage + N']') d WHERE d.[type] = 1)
            END AS Decoded) d
        CROSS APPLY (SELECT CASE WHEN ISJSON(d.Decoded) = 1 AND LEFT(LTRIM(d.Decoded), 1) = N'{' THEN d.Decoded END AS Content) c
        WHERE i.DocId IS NOT NULL
          AND NOT EXISTS (SELECT 1 FROM dbo.Migration_LegacyMap mp WHERE mp.SourceTable = i.SourceTable AND mp.SourceId = i.LegacyId)
    ) AS s
    ON 1 = 0
    WHEN NOT MATCHED THEN
        INSERT (TaskType, ProjectVersionId, DocId, StatusCode, ResMessage, ResContent, EndStatus, CreatedAt)
        VALUES (s.TaskType, NULL, s.DocId, s.HttpStatus, s.Message, s.Content, s.EndStatus, COALESCE(s.DateCreate, SYSDATETIME()))
    OUTPUT s.SourceTable, s.LegacyId, NULL, N'Inference_Request', NULL, inserted.Id
    INTO dbo.Migration_LegacyMap (SourceTable, SourceId, SourceParentId, TargetTable, TargetId, TargetGuid);
    SET @n = @@ROWCOUNT; PRINT CONCAT(N'Inference_Request                : ', @n, N' ligne(s) insérée(s)');

    -- 8. DocumentClass -> Document_Class (rapprochement par nom) ---------
    SET @Step = N'DocumentClass -> Document_Class';
    SELECT @Msg = STRING_AGG(CONVERT(nvarchar(max), CONCAT(N'IdClass ', LegacyId)), N', ') FROM #DocClass WHERE Name IS NULL;
    IF @Msg IS NOT NULL RAISERROR (N'Classes sans nom : %s', 16, 1, @Msg);

    INSERT INTO dbo.Document_Class (Name, Description, CreatedBy, CreatedAt, UpdatedBy, UpdatedAt)
    SELECT s.Name, s.Description, COALESCE(wc.Resolved, N'MIGRATION'), COALESCE(s.DateCreate, SYSDATETIME()), wu.Resolved, s.DateUpdate
    FROM (SELECT d.*, ROW_NUMBER() OVER (PARTITION BY d.Name ORDER BY d.LegacyId) AS rn FROM #DocClass d) s
    LEFT JOIN #Who wc ON wc.Raw = LTRIM(RTRIM(s.Creator))
    LEFT JOIN #Who wu ON wu.Raw = LTRIM(RTRIM(s.Updater))
    WHERE s.rn = 1
      AND NOT EXISTS (SELECT 1 FROM dbo.Migration_LegacyMap mp WHERE mp.SourceTable = s.SourceTable AND mp.SourceId = s.LegacyId)
      AND NOT EXISTS (SELECT 1 FROM dbo.Document_Class x WHERE x.Name = s.Name);
    SET @n = @@ROWCOUNT; PRINT CONCAT(N'Document_Class                   : ', @n, N' ligne(s) insérée(s)');

    INSERT INTO dbo.Migration_LegacyMap (SourceTable, SourceId, SourceParentId, TargetTable, TargetId)
    SELECT d.SourceTable, d.LegacyId, NULL, N'Document_Class', x.Id
    FROM #DocClass d
    JOIN dbo.Document_Class x ON x.Name = d.Name
    WHERE NOT EXISTS (SELECT 1 FROM dbo.Migration_LegacyMap mp WHERE mp.SourceTable = d.SourceTable AND mp.SourceId = d.LegacyId);

    -- 9. DocumentField -> Document_Field (rapprochement par classe + nom) -
    SET @Step = N'DocumentField -> Document_Field';
    ALTER TABLE #DocField ADD DocumentClassId int NULL;
    UPDATE f SET DocumentClassId = mp.TargetId
    FROM #DocField f
    JOIN dbo.Migration_LegacyMap mp ON mp.SourceTable = N'DocumentClass' AND mp.SourceId = f.LegacyClassId;
    SELECT @Msg = STRING_AGG(CONVERT(nvarchar(max), CONCAT(N'IdField ', LegacyId, N' (IdClass ', LegacyClassId, N')')), N', ')
    FROM #DocField WHERE DocumentClassId IS NULL OR Name IS NULL;
    IF @Msg IS NOT NULL RAISERROR (N'Champs sans classe connue ou sans nom : %s', 16, 1, @Msg);

    INSERT INTO dbo.Document_Field (DocumentClassId, Name, Description, CreatedBy, CreatedAt, UpdatedBy, UpdatedAt)
    SELECT s.DocumentClassId, s.Name, s.Description, COALESCE(wc.Resolved, N'MIGRATION'), COALESCE(s.DateCreate, SYSDATETIME()), wu.Resolved, s.DateUpdate
    FROM (SELECT f.*, ROW_NUMBER() OVER (PARTITION BY f.DocumentClassId, f.Name ORDER BY f.LegacyId) AS rn FROM #DocField f) s
    LEFT JOIN #Who wc ON wc.Raw = LTRIM(RTRIM(s.Creator))
    LEFT JOIN #Who wu ON wu.Raw = LTRIM(RTRIM(s.Updater))
    WHERE s.rn = 1
      AND NOT EXISTS (SELECT 1 FROM dbo.Migration_LegacyMap mp WHERE mp.SourceTable = s.SourceTable AND mp.SourceId = s.LegacyId)
      AND NOT EXISTS (SELECT 1 FROM dbo.Document_Field x WHERE x.DocumentClassId = s.DocumentClassId AND x.Name = s.Name);
    SET @n = @@ROWCOUNT; PRINT CONCAT(N'Document_Field                   : ', @n, N' ligne(s) insérée(s)');

    INSERT INTO dbo.Migration_LegacyMap (SourceTable, SourceId, SourceParentId, TargetTable, TargetId)
    SELECT f.SourceTable, f.LegacyId, f.LegacyClassId, N'Document_Field', x.Id
    FROM #DocField f
    JOIN dbo.Document_Field x ON x.DocumentClassId = f.DocumentClassId AND x.Name = f.Name
    WHERE NOT EXISTS (SELECT 1 FROM dbo.Migration_LegacyMap mp WHERE mp.SourceTable = f.SourceTable AND mp.SourceId = f.LegacyId);

    -- 10. DocumentProperty -> Document_Property (rapprochement par nom) ---
    SET @Step = N'DocumentProperty -> Document_Property';
    SELECT @Msg = STRING_AGG(CONVERT(nvarchar(max), CONCAT(N'IdProperty ', LegacyId)), N', ') FROM #DocProperty WHERE Name IS NULL;
    IF @Msg IS NOT NULL RAISERROR (N'Propriétés sans nom : %s', 16, 1, @Msg);

    INSERT INTO dbo.Document_Property (Name, Description, CreatedBy, CreatedAt, UpdatedBy, UpdatedAt)
    SELECT s.Name, s.Description, COALESCE(wc.Resolved, N'MIGRATION'), COALESCE(s.DateCreate, SYSDATETIME()), wu.Resolved, s.DateUpdate
    FROM (SELECT p.*, ROW_NUMBER() OVER (PARTITION BY p.Name ORDER BY p.LegacyId) AS rn FROM #DocProperty p) s
    LEFT JOIN #Who wc ON wc.Raw = LTRIM(RTRIM(s.Creator))
    LEFT JOIN #Who wu ON wu.Raw = LTRIM(RTRIM(s.Updater))
    WHERE s.rn = 1
      AND NOT EXISTS (SELECT 1 FROM dbo.Migration_LegacyMap mp WHERE mp.SourceTable = s.SourceTable AND mp.SourceId = s.LegacyId)
      AND NOT EXISTS (SELECT 1 FROM dbo.Document_Property x WHERE x.Name = s.Name);
    SET @n = @@ROWCOUNT; PRINT CONCAT(N'Document_Property                : ', @n, N' ligne(s) insérée(s)');

    INSERT INTO dbo.Migration_LegacyMap (SourceTable, SourceId, SourceParentId, TargetTable, TargetId)
    SELECT p.SourceTable, p.LegacyId, NULL, N'Document_Property', x.Id
    FROM #DocProperty p
    JOIN dbo.Document_Property x ON x.Name = p.Name
    WHERE NOT EXISTS (SELECT 1 FROM dbo.Migration_LegacyMap mp WHERE mp.SourceTable = p.SourceTable AND mp.SourceId = p.LegacyId);

    -- 11. Document*Projects -> Project_Version_Document_* ------------------
    --     IdModelVersion désigne la version : d'abord comme identifiant de version
    --     (tables Model*_Version) rattaché au même IdModel, sinon comme numéro de version.
    SET @Step = N'Document*Projects -> Project_Version_Document_*';
    ALTER TABLE #DocAssoc ADD ProjectVersionId int NULL, ItemId int NULL;
    UPDATE a SET ProjectVersionId = COALESCE(
        (SELECT TOP (1) mp.TargetId FROM dbo.Migration_LegacyMap mp
         WHERE mp.TargetTable = N'Project_Version' AND mp.SourceId = a.LegacyVersionRef AND mp.SourceParentId = a.LegacyModelId
         ORDER BY mp.SourceTable),
        (SELECT pv.Id FROM dbo.Migration_LegacyMap mm
         JOIN dbo.Project_Version pv ON pv.ProjectId = mm.TargetId AND pv.VersionNumber = a.LegacyVersionRef
         WHERE mm.SourceTable = N'Model' AND mm.SourceId = a.LegacyModelId))
    FROM #DocAssoc a;
    UPDATE a SET ItemId = mp.TargetId
    FROM #DocAssoc a
    JOIN dbo.Migration_LegacyMap mp
      ON mp.SourceId = a.LegacyItemId
     AND mp.SourceTable = CASE a.SourceTable WHEN N'DocumentClassProjects' THEN N'DocumentClass'
                                             WHEN N'DocumentFieldProjects' THEN N'DocumentField'
                                             ELSE N'DocumentProperty' END;
    SELECT @Msg = STRING_AGG(CONVERT(nvarchar(max), CONCAT(SourceTable, N' #', Seq, N' (IdModel ', LegacyModelId, N', IdModelVersion ', LegacyVersionRef, N', élément ', LegacyItemId, N')')), N', ')
    FROM #DocAssoc WHERE ProjectVersionId IS NULL OR ItemId IS NULL;
    IF @Msg IS NOT NULL RAISERROR (N'Associations dont la version ou l''élément est introuvable : %s', 16, 1, @Msg);

    INSERT INTO dbo.Project_Version_Document_Class (ProjectVersionId, DocumentClassId)
    SELECT DISTINCT a.ProjectVersionId, a.ItemId FROM #DocAssoc a
    WHERE a.SourceTable = N'DocumentClassProjects'
      AND NOT EXISTS (SELECT 1 FROM dbo.Project_Version_Document_Class x WHERE x.ProjectVersionId = a.ProjectVersionId AND x.DocumentClassId = a.ItemId);
    SET @n = @@ROWCOUNT; PRINT CONCAT(N'Project_Version_Document_Class   : ', @n, N' ligne(s) insérée(s)');

    INSERT INTO dbo.Project_Version_Document_Field (ProjectVersionId, DocumentFieldId)
    SELECT DISTINCT a.ProjectVersionId, a.ItemId FROM #DocAssoc a
    WHERE a.SourceTable = N'DocumentFieldProjects'
      AND NOT EXISTS (SELECT 1 FROM dbo.Project_Version_Document_Field x WHERE x.ProjectVersionId = a.ProjectVersionId AND x.DocumentFieldId = a.ItemId);
    SET @n = @@ROWCOUNT; PRINT CONCAT(N'Project_Version_Document_Field   : ', @n, N' ligne(s) insérée(s)');

    INSERT INTO dbo.Project_Version_Document_Property (ProjectVersionId, DocumentPropertyId)
    SELECT DISTINCT a.ProjectVersionId, a.ItemId FROM #DocAssoc a
    WHERE a.SourceTable = N'DocumentPropertyProjects'
      AND NOT EXISTS (SELECT 1 FROM dbo.Project_Version_Document_Property x WHERE x.ProjectVersionId = a.ProjectVersionId AND x.DocumentPropertyId = a.ItemId);
    SET @n = @@ROWCOUNT; PRINT CONCAT(N'Project_Version_Document_Property: ', @n, N' ligne(s) insérée(s)');

    -- 12. DocumentRequest -> Document_Request ---------------------------
    SET @Step = N'DocumentRequest -> Document_Request';
    MERGE dbo.Document_Request AS t
    USING (
        SELECT r.*, COALESCE(wc.Resolved, N'MIGRATION') AS CreatedBy, wu.Resolved AS UpdatedBy
        FROM #DocRequest r
        LEFT JOIN #Who wc ON wc.Raw = LTRIM(RTRIM(r.Creator))
        LEFT JOIN #Who wu ON wu.Raw = LTRIM(RTRIM(r.Updater))
        WHERE NOT EXISTS (SELECT 1 FROM dbo.Migration_LegacyMap mp WHERE mp.SourceTable = r.SourceTable AND mp.SourceId = r.LegacyId)
    ) AS s
    ON 1 = 0
    WHEN NOT MATCHED THEN
        INSERT ([Type], Name, Description, [Status], Comment, Response, CreatedBy, CreatedAt, UpdatedBy, UpdatedAt)
        VALUES (s.[Type], s.Name, s.Description, COALESCE(s.[Status], N'OPEN'), s.Comment, s.Response,
                s.CreatedBy, COALESCE(s.DateCreate, SYSDATETIME()), s.UpdatedBy, s.DateUpdate)
    OUTPUT s.SourceTable, s.LegacyId, NULL, N'Document_Request', inserted.Id, NULL
    INTO dbo.Migration_LegacyMap (SourceTable, SourceId, SourceParentId, TargetTable, TargetId, TargetGuid);
    SET @n = @@ROWCOUNT; PRINT CONCAT(N'Document_Request                 : ', @n, N' ligne(s) insérée(s)');

    -- Réactivation des triggers ------------------------------------------
    SET @Step = N'Réactivation des triggers d''insertion';
    IF @CanAlter = 1
    BEGIN
        IF OBJECT_ID(N'dbo.trg_Project_Insert', N'TR') IS NOT NULL ALTER TABLE dbo.Project ENABLE TRIGGER trg_Project_Insert;
        IF OBJECT_ID(N'dbo.trg_ProjectVersion_Insert', N'TR') IS NOT NULL ALTER TABLE dbo.Project_Version ENABLE TRIGGER trg_ProjectVersion_Insert;
    END

    COMMIT TRANSACTION;
    PRINT N'=== MIGRATION TERMINÉE : transaction validée ===';
END TRY
BEGIN CATCH
    IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
    SET @Msg = CONCAT(N'ÉCHEC DE LA MIGRATION à l''étape [', @Step, N'] : ', ERROR_MESSAGE());
    PRINT N'=== MIGRATION ANNULÉE : aucune donnée écrite (transaction annulée) ===';
    RAISERROR (N'%s', 16, 1, @Msg);
END CATCH
GO
IF OBJECT_ID(N'tempdb..#Src') IS NOT NULL DROP TABLE #Src;
IF OBJECT_ID(N'tempdb..#Expected') IS NOT NULL DROP TABLE #Expected;
IF OBJECT_ID(N'tempdb..#StatusMap') IS NOT NULL DROP TABLE #StatusMap;
IF OBJECT_ID(N'tempdb..#MetricKey') IS NOT NULL DROP TABLE #MetricKey;
GO
-- Toujours exécuté (même après SET NOEXEC ON) : la fenêtre SSMS reste utilisable.
SET NOEXEC OFF;
GO
'@)

# UTF-8 avec BOM : accents lus correctement par SSMS et sqlcmd
[System.IO.File]::WriteAllText($OutputFile, $sb.ToString(), (New-Object System.Text.UTF8Encoding($true)))
Write-Host ("Script SQL généré : {0} ({1} ligne(s) à migrer)" -f $OutputFile, $rowsToLoad.Count) -ForegroundColor Green
if ($problems -gt 0) {
    Write-Host 'Écarts détectés : le script SQL ne migre que les lignes lisibles. Relancer avec -Strict pour bloquer la génération.' -ForegroundColor Yellow
}
