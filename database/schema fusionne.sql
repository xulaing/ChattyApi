-- ============================================================================
-- Schéma de base de données fusionné — plateforme ML de traitement documentaire
-- + base projets existante (project / project_version)
--
-- Fusion :
--   - model         -> absorbé dans project (project_type = task_type)
--   - model_version -> absorbé dans project_version (state remplace in_prod)
--
-- Dialecte : PostgreSQL.
-- ============================================================================

-- ----------------------------------------------------------------------------
-- Types énumérés
-- ----------------------------------------------------------------------------

CREATE TYPE model_type AS ENUM (
    'classification',
    'segmentation',
    'detection',
    'extraction',
    'decoupage'
);

CREATE TYPE run_status AS ENUM (
    'pending', 'running', 'succeeded', 'failed', 'cancelled'
);

CREATE TYPE metric_scope AS ENUM ('validation', 'test');

-- ----------------------------------------------------------------------------
-- 1. Projets et versions (table existante, étendue)
-- ----------------------------------------------------------------------------

-- Table existante project, étendue avec les colonnes de l'ancienne table model.
-- project_type portait déjà cette info : on le retype en ENUM model_type
-- au lieu d'ajouter une colonne task_type séparée.
CREATE TABLE project (
    id                      BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    name                    TEXT        NOT NULL,
    project_type            model_type  NOT NULL,  -- ex-project_type (varchar) + ex-model.model_type, fusionnés
    description             TEXT,
    is_active               BOOLEAN     NOT NULL DEFAULT TRUE,
    associated_solution_id  BIGINT,                 -- ajouté (venait de model)
    created_at              TIMESTAMPTZ NOT NULL DEFAULT now(),
    created_by              TEXT        NOT NULL,
    updated_by              TEXT,
    UNIQUE (name, project_type)
);

-- Table existante project_version, étendue avec les colonnes de
-- l'ancienne table model_version. "state" remplace in_prod : on suppose
-- que l'une des valeurs de state signifie "en production"
-- (ex. 'production') — à confirmer / adapter à tes valeurs réelles.
CREATE TABLE project_version (
    id               BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    project_id       BIGINT      NOT NULL REFERENCES project(id) ON DELETE CASCADE,
    version_nb       INT         NOT NULL,
    title            TEXT,
    description      TEXT,                          -- fusionné avec l'ex-"comment" de model_version
    state            TEXT        NOT NULL,           -- ex: 'training', 'trained', 'production', ...
    algo             TEXT,                           -- ajouté (venait de model_version)
    model_path       TEXT,                           -- ajouté
    annotation_file  TEXT,                           -- ajouté
    train_data_count INT,                             -- ajouté
    valid_data_count INT,                             -- ajouté
    train_data_path  TEXT,                            -- ajouté
    is_itc           BOOLEAN     NOT NULL DEFAULT FALSE, -- ajouté
    config_path      TEXT,                            -- ajouté : JSON externe (hyperparamètres, epochs cible, classes)
    created_at       TIMESTAMPTZ NOT NULL DEFAULT now(),
    created_by       TEXT        NOT NULL,
    updated_by       TEXT,
    UNIQUE (project_id, version_nb)
);

-- Une seule version "en production" par projet.
-- ADAPTER la valeur 'production' si ton champ state utilise un autre libellé.
CREATE UNIQUE INDEX ux_project_version_prod
    ON project_version (project_id) WHERE state = 'production';

-- ----------------------------------------------------------------------------
-- 2. Exécutions : entraînement, test, inférence
-- ----------------------------------------------------------------------------

-- Remplace : TrainTrack, SegmentationTrainTrack, DetectionTrainTrack,
--            ExtractionTrainTrack
-- Pas de colonne epoch/classes : ce sont des hyperparamètres, stockés dans
-- project_version.config_path (fichier JSON externe).
CREATE TABLE training_run (
    id                 BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    project_version_id BIGINT      NOT NULL REFERENCES project_version(id) ON DELETE CASCADE,
    status             run_status  NOT NULL DEFAULT 'pending',
    started_at         TIMESTAMPTZ,
    ended_at           TIMESTAMPTZ,
    current_step       INT,
    total_step         INT,
    current_phase      TEXT,
    image_size         INT,
    dataset_path       TEXT,
    output_path        TEXT,
    created_by         TEXT        NOT NULL,
    created_at         TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX ix_training_run_version ON training_run (project_version_id);

-- Remplace : Model_Version_Test, ModelSegmentation_Version_Test,
--            ModelDecoupage_Version_Test, ModelDetection_Version_Test,
--            ModelExtraction_Version_Test, Evaluation_Run
CREATE TABLE test_run (
    id                 BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    project_version_id BIGINT      NOT NULL REFERENCES project_version(id) ON DELETE CASCADE,
    test_data_count    INT,
    test_data_path     TEXT,
    test_results_path  TEXT,
    annotation_file    TEXT,
    is_itc             BOOLEAN     NOT NULL DEFAULT FALSE,
    comment            TEXT,
    created_by         TEXT        NOT NULL,
    created_at         TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX ix_test_run_version ON test_run (project_version_id);

-- Toutes les métriques (validation et test), en lignes clé/valeur.
CREATE TABLE metric (
    id                 BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    project_version_id BIGINT           NOT NULL REFERENCES project_version(id) ON DELETE CASCADE,
    test_run_id        BIGINT           REFERENCES test_run(id) ON DELETE CASCADE,
    scope              metric_scope     NOT NULL,
    name               TEXT             NOT NULL,
    value              DOUBLE PRECISION NOT NULL,
    CONSTRAINT ck_metric_scope CHECK (
        (scope = 'validation' AND test_run_id IS NULL) OR
        (scope = 'test'       AND test_run_id IS NOT NULL)
    )
);

CREATE UNIQUE INDEX ux_metric_validation
    ON metric (project_version_id, name) WHERE test_run_id IS NULL;
CREATE UNIQUE INDEX ux_metric_test
    ON metric (test_run_id, name) WHERE test_run_id IS NOT NULL;

-- Remplace : Classification_Test, Decoupage_Test, Detection_Test,
--            Segmentation_Test, Extraction_Test
CREATE TABLE inference_request (
    id                 BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    task_type          model_type  NOT NULL,
    project_version_id BIGINT      REFERENCES project_version(id) ON DELETE SET NULL,
    doc_id             TEXT        NOT NULL,
    status_code        INT,
    res_message        TEXT,
    res_content        JSONB,
    end_status         TEXT,
    created_at         TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX ix_inference_request_doc  ON inference_request (doc_id);
CREATE INDEX ix_inference_request_type ON inference_request (task_type, created_at);

-- ----------------------------------------------------------------------------
-- 3. Référentiel documentaire
-- ----------------------------------------------------------------------------

CREATE TABLE document_class (
    id          BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    name        TEXT        NOT NULL UNIQUE,
    description TEXT,
    created_by  TEXT        NOT NULL,
    created_at  TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_by  TEXT,
    updated_at  TIMESTAMPTZ
);

CREATE TABLE document_field (
    id                BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    document_class_id BIGINT      NOT NULL REFERENCES document_class(id) ON DELETE CASCADE,
    name              TEXT        NOT NULL,
    description       TEXT,
    created_by        TEXT        NOT NULL,
    created_at        TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_by        TEXT,
    updated_at        TIMESTAMPTZ,
    UNIQUE (document_class_id, name)
);

CREATE TABLE document_property (
    id          BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    name        TEXT        NOT NULL UNIQUE,
    description TEXT,
    created_by  TEXT        NOT NULL,
    created_at  TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_by  TEXT,
    updated_at  TIMESTAMPTZ
);

-- ----------------------------------------------------------------------------
-- 4. Associations project_version <-> référentiel documentaire
-- ----------------------------------------------------------------------------

CREATE TABLE project_version_document_class (
    project_version_id BIGINT NOT NULL REFERENCES project_version(id) ON DELETE CASCADE,
    document_class_id  BIGINT NOT NULL REFERENCES document_class(id)  ON DELETE CASCADE,
    PRIMARY KEY (project_version_id, document_class_id)
);

CREATE TABLE project_version_document_field (
    project_version_id BIGINT NOT NULL REFERENCES project_version(id) ON DELETE CASCADE,
    document_field_id  BIGINT NOT NULL REFERENCES document_field(id)  ON DELETE CASCADE,
    PRIMARY KEY (project_version_id, document_field_id)
);

CREATE TABLE project_version_document_property (
    project_version_id   BIGINT NOT NULL REFERENCES project_version(id)   ON DELETE CASCADE,
    document_property_id BIGINT NOT NULL REFERENCES document_property(id) ON DELETE CASCADE,
    PRIMARY KEY (project_version_id, document_property_id)
);

-- ----------------------------------------------------------------------------
-- 5. Demandes documentaires
-- ----------------------------------------------------------------------------

CREATE TABLE document_request (
    id          BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    type        TEXT        NOT NULL,
    name        TEXT        NOT NULL,
    description TEXT,
    status      TEXT        NOT NULL DEFAULT 'open',
    comment     TEXT,
    response    TEXT,
    created_by  TEXT        NOT NULL,
    created_at  TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_by  TEXT,
    updated_at  TIMESTAMPTZ
);
