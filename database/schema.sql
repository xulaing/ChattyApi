-- ============================================================================
-- Schéma de base de données optimisé — plateforme ML de traitement documentaire
-- Remplace les ~28 tables dupliquées par 13 tables unifiées.
--
-- Principe central : les 5 familles de tables dupliquées par type de modèle
-- (Model_Version / ModelSegmentation_Version / ModelDecoupage_Version /
--  ModelDetection_Version / ModelExtraction_Version, idem pour *_Version_Test,
--  *TrainTrack et *_Test) sont fusionnées en une seule table chacune.
-- Le type de tâche est porté par model.model_type (discriminateur), et les
-- métriques hétérogènes (accuracy, kappa, AP_bbox, …) sont stockées en
-- lignes clé/valeur dans la table metric.
--
-- Dialecte : PostgreSQL.
-- ============================================================================

-- ----------------------------------------------------------------------------
-- Types énumérés
-- ----------------------------------------------------------------------------

CREATE TYPE model_type AS ENUM (
    'classification',   -- ex. Model_Version / Classification_Test
    'segmentation',     -- ex. ModelSegmentation_Version / Segmentation_Test
    'detection',        -- ex. ModelDetection_Version / Detection_Test
    'extraction',       -- ex. ModelExtraction_Version / Extraction_Test
    'decoupage'         -- ex. ModelDecoupage_Version / Decoupage_Test
);

CREATE TYPE run_status AS ENUM (
    'pending', 'running', 'succeeded', 'failed', 'cancelled'
);

-- Portée d'une métrique : mesurée sur le jeu de validation (à l'entraînement)
-- ou sur un jeu de test (via un test_run).
CREATE TYPE metric_scope AS ENUM ('validation', 'test');

-- ----------------------------------------------------------------------------
-- 1. Modèles et versions
-- ----------------------------------------------------------------------------

-- Remplace : Model (inchangée sur le fond, colonnes normalisées)
CREATE TABLE model (
    id                     BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    name                   TEXT        NOT NULL,
    model_type             model_type  NOT NULL,
    project_type           TEXT,
    associated_solution_id BIGINT,
    created_by             TEXT        NOT NULL,
    created_at             TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE (name, model_type)
);

-- Remplace : Model_Version, ModelSegmentation_Version, ModelDecoupage_Version,
--            ModelDetection_Version, ModelExtraction_Version
-- Les colonnes de métriques (Accuracy, ErrorRate, PrecisionScore, RecallScore,
-- f1_score, kappa, AP_bbox, Recall_bbox, AP_segm, Recall_segm, MeanErrors,
-- NbErrors) partent dans la table metric.
CREATE TABLE model_version (
    id               BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    model_id         BIGINT      NOT NULL REFERENCES model(id) ON DELETE CASCADE,
    version_nb       INT         NOT NULL,
    algo             TEXT,
    model_path       TEXT,
    annotation_file  TEXT,
    train_data_count INT,
    valid_data_count INT,
    train_data_path  TEXT,
    is_itc           BOOLEAN     NOT NULL DEFAULT FALSE,
    in_prod          BOOLEAN     NOT NULL DEFAULT FALSE,
    comment          TEXT,
    created_by       TEXT        NOT NULL,
    created_at       TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE (model_id, version_nb)
);

-- Une seule version en production par modèle.
CREATE UNIQUE INDEX ux_model_version_in_prod
    ON model_version (model_id) WHERE in_prod;

-- ----------------------------------------------------------------------------
-- 2. Exécutions : entraînement, test, évaluation, inférence
-- ----------------------------------------------------------------------------

-- Remplace : TrainTrack, SegmentationTrainTrack, DetectionTrainTrack,
--            ExtractionTrainTrack
CREATE TABLE training_run (
    id               BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    model_version_id BIGINT      NOT NULL REFERENCES model_version(id) ON DELETE CASCADE,
    status           run_status  NOT NULL DEFAULT 'pending',
    started_at       TIMESTAMPTZ,
    ended_at         TIMESTAMPTZ,
    epoch            INT,
    current_step     INT,
    total_step       INT,
    current_phase    TEXT,
    classes          JSONB,       -- liste des classes entraînées
    image_size       INT,
    dataset_path     TEXT,
    output_path      TEXT,
    created_by       TEXT        NOT NULL,
    created_at       TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX ix_training_run_version ON training_run (model_version_id);

-- Remplace : Model_Version_Test, ModelSegmentation_Version_Test,
--            ModelDecoupage_Version_Test, ModelDetection_Version_Test,
--            ModelExtraction_Version_Test, ainsi que Evaluation_Run
-- (une évaluation = un test_run ; ses métriques vont dans metric).
CREATE TABLE test_run (
    id                BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    model_version_id  BIGINT      NOT NULL REFERENCES model_version(id) ON DELETE CASCADE,
    test_data_count   INT,
    test_data_path    TEXT,
    test_results_path TEXT,
    annotation_file   TEXT,
    is_itc            BOOLEAN     NOT NULL DEFAULT FALSE,
    comment           TEXT,
    created_by        TEXT        NOT NULL,
    created_at        TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX ix_test_run_version ON test_run (model_version_id);

-- Toutes les métriques de toutes les versions et de tous les tests.
-- scope = 'validation' : mesurée à l'entraînement (test_run_id IS NULL).
-- scope = 'test'       : mesurée par un test_run (test_run_id NOT NULL).
-- Noms attendus : accuracy, error_rate, precision, recall, f1, kappa,
--                 ap_bbox, recall_bbox, ap_segm, recall_segm,
--                 mean_errors, nb_errors, …
CREATE TABLE metric (
    id               BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    model_version_id BIGINT           NOT NULL REFERENCES model_version(id) ON DELETE CASCADE,
    test_run_id      BIGINT           REFERENCES test_run(id) ON DELETE CASCADE,
    scope            metric_scope     NOT NULL,
    name             TEXT             NOT NULL,
    value            DOUBLE PRECISION NOT NULL,
    CONSTRAINT ck_metric_scope CHECK (
        (scope = 'validation' AND test_run_id IS NULL) OR
        (scope = 'test'       AND test_run_id IS NOT NULL)
    )
);

-- Unicité : une métrique par nom et par contexte.
CREATE UNIQUE INDEX ux_metric_validation
    ON metric (model_version_id, name) WHERE test_run_id IS NULL;
CREATE UNIQUE INDEX ux_metric_test
    ON metric (test_run_id, name) WHERE test_run_id IS NOT NULL;

-- Remplace : Classification_Test, Decoupage_Test, Detection_Test,
--            Segmentation_Test, Extraction_Test
-- (résultats d'inférence sur un document — les 5 tables étaient identiques).
-- model_version_id est nullable car les anciennes tables ne traçaient pas le
-- modèle utilisé ; à renseigner pour les nouvelles inférences.
CREATE TABLE inference_request (
    id               BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    task_type        model_type  NOT NULL,
    model_version_id BIGINT      REFERENCES model_version(id) ON DELETE SET NULL,
    doc_id           TEXT        NOT NULL,
    status_code      INT,
    res_message      TEXT,
    res_content      JSONB,
    end_status       TEXT,
    created_at       TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX ix_inference_request_doc  ON inference_request (doc_id);
CREATE INDEX ix_inference_request_type ON inference_request (task_type, created_at);

-- ----------------------------------------------------------------------------
-- 3. Référentiel documentaire
-- ----------------------------------------------------------------------------

-- Remplace : DocumentClass (préfixes de colonnes supprimés, audit normalisé)
CREATE TABLE document_class (
    id          BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    name        TEXT        NOT NULL UNIQUE,
    description TEXT,
    created_by  TEXT        NOT NULL,
    created_at  TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_by  TEXT,
    updated_at  TIMESTAMPTZ
);

-- Remplace : DocumentField
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

-- Remplace : DocumentProperty
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
-- 4. Associations version de modèle <-> référentiel documentaire
--    (l'ancien IdModel des tables d'association était redondant :
--     model_version connaît déjà son modèle)
-- ----------------------------------------------------------------------------

-- Remplace : DocumentClassProjects
CREATE TABLE model_version_document_class (
    model_version_id  BIGINT NOT NULL REFERENCES model_version(id)  ON DELETE CASCADE,
    document_class_id BIGINT NOT NULL REFERENCES document_class(id) ON DELETE CASCADE,
    PRIMARY KEY (model_version_id, document_class_id)
);

-- Remplace : DocumentFieldProjects
CREATE TABLE model_version_document_field (
    model_version_id  BIGINT NOT NULL REFERENCES model_version(id)  ON DELETE CASCADE,
    document_field_id BIGINT NOT NULL REFERENCES document_field(id) ON DELETE CASCADE,
    PRIMARY KEY (model_version_id, document_field_id)
);

-- Remplace : DocumentPropertyProjects
CREATE TABLE model_version_document_property (
    model_version_id     BIGINT NOT NULL REFERENCES model_version(id)     ON DELETE CASCADE,
    document_property_id BIGINT NOT NULL REFERENCES document_property(id) ON DELETE CASCADE,
    PRIMARY KEY (model_version_id, document_property_id)
);

-- ----------------------------------------------------------------------------
-- 5. Demandes documentaires
-- ----------------------------------------------------------------------------

-- Remplace : DocumentRequest (préfixes de colonnes supprimés, audit normalisé)
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
