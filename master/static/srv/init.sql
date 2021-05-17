--
-- PostgreSQL database dump
--

-- Dumped from database version 10.14 (Debian 10.14-1.pgdg90+1)
-- Dumped by pg_dump version 13.2

SET statement_timeout = 0;
SET lock_timeout = 0;
SET idle_in_transaction_session_timeout = 0;
SET client_encoding = 'UTF8';
SET standard_conforming_strings = on;
SELECT pg_catalog.set_config('search_path', '', false);
SET check_function_bodies = false;
SET xmloption = content;
SET client_min_messages = warning;
SET row_security = off;

--
-- Name: checkpoint_state; Type: TYPE; Schema: public; Owner: postgres
--

CREATE TYPE public.checkpoint_state AS ENUM (
    'ACTIVE',
    'COMPLETED',
    'ERROR',
    'DELETED'
);


ALTER TYPE public.checkpoint_state OWNER TO postgres;

--
-- Name: experiment_state; Type: TYPE; Schema: public; Owner: postgres
--

CREATE TYPE public.experiment_state AS ENUM (
    'ACTIVE',
    'CANCELED',
    'COMPLETED',
    'ERROR',
    'PAUSED',
    'STOPPING_CANCELED',
    'STOPPING_COMPLETED',
    'STOPPING_ERROR'
);


ALTER TYPE public.experiment_state OWNER TO postgres;

--
-- Name: step_state; Type: TYPE; Schema: public; Owner: postgres
--

CREATE TYPE public.step_state AS ENUM (
    'ACTIVE',
    'COMPLETED',
    'ERROR'
);


ALTER TYPE public.step_state OWNER TO postgres;

--
-- Name: trial_state; Type: TYPE; Schema: public; Owner: postgres
--

CREATE TYPE public.trial_state AS ENUM (
    'ACTIVE',
    'CANCELED',
    'COMPLETED',
    'ERROR'
);


ALTER TYPE public.trial_state OWNER TO postgres;

--
-- Name: validation_state; Type: TYPE; Schema: public; Owner: postgres
--

CREATE TYPE public.validation_state AS ENUM (
    'ACTIVE',
    'COMPLETED',
    'ERROR'
);


ALTER TYPE public.validation_state OWNER TO postgres;

SET default_tablespace = '';

--
-- Name: checkpoints; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.checkpoints (
    id integer NOT NULL,
    trial_id integer NOT NULL,
    state public.checkpoint_state NOT NULL,
    start_time timestamp with time zone NOT NULL,
    end_time timestamp with time zone,
    uuid uuid,
    resources jsonb,
    metadata jsonb,
    format character varying,
    framework character varying,
    determined_version character varying,
    total_batches integer DEFAULT 0 NOT NULL
);


ALTER TABLE public.checkpoints OWNER TO postgres;

--
-- Name: best_checkpoint_by_metric(integer, text, boolean); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.best_checkpoint_by_metric(tid integer, metric text, smaller_is_better boolean) RETURNS SETOF public.checkpoints
    LANGUAGE sql STABLE
    AS $$
    SELECT c.*
    FROM checkpoints c JOIN validations v ON (c.trial_id, c.step_id) = (v.trial_id, v.step_id)
    WHERE c.trial_id = tid AND c.state = 'COMPLETED' AND v.state = 'COMPLETED'
    ORDER BY (SELECT CASE WHEN smaller_is_better THEN 1 ELSE -1 END) * (v.metrics->'validation_metrics'->>metric)::float8 ASC
    LIMIT 1
$$;


ALTER FUNCTION public.best_checkpoint_by_metric(tid integer, metric text, smaller_is_better boolean) OWNER TO postgres;

--
-- Name: experiments; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.experiments (
    id integer NOT NULL,
    state public.experiment_state NOT NULL,
    config jsonb NOT NULL,
    model_definition bytea NOT NULL,
    start_time timestamp with time zone NOT NULL,
    end_time timestamp with time zone,
    model_packages bytea,
    archived boolean DEFAULT false NOT NULL,
    git_remote character varying,
    git_commit character varying,
    git_committer character varying,
    git_commit_date timestamp without time zone,
    parent_id integer,
    owner_id integer NOT NULL,
    progress double precision,
    hpimportance jsonb,
    original_config text
);


ALTER TABLE public.experiments OWNER TO postgres;

--
-- Name: experiments_best_checkpoints_by_metric(public.experiments, text, boolean, integer); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.experiments_best_checkpoints_by_metric(exp public.experiments, metric text, smaller_is_better boolean, lim integer) RETURNS SETOF public.checkpoints
    LANGUAGE sql STABLE
    AS $$
    WITH const AS (
        SELECT
            coalesce(smaller_is_better, (exp.config->'searcher'->>'smaller_is_better')::boolean, true) AS smaller_is_better,
            coalesce(metric, exp.config->'searcher'->>'metric') AS metric
    )
    SELECT c.*
    FROM (
        SELECT c.*
        FROM const, trials t, LATERAL best_checkpoint_by_metric(t.id, const.metric, const.smaller_is_better) c WHERE t.experiment_id = exp.id
    ) c, validations v, const WHERE (c.trial_id, c.step_id) = (v.trial_id, v.step_id)
    ORDER BY (SELECT CASE WHEN const.smaller_is_better THEN 1 ELSE -1 END) * (v.metrics->'validation_metrics'->>const.metric)::float8 ASC
    LIMIT lim
$$;


ALTER FUNCTION public.experiments_best_checkpoints_by_metric(exp public.experiments, metric text, smaller_is_better boolean, lim integer) OWNER TO postgres;

--
-- Name: validations; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.validations (
    id integer NOT NULL,
    trial_id integer NOT NULL,
    state public.validation_state NOT NULL,
    start_time timestamp with time zone NOT NULL,
    end_time timestamp with time zone,
    metrics jsonb,
    total_batches integer DEFAULT 0 NOT NULL
);


ALTER TABLE public.validations OWNER TO postgres;

--
-- Name: experiments_best_validation_history(public.experiments); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.experiments_best_validation_history(e public.experiments) RETURNS SETOF public.validations
    LANGUAGE sql STABLE
    AS $$
    WITH is_best AS (
        SELECT v.id,
               coalesce(
                   get_signed_metric(v, e) < min(get_signed_metric(v, e))
                   OVER (
                       PARTITION BY e.id
                       ORDER BY v.end_time ASC
                       ROWS BETWEEN UNBOUNDED PRECEDING AND 1 PRECEDING
                   ),
                   true
               ) AS is_best
        FROM trials t, validations v
        WHERE e.id = t.experiment_id AND t.id = v.trial_id AND v.state = 'COMPLETED'
    )
    SELECT v.* FROM validations v, is_best WHERE v.id = is_best.id AND is_best.is_best
$$;


ALTER FUNCTION public.experiments_best_validation_history(e public.experiments) OWNER TO postgres;

--
-- Name: get_raw_metric(public.validations, public.experiments); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.get_raw_metric(v public.validations, e public.experiments) RETURNS double precision
    LANGUAGE sql STABLE
    AS $$
    SELECT (v.metrics->'validation_metrics'->>(e.config->'searcher'->>'metric'))::float8
$$;


ALTER FUNCTION public.get_raw_metric(v public.validations, e public.experiments) OWNER TO postgres;

--
-- Name: get_signed_metric(public.validations, public.experiments); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.get_signed_metric(v public.validations, e public.experiments) RETURNS double precision
    LANGUAGE sql STABLE
    AS $$
    SELECT get_raw_metric(v, e) * (
        SELECT
        CASE
            WHEN coalesce((e.config->'searcher'->>'smaller_is_better')::boolean, true)
            THEN 1
            ELSE -1
        END)
$$;


ALTER FUNCTION public.get_signed_metric(v public.validations, e public.experiments) OWNER TO postgres;

--
-- Name: page_info(bigint, integer, integer); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.page_info(total bigint, "offset" integer, "limit" integer) RETURNS json
    LANGUAGE sql IMMUTABLE
    AS $$
WITH start_index AS (
    SELECT (CASE WHEN "offset" < -total OR "offset" > total THEN total
                 WHEN "offset" < 0 THEN total + "offset"
                 ELSE "offset" END) AS start_index
), end_index AS (
    SELECT (CASE WHEN "limit" = -2 THEN (SELECT start_index FROM start_index)
                 WHEN "limit" = -1 THEN total
                 WHEN "limit" = 0 THEN least(100::bigint + (SELECT start_index FROM start_index), total)
                 WHEN (SELECT start_index FROM start_index) + "limit" > total THEN total
                 ELSE (SELECT start_index FROM start_index) + "limit" END) AS end_index
), page_info AS (
    SELECT
        total AS total,
        "offset" AS "offset",
        "limit" AS "limit",
        (SELECT start_index FROM start_index) AS start_index,
        (SELECT end_index FROM end_index) AS end_index)
SELECT row_to_json(p)
FROM page_info p
$$;


ALTER FUNCTION public.page_info(total bigint, "offset" integer, "limit" integer) OWNER TO postgres;

--
-- Name: try_float8_cast(text); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.try_float8_cast(text) RETURNS double precision
    LANGUAGE sql IMMUTABLE STRICT
    AS $_$
            SELECT
                CASE
                    WHEN $1 ~ e'^-?(?:0|[1-9]\\d*)'
                               '(?:\\.\\d+)?(?:[eE][+-]?\\d+)?$' THEN
                        $1::float8
                END;
        $_$;


ALTER FUNCTION public.try_float8_cast(text) OWNER TO postgres;

--
-- Name: agent_user_groups; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.agent_user_groups (
    id integer NOT NULL,
    user_id integer NOT NULL,
    user_ text NOT NULL,
    uid integer NOT NULL,
    group_ text NOT NULL,
    gid integer NOT NULL
);


ALTER TABLE public.agent_user_groups OWNER TO postgres;

--
-- Name: agent_user_groups_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.agent_user_groups_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.agent_user_groups_id_seq OWNER TO postgres;

--
-- Name: agent_user_groups_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public.agent_user_groups_id_seq OWNED BY public.agent_user_groups.id;


--
-- Name: auth_token_keypair; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.auth_token_keypair (
    public_key bytea NOT NULL,
    private_key bytea NOT NULL
);


ALTER TABLE public.auth_token_keypair OWNER TO postgres;

--
-- Name: checkpoints_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

ALTER TABLE public.checkpoints ALTER COLUMN id ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME public.checkpoints_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: cluster_id; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.cluster_id (
    cluster_id text NOT NULL
);


ALTER TABLE public.cluster_id OWNER TO postgres;

--
-- Name: config_files; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.config_files (
    id integer NOT NULL,
    content bytea
);


ALTER TABLE public.config_files OWNER TO postgres;

--
-- Name: config_files_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.config_files_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.config_files_id_seq OWNER TO postgres;

--
-- Name: config_files_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public.config_files_id_seq OWNED BY public.config_files.id;


--
-- Name: experiment_snapshots; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.experiment_snapshots (
    id integer NOT NULL,
    experiment_id integer NOT NULL,
    content jsonb NOT NULL,
    version integer NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL
);


ALTER TABLE public.experiment_snapshots OWNER TO postgres;

--
-- Name: experiment_snapshots_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.experiment_snapshots_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.experiment_snapshots_id_seq OWNER TO postgres;

--
-- Name: experiment_snapshots_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public.experiment_snapshots_id_seq OWNED BY public.experiment_snapshots.id;


--
-- Name: experiments_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

ALTER TABLE public.experiments ALTER COLUMN id ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME public.experiments_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: model_versions; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.model_versions (
    version integer NOT NULL,
    model_name character varying NOT NULL,
    checkpoint_uuid uuid NOT NULL,
    creation_time timestamp with time zone NOT NULL,
    last_updated_time timestamp with time zone,
    metadata jsonb
);


ALTER TABLE public.model_versions OWNER TO postgres;

--
-- Name: models; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.models (
    name character varying NOT NULL,
    description character varying,
    creation_time timestamp with time zone NOT NULL,
    last_updated_time timestamp with time zone,
    metadata jsonb
);


ALTER TABLE public.models OWNER TO postgres;

--
-- Name: resource_aggregates; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.resource_aggregates (
    date date NOT NULL,
    aggregation_type text NOT NULL,
    aggregation_key text NOT NULL,
    seconds double precision NOT NULL
);


ALTER TABLE public.resource_aggregates OWNER TO postgres;

--
-- Name: schema_migrations; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.schema_migrations (
    version bigint NOT NULL,
    dirty boolean NOT NULL
);


ALTER TABLE public.schema_migrations OWNER TO postgres;

--
-- Name: steps; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.steps (
    trial_id integer NOT NULL,
    id integer NOT NULL,
    state public.step_state NOT NULL,
    start_time timestamp with time zone NOT NULL,
    end_time timestamp with time zone,
    metrics jsonb,
    total_batches integer DEFAULT 0 NOT NULL
);


ALTER TABLE public.steps OWNER TO postgres;

--
-- Name: task_sessions_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.task_sessions_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.task_sessions_id_seq OWNER TO postgres;

--
-- Name: task_sessions; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.task_sessions (
    id integer DEFAULT nextval('public.task_sessions_id_seq'::regclass) NOT NULL,
    task_id uuid NOT NULL
);


ALTER TABLE public.task_sessions OWNER TO postgres;

--
-- Name: templates; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.templates (
    name character varying NOT NULL,
    config jsonb NOT NULL
);


ALTER TABLE public.templates OWNER TO postgres;

--
-- Name: trial_logs; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.trial_logs (
    trial_id integer NOT NULL,
    message bytea NOT NULL,
    agent_id text,
    container_id text,
    rank_id smallint,
    log bytea,
    "timestamp" timestamp without time zone,
    level text,
    source text,
    stdtype text,
    id bigint NOT NULL
);


ALTER TABLE public.trial_logs OWNER TO postgres;

--
-- Name: trial_logs_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

ALTER TABLE public.trial_logs ALTER COLUMN id ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME public.trial_logs_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: trial_profiler_metrics; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.trial_profiler_metrics (
    id bigint NOT NULL,
    "values" real[] NOT NULL,
    batches integer[] NOT NULL,
    ts timestamp with time zone[] NOT NULL,
    labels jsonb DEFAULT '{}'::jsonb NOT NULL
);


ALTER TABLE public.trial_profiler_metrics OWNER TO postgres;

--
-- Name: trial_profiler_metrics_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.trial_profiler_metrics_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.trial_profiler_metrics_id_seq OWNER TO postgres;

--
-- Name: trial_profiler_metrics_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public.trial_profiler_metrics_id_seq OWNED BY public.trial_profiler_metrics.id;


--
-- Name: trial_snapshots; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.trial_snapshots (
    id integer NOT NULL,
    trial_id integer NOT NULL,
    request_id bytea NOT NULL,
    experiment_id integer NOT NULL,
    content jsonb NOT NULL,
    version integer NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL
);


ALTER TABLE public.trial_snapshots OWNER TO postgres;

--
-- Name: trial_snapshots_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.trial_snapshots_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.trial_snapshots_id_seq OWNER TO postgres;

--
-- Name: trial_snapshots_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public.trial_snapshots_id_seq OWNED BY public.trial_snapshots.id;


--
-- Name: trials; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.trials (
    id integer NOT NULL,
    experiment_id integer NOT NULL,
    state public.trial_state NOT NULL,
    start_time timestamp with time zone NOT NULL,
    end_time timestamp with time zone,
    hparams jsonb NOT NULL,
    warm_start_checkpoint_id integer,
    seed integer DEFAULT 0 NOT NULL,
    request_id text,
    best_validation_id integer
);


ALTER TABLE public.trials OWNER TO postgres;

--
-- Name: trials_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

ALTER TABLE public.trials ALTER COLUMN id ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME public.trials_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: user_sessions; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.user_sessions (
    id integer NOT NULL,
    user_id integer NOT NULL,
    expiry timestamp without time zone NOT NULL
);


ALTER TABLE public.user_sessions OWNER TO postgres;

--
-- Name: user_sessions_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.user_sessions_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.user_sessions_id_seq OWNER TO postgres;

--
-- Name: user_sessions_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public.user_sessions_id_seq OWNED BY public.user_sessions.id;


--
-- Name: users; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.users (
    id integer NOT NULL,
    username text NOT NULL,
    password_hash text,
    admin boolean DEFAULT false,
    active boolean DEFAULT false
);


ALTER TABLE public.users OWNER TO postgres;

--
-- Name: users_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.users_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.users_id_seq OWNER TO postgres;

--
-- Name: users_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public.users_id_seq OWNED BY public.users.id;


--
-- Name: validation_metrics; Type: VIEW; Schema: public; Owner: postgres
--

CREATE VIEW public.validation_metrics AS
 SELECT v.id,
    public.get_raw_metric(v.*, e.*) AS raw,
    public.get_signed_metric(v.*, e.*) AS signed
   FROM public.experiments e,
    public.trials t,
    public.validations v
  WHERE ((e.id = t.experiment_id) AND (t.id = v.trial_id));


ALTER TABLE public.validation_metrics OWNER TO postgres;

--
-- Name: validations_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

ALTER TABLE public.validations ALTER COLUMN id ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME public.validations_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: agent_user_groups id; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.agent_user_groups ALTER COLUMN id SET DEFAULT nextval('public.agent_user_groups_id_seq'::regclass);


--
-- Name: config_files id; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.config_files ALTER COLUMN id SET DEFAULT nextval('public.config_files_id_seq'::regclass);


--
-- Name: experiment_snapshots id; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.experiment_snapshots ALTER COLUMN id SET DEFAULT nextval('public.experiment_snapshots_id_seq'::regclass);


--
-- Name: trial_profiler_metrics id; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.trial_profiler_metrics ALTER COLUMN id SET DEFAULT nextval('public.trial_profiler_metrics_id_seq'::regclass);


--
-- Name: trial_snapshots id; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.trial_snapshots ALTER COLUMN id SET DEFAULT nextval('public.trial_snapshots_id_seq'::regclass);


--
-- Name: user_sessions id; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.user_sessions ALTER COLUMN id SET DEFAULT nextval('public.user_sessions_id_seq'::regclass);


--
-- Name: users id; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.users ALTER COLUMN id SET DEFAULT nextval('public.users_id_seq'::regclass);


--
-- Data for Name: agent_user_groups; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.agent_user_groups (id, user_id, user_, uid, group_, gid) FROM stdin;
\.


--
-- Data for Name: auth_token_keypair; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.auth_token_keypair (public_key, private_key) FROM stdin;
\\x3c8e7fc8fd0545efc9e39f97f63d7de0d08afa3836c6613e2f5648427d595b77	\\x4190d333edad7d4c8a67544272853e72e0fb2df13f3904a24da2ef2cc4edafd33c8e7fc8fd0545efc9e39f97f63d7de0d08afa3836c6613e2f5648427d595b77
\.


--
-- Data for Name: checkpoints; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.checkpoints (id, trial_id, state, start_time, end_time, uuid, resources, metadata, format, framework, determined_version, total_batches) FROM stdin;
\.


--
-- Data for Name: cluster_id; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.cluster_id (cluster_id) FROM stdin;
b729cd5b-bd26-47e0-8d8f-097fce8ac8a4
\.


--
-- Data for Name: config_files; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.config_files (id, content) FROM stdin;
\.


--
-- Data for Name: experiment_snapshots; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.experiment_snapshots (id, experiment_id, content, version, created_at, updated_at) FROM stdin;
\.


--
-- Data for Name: experiments; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.experiments (id, state, config, model_definition, start_time, end_time, model_packages, archived, git_remote, git_commit, git_committer, git_commit_date, parent_id, owner_id, progress, hpimportance, original_config) FROM stdin;
1	ERROR	{"debug": false, "internal": null, "searcher": {"name": "single", "metric": "validation_error", "max_length": {"batches": 3000}, "source_trial_id": null, "smaller_is_better": true, "source_checkpoint_uuid": null}, "profiling": {"enabled": false, "begin_on_batch": 0, "end_after_batch": 0}, "resources": {"weight": 1, "devices": null, "agent_label": "", "resource_pool": "default", "native_parallel": false, "slots_per_trial": 1}, "data_layer": {"type": "shared_fs", "container_storage_path": null}, "entrypoint": "model_def:NoOpTrial", "description": "noop_single", "environment": {"image": {"cpu": "determinedai/environments:py-3.7-pytorch-1.7-tf-1.15-cpu-baefbf7", "gpu": "determinedai/environments:cuda-10.2-pytorch-1.7-tf-1.15-gpu-baefbf7"}, "ports": null, "pod_spec": null, "add_capabilities": null, "force_pull_image": false, "drop_capabilities": null, "environment_variables": {}}, "max_restarts": 0, "optimizations": {"mixed_precision": "O0", "gradient_compression": false, "aggregation_frequency": 1, "auto_tune_tensor_fusion": false, "tensor_fusion_threshold": 64, "average_training_metrics": false, "tensor_fusion_cycle_time": 5, "average_aggregated_gradients": true}, "hyperparameters": {"metrics_base": {"val": 0.9, "type": "const"}, "metrics_sigma": {"val": 0, "type": "const"}, "global_batch_size": {"val": 32, "type": "const"}, "metrics_progression": {"val": "decreasing", "type": "const"}}, "reproducibility": {"experiment_seed": 999}, "scheduling_unit": 100, "checkpoint_policy": "best", "records_per_epoch": 0, "checkpoint_storage": {"type": "shared_fs", "host_path": "/tmp", "storage_path": "determined-integration-checkpoints", "save_trial_best": 30, "save_trial_latest": 1, "save_experiment_best": 0}, "min_checkpoint_period": {"batches": 100}, "min_validation_period": {"batches": 100}, "perform_initial_validation": false}	\\x1f8b08000000000000ffec5ddd73dbb811f7b3fe0a947da17c1243eab3d19c6f9a499db99b5e939b5ea62f698607912b096712e001a06c3593ffbd0390e23725db9195e4c27db1252e171fdcfde1b74b905a7baeb701ef2662844ae112ea71c082d0b5b5c361707112b11ddb9e4d26177622d5bff6dc1e5f38e3b9339dd9ce6436bdb09de97834bb40f6699a3f2cb190985fd89fdc5675705f89f8203c4e2249185d20ca58e4563c428c0b4ed1cb8fb842328ed7b0e82124f0165cb88b809310a8749720e4028df74724273870032cf5d7a3de6617018f30c72148e0425958076c89037789a5b77105f91f2cd078d44388c6a12b392694d0b51b82e4c4130b34ed21947e7023ced61c84d00328f45400e6de06f822d35da02d0e888fd5585de09c71d5c1100701709708770952025f20c963504de3101648d90ad4c710dfb901d0b5dc288b08e9ae825820c7b6ed5e48a85bb0ae6682f94ab1a8a6b50a33d8a685ef5c0eca2da55820bb0754f29d3e638142e643e0fab05abc666fa2b76a627b9f74fd93f10d1985a1d8302e87424274c2d8bf381eff8e3db32bf13f19db932efecf21f5f84f3dbe39d2e52e5241b1c11c7c77257a086d98906e84e566819ec930522195a8a75ffa2ac64342c11f122a61cd75840c0b10538689143bec87a0442316f8906141aeb1c40216c8b69e17be13641d621568c2db801f070a6a624ae402396745911e8788333ff6c8920444ee944601540580bf40cf9f3fff7ac1a6932f4e52fcdf02df0d434c77c380d1b55e04c4c95681a3fc6fe254f9df6432eaf0ff1c52c3ffe1018f38e7a2500763fb416b42c61ad323e031ea2b88b3ec32ac5711fa31287f901c7ed1ec30bdda21f8240e877ad24e4e018ff2bf7935fe27f3d9b88bff73483dfe5357504e70ce787f3abaa72332e9b3cfe2a58e72844242b7385078304d3ee3bbf473233744e8afe81a7b1ba4e605dd92204012df808293294ac1053d4b42155daa48dd872dba4299c6615c9a3e12975ad167fa1052d911c16f5138a63e0b4f9cf057e418ff9bcea615fc7726a37987ffe7907afe9f78c4170afd6df5c013e5e9e9d81348d5f508a16b114730f62bc6ce3527fe70cdb107ab3818ea210f930ba667ee24c07034ff9b55f9df6c3cb2bbf83f8794e25f3983bb7786b41e5770862f14131e5efd9b36333c0e7fc420f4d8a2226bf4b08435e3c4c381fe76ab61e1dd5b1ec300bdc28180f70dcc4d4de62379dbe47cbc2dcdff7c58e1389043ef2692272703c7e27f369dabf89fdab3d1683eb355fe673b5dfe771669adff77e5f76fa2fc8e7d1c49b205d7db6076ba926f498ed67f9cd98533b1c7b3b93d9bcdc617b633769ceefedf59a41eff658ff873acf9272a01e919516d2e718a11c8b6ecc6ba4d368b586cf0711a70bf5c6336b11fcd0cf43685af2831e9e42ca2dd238e861bc66e2cb17992368ef13f6732bd70c6b399339e8eedf1e8c27646a349c7ffce22e06d1832784c29a16b54f18601bae5444a75045304612477684502409221eb595179c831357a3dc9625d222f1fe860e5cb95ca6ebf7c09fdccfb3f9daefe7316b9cffecf02affac2f77f167adaedffbc97a4f51f42871c3cc6fda748018fc67fedfeff7832eff6ff9c45bafd9f8502d41343461a610bf4b707a5716dd09299d359e12351c3750925d275ad68f7643e762cfed5ff65feef8c27ddf31f67911cff2162dee6492a80c7f7ff8faaf8dfedff3f9374f87f3efc4f224c31e0fb627f0af10af45d7d76ba767cb574b3932f4cb22bfc8404e030fe3bb3d17cacefff8c27d3d1683e53ebff74dae1ff59848411e312792c08c05360227ae957bf0b46f7ff076cbd56409a7e649992c2f8802cf71fd3fd53e9274942e8ad380bd5b241e81aa5dfbfa0bb01fa07f1e400bdd12b0f0e7afb73681c463b8405a251f65dbe84a8033ec8c468e1eb5471c338db32bf7ad8f2581832bad7d290d8ebf5bc000b8132607bc9a8e46a1ab8e983b45ee2205862efa672ac9f40b96118faef0ba4572d94d8badd106f837c06025126376ac826dc791049b4621c8578b704240280a88ffc98abe3fbe286b686a95f58702c845e318e24085d818d621e3101c2ca3aa0ff79f9e3f5cb7ffef2e6a7d76fdd573ffd7cfdfac5bfaed115322873595440ff54db8715da537e5340b01aa04bccd762915c94cbcb9bdbec631f0d7f40af194d6f9f29117104dcec5b99097d727e5ebf97a9eaa6ddb414ec6e18bb7139a6e80aa9562da05b6ba3177761ad419a46b3ba91eeafe96766c9aac572dec9ac754b2dcb261396f2528b881509c0346a65ebfe0019af4800486c581cf808ee8890c2320a83d17dd677ffd055eae4d6af3b2121fcb7fe60f6cbaa058ab21fb1c7a8843ba946ab977311305950ab5aa8dd6a3c3073154d6380ec63d692a2dafd6d26fac651b3a9f7c2032cef4f396e3cf7e607982f8440a581152681cba8bb225cc8029d6a35de76823140469b71d5fc26a5d178db3e2f2dfa4da60bc44f802c3959cd6c83ae3140e311ba44e351c5aebec4f96309a2d568f3230c0d6e576abddd602972cb5d4e2d97345a27e1b2651ccf6a41991bacf4b8a9dedc3a0f4dcac60039b94d2c047079c0f40f7a5f41a50385b1dda70b75f5c39d68305feb864ec80e3a81d6282689ad5e1030ec1fb6a535cab69a0c35a479ad261b74552ce549a1d13c414d6d108a4c237fb544c5ce00191ea342e23ac214b3cea33d554a6ad0d6f35acf6cf47d83c1ef91d3dc9c4e688fb6a7b57483765383570d36cbcddd7222c1a57110b4b695abe42b79d94871cf6dab99a2528321b22a389a5aeb111115e2520639f05dfd3c2bba2a125feb258ba954fc263b0d02d164443564969b4cbbf37721b1245e0872c3fc8c71293e9a9437cca4c841a890ba3462697a798c84658a390fcd7bc541c69c36f2d86676d6dcc788830b77e0c51234a732816e932e5ed3edcb84bc0cd066ebbb1ea32bb25eecd9b6f563f237d569608d34b252ce24007c65d84aa6417dece7c4545f1337bd427a7eb53142656db4220ecdfaf554ab420cc2ec178c7a31e740650a75b9d555c070c12e6544c768de57ca7888033360de956dd903243c1cc05543a05d5ea251bfe68c8d607555c08ab25fedc7558bf2ef92ae155cf2580b056cba671b97e9ca59be00fd47b45d40c9c6b61d3444e6bd3bd0d4836a4072ac2edc7fd485bfe69c71d3f889ea150efdd6d0c9dfd0878f86b55297569a6d2329ba4f4226568c6b0f4b5326f5af4bfc8572cd81be479d55d4084d2240a5b7ef84e40315c4ef1735f7a83f6b5042987db6a0b98d64919bea836fbee5313452654521630ee621c69f9fa892734be7a266336bba2c0eaceedf39b497bb7f4be406b108a8693cf361fb4c489fc552ad92b74ba3af12f855f90425a9397369fcf7ceb6abcb6829c6dfa593ff1e7d7755580073a2f421adc2ea5928077f5fa7e1eab85ad3df1901138a675ce6ad14b899d97fffb1003b22625423c487325ddd53ae042b6349022bc4379059a98db5962096267a80dea567be2f1f28d9e99719b151761163514f392b4e5430f0b18aadfbb116309485915a17eaccb12120eee5fe6da954536c5feb0a0a61d43c78ea6362629f7bb687452585e937395ca9cff7f7beeaad85cc131ba6b9ffbef17a1d77ca0f46437ab0d8f77e8074064168144bb1779b86d4eae379fdad168ad9aadde657a9a90fe9c8dd02ca93fe42f3113dfb444d3dc7740da63368cfcbfa1ff3ceb438fdbdbad39ad93eae9bf5aef40bd39af5b850553a4ca22a48546062780b69682777f1d23aaff58ba2ba7586570deb4a15e301515d39f331419d2792ed619de5b7a5858db2a4a26d252540b35feeb83e14def8849b1156912dae926700b5bacb6eaeca6bf34ae72257c979bf3342d53f49fb0d55dbfcbcb4da6e11ba62a6f12bde12ba4685e2d7878f8332572e921adde8a0994ee54de8555aab5ac95a7ddbb836ff2e18b5fc388c1ac8f60029e0675cba37b0dbcf04a13e507935c95bd26d789b90f9a6cde6f379657aca873207cc32ac7b3ae069bd23ab587cfab5ac4d346f9ee825f3770ac70995e64d7f81b61a076e0668aba0405f073d27abbe452484c2ec7f2c1928692b637bb53ad94a6ae36be9c21fe64da9ca52d620c295bb08cced009566abc9ceb666e7ded9b6ee6df9dc5200d4da357e66d807ff241151665505c65373a5012a3df7b3bf71f54ee791ef9b31b158be6f2c4934d4f76b1e5b03d9e4493d9ede7840df973a7610698d973fbe78f3eb5fd0b5cef315aa2456503a507dcfa37a5fccccaa0fa92f25b9bb979519dce484aba61244eb5da7942b2ccab58de6fa41915c6827d2ff751b114e21fbe7d49ef20d3047f7ff4eedcaf39fcebc7bfee73cd2fefc67f7e467e3c6b0a77dbcf3ecafeb8a96a77fdf43558eedff74a693cafe4f7bdebdffe93c528fff6829bbd03f10fa6a7e0e067cc4a23848eb27baf3ca7012f07ae7076731f5aba16fdbe9d34efaa8489e9ee21005d8037715532faf8e491e530f4b70571c275f23db1a254011305e55e720701805507d6e7da48f46c065cc97ee0a7b92f1e4fbee9581df8e249b953febfbff1c7b3cabbfffaf7bfeeb2cd2edff3fdffeff0cedc72779feabdbebdfc9274be98d0f4fb40a1ce5ffa37905ff4733bbc3ffb3c8e7c27f09428ae1defb923e342d04ce675807da36af2fd05b85f3dd7beaba85e34f23fbdf7f78a29f7ed172b4fe3baebeff65329975ef7f398bb4fefe4bf7d32f9ff8d32fa3afe241ddf46aeb0bfd34bffe720ffee7d47eff65329e76f17f0e698dff8a477c8bf5807624e9185fc7f83ae9a4934ebe6ef97f000000ffffc13cfb0e007e0000	2021-05-11 23:09:51.979907+00	2021-05-11 23:10:01.425591+00	\N	f	\N	\N	\N	\N	\N	2	\N	\N	checkpoint_storage: {host_path: /tmp, save_trial_best: 30, storage_path: determined-integration-checkpoints,\n  type: shared_fs}\ndescription: noop_single\nentrypoint: model_def:NoOpTrial\nhyperparameters: {global_batch_size: 32, metrics_base: 0.9, metrics_progression: decreasing,\n  metrics_sigma: 0}\nmax_restarts: 0\nmin_checkpoint_period: {batches: 100}\nmin_validation_period: {batches: 100}\nreproducibility: {experiment_seed: 999}\nsearcher:\n  max_length: {batches: 3000}\n  metric: validation_error\n  name: single\n  smaller_is_better: true\n
2	ERROR	{"debug": false, "internal": null, "searcher": {"name": "single", "metric": "validation_error", "max_length": {"batches": 3000}, "source_trial_id": null, "smaller_is_better": true, "source_checkpoint_uuid": null}, "profiling": {"enabled": false, "begin_on_batch": 0, "end_after_batch": 0}, "resources": {"weight": 1, "devices": null, "agent_label": "", "resource_pool": "default", "native_parallel": false, "slots_per_trial": 1}, "data_layer": {"type": "shared_fs", "container_storage_path": null}, "entrypoint": "model_def:NoOpTrial", "description": "noop_single", "environment": {"image": {"cpu": "determinedai/environments:py-3.7-pytorch-1.7-tf-1.15-cpu-baefbf7", "gpu": "determinedai/environments:cuda-10.2-pytorch-1.7-tf-1.15-gpu-baefbf7"}, "ports": null, "pod_spec": null, "add_capabilities": null, "force_pull_image": false, "drop_capabilities": null, "environment_variables": {}}, "max_restarts": 0, "optimizations": {"mixed_precision": "O0", "gradient_compression": false, "aggregation_frequency": 1, "auto_tune_tensor_fusion": false, "tensor_fusion_threshold": 64, "average_training_metrics": false, "tensor_fusion_cycle_time": 5, "average_aggregated_gradients": true}, "hyperparameters": {"metrics_base": {"val": 0.9, "type": "const"}, "metrics_sigma": {"val": 0, "type": "const"}, "global_batch_size": {"val": 32, "type": "const"}, "metrics_progression": {"val": "decreasing", "type": "const"}}, "reproducibility": {"experiment_seed": 999}, "scheduling_unit": 100, "checkpoint_policy": "best", "records_per_epoch": 0, "checkpoint_storage": {"type": "shared_fs", "host_path": "/tmp", "storage_path": "determined-integration-checkpoints", "save_trial_best": 30, "save_trial_latest": 1, "save_experiment_best": 0}, "min_checkpoint_period": {"batches": 100}, "min_validation_period": {"batches": 100}, "perform_initial_validation": false}	\\x1f8b08000000000000ffec5ddd73dbb811f7b3fe0a947da17c1243eab3d19c6f9a499db99b5e939b5ea62f698607912b096712e001a06c3593ffbd0390e23725db9195e4c27db1252e171fdcfde1b74b905a7baeb701ef2662844ae112ea71c082d0b5b5c361707112b11ddb9e4d26177622d5bff6dc1e5f38e3b9339dd9ce6436bdb09de97834bb40f6699a3f2cb190985fd89fdc5675705f89f8203c4e2249185d20ca58e4563c428c0b4ed1cb8fb842328ed7b0e82124f0165cb88b809310a8749720e4028df74724273870032cf5d7a3de6617018f30c72148e0425958076c89037789a5b77105f91f2cd078d44388c6a12b392694d0b51b82e4c4130b34ed21947e7023ced61c84d00328f45400e6de06f822d35da02d0e888fd5585de09c71d5c1100701709708770952025f20c963504de3101648d90ad4c710dfb901d0b5dc288b08e9ae825820c7b6ed5e48a85bb0ae6682f94ab1a8a6b50a33d8a685ef5c0eca2da55820bb0754f29d3e638142e643e0fab05abc666fa2b76a627b9f74fd93f10d1985a1d8302e87424274c2d8bf381eff8e3db32bf13f19db932efecf21f5f84f3dbe39d2e52e5241b1c11c7c77257a086d98906e84e566819ec930522195a8a75ffa2ac64342c11f122a61cd75840c0b10538689143bec87a0442316f8906141aeb1c40216c8b69e17be13641d621568c2db801f070a6a624ae402396745911e8788333ff6c8920444ee944601540580bf40cf9f3fff7ac1a6932f4e52fcdf02df0d434c77c380d1b55e04c4c95681a3fc6fe254f9df6432eaf0ff1c52c3ffe1018f38e7a2500763fb416b42c61ad323e031ea2b88b3ec32ac5711fa31287f901c7ed1ec30bdda21f8240e877ad24e4e018ff2bf7935fe27f3d9b88bff73483dfe5357504e70ce787f3abaa72332e9b3cfe2a58e72844242b7385078304d3ee3bbf473233744e8afe81a7b1ba4e605dd92204012df808293294ac1053d4b42155daa48dd872dba4299c6615c9a3e12975ad167fa1052d911c16f5138a63e0b4f9cf057e418ff9bcea615fc7726a37987ffe7907afe9f78c4170afd6df5c013e5e9e9d81348d5f508a16b114730f62bc6ce3527fe70cdb107ab3818ea210f930ba667ee24c07034ff9b55f9df6c3cb2bbf83f8794e25f3983bb7786b41e5770862f14131e5efd9b36333c0e7fc420f4d8a2226bf4b08435e3c4c381fe76ab61e1dd5b1ec300bdc28180f70dcc4d4de62379dbe47cbc2dcdff7c58e1389043ef2692272703c7e27f369dabf89fdab3d1683eb355fe673b5dfe771669adff77e5f76fa2fc8e7d1c49b205d7db6076ba926f498ed67f9cd98533b1c7b3b93d9bcdc617b633769ceefedf59a41eff658ff873acf9272a01e919516d2e718a11c8b6ecc6ba4d368b586cf0711a70bf5c6336b11fcd0cf43685af2831e9e42ca2dd238e861bc66e2cb17992368ef13f6732bd70c6b399339e8eedf1e8c27646a349c7ffce22e06d1832784c29a16b54f18601bae5444a75045304612477684502409221eb595179c831357a3dc9625d222f1fe860e5cb95ca6ebf7c09fdccfb3f9daefe7316b9cffecf02affac2f77f167adaedffbc97a4f51f42871c3cc6fda748018fc67fedfeff7832eff6ff9c45bafd9f8502d41343461a610bf4b707a5716dd09299d359e12351c3750925d275ad68f7643e762cfed5ff65feef8c27ddf31f67911cff2162dee6492a80c7f7ff8faaf8dfedff3f9374f87f3efc4f224c31e0fb627f0af10af45d7d76ba767cb574b3932f4cb22bfc8404e030fe3bb3d17cacefff8c27d3d1683e53ebff74dae1ff59848411e312792c08c05360227ae957bf0b46f7ff076cbd56409a7e649992c2f8802cf71fd3fd53e9274942e8ad380bd5b241e81aa5dfbfa0bb01fa07f1e400bdd12b0f0e7afb73681c463b8405a251f65dbe84a8033ec8c468e1eb5471c338db32bf7ad8f2581832bad7d290d8ebf5bc000b8132607bc9a8e46a1ab8e983b45ee2205862efa672ac9f40b96118faef0ba4572d94d8badd106f837c06025126376ac826dc791049b4621c8578b704240280a88ffc98abe3fbe286b686a95f58702c845e318e24085d818d621e3101c2ca3aa0ff79f9e3f5cb7ffef2e6a7d76fdd573ffd7cfdfac5bfaed115322873595440ff54db8715da537e5340b01aa04bccd762915c94cbcb9bdbec631f0d7f40af194d6f9f29117104dcec5b99097d727e5ebf97a9eaa6ddb414ec6e18bb7139a6e80aa9562da05b6ba3177761ad419a46b3ba91eeafe96766c9aac572dec9ac754b2dcb261396f2528b881509c0346a65ebfe0019af4800486c581cf808ee8890c2320a83d17dd677ffd055eae4d6af3b2121fcb7fe60f6cbaa058ab21fb1c7a8843ba946ab977311305950ab5aa8dd6a3c3073154d6380ec63d692a2dafd6d26fac651b3a9f7c2032cef4f396e3cf7e607982f8440a581152681cba8bb225cc8029d6a35de76823140469b71d5fc26a5d178db3e2f2dfa4da60bc44f802c3959cd6c83ae3140e311ba44e351c5aebec4f96309a2d568f3230c0d6e576abddd602972cb5d4e2d97345a27e1b2651ccf6a41991bacf4b8a9dedc3a0f4dcac60039b94d2c047079c0f40f7a5f41a50385b1dda70b75f5c39d68305feb864ec80e3a81d6282689ad5e1030ec1fb6a535cab69a0c35a479ad261b74552ce549a1d13c414d6d108a4c237fb544c5ce00191ea342e23ac214b3cea33d554a6ad0d6f35acf6cf47d83c1ef91d3dc9c4e688fb6a7b57483765383570d36cbcddd7222c1a57110b4b695abe42b79d94871cf6dab99a2528321b22a389a5aeb111115e2520639f05dfd3c2bba2a125feb258ba954fc263b0d02d164443564969b4cbbf37721b1245e0872c3fc8c71293e9a9437cca4c841a890ba3462697a798c84658a390fcd7bc541c69c36f2d86676d6dcc788830b77e0c51234a732816e932e5ed3edcb84bc0cd066ebbb1ea32bb25eecd9b6f563f237d569608d34b252ce24007c65d84aa6417dece7c4545f1337bd427a7eb53142656db4220ecdfaf554ab420cc2ec178c7a31e740650a75b9d555c070c12e6544c768de57ca7888033360de956dd903243c1cc05543a05d5ea251bfe68c8d607555c08ab25fedc7558bf2ef92ae155cf2580b056cba671b97e9ca59be00fd47b45d40c9c6b61d3444e6bd3bd0d4836a4072ac2edc7fd485bfe69c71d3f889ea150efdd6d0c9dfd0878f86b55297569a6d2329ba4f4226568c6b0f4b5326f5af4bfc8572cd81be479d55d4084d2240a5b7ef84e40315c4ef1735f7a83f6b5042987db6a0b98d64919bea836fbee5313452654521630ee621c69f9fa892734be7a266336bba2c0eaceedf39b497bb7f4be406b108a8693cf361fb4c489fc552ad92b74ba3af12f855f90425a9397369fcf7ceb6abcb6829c6dfa593ff1e7d7755580073a2f421adc2ea5928077f5fa7e1eab85ad3df1901138a675ce6ad14b899d97fffb1003b22625423c487325ddd53ae042b6349022bc4379059a98db5962096267a80dea567be2f1f28d9e99719b151761163514f392b4e5430f0b18aadfbb116309485915a17eaccb12120eee5fe6da954536c5feb0a0a61d43c78ea6362629f7bb687452585e937395ca9cff7f7beeaad85cc131ba6b9ffbef17a1d77ca0f46437ab0d8f77e8074064168144bb1779b86d4eae379fdad168ad9aadde657a9a90fe9c8dd02ca93fe42f3113dfb444d3dc7740da63368cfcbfa1ff3ceb438fdbdbad39ad93eae9bf5aef40bd39af5b850553a4ca22a48546062780b69682777f1d23aaff58ba2ba7586570deb4a15e301515d39f331419d2792ed619de5b7a5858db2a4a26d252540b35feeb83e14def8849b1156912dae926700b5bacb6eaeca6bf34ae72257c979bf3342d53f49fb0d55dbfcbcb4da6e11ba62a6f12bde12ba4685e2d7878f8332572e921adde8a0994ee54de8555aab5ac95a7ddbb836ff2e18b5fc388c1ac8f60029e0675cba37b0dbcf04a13e507935c95bd26d789b90f9a6cde6f379657aca873207cc32ac7b3ae069bd23ab587cfab5ac4d346f9ee825f3770ac70995e64d7f81b61a076e0668aba0405f073d27abbe452484c2ec7f2c1928692b637bb53ad94a6ae36be9c21fe64da9ca52d620c295bb08cced009566abc9ceb666e7ded9b6ee6df9dc5200d4da357e66d807ff241151665505c65373a5012a3df7b3bf71f54ee791ef9b31b158be6f2c4934d4f76b1e5b03d9e4493d9ede7840df973a7610698d973fbe78f3eb5fd0b5cef315aa2456503a507dcfa37a5fccccaa0fa92f25b9bb979519dce484aba61244eb5da7942b2ccab58de6fa41915c6827d2ff751b114e21fbe7d49ef20d3047f7ff4eedcaf39fcebc7bfee73cd2fefc67f7e467e3c6b0a77dbcf3ecafeb8a96a77fdf43558eedff74a693cafe4f7bdebdffe93c528fff6829bbd03f10fa6a7e0e067cc4a23848eb27baf3ca7012f07ae7076731f5aba16fdbe9d34efaa8489e9ee21005d8037715532faf8e491e530f4b70571c275f23db1a254011305e55e720701805507d6e7da48f46c065cc97ee0a7b92f1e4fbee9581df8e249b953febfbff1c7b3cabbfffaf7bfeeb2cd2edff3fdffeff0cedc72779feabdbebdfc9274be98d0f4fb40a1ce5ffa37905ff4733bbc3ffb3c8e7c27f09428ae1defb923e342d04ce675807da36af2fd05b85f3dd7beaba85e34f23fbdf7f78a29f7ed172b4fe3baebeff65329975ef7f398bb4fefe4bf7d32f9ff8d32fa3afe241ddf46aeb0bfd34bffe720ffee7d47eff65329e76f17f0e698dff8a477c8bf5807624e9185fc7f83ae9a4934ebe6ef97f000000ffffc13cfb0e007e0000	2021-05-11 23:09:55.588006+00	2021-05-11 23:10:09.78757+00	\N	f	\N	\N	\N	\N	\N	2	\N	\N	checkpoint_storage: {host_path: /tmp, save_trial_best: 30, storage_path: determined-integration-checkpoints,\n  type: shared_fs}\ndescription: noop_single\nentrypoint: model_def:NoOpTrial\nhyperparameters: {global_batch_size: 32, metrics_base: 0.9, metrics_progression: decreasing,\n  metrics_sigma: 0}\nmax_restarts: 0\nmin_checkpoint_period: {batches: 100}\nmin_validation_period: {batches: 100}\nreproducibility: {experiment_seed: 999}\nsearcher:\n  max_length: {batches: 3000}\n  metric: validation_error\n  name: single\n  smaller_is_better: true\n
\.


--
-- Data for Name: model_versions; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.model_versions (version, model_name, checkpoint_uuid, creation_time, last_updated_time, metadata) FROM stdin;
\.


--
-- Data for Name: models; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.models (name, description, creation_time, last_updated_time, metadata) FROM stdin;
\.


--
-- Data for Name: resource_aggregates; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.resource_aggregates (date, aggregation_type, aggregation_key, seconds) FROM stdin;
\.


--
-- Data for Name: schema_migrations; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.schema_migrations (version, dirty) FROM stdin;
20210511105441	f
\.


--
-- Data for Name: steps; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.steps (trial_id, id, state, start_time, end_time, metrics, total_batches) FROM stdin;
1	1	ERROR	2021-05-11 23:09:52.478482+00	2021-05-11 23:10:01.412778+00	\N	100
2	1	ERROR	2021-05-11 23:10:01.492306+00	2021-05-11 23:10:09.777732+00	\N	100
\.


--
-- Data for Name: task_sessions; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.task_sessions (id, task_id) FROM stdin;
\.


--
-- Data for Name: templates; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.templates (name, config) FROM stdin;
\.


--
-- Data for Name: trial_logs; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.trial_logs (trial_id, message, agent_id, container_id, rank_id, log, "timestamp", level, source, stdtype, id) FROM stdin;
1	\\x	hx1	fbf7db91-ba1b-4bed-80cb-372307e1e9f0	\N	\\x696d61676520616c726561647920666f756e642c20736b697070696e672070756c6c2070686173653a20646f636b65722e696f2f64657465726d696e656461692f656e7669726f6e6d656e74733a70792d332e372d7079746f7263682d312e372d74662d312e31352d6370752d626165666266370a	2021-05-11 23:09:52.525765	INFO	agent	stdout	1
1	\\x	hx1	fbf7db91-ba1b-4bed-80cb-372307e1e9f0	\N	\\x636f7079696e672066696c657320746f20636f6e7461696e65723a202f0a	2021-05-11 23:09:53.051545	INFO	agent	stdout	2
1	\\x	hx1	fbf7db91-ba1b-4bed-80cb-372307e1e9f0	\N	\\x636f7079696e672066696c657320746f20636f6e7461696e65723a202f0a	2021-05-11 23:09:53.166578	INFO	agent	stdout	3
1	\\x	hx1	fbf7db91-ba1b-4bed-80cb-372307e1e9f0	\N	\\x636f7079696e672066696c657320746f20636f6e7461696e65723a202f0a	2021-05-11 23:09:53.245916	INFO	agent	stdout	4
1	\\x	hx1	fbf7db91-ba1b-4bed-80cb-372307e1e9f0	\N	\\x636f7079696e672066696c657320746f20636f6e7461696e65723a202f0a	2021-05-11 23:09:53.296102	INFO	agent	stdout	5
1	\\x	hx1	fbf7db91-ba1b-4bed-80cb-372307e1e9f0	\N	\\x636f7079696e672066696c657320746f20636f6e7461696e65723a202f0a	2021-05-11 23:09:53.347585	INFO	agent	stdout	6
1	\\x	hx1	fbf7db91-ba1b-4bed-80cb-372307e1e9f0	\N	\\x636f7079696e672066696c657320746f20636f6e7461696e65723a202f0a	2021-05-11 23:09:53.399607	INFO	agent	stdout	7
1	\\x	hx1	fbf7db91-ba1b-4bed-80cb-372307e1e9f0	\N	\\x636f7079696e672066696c657320746f20636f6e7461696e65723a202f72756e2f64657465726d696e65642f747261696e0a	2021-05-11 23:09:53.450365	INFO	agent	stdout	8
1	\\x	hx1	fbf7db91-ba1b-4bed-80cb-372307e1e9f0	\N	\\x636f7079696e672066696c657320746f20636f6e7461696e65723a202f72756e2f64657465726d696e65642f747261696e2f6d6f64656c0a	2021-05-11 23:09:53.498466	INFO	agent	stdout	9
1	\\x	hx1	fbf7db91-ba1b-4bed-80cb-372307e1e9f0	\N	\\x636f7079696e672066696c657320746f20636f6e7461696e65723a202f72756e2f64657465726d696e65642f776f726b6469720a	2021-05-11 23:09:53.547859	INFO	agent	stdout	10
1	\\x	hx1	fbf7db91-ba1b-4bed-80cb-372307e1e9f0	\N	\\x2b20574f524b494e475f4449523d2f72756e2f64657465726d696e65642f776f726b6469720a	2021-05-11 23:09:53.773372	\N	\N	stderr	11
1	\\x	hx1	fbf7db91-ba1b-4bed-80cb-372307e1e9f0	\N	\\x2b20535441525455505f484f4f4b3d737461727475702d686f6f6b2e73680a	2021-05-11 23:09:53.773379	\N	\N	stderr	12
1	\\x	hx1	fbf7db91-ba1b-4bed-80cb-372307e1e9f0	\N	\\x2b206578706f727420504154483d2f72756e2f64657465726d696e65642f707974686f6e75736572626173652f62696e3a2f6f70742f636f6e64612f62696e3a2f7573722f6c6f63616c2f7362696e3a2f7573722f6c6f63616c2f62696e3a2f7573722f7362696e3a2f7573722f62696e3a2f7362696e3a2f62696e0a	2021-05-11 23:09:53.77338	\N	\N	stderr	13
1	\\x	hx1	fbf7db91-ba1b-4bed-80cb-372307e1e9f0	\N	\\x2b20504154483d2f72756e2f64657465726d696e65642f707974686f6e75736572626173652f62696e3a2f6f70742f636f6e64612f62696e3a2f7573722f6c6f63616c2f7362696e3a2f7573722f6c6f63616c2f62696e3a2f7573722f7362696e3a2f7573722f62696e3a2f7362696e3a2f62696e0a	2021-05-11 23:09:53.773381	\N	\N	stderr	14
1	\\x	hx1	fbf7db91-ba1b-4bed-80cb-372307e1e9f0	\N	\\x2b20275b27202d7a20272720275d270a	2021-05-11 23:09:53.773382	\N	\N	stderr	15
1	\\x	hx1	fbf7db91-ba1b-4bed-80cb-372307e1e9f0	\N	\\x2b206578706f7274204445545f505954484f4e5f45584543555441424c453d707974686f6e330a	2021-05-11 23:09:53.773383	\N	\N	stderr	16
1	\\x	hx1	fbf7db91-ba1b-4bed-80cb-372307e1e9f0	\N	\\x2b204445545f505954484f4e5f45584543555441424c453d707974686f6e330a	2021-05-11 23:09:53.773384	\N	\N	stderr	17
1	\\x	hx1	fbf7db91-ba1b-4bed-80cb-372307e1e9f0	\N	\\x2b202f62696e2f776869636820707974686f6e330a	2021-05-11 23:09:53.773424	\N	\N	stderr	18
1	\\x	hx1	fbf7db91-ba1b-4bed-80cb-372307e1e9f0	\N	\\x2b20275b27202f726f6f74203d202f20275d270a	2021-05-11 23:09:53.77559	\N	\N	stderr	19
1	\\x	hx1	fbf7db91-ba1b-4bed-80cb-372307e1e9f0	\N	\\x2b20707974686f6e33202d6d2070697020696e7374616c6c202d71202d2d75736572202f6f70742f64657465726d696e65642f776865656c732f64657465726d696e65642d302e31352e332e646576302d7079332d6e6f6e652d616e792e77686c0a	2021-05-11 23:09:53.775637	\N	\N	stderr	20
1	\\x	hx1	fbf7db91-ba1b-4bed-80cb-372307e1e9f0	\N	\\x2b206364202f72756e2f64657465726d696e65642f776f726b6469720a	2021-05-11 23:09:58.92857	\N	\N	stderr	21
1	\\x	hx1	fbf7db91-ba1b-4bed-80cb-372307e1e9f0	\N	\\x2b2074657374202d6620737461727475702d686f6f6b2e73680a	2021-05-11 23:09:58.928579	\N	\N	stderr	22
1	\\x	hx1	fbf7db91-ba1b-4bed-80cb-372307e1e9f0	\N	\\x2b20736f7572636520737461727475702d686f6f6b2e73680a	2021-05-11 23:09:58.928579	\N	\N	stderr	23
1	\\x	hx1	fbf7db91-ba1b-4bed-80cb-372307e1e9f0	\N	\\x2b2b206563686f202772756e6e696e6720737461727475702d686f6f6b2e73682c207772697474696e6720616e20656d7074792066696c6520746f202e2f737461727475702d686f6f6b2d72616e270a	2021-05-11 23:09:58.928778	\N	\N	stderr	24
1	\\x	hx1	fbf7db91-ba1b-4bed-80cb-372307e1e9f0	\N	\\x2b2b20746f75636820737461727475702d686f6f6b2d72616e0a	2021-05-11 23:09:58.928781	\N	\N	stderr	25
1	\\x	hx1	fbf7db91-ba1b-4bed-80cb-372307e1e9f0	\N	\\x72756e6e696e6720737461727475702d686f6f6b2e73682c207772697474696e6720616e20656d7074792066696c6520746f202e2f737461727475702d686f6f6b2d72616e0a	2021-05-11 23:09:58.928786	\N	\N	stdout	26
1	\\x	hx1	fbf7db91-ba1b-4bed-80cb-372307e1e9f0	\N	\\x2b206578656320707974686f6e33202d6d2064657465726d696e65642e657865632e6861726e6573730a	2021-05-11 23:09:58.933069	\N	\N	stderr	27
1	\\x	hx1	fbf7db91-ba1b-4bed-80cb-372307e1e9f0	\N	\\x4e657720747269616c2072756e6e657220696e2028636f6e7461696e65722066626637646239312d626131622d346265642d383063622d33373233303765316539663029206f6e206167656e74206878313a207b276d61737465725f61646472273a20276c6f63616c686f7374272c20276d61737465725f706f7274273a20383038302c20277573655f746c73273a20302c20276d61737465725f636572745f66696c65273a204e6f6e652c20276d61737465725f636572745f6e616d65273a204e6f6e652c2027636f6e7461696e65725f6964273a202766626637646239312d626131622d346265642d383063622d333732333037653165396630272c20276578706572696d656e745f636f6e666967273a207b276465736372697074696f6e273a20276e6f6f705f73696e676c65272c2027636865636b706f696e745f73746f72616765273a207b27686f73745f70617468273a20272f746d70272c2027736176655f6578706572696d656e745f62657374273a20302c2027736176655f747269616c5f62657374273a2033302c2027736176655f747269616c5f6c6174657374273a20312c202773746f726167655f70617468273a202764657465726d696e65642d696e746567726174696f6e2d636865636b706f696e7473272c202774797065273a20277368617265645f6673277d2c2027706572666f726d5f696e697469616c5f76616c69646174696f6e273a2046616c73652c20276d696e5f636865636b706f696e745f706572696f64273a207b2762617463686573273a203130307d2c20276d696e5f76616c69646174696f6e5f706572696f64273a207b2762617463686573273a203130307d2c2027636865636b706f696e745f706f6c696379273a202762657374272c20276879706572706172616d6574657273273a207b27676c6f62616c5f62617463685f73697a65273a207b2774797065273a2027636f6e7374272c202776616c273a2033327d2c20276d6574726963735f62617365273a207b2774797065273a2027636f6e7374272c202776616c273a20302e397d2c20276d6574726963735f70726f6772657373696f6e273a207b2774797065273a2027636f6e7374272c202776616c273a202764656372656173696e67277d2c20276d6574726963735f7369676d61273a207b2774797065273a2027636f6e7374272c202776616c273a20307d7d2c20277365617263686572273a207b276d61785f6c656e677468273a207b2762617463686573273a20333030307d2c20276d6574726963273a202776616c69646174696f6e5f6572726f72272c20276e616d65273a202773696e676c65272c2027736d616c6c65725f69735f626574746572273a20547275652c2027736f757263655f636865636b706f696e745f75756964273a204e6f6e652c2027736f757263655f747269616c5f6964273a204e6f6e657d2c20277265736f7572636573273a207b27736c6f74735f7065725f747269616c273a20312c2027776569676874273a20312c20276e61746976655f706172616c6c656c273a2046616c73652c20276167656e745f6c6162656c273a2027272c20277265736f757263655f706f6f6c273a202764656661756c74272c202764657669636573273a204e6f6e657d2c20276f7074696d697a6174696f6e73273a207b276167677265676174696f6e5f6672657175656e6379273a20312c2027617665726167655f616767726567617465645f6772616469656e7473273a20547275652c2027617665726167655f747261696e696e675f6d657472696373273a2046616c73652c20276772616469656e745f636f6d7072657373696f6e273a2046616c73652c20276d697865645f707265636973696f6e273a20274f30272c202774656e736f725f667573696f6e5f7468726573686f6c64273a2036342c202774656e736f725f667573696f6e5f6379636c655f74696d65273a20352c20276175746f5f74756e655f74656e736f725f667573696f6e273a2046616c73657d2c20277265636f7264735f7065725f65706f6368273a20302c20277363686564756c696e675f756e6974273a203130302c2027656e7669726f6e6d656e74273a207b27696d616765273a207b27637075273a202764657465726d696e656461692f656e7669726f6e6d656e74733a70792d332e372d7079746f7263682d312e372d74662d312e31352d6370752d62616566626637272c2027677075273a202764657465726d696e656461692f656e7669726f6e6d656e74733a637564612d31302e322d7079746f7263682d312e372d74662d312e31352d6770752d62616566626637277d2c2027656e7669726f6e6d656e745f7661726961626c6573273a207b7d2c2027706f727473273a204e6f6e652c2027666f7263655f70756c6c5f696d616765273a2046616c73652c2027706f645f73706563273a204e6f6e652c20276164645f6361706162696c6974696573273a204e6f6e652c202764726f705f6361706162696c6974696573273a204e6f6e657d2c2027726570726f6475636962696c697479273a207b276578706572696d656e745f73656564273a203939397d2c20276d61785f7265737461727473273a20302c20276465627567273a2046616c73652c2027696e7465726e616c273a204e6f6e652c2027656e747279706f696e74273a20276d6f64656c5f6465663a4e6f4f70547269616c272c2027646174615f6c61796572273a207b27636f6e7461696e65725f73746f726167655f70617468273a204e6f6e652c202774797065273a20277368617265645f6673277d2c202770726f66696c696e67273a207b27656e61626c6564273a2046616c73652c2027626567696e5f6f6e5f6261746368273a20302c2027656e645f61667465725f6261746368273a20307d7d2c202768706172616d73273a207b27676c6f62616c5f62617463685f73697a65273a2033322c20276d6574726963735f62617365273a20302e392c20276d6574726963735f70726f6772657373696f6e273a202764656372656173696e67272c20276d6574726963735f7369676d61273a20307d2c2027696e697469616c5f776f726b6c6f6164273a203c52554e5f5354455020283130302042617463686573293a2028312c312c31293e2c20276c61746573745f636865636b706f696e74273a204e6f6e652c20277573655f677075273a20302c2027636f6e7461696e65725f67707573273a205b5d2c2027736c6f745f696473273a205b305d2c20276465627567273a2046616c73652c2027776f726b6c6f61645f6d616e616765725f74797065273a2027545249414c5f574f524b4c4f41445f4d414e41474552272c20276465745f72656e64657a766f75735f706f727473273a2027313733342c31373530272c20276465745f747269616c5f756e697175655f706f72745f6f6666736574273a20302c20276465745f747269616c5f72756e6e65725f6e6574776f726b5f696e74657266616365273a20274445545f4155544f5f4445544543545f4e4554574f524b5f494e54455246414345272c20276465745f747269616c5f6964273a202731272c20276465745f6578706572696d656e745f6964273a202731272c20276465745f6167656e745f6964273a2027687831272c20276465745f636c75737465725f6964273a202762373239636435622d626432362d343765302d386438662d303937666365386163386134272c20276465745f7461736b5f746f6b656e273a202776322e7075626c69632e65794a705a4349364d5377696447467a613139705a434936496a5178595451794e7a63774c5441304e6a6b744e4451335a6931694e546b354c574a6b5954526859574a69596a686b4d434a3930384a326a694a37675f50316f5f4b7a6669306c53456f6643795264656f4a75317269414979724838786f79326a686d646b38433467747169686e4e706f6b70774f5163514d6f6356563264765a575966537a6942672e626e56736241272c2027747269616c5f73656564273a203531313537393834382c20276d616e616765645f747261696e696e67273a20547275652c2027746573745f6d6f6465273a2046616c73652c20276f6e5f636c7573746572273a20547275652c20275f7065725f736c6f745f62617463685f73697a65273a2033322c20275f676c6f62616c5f62617463685f73697a65273a2033327d2e0a	2021-05-11 23:10:00.949713	INFO	\N	stdout	28
1	\\x	hx1	fbf7db91-ba1b-4bed-80cb-372307e1e9f0	\N	\\x436f6e6e656374696e6720746f206d61737465722061742077733a2f2f6c6f63616c686f73743a383038302f77732f747269616c2f312f312f66626637646239312d626131622d346265642d383063622d3337323330376531653966300a	2021-05-11 23:10:00.958655	INFO	\N	stdout	29
1	\\x	hx1	fbf7db91-ba1b-4bed-80cb-372307e1e9f0	\N	\\x54726163656261636b20286d6f737420726563656e742063616c6c206c617374293a0a	2021-05-11 23:10:01.056871	\N	\N	stderr	30
1	\\x	hx1	fbf7db91-ba1b-4bed-80cb-372307e1e9f0	\N	\\x4661696c656420746f20636f6e6e65637420746f206d61737465723a20756e61626c6520746f20636f6e6e6563743b205b4572726e6f202d325d204e616d65206f722073657276696365206e6f74206b6e6f776e0a	2021-05-11 23:10:01.056873	WARNING	\N	stdout	31
1	\\x	hx1	fbf7db91-ba1b-4bed-80cb-372307e1e9f0	\N	\\x202046696c6520222f6f70742f636f6e64612f6c69622f707974686f6e332e372f72756e70792e7079222c206c696e65203139332c20696e205f72756e5f6d6f64756c655f61735f6d61696e0a	2021-05-11 23:10:01.056879	\N	\N	stderr	32
1	\\x	hx1	fbf7db91-ba1b-4bed-80cb-372307e1e9f0	\N	\\x20202020225f5f6d61696e5f5f222c206d6f645f73706563290a	2021-05-11 23:10:01.05773	\N	\N	stderr	33
1	\\x	hx1	fbf7db91-ba1b-4bed-80cb-372307e1e9f0	\N	\\x202046696c6520222f6f70742f636f6e64612f6c69622f707974686f6e332e372f72756e70792e7079222c206c696e652038352c20696e205f72756e5f636f64650a	2021-05-11 23:10:01.057734	\N	\N	stderr	34
1	\\x	hx1	fbf7db91-ba1b-4bed-80cb-372307e1e9f0	\N	\\x202020206578656328636f64652c2072756e5f676c6f62616c73290a	2021-05-11 23:10:01.058114	\N	\N	stderr	35
1	\\x	hx1	fbf7db91-ba1b-4bed-80cb-372307e1e9f0	\N	\\x202046696c6520222f72756e2f64657465726d696e65642f707974686f6e75736572626173652f6c69622f707974686f6e332e372f736974652d7061636b616765732f64657465726d696e65642f657865632f6861726e6573732e7079222c206c696e65203234312c20696e203c6d6f64756c653e0a	2021-05-11 23:10:01.05812	\N	\N	stderr	36
1	\\x	hx1	fbf7db91-ba1b-4bed-80cb-372307e1e9f0	\N	\\x202020206d61696e28290a	2021-05-11 23:10:01.058503	\N	\N	stderr	37
2	\\x	hx1	3de9a494-0dc4-4363-a01c-e873a0c474fa	\N	\\x636f7079696e672066696c657320746f20636f6e7461696e65723a202f0a	2021-05-11 23:10:01.581932	INFO	agent	stdout	47
1	\\x	hx1	fbf7db91-ba1b-4bed-80cb-372307e1e9f0	\N	\\x202046696c6520222f72756e2f64657465726d696e65642f707974686f6e75736572626173652f6c69622f707974686f6e332e372f736974652d7061636b616765732f64657465726d696e65642f657865632f6861726e6573732e7079222c206c696e65203233342c20696e206d61696e0a	2021-05-11 23:10:01.05851	\N	\N	stderr	38
1	\\x	hx1	fbf7db91-ba1b-4bed-80cb-372307e1e9f0	\N	\\x202020206275696c645f616e645f72756e5f747261696e696e675f706970656c696e6528656e76290a	2021-05-11 23:10:01.058832	\N	\N	stderr	39
1	\\x	hx1	fbf7db91-ba1b-4bed-80cb-372307e1e9f0	\N	\\x202046696c6520222f72756e2f64657465726d696e65642f707974686f6e75736572626173652f6c69622f707974686f6e332e372f736974652d7061636b616765732f64657465726d696e65642f657865632f6861726e6573732e7079222c206c696e652039302c20696e206275696c645f616e645f72756e5f747261696e696e675f706970656c696e650a	2021-05-11 23:10:01.058835	\N	\N	stderr	40
1	\\x	hx1	fbf7db91-ba1b-4bed-80cb-372307e1e9f0	\N	\\x2020202077697468206c61796572732e536f636b65744d616e6167657228656e762920617320736f636b65745f6d67723a0a	2021-05-11 23:10:01.059151	\N	\N	stderr	41
1	\\x	hx1	fbf7db91-ba1b-4bed-80cb-372307e1e9f0	\N	\\x202046696c6520222f72756e2f64657465726d696e65642f707974686f6e75736572626173652f6c69622f707974686f6e332e372f736974652d7061636b616765732f64657465726d696e65642f6c61796572732f5f736f636b65745f6d616e616765722e7079222c206c696e652036392c20696e205f5f696e69745f5f0a	2021-05-11 23:10:01.059168	\N	\N	stderr	42
1	\\x	hx1	fbf7db91-ba1b-4bed-80cb-372307e1e9f0	\N	\\x2020202072616973652056616c75654572726f72282252616e206f7574206f66206576656e747320776974686f75742066696e64696e672072656e64657a766f7573206d65737361676522290a	2021-05-11 23:10:01.059345	\N	\N	stderr	43
1	\\x	hx1	fbf7db91-ba1b-4bed-80cb-372307e1e9f0	\N	\\x56616c75654572726f723a2052616e206f7574206f66206576656e747320776974686f75742066696e64696e672072656e64657a766f7573206d6573736167650a	2021-05-11 23:10:01.059348	\N	\N	stderr	44
1	\\x	\N	fbf7db91-ba1b-4bed-80cb-372307e1e9f0	\N	\\x636f6e7461696e6572206661696c65642077697468206e6f6e2d7a65726f206578697420636f64653a20636f6e7461696e6572206661696c65642077697468206e6f6e2d7a65726f206578697420636f64653a203120286578697420636f64652031290a	2021-05-11 16:10:01.407664	INFO	master	stdout	45
2	\\x	hx1	3de9a494-0dc4-4363-a01c-e873a0c474fa	\N	\\x696d61676520616c726561647920666f756e642c20736b697070696e672070756c6c2070686173653a20646f636b65722e696f2f64657465726d696e656461692f656e7669726f6e6d656e74733a70792d332e372d7079746f7263682d312e372d74662d312e31352d6370752d626165666266370a	2021-05-11 23:10:01.528808	INFO	agent	stdout	46
2	\\x	hx1	3de9a494-0dc4-4363-a01c-e873a0c474fa	\N	\\x636f7079696e672066696c657320746f20636f6e7461696e65723a202f0a	2021-05-11 23:10:01.695176	INFO	agent	stdout	48
2	\\x	hx1	3de9a494-0dc4-4363-a01c-e873a0c474fa	\N	\\x636f7079696e672066696c657320746f20636f6e7461696e65723a202f0a	2021-05-11 23:10:01.943772	INFO	agent	stdout	50
2	\\x	hx1	3de9a494-0dc4-4363-a01c-e873a0c474fa	\N	\\x636f7079696e672066696c657320746f20636f6e7461696e65723a202f0a	2021-05-11 23:10:02.200593	INFO	agent	stdout	52
2	\\x	hx1	3de9a494-0dc4-4363-a01c-e873a0c474fa	\N	\\x636f7079696e672066696c657320746f20636f6e7461696e65723a202f72756e2f64657465726d696e65642f747261696e2f6d6f64656c0a	2021-05-11 23:10:02.448271	INFO	agent	stdout	54
2	\\x	hx1	3de9a494-0dc4-4363-a01c-e873a0c474fa	\N	\\x2b20574f524b494e475f4449523d2f72756e2f64657465726d696e65642f776f726b6469720a	2021-05-11 23:10:02.746453	\N	\N	stderr	56
2	\\x	hx1	3de9a494-0dc4-4363-a01c-e873a0c474fa	\N	\\x2b20535441525455505f484f4f4b3d737461727475702d686f6f6b2e73680a	2021-05-11 23:10:02.746457	\N	\N	stderr	57
2	\\x	hx1	3de9a494-0dc4-4363-a01c-e873a0c474fa	\N	\\x2b206578706f727420504154483d2f72756e2f64657465726d696e65642f707974686f6e75736572626173652f62696e3a2f6f70742f636f6e64612f62696e3a2f7573722f6c6f63616c2f7362696e3a2f7573722f6c6f63616c2f62696e3a2f7573722f7362696e3a2f7573722f62696e3a2f7362696e3a2f62696e0a	2021-05-11 23:10:02.746459	\N	\N	stderr	58
2	\\x	hx1	3de9a494-0dc4-4363-a01c-e873a0c474fa	\N	\\x2b20504154483d2f72756e2f64657465726d696e65642f707974686f6e75736572626173652f62696e3a2f6f70742f636f6e64612f62696e3a2f7573722f6c6f63616c2f7362696e3a2f7573722f6c6f63616c2f62696e3a2f7573722f7362696e3a2f7573722f62696e3a2f7362696e3a2f62696e0a	2021-05-11 23:10:02.746461	\N	\N	stderr	59
2	\\x	hx1	3de9a494-0dc4-4363-a01c-e873a0c474fa	\N	\\x2b20275b27202d7a20272720275d270a	2021-05-11 23:10:02.746462	\N	\N	stderr	60
2	\\x	hx1	3de9a494-0dc4-4363-a01c-e873a0c474fa	\N	\\x2b206578706f7274204445545f505954484f4e5f45584543555441424c453d707974686f6e330a	2021-05-11 23:10:02.746464	\N	\N	stderr	61
2	\\x	hx1	3de9a494-0dc4-4363-a01c-e873a0c474fa	\N	\\x2b204445545f505954484f4e5f45584543555441424c453d707974686f6e330a	2021-05-11 23:10:02.746466	\N	\N	stderr	62
2	\\x	hx1	3de9a494-0dc4-4363-a01c-e873a0c474fa	\N	\\x2b202f62696e2f776869636820707974686f6e330a	2021-05-11 23:10:02.746469	\N	\N	stderr	63
2	\\x	hx1	3de9a494-0dc4-4363-a01c-e873a0c474fa	\N	\\x2b20275b27202f726f6f74203d202f20275d270a	2021-05-11 23:10:02.747599	\N	\N	stderr	64
2	\\x	hx1	3de9a494-0dc4-4363-a01c-e873a0c474fa	\N	\\x2b20707974686f6e33202d6d2070697020696e7374616c6c202d71202d2d75736572202f6f70742f64657465726d696e65642f776865656c732f64657465726d696e65642d302e31352e332e646576302d7079332d6e6f6e652d616e792e77686c0a	2021-05-11 23:10:02.747657	\N	\N	stderr	65
2	\\x	hx1	3de9a494-0dc4-4363-a01c-e873a0c474fa	\N	\\x54726163656261636b20286d6f737420726563656e742063616c6c206c617374293a0a	2021-05-11 23:10:09.529606	\N	\N	stderr	75
2	\\x	hx1	3de9a494-0dc4-4363-a01c-e873a0c474fa	\N	\\x202046696c6520222f6f70742f636f6e64612f6c69622f707974686f6e332e372f72756e70792e7079222c206c696e65203139332c20696e205f72756e5f6d6f64756c655f61735f6d61696e0a	2021-05-11 23:10:09.529612	\N	\N	stderr	76
2	\\x	hx1	3de9a494-0dc4-4363-a01c-e873a0c474fa	\N	\\x4661696c656420746f20636f6e6e65637420746f206d61737465723a20756e61626c6520746f20636f6e6e6563743b205b4572726e6f202d325d204e616d65206f722073657276696365206e6f74206b6e6f776e0a	2021-05-11 23:10:09.529644	WARNING	\N	stdout	77
2	\\x	hx1	3de9a494-0dc4-4363-a01c-e873a0c474fa	\N	\\x20202020225f5f6d61696e5f5f222c206d6f645f73706563290a	2021-05-11 23:10:09.529885	\N	\N	stderr	78
2	\\x	hx1	3de9a494-0dc4-4363-a01c-e873a0c474fa	\N	\\x202046696c6520222f6f70742f636f6e64612f6c69622f707974686f6e332e372f72756e70792e7079222c206c696e652038352c20696e205f72756e5f636f64650a	2021-05-11 23:10:09.529888	\N	\N	stderr	79
2	\\x	hx1	3de9a494-0dc4-4363-a01c-e873a0c474fa	\N	\\x202020206578656328636f64652c2072756e5f676c6f62616c73290a	2021-05-11 23:10:09.530051	\N	\N	stderr	80
2	\\x	hx1	3de9a494-0dc4-4363-a01c-e873a0c474fa	\N	\\x202046696c6520222f72756e2f64657465726d696e65642f707974686f6e75736572626173652f6c69622f707974686f6e332e372f736974652d7061636b616765732f64657465726d696e65642f657865632f6861726e6573732e7079222c206c696e65203234312c20696e203c6d6f64756c653e0a	2021-05-11 23:10:09.530054	\N	\N	stderr	81
2	\\x	hx1	3de9a494-0dc4-4363-a01c-e873a0c474fa	\N	\\x202020206d61696e28290a	2021-05-11 23:10:09.530335	\N	\N	stderr	82
2	\\x	hx1	3de9a494-0dc4-4363-a01c-e873a0c474fa	\N	\\x202046696c6520222f72756e2f64657465726d696e65642f707974686f6e75736572626173652f6c69622f707974686f6e332e372f736974652d7061636b616765732f64657465726d696e65642f657865632f6861726e6573732e7079222c206c696e65203233342c20696e206d61696e0a	2021-05-11 23:10:09.530338	\N	\N	stderr	83
2	\\x	hx1	3de9a494-0dc4-4363-a01c-e873a0c474fa	\N	\\x202020206275696c645f616e645f72756e5f747261696e696e675f706970656c696e6528656e76290a	2021-05-11 23:10:09.530623	\N	\N	stderr	84
2	\\x	hx1	3de9a494-0dc4-4363-a01c-e873a0c474fa	\N	\\x202046696c6520222f72756e2f64657465726d696e65642f707974686f6e75736572626173652f6c69622f707974686f6e332e372f736974652d7061636b616765732f64657465726d696e65642f657865632f6861726e6573732e7079222c206c696e652039302c20696e206275696c645f616e645f72756e5f747261696e696e675f706970656c696e650a	2021-05-11 23:10:09.530626	\N	\N	stderr	85
2	\\x	hx1	3de9a494-0dc4-4363-a01c-e873a0c474fa	\N	\\x2020202077697468206c61796572732e536f636b65744d616e6167657228656e762920617320736f636b65745f6d67723a0a	2021-05-11 23:10:09.530786	\N	\N	stderr	86
2	\\x	hx1	3de9a494-0dc4-4363-a01c-e873a0c474fa	\N	\\x202046696c6520222f72756e2f64657465726d696e65642f707974686f6e75736572626173652f6c69622f707974686f6e332e372f736974652d7061636b616765732f64657465726d696e65642f6c61796572732f5f736f636b65745f6d616e616765722e7079222c206c696e652036392c20696e205f5f696e69745f5f0a	2021-05-11 23:10:09.530789	\N	\N	stderr	87
2	\\x	hx1	3de9a494-0dc4-4363-a01c-e873a0c474fa	\N	\\x2020202072616973652056616c75654572726f72282252616e206f7574206f66206576656e747320776974686f75742066696e64696e672072656e64657a766f7573206d65737361676522290a	2021-05-11 23:10:09.530954	\N	\N	stderr	88
2	\\x	hx1	3de9a494-0dc4-4363-a01c-e873a0c474fa	\N	\\x56616c75654572726f723a2052616e206f7574206f66206576656e747320776974686f75742066696e64696e672072656e64657a766f7573206d6573736167650a	2021-05-11 23:10:09.530957	\N	\N	stderr	89
2	\\x	hx1	3de9a494-0dc4-4363-a01c-e873a0c474fa	\N	\\x636f7079696e672066696c657320746f20636f6e7461696e65723a202f0a	2021-05-11 23:10:01.827195	INFO	agent	stdout	49
2	\\x	hx1	3de9a494-0dc4-4363-a01c-e873a0c474fa	\N	\\x636f7079696e672066696c657320746f20636f6e7461696e65723a202f0a	2021-05-11 23:10:02.059054	INFO	agent	stdout	51
2	\\x	hx1	3de9a494-0dc4-4363-a01c-e873a0c474fa	\N	\\x636f7079696e672066696c657320746f20636f6e7461696e65723a202f72756e2f64657465726d696e65642f747261696e0a	2021-05-11 23:10:02.332091	INFO	agent	stdout	53
2	\\x	hx1	3de9a494-0dc4-4363-a01c-e873a0c474fa	\N	\\x636f7079696e672066696c657320746f20636f6e7461696e65723a202f72756e2f64657465726d696e65642f776f726b6469720a	2021-05-11 23:10:02.55703	INFO	agent	stdout	55
2	\\x	hx1	3de9a494-0dc4-4363-a01c-e873a0c474fa	\N	\\x2b206364202f72756e2f64657465726d696e65642f776f726b6469720a	2021-05-11 23:10:07.67271	\N	\N	stderr	66
2	\\x	hx1	3de9a494-0dc4-4363-a01c-e873a0c474fa	\N	\\x2b2074657374202d6620737461727475702d686f6f6b2e73680a	2021-05-11 23:10:07.672714	\N	\N	stderr	67
2	\\x	hx1	3de9a494-0dc4-4363-a01c-e873a0c474fa	\N	\\x2b20736f7572636520737461727475702d686f6f6b2e73680a	2021-05-11 23:10:07.672715	\N	\N	stderr	68
2	\\x	hx1	3de9a494-0dc4-4363-a01c-e873a0c474fa	\N	\\x2b2b206563686f202772756e6e696e6720737461727475702d686f6f6b2e73682c207772697474696e6720616e20656d7074792066696c6520746f202e2f737461727475702d686f6f6b2d72616e270a	2021-05-11 23:10:07.672806	\N	\N	stderr	69
2	\\x	hx1	3de9a494-0dc4-4363-a01c-e873a0c474fa	\N	\\x2b2b20746f75636820737461727475702d686f6f6b2d72616e0a	2021-05-11 23:10:07.672808	\N	\N	stderr	70
2	\\x	hx1	3de9a494-0dc4-4363-a01c-e873a0c474fa	\N	\\x72756e6e696e6720737461727475702d686f6f6b2e73682c207772697474696e6720616e20656d7074792066696c6520746f202e2f737461727475702d686f6f6b2d72616e0a	2021-05-11 23:10:07.672866	\N	\N	stdout	71
2	\\x	hx1	3de9a494-0dc4-4363-a01c-e873a0c474fa	\N	\\x2b206578656320707974686f6e33202d6d2064657465726d696e65642e657865632e6861726e6573730a	2021-05-11 23:10:07.674163	\N	\N	stderr	72
2	\\x	hx1	3de9a494-0dc4-4363-a01c-e873a0c474fa	\N	\\x4e657720747269616c2072756e6e657220696e2028636f6e7461696e65722033646539613439342d306463342d343336332d613031632d65383733613063343734666129206f6e206167656e74206878313a207b276d61737465725f61646472273a20276c6f63616c686f7374272c20276d61737465725f706f7274273a20383038302c20277573655f746c73273a20302c20276d61737465725f636572745f66696c65273a204e6f6e652c20276d61737465725f636572745f6e616d65273a204e6f6e652c2027636f6e7461696e65725f6964273a202733646539613439342d306463342d343336332d613031632d653837336130633437346661272c20276578706572696d656e745f636f6e666967273a207b276465736372697074696f6e273a20276e6f6f705f73696e676c65272c2027636865636b706f696e745f73746f72616765273a207b27686f73745f70617468273a20272f746d70272c2027736176655f6578706572696d656e745f62657374273a20302c2027736176655f747269616c5f62657374273a2033302c2027736176655f747269616c5f6c6174657374273a20312c202773746f726167655f70617468273a202764657465726d696e65642d696e746567726174696f6e2d636865636b706f696e7473272c202774797065273a20277368617265645f6673277d2c2027706572666f726d5f696e697469616c5f76616c69646174696f6e273a2046616c73652c20276d696e5f636865636b706f696e745f706572696f64273a207b2762617463686573273a203130307d2c20276d696e5f76616c69646174696f6e5f706572696f64273a207b2762617463686573273a203130307d2c2027636865636b706f696e745f706f6c696379273a202762657374272c20276879706572706172616d6574657273273a207b27676c6f62616c5f62617463685f73697a65273a207b2774797065273a2027636f6e7374272c202776616c273a2033327d2c20276d6574726963735f62617365273a207b2774797065273a2027636f6e7374272c202776616c273a20302e397d2c20276d6574726963735f70726f6772657373696f6e273a207b2774797065273a2027636f6e7374272c202776616c273a202764656372656173696e67277d2c20276d6574726963735f7369676d61273a207b2774797065273a2027636f6e7374272c202776616c273a20307d7d2c20277365617263686572273a207b276d61785f6c656e677468273a207b2762617463686573273a20333030307d2c20276d6574726963273a202776616c69646174696f6e5f6572726f72272c20276e616d65273a202773696e676c65272c2027736d616c6c65725f69735f626574746572273a20547275652c2027736f757263655f636865636b706f696e745f75756964273a204e6f6e652c2027736f757263655f747269616c5f6964273a204e6f6e657d2c20277265736f7572636573273a207b27736c6f74735f7065725f747269616c273a20312c2027776569676874273a20312c20276e61746976655f706172616c6c656c273a2046616c73652c20276167656e745f6c6162656c273a2027272c20277265736f757263655f706f6f6c273a202764656661756c74272c202764657669636573273a204e6f6e657d2c20276f7074696d697a6174696f6e73273a207b276167677265676174696f6e5f6672657175656e6379273a20312c2027617665726167655f616767726567617465645f6772616469656e7473273a20547275652c2027617665726167655f747261696e696e675f6d657472696373273a2046616c73652c20276772616469656e745f636f6d7072657373696f6e273a2046616c73652c20276d697865645f707265636973696f6e273a20274f30272c202774656e736f725f667573696f6e5f7468726573686f6c64273a2036342c202774656e736f725f667573696f6e5f6379636c655f74696d65273a20352c20276175746f5f74756e655f74656e736f725f667573696f6e273a2046616c73657d2c20277265636f7264735f7065725f65706f6368273a20302c20277363686564756c696e675f756e6974273a203130302c2027656e7669726f6e6d656e74273a207b27696d616765273a207b27637075273a202764657465726d696e656461692f656e7669726f6e6d656e74733a70792d332e372d7079746f7263682d312e372d74662d312e31352d6370752d62616566626637272c2027677075273a202764657465726d696e656461692f656e7669726f6e6d656e74733a637564612d31302e322d7079746f7263682d312e372d74662d312e31352d6770752d62616566626637277d2c2027656e7669726f6e6d656e745f7661726961626c6573273a207b7d2c2027706f727473273a204e6f6e652c2027666f7263655f70756c6c5f696d616765273a2046616c73652c2027706f645f73706563273a204e6f6e652c20276164645f6361706162696c6974696573273a204e6f6e652c202764726f705f6361706162696c6974696573273a204e6f6e657d2c2027726570726f6475636962696c697479273a207b276578706572696d656e745f73656564273a203939397d2c20276d61785f7265737461727473273a20302c20276465627567273a2046616c73652c2027696e7465726e616c273a204e6f6e652c2027656e747279706f696e74273a20276d6f64656c5f6465663a4e6f4f70547269616c272c2027646174615f6c61796572273a207b27636f6e7461696e65725f73746f726167655f70617468273a204e6f6e652c202774797065273a20277368617265645f6673277d2c202770726f66696c696e67273a207b27656e61626c6564273a2046616c73652c2027626567696e5f6f6e5f6261746368273a20302c2027656e645f61667465725f6261746368273a20307d7d2c202768706172616d73273a207b27676c6f62616c5f62617463685f73697a65273a2033322c20276d6574726963735f62617365273a20302e392c20276d6574726963735f70726f6772657373696f6e273a202764656372656173696e67272c20276d6574726963735f7369676d61273a20307d2c2027696e697469616c5f776f726b6c6f6164273a203c52554e5f5354455020283130302042617463686573293a2028322c322c31293e2c20276c61746573745f636865636b706f696e74273a204e6f6e652c20277573655f677075273a20302c2027636f6e7461696e65725f67707573273a205b5d2c2027736c6f745f696473273a205b305d2c20276465627567273a2046616c73652c2027776f726b6c6f61645f6d616e616765725f74797065273a2027545249414c5f574f524b4c4f41445f4d414e41474552272c20276465745f72656e64657a766f75735f706f727473273a2027313733342c31373530272c20276465745f747269616c5f756e697175655f706f72745f6f6666736574273a20302c20276465745f747269616c5f72756e6e65725f6e6574776f726b5f696e74657266616365273a20274445545f4155544f5f4445544543545f4e4554574f524b5f494e54455246414345272c20276465745f747269616c5f6964273a202732272c20276465745f6578706572696d656e745f6964273a202732272c20276465745f6167656e745f6964273a2027687831272c20276465745f636c75737465725f6964273a202762373239636435622d626432362d343765302d386438662d303937666365386163386134272c20276465745f7461736b5f746f6b656e273a202776322e7075626c69632e65794a705a4349364d7977696447467a613139705a434936496d4e6b4f5467355a6d566a4c5463785a5745744e4463355a4331685a6a466d4c5759324e7a686d5957566c5a5463784e434a394d6d785a5276446f58316f45576362374e594c356f5f70754157312d7045787265424e5f54613968333942324d557237677a5779715144784d6c4b57594a4f6144475f41484a427055677543597541547a78776a44772e626e56736241272c2027747269616c5f73656564273a203531313537393834382c20276d616e616765645f747261696e696e67273a20547275652c2027746573745f6d6f6465273a2046616c73652c20276f6e5f636c7573746572273a20547275652c20275f7065725f736c6f745f62617463685f73697a65273a2033322c20275f676c6f62616c5f62617463685f73697a65273a2033327d2e0a	2021-05-11 23:10:09.491285	INFO	\N	stdout	73
2	\\x	hx1	3de9a494-0dc4-4363-a01c-e873a0c474fa	\N	\\x436f6e6e656374696e6720746f206d61737465722061742077733a2f2f6c6f63616c686f73743a383038302f77732f747269616c2f322f322f33646539613439342d306463342d343336332d613031632d6538373361306334373466610a	2021-05-11 23:10:09.500368	INFO	\N	stdout	74
2	\\x	\N	3de9a494-0dc4-4363-a01c-e873a0c474fa	\N	\\x636f6e7461696e6572206661696c65642077697468206e6f6e2d7a65726f206578697420636f64653a20636f6e7461696e6572206661696c65642077697468206e6f6e2d7a65726f206578697420636f64653a203120286578697420636f64652031290a	2021-05-11 16:10:09.776406	INFO	master	stdout	90
\.


--
-- Data for Name: trial_profiler_metrics; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.trial_profiler_metrics (id, "values", batches, ts, labels) FROM stdin;
\.


--
-- Data for Name: trial_snapshots; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.trial_snapshots (id, trial_id, request_id, experiment_id, content, version, created_at, updated_at) FROM stdin;
\.


--
-- Data for Name: trials; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.trials (id, experiment_id, state, start_time, end_time, hparams, warm_start_checkpoint_id, seed, request_id, best_validation_id) FROM stdin;
1	1	ERROR	2021-05-11 23:09:52.470746+00	2021-05-11 23:10:01.416498+00	{"metrics_base": 0.9, "metrics_sigma": 0, "global_batch_size": 32, "metrics_progression": "decreasing"}	\N	511579848	c075adcd-5c31-4726-a5b3-0b87e141f1fe	\N
2	2	ERROR	2021-05-11 23:10:01.488075+00	2021-05-11 23:10:09.77884+00	{"metrics_base": 0.9, "metrics_sigma": 0, "global_batch_size": 32, "metrics_progression": "decreasing"}	\N	511579848	c075adcd-5c31-4726-a5b3-0b87e141f1fe	\N
\.


--
-- Data for Name: user_sessions; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.user_sessions (id, user_id, expiry) FROM stdin;
1	2	2021-05-18 16:09:51.859284
\.


--
-- Data for Name: users; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.users (id, username, password_hash, admin, active) FROM stdin;
1	admin	\N	t	t
2	determined	\N	f	t
\.


--
-- Data for Name: validations; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.validations (id, trial_id, state, start_time, end_time, metrics, total_batches) FROM stdin;
\.


--
-- Name: agent_user_groups_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.agent_user_groups_id_seq', 1, false);


--
-- Name: checkpoints_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.checkpoints_id_seq', 1, false);


--
-- Name: config_files_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.config_files_id_seq', 1, false);


--
-- Name: experiment_snapshots_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.experiment_snapshots_id_seq', 4, true);


--
-- Name: experiments_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.experiments_id_seq', 2, true);


--
-- Name: task_sessions_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.task_sessions_id_seq', 4, true);


--
-- Name: trial_logs_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.trial_logs_id_seq', 90, true);


--
-- Name: trial_profiler_metrics_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.trial_profiler_metrics_id_seq', 1, false);


--
-- Name: trial_snapshots_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.trial_snapshots_id_seq', 4, true);


--
-- Name: trials_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.trials_id_seq', 2, true);


--
-- Name: user_sessions_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.user_sessions_id_seq', 1, true);


--
-- Name: users_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.users_id_seq', 2, true);


--
-- Name: validations_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.validations_id_seq', 1, false);


--
-- Name: agent_user_groups agent_user_groups_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.agent_user_groups
    ADD CONSTRAINT agent_user_groups_pkey PRIMARY KEY (id);


--
-- Name: agent_user_groups agent_user_groups_user_id_unique; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.agent_user_groups
    ADD CONSTRAINT agent_user_groups_user_id_unique UNIQUE (user_id);


--
-- Name: checkpoints checkpoint_uuid_uniq; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.checkpoints
    ADD CONSTRAINT checkpoint_uuid_uniq UNIQUE (uuid);


--
-- Name: checkpoints checkpoints_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.checkpoints
    ADD CONSTRAINT checkpoints_pkey PRIMARY KEY (id);


--
-- Name: checkpoints checkpoints_trial_total_batches_unique; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.checkpoints
    ADD CONSTRAINT checkpoints_trial_total_batches_unique UNIQUE (trial_id, total_batches);


--
-- Name: config_files config_files_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.config_files
    ADD CONSTRAINT config_files_pkey PRIMARY KEY (id);


--
-- Name: experiment_snapshots experiment_snapshots_experiment_id_key; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.experiment_snapshots
    ADD CONSTRAINT experiment_snapshots_experiment_id_key UNIQUE (experiment_id);


--
-- Name: experiments experiments_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.experiments
    ADD CONSTRAINT experiments_pkey PRIMARY KEY (id);


--
-- Name: model_versions model_versions_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.model_versions
    ADD CONSTRAINT model_versions_pkey PRIMARY KEY (model_name, version);


--
-- Name: models models_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.models
    ADD CONSTRAINT models_pkey PRIMARY KEY (name);


--
-- Name: resource_aggregates resource_aggregates_keys_unique; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.resource_aggregates
    ADD CONSTRAINT resource_aggregates_keys_unique UNIQUE (date, aggregation_type, aggregation_key);


--
-- Name: schema_migrations schema_migrations_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.schema_migrations
    ADD CONSTRAINT schema_migrations_pkey PRIMARY KEY (version);


--
-- Name: steps steps_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.steps
    ADD CONSTRAINT steps_pkey PRIMARY KEY (trial_id, id);


--
-- Name: steps steps_trial_total_batches_unique; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.steps
    ADD CONSTRAINT steps_trial_total_batches_unique UNIQUE (trial_id, total_batches);


--
-- Name: task_sessions task_sessions_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.task_sessions
    ADD CONSTRAINT task_sessions_pkey PRIMARY KEY (id);


--
-- Name: task_sessions task_sessions_task_id_key; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.task_sessions
    ADD CONSTRAINT task_sessions_task_id_key UNIQUE (task_id);


--
-- Name: templates templates_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.templates
    ADD CONSTRAINT templates_pkey PRIMARY KEY (name);


--
-- Name: trial_logs trial_logs_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.trial_logs
    ADD CONSTRAINT trial_logs_pkey PRIMARY KEY (id);


--
-- Name: trial_snapshots trial_snapshots_trial_id_key; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.trial_snapshots
    ADD CONSTRAINT trial_snapshots_trial_id_key UNIQUE (trial_id);


--
-- Name: trials trials_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.trials
    ADD CONSTRAINT trials_pkey PRIMARY KEY (id);


--
-- Name: trial_snapshots uq_trial_snapshots_experiment_id_request_id; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.trial_snapshots
    ADD CONSTRAINT uq_trial_snapshots_experiment_id_request_id UNIQUE (experiment_id, request_id);


--
-- Name: user_sessions user_sessions_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.user_sessions
    ADD CONSTRAINT user_sessions_pkey PRIMARY KEY (id);


--
-- Name: users users_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.users
    ADD CONSTRAINT users_pkey PRIMARY KEY (id);


--
-- Name: users users_username_key; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.users
    ADD CONSTRAINT users_username_key UNIQUE (username);


--
-- Name: validations validations_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.validations
    ADD CONSTRAINT validations_pkey PRIMARY KEY (id);


--
-- Name: validations validations_trial_total_batches_unique; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.validations
    ADD CONSTRAINT validations_trial_total_batches_unique UNIQUE (trial_id, total_batches);


--
-- Name: ix_checkpoints_trial_id; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX ix_checkpoints_trial_id ON public.checkpoints USING btree (trial_id);


--
-- Name: ix_trial_logs_trial_id; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX ix_trial_logs_trial_id ON public.trial_logs USING btree (trial_id);


--
-- Name: ix_trials_experiment_id; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX ix_trials_experiment_id ON public.trials USING btree (experiment_id);


--
-- Name: ix_trials_warm_start_checkpoint_id; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX ix_trials_warm_start_checkpoint_id ON public.trials USING btree (warm_start_checkpoint_id);


--
-- Name: ix_validations_trial_id; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX ix_validations_trial_id ON public.validations USING btree (trial_id);


--
-- Name: trial_profiler_metric_labels; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX trial_profiler_metric_labels ON public.trial_profiler_metrics USING gin (labels);


--
-- Name: agent_user_groups agent_user_groups_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.agent_user_groups
    ADD CONSTRAINT agent_user_groups_user_id_fkey FOREIGN KEY (user_id) REFERENCES public.users(id);


--
-- Name: experiments experiments_owner_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.experiments
    ADD CONSTRAINT experiments_owner_fkey FOREIGN KEY (owner_id) REFERENCES public.users(id);


--
-- Name: experiment_snapshots fk_experiment_snapshots_experiments_experiment_id; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.experiment_snapshots
    ADD CONSTRAINT fk_experiment_snapshots_experiments_experiment_id FOREIGN KEY (experiment_id) REFERENCES public.experiments(id);


--
-- Name: trial_snapshots fk_trial_snapshots_experiments_experiment_id; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.trial_snapshots
    ADD CONSTRAINT fk_trial_snapshots_experiments_experiment_id FOREIGN KEY (experiment_id) REFERENCES public.experiments(id);


--
-- Name: trial_snapshots fk_trial_snapshots_trials_trial_id; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.trial_snapshots
    ADD CONSTRAINT fk_trial_snapshots_trials_trial_id FOREIGN KEY (trial_id) REFERENCES public.trials(id);


--
-- Name: model_versions model_versions_checkpoint_uuid_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.model_versions
    ADD CONSTRAINT model_versions_checkpoint_uuid_fkey FOREIGN KEY (checkpoint_uuid) REFERENCES public.checkpoints(uuid);


--
-- Name: model_versions model_versions_model_name_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.model_versions
    ADD CONSTRAINT model_versions_model_name_fkey FOREIGN KEY (model_name) REFERENCES public.models(name);


--
-- Name: steps steps_trial_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.steps
    ADD CONSTRAINT steps_trial_id_fkey FOREIGN KEY (trial_id) REFERENCES public.trials(id);


--
-- Name: trial_logs trial_logs_trial_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.trial_logs
    ADD CONSTRAINT trial_logs_trial_id_fkey FOREIGN KEY (trial_id) REFERENCES public.trials(id);


--
-- Name: trials trials_experiment_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.trials
    ADD CONSTRAINT trials_experiment_id_fkey FOREIGN KEY (experiment_id) REFERENCES public.experiments(id);


--
-- Name: trials trials_warm_start_checkpoint_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.trials
    ADD CONSTRAINT trials_warm_start_checkpoint_id_fkey FOREIGN KEY (warm_start_checkpoint_id) REFERENCES public.checkpoints(id);


--
-- Name: user_sessions user_sessions_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.user_sessions
    ADD CONSTRAINT user_sessions_user_id_fkey FOREIGN KEY (user_id) REFERENCES public.users(id);


--
-- PostgreSQL database dump complete
--

