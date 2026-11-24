-- ============================================================
-- ai_ecommerce 完整导出：建库 + public 模式 + 全部表数据
-- 来源：120.46.149.36:5432 / ai_ecommerce（PostgreSQL 18.7）
-- ============================================================

-- 单独执行（不要放在事务块内）：
CREATE DATABASE ai_ecommerce;

--
-- PostgreSQL database dump
--


-- Dumped from database version 18.7
-- Dumped by pg_dump version 18.7 (Debian 18.7-1.pgdg13+5)

SET statement_timeout = 0;
SET lock_timeout = 0;
SET idle_in_transaction_session_timeout = 0;
SET transaction_timeout = 0;
SET client_encoding = 'UTF8';
SET standard_conforming_strings = on;
SELECT pg_catalog.set_config('search_path', 'public, pg_catalog', false);
SET check_function_bodies = false;
SET xmloption = content;
SET client_min_messages = warning;
SET row_security = off;

--
-- Name: public; Type: SCHEMA; Schema: -; Owner: -
--

CREATE SCHEMA IF NOT EXISTS public;


--
-- Name: SCHEMA public; Type: COMMENT; Schema: -; Owner: -
--

COMMENT ON SCHEMA public IS 'standard public schema';


--
-- Name: buyer_intent_enum; Type: TYPE; Schema: public; Owner: -
--

CREATE TYPE public.buyer_intent_enum AS ENUM (
    'INQUIRY',
    'COMPLAINT',
    'AFTER_SALES_COMPLAINT',
    'PRESALE_ADVICE'
);


--
-- Name: case_status_enum; Type: TYPE; Schema: public; Owner: -
--

CREATE TYPE public.case_status_enum AS ENUM (
    'PENDING_REVIEW',
    'APPROVED',
    'REJECTED'
);


--
-- Name: case_type_enum; Type: TYPE; Schema: public; Owner: -
--

CREATE TYPE public.case_type_enum AS ENUM (
    'RETURN',
    'REFUND',
    'REPLACEMENT',
    'EXCHANGE_VARIANT'
);


--
-- Name: data_nature_enum; Type: TYPE; Schema: public; Owner: -
--

CREATE TYPE public.data_nature_enum AS ENUM (
    'INTERNAL',
    'PAID_EXTERNAL',
    'OPEN_PUBLIC',
    'MOCK'
);


--
-- Name: import_job_status_enum; Type: TYPE; Schema: public; Owner: -
--

CREATE TYPE public.import_job_status_enum AS ENUM (
    'QUEUED',
    'RUNNING',
    'SUCCEEDED',
    'FAILED'
);


--
-- Name: message_direction_enum; Type: TYPE; Schema: public; Owner: -
--

CREATE TYPE public.message_direction_enum AS ENUM (
    'INBOUND',
    'OUTBOUND'
);


--
-- Name: outbox_status_enum; Type: TYPE; Schema: public; Owner: -
--

CREATE TYPE public.outbox_status_enum AS ENUM (
    'PENDING',
    'SENT',
    'FAILED'
);


--
-- Name: plan_status_enum; Type: TYPE; Schema: public; Owner: -
--

CREATE TYPE public.plan_status_enum AS ENUM (
    'READY_FOR_REVIEW',
    'APPROVED',
    'EXECUTING',
    'PURCHASE_ORDERED',
    'INSPECTED',
    'SHIPPED',
    'REJECTED'
);


--
-- Name: review_decision_enum; Type: TYPE; Schema: public; Owner: -
--

CREATE TYPE public.review_decision_enum AS ENUM (
    'APPROVED',
    'REJECTED'
);


--
-- Name: source_type_enum; Type: TYPE; Schema: public; Owner: -
--

CREATE TYPE public.source_type_enum AS ENUM (
    'PLATFORM',
    'ERP',
    'VENDOR',
    'PUBLIC',
    'MANUAL'
);


--
-- Name: study_calc_state_enum; Type: TYPE; Schema: public; Owner: -
--

CREATE TYPE public.study_calc_state_enum AS ENUM (
    'NONE',
    'DEMO_ONLY',
    'ESTIMATE_ONLY',
    'NEED_DATA',
    'BLOCKED'
);


--
-- Name: study_status_enum; Type: TYPE; Schema: public; Owner: -
--

CREATE TYPE public.study_status_enum AS ENUM (
    'RESEARCHING',
    'RESEARCH_ONLY',
    'SCREENED',
    'PENDING_REVIEW',
    'TRIALING',
    'PRODUCED',
    'DELISTED',
    'REJECTED'
);


--
-- Name: trial_status_enum; Type: TYPE; Schema: public; Owner: -
--

CREATE TYPE public.trial_status_enum AS ENUM (
    'PLANNED',
    'RUNNING',
    'PRODUCED',
    'DELISTED'
);


--
-- Name: trial_suggestion_enum; Type: TYPE; Schema: public; Owner: -
--

CREATE TYPE public.trial_suggestion_enum AS ENUM (
    'PRODUCE',
    'SUPPLEMENT',
    'DELIST',
    'VERIFY_DATA'
);


--
-- Name: check_department_parent_org(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.check_department_parent_org() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
    IF NEW.parent_id <> 0 THEN
        IF NEW.parent_id = NEW.id OR NOT EXISTS (
            SELECT 1 FROM public.biz_department p
            WHERE p.id = NEW.parent_id
              AND p.org_id = NEW.org_id
              AND p.deleted = false
        ) THEN
            RAISE EXCEPTION 'parent department must be active and in the same org';
        END IF;
    END IF;
    RETURN NEW;
END;
$$;


--
-- Name: trg_clear_inactive_department_manager(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.trg_clear_inactive_department_manager() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
    IF TG_OP = 'DELETE' THEN
        UPDATE public.biz_department d
        SET manager_id = NULL, manager_name = NULL, updated_at = now()
        WHERE d.manager_id = OLD.id AND d.deleted = false;
        RETURN NULL;
    END IF;

    IF (NEW.deleted = true OR NEW.status <> 'ENABLED')
       AND (OLD.deleted IS DISTINCT FROM NEW.deleted OR OLD.status IS DISTINCT FROM NEW.status) THEN
        UPDATE public.biz_department d
        SET manager_id = NULL, manager_name = NULL, updated_at = now()
        WHERE d.manager_id = OLD.id AND d.deleted = false;
    END IF;
    RETURN NULL;
END;
$$;


--
-- Name: trg_record_department_manager_history(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.trg_record_department_manager_history() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
    IF TG_OP = 'INSERT' THEN
        IF NEW.manager_id IS NOT NULL OR NEW.manager_name IS NOT NULL THEN
            INSERT INTO public.biz_department_manager_history
                (org_id, dept_id, user_id, manager_name, change_type, start_at)
            VALUES (NEW.org_id, NEW.id, NEW.manager_id, NEW.manager_name, 'ASSIGN', now());
        END IF;
        RETURN NULL;
    END IF;

    IF OLD.manager_id IS DISTINCT FROM NEW.manager_id
       OR OLD.manager_name IS DISTINCT FROM NEW.manager_name THEN
        UPDATE public.biz_department_manager_history
        SET end_at = now()
        WHERE org_id = OLD.org_id AND dept_id = OLD.id AND end_at IS NULL;

        INSERT INTO public.biz_department_manager_history
            (org_id, dept_id, user_id, manager_name, change_type, start_at)
        VALUES (
            NEW.org_id, NEW.id, NEW.manager_id, NEW.manager_name,
            CASE WHEN NEW.manager_id IS NULL AND NEW.manager_name IS NULL
                 THEN 'CLEAR' ELSE 'ASSIGN' END,
            now()
        );
    END IF;
    RETURN NULL;
END;
$$;


SET default_tablespace = '';

SET default_table_access_method = heap;

--
-- Name: after_sales_case; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.after_sales_case (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    org_id uuid NOT NULL,
    conversation_id uuid,
    order_ref character varying(64) NOT NULL,
    order_item_ref character varying(64),
    case_type public.case_type_enum NOT NULL,
    status public.case_status_enum DEFAULT 'PENDING_REVIEW'::public.case_status_enum NOT NULL,
    external_status character varying(16) DEFAULT 'UNKNOWN'::character varying NOT NULL,
    qty integer,
    refund_amount numeric(14,2),
    reason text NOT NULL,
    buyer_confirmed boolean DEFAULT false NOT NULL,
    submitted_by uuid NOT NULL,
    decided_by uuid,
    decided_reason text,
    decided_at timestamp with time zone,
    version integer DEFAULT 1 NOT NULL,
    is_deleted boolean DEFAULT false NOT NULL,
    create_time timestamp with time zone DEFAULT now() NOT NULL,
    update_time timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT ck_case_amount CHECK (((refund_amount IS NULL) OR (refund_amount >= (0)::numeric))),
    CONSTRAINT ck_case_decide CHECK (((decided_at IS NULL) OR (decided_by IS NOT NULL))),
    CONSTRAINT ck_case_qty CHECK (((qty IS NULL) OR (qty > 0))),
    CONSTRAINT ck_case_reason CHECK (((length(reason) >= 5) AND (length(reason) <= 1000))),
    CONSTRAINT ck_case_sep CHECK (((decided_by IS NULL) OR (decided_by <> submitted_by)))
);


--
-- Name: agent_run; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.agent_run (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    org_id uuid NOT NULL,
    job_id uuid,
    agent_name character varying(64) NOT NULL,
    status character varying(16),
    input jsonb,
    output jsonb,
    is_deleted boolean DEFAULT false NOT NULL,
    create_time timestamp with time zone DEFAULT now() NOT NULL,
    update_time timestamp with time zone DEFAULT now() NOT NULL
);


--
-- Name: ai_call_log; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.ai_call_log (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    org_id uuid NOT NULL,
    study_id uuid,
    scene character varying(40) NOT NULL,
    prompt_name character varying(64) NOT NULL,
    prompt_version character varying(16) NOT NULL,
    model_tier character varying(16) NOT NULL,
    model_name character varying(64),
    input_fingerprint character(71),
    input_tokens integer,
    output_tokens integer,
    latency_ms integer,
    degraded boolean DEFAULT false NOT NULL,
    degrade_reason character varying(64),
    validator_stage character varying(8),
    cache_hit boolean DEFAULT false NOT NULL,
    is_deleted boolean DEFAULT false NOT NULL,
    create_time timestamp with time zone DEFAULT now() NOT NULL,
    update_time timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT ck_ai_degrade CHECK (((NOT degraded) OR (degrade_reason IS NOT NULL))),
    CONSTRAINT ck_ai_stage CHECK (((validator_stage IS NULL) OR ((validator_stage)::text = ANY (ARRAY[('L1'::character varying)::text, ('L2'::character varying)::text, ('L3'::character varying)::text])))),
    CONSTRAINT ck_ai_tokens CHECK ((((input_tokens IS NULL) OR (input_tokens >= 0)) AND ((output_tokens IS NULL) OR (output_tokens >= 0)) AND ((latency_ms IS NULL) OR (latency_ms >= 0))))
);


--
-- Name: alembic_version; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.alembic_version (
    version_num character varying(32) NOT NULL
);


--
-- Name: audit_log; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.audit_log (
    id integer NOT NULL,
    request_id character varying(64),
    method character varying(16) NOT NULL,
    path character varying(512) NOT NULL,
    client_ip character varying(64),
    "user" character varying(128),
    status integer NOT NULL,
    cost_ms double precision,
    created_at timestamp without time zone DEFAULT now() NOT NULL
);


--
-- Name: audit_log_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.audit_log_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: audit_log_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.audit_log_id_seq OWNED BY public.audit_log.id;


--
-- Name: bi_approval_flow; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.bi_approval_flow (
    id bigint NOT NULL,
    org_id bigint NOT NULL,
    flow_code character varying(32) NOT NULL,
    flow_name character varying(64) NOT NULL,
    scope_level character varying(16) NOT NULL,
    dept_id integer,
    nodes jsonb DEFAULT '[]'::jsonb NOT NULL,
    status character varying(16) DEFAULT 'enabled'::character varying NOT NULL,
    version integer DEFAULT 1 NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT bi_approval_flow_scope_level_check CHECK (((scope_level)::text = ANY ((ARRAY['company'::character varying, 'department'::character varying])::text[]))),
    CONSTRAINT bi_approval_flow_status_check CHECK (((status)::text = ANY ((ARRAY['enabled'::character varying, 'disabled'::character varying])::text[]))),
    CONSTRAINT ck_af_scope_dept CHECK (((((scope_level)::text = 'company'::text) AND (dept_id IS NULL)) OR (((scope_level)::text = 'department'::text) AND (dept_id > 0))))
);


--
-- Name: bi_approval_flow_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.bi_approval_flow_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: bi_approval_flow_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.bi_approval_flow_id_seq OWNED BY public.bi_approval_flow.id;


--
-- Name: bi_conversation_turn; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.bi_conversation_turn (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    org_id uuid NOT NULL,
    session_id uuid NOT NULL,
    seq_no integer,
    question text NOT NULL,
    answer text,
    status character varying(20) DEFAULT 'ANSWERED'::character varying NOT NULL,
    metric_scope jsonb,
    evidence jsonb,
    quality jsonb,
    is_deleted boolean DEFAULT false NOT NULL,
    create_time timestamp with time zone DEFAULT now() NOT NULL,
    update_time timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT ck_qa_seq CHECK (((seq_no IS NULL) OR (seq_no > 0)))
);


--
-- Name: bi_dashboard_access_request; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.bi_dashboard_access_request (
    id bigint NOT NULL,
    request_no character varying(32) NOT NULL,
    org_id bigint NOT NULL,
    dashboard_id character varying(32) NOT NULL,
    target_dept_id integer NOT NULL,
    requester_id character varying(64) NOT NULL,
    requester_dept_id integer,
    reason character varying(255) NOT NULL,
    status character varying(16) DEFAULT 'pending'::character varying NOT NULL,
    approver character varying(64),
    approve_at timestamp with time zone,
    approve_comment character varying(255),
    valid_from timestamp with time zone,
    valid_to timestamp with time zone,
    grant_ref character varying(64),
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT bi_dashboard_access_request_status_check CHECK (((status)::text = ANY ((ARRAY['pending'::character varying, 'approved'::character varying, 'rejected'::character varying, 'expired'::character varying, 'revoked'::character varying])::text[])))
);


--
-- Name: bi_dashboard_access_request_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.bi_dashboard_access_request_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: bi_dashboard_access_request_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.bi_dashboard_access_request_id_seq OWNED BY public.bi_dashboard_access_request.id;


--
-- Name: bi_dashboard_design; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.bi_dashboard_design (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    org_id uuid NOT NULL,
    draft_layout jsonb,
    published_layout jsonb,
    version integer DEFAULT 1 NOT NULL,
    published_at timestamp with time zone,
    data_as_of timestamp with time zone,
    queried_at timestamp with time zone,
    is_deleted boolean DEFAULT false NOT NULL,
    create_time timestamp with time zone DEFAULT now() NOT NULL,
    update_time timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT ck_bi_published CHECK (((published_at IS NULL) OR (published_layout IS NOT NULL)))
);


--
-- Name: bi_dashboard_designs; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.bi_dashboard_designs (
    id bigint NOT NULL,
    org_id bigint NOT NULL,
    dashboard_name character varying(128) NOT NULL,
    deleted_at timestamp with time zone,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    scope_level character varying(16) DEFAULT 'company'::character varying NOT NULL,
    dept_id integer,
    dept_name_snapshot character varying(64),
    dashboard_id character varying(32) NOT NULL,
    board_status character varying(16) DEFAULT 'draft'::character varying NOT NULL,
    draft_layout jsonb DEFAULT '{}'::jsonb NOT NULL,
    published_layout jsonb,
    version bigint DEFAULT 1 NOT NULL,
    published_at timestamp with time zone,
    CONSTRAINT ck_bdd_board_status CHECK (((board_status)::text = ANY ((ARRAY['draft'::character varying, 'running'::character varying])::text[]))),
    CONSTRAINT ck_bdd_scope_dept CHECK (((((scope_level)::text = 'company'::text) AND (dept_id IS NULL)) OR (((scope_level)::text = 'department'::text) AND (dept_id > 0)))),
    CONSTRAINT ck_scope_level CHECK (((scope_level)::text = ANY ((ARRAY['company'::character varying, 'department'::character varying])::text[])))
);


--
-- Name: COLUMN bi_dashboard_designs.dashboard_id; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.bi_dashboard_designs.dashboard_id IS 'v2.0 看板业务键(VARCHAR32)，组织内唯一；接口/路由/关联键';


--
-- Name: COLUMN bi_dashboard_designs.board_status; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.bi_dashboard_designs.board_status IS 'v2.0 两区状态：draft 草稿 / running 运行中';


--
-- Name: COLUMN bi_dashboard_designs.draft_layout; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.bi_dashboard_designs.draft_layout IS 'v2.0 草稿布局快照 JSONB（schema_version/theme/device/widgets[]）';


--
-- Name: COLUMN bi_dashboard_designs.published_layout; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.bi_dashboard_designs.published_layout IS 'v2.0 发布布局快照 JSONB，仅审核通过时由 draft_layout 整体复制';


--
-- Name: COLUMN bi_dashboard_designs.version; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.bi_dashboard_designs.version IS 'v2.0 草稿版本号，乐观锁依据（每次保存 +1）';


--
-- Name: COLUMN bi_dashboard_designs.published_at; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.bi_dashboard_designs.published_at IS 'v2.0 最近一次审核通过发布时间';


--
-- Name: bi_dashboard_designs_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.bi_dashboard_designs_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: bi_dashboard_designs_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.bi_dashboard_designs_id_seq OWNED BY public.bi_dashboard_designs.id;


--
-- Name: bi_operation_log; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.bi_operation_log (
    id bigint NOT NULL,
    org_id bigint NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    scope_level character varying(16),
    dept_id integer,
    dashboard_id character varying(32),
    action character varying(32) DEFAULT 'unknown'::character varying NOT NULL,
    payload jsonb DEFAULT '{}'::jsonb NOT NULL,
    operator character varying(64),
    trace_id character varying(64)
);


--
-- Name: COLUMN bi_operation_log.dashboard_id; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.bi_operation_log.dashboard_id IS 'v2.0 归属看板业务键（逻辑关联，无外键）';


--
-- Name: COLUMN bi_operation_log.action; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.bi_operation_log.action IS 'v2.0 动作：save_draft/submit_publish/approve/reject/delete_draft/flow_config/access_submit/access_approve/access_reject';


--
-- Name: COLUMN bi_operation_log.payload; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.bi_operation_log.payload IS 'v2.0 变更摘要 JSONB';


--
-- Name: COLUMN bi_operation_log.operator; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.bi_operation_log.operator IS 'v2.0 操作人（系统任务可为空）';


--
-- Name: COLUMN bi_operation_log.trace_id; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.bi_operation_log.trace_id IS 'v2.0 链路追踪 ID';


--
-- Name: bi_operation_log_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.bi_operation_log_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: bi_operation_log_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.bi_operation_log_id_seq OWNED BY public.bi_operation_log.id;


--
-- Name: bi_publish_approvals; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.bi_publish_approvals (
    id bigint NOT NULL,
    org_id bigint NOT NULL,
    dashboard_id character varying(32) NOT NULL,
    status character varying(16) DEFAULT 'pending'::character varying NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    scope_level character varying(16),
    dept_id integer,
    flow_id bigint,
    flow_version integer,
    current_node_seq integer DEFAULT 1 NOT NULL,
    submitter_scope_snapshot jsonb DEFAULT '{}'::jsonb NOT NULL,
    approval_no character varying(32) NOT NULL,
    target_version bigint NOT NULL,
    type character varying(16) DEFAULT 'new_board'::character varying NOT NULL,
    submitter character varying(64) NOT NULL,
    submit_at timestamp with time zone DEFAULT now() NOT NULL,
    reviewer character varying(64),
    review_at timestamp with time zone,
    comment character varying(255),
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT ck_bpa_scope_level CHECK (((scope_level)::text = ANY ((ARRAY['company'::character varying, 'department'::character varying])::text[]))),
    CONSTRAINT ck_bpa_type CHECK (((type)::text = ANY ((ARRAY['new_board'::character varying, 'version_update'::character varying])::text[])))
);


--
-- Name: COLUMN bi_publish_approvals.approval_no; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.bi_publish_approvals.approval_no IS 'v2.0 业务单号 AP-YYYY-NNNN，唯一；接口定位键';


--
-- Name: COLUMN bi_publish_approvals.target_version; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.bi_publish_approvals.target_version IS 'v2.0 提交时锁定的草稿版本；与实际 version 不符则审核作废(40008)';


--
-- Name: COLUMN bi_publish_approvals.type; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.bi_publish_approvals.type IS 'v2.0 类型：new_board 首发布 / version_update 版本更新';


--
-- Name: COLUMN bi_publish_approvals.submitter; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.bi_publish_approvals.submitter IS 'v2.0 提交人';


--
-- Name: COLUMN bi_publish_approvals.submit_at; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.bi_publish_approvals.submit_at IS 'v2.0 提交时间';


--
-- Name: COLUMN bi_publish_approvals.reviewer; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.bi_publish_approvals.reviewer IS 'v2.0 审核人（末次处理人）';


--
-- Name: COLUMN bi_publish_approvals.review_at; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.bi_publish_approvals.review_at IS 'v2.0 审核时间';


--
-- Name: COLUMN bi_publish_approvals.comment; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.bi_publish_approvals.comment IS 'v2.0 审核意见 / 驳回理由';


--
-- Name: COLUMN bi_publish_approvals.updated_at; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.bi_publish_approvals.updated_at IS 'v2.0 状态流转更新时间';


--
-- Name: bi_publish_approvals_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.bi_publish_approvals_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: bi_publish_approvals_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.bi_publish_approvals_id_seq OWNED BY public.bi_publish_approvals.id;


--
-- Name: biz_department; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.biz_department (
    id integer NOT NULL,
    org_id integer NOT NULL,
    parent_id integer DEFAULT 0 NOT NULL,
    dept_name character varying(128) NOT NULL,
    dept_code character varying(64) NOT NULL,
    manager_name character varying(64),
    phone character varying(32),
    email character varying(128),
    sort integer DEFAULT 0 NOT NULL,
    status character varying(16) DEFAULT 'ENABLED'::character varying NOT NULL,
    created_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    updated_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    created_by integer,
    updated_by integer,
    deleted boolean DEFAULT false NOT NULL,
    manager_id integer,
    parent_fk_id integer GENERATED ALWAYS AS (
CASE
    WHEN (parent_id = 0) THEN NULL::integer
    ELSE parent_id
END) STORED,
    CONSTRAINT ck_biz_department_no_self_parent CHECK (((parent_id = 0) OR (parent_id <> id))),
    CONSTRAINT ck_department_parent_id_nonnegative CHECK ((parent_id >= 0))
);


--
-- Name: biz_department_closure; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.biz_department_closure (
    org_id integer NOT NULL,
    ancestor_id integer NOT NULL,
    descendant_id integer NOT NULL,
    depth integer DEFAULT 0 NOT NULL,
    CONSTRAINT ck_bdc_depth CHECK ((depth >= 0))
);


--
-- Name: biz_department_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

ALTER TABLE public.biz_department ALTER COLUMN id ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME public.biz_department_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: biz_department_manager_history; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.biz_department_manager_history (
    id bigint NOT NULL,
    org_id integer NOT NULL,
    dept_id integer NOT NULL,
    user_id integer,
    manager_name character varying(64),
    change_type character varying(16) DEFAULT 'ASSIGN'::character varying NOT NULL,
    start_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    end_at timestamp without time zone,
    created_by integer,
    created_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    CONSTRAINT ck_bd_history_change_type CHECK (((change_type)::text = ANY ((ARRAY['ASSIGN'::character varying, 'CLEAR'::character varying, 'INVALID_CLEARED'::character varying])::text[])))
);


--
-- Name: biz_department_manager_history_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

ALTER TABLE public.biz_department_manager_history ALTER COLUMN id ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME public.biz_department_manager_history_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: biz_department_shop; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.biz_department_shop (
    id integer NOT NULL,
    org_id integer NOT NULL,
    dept_id integer NOT NULL,
    shop_id integer NOT NULL,
    created_at timestamp without time zone DEFAULT now() NOT NULL,
    updated_at timestamp without time zone DEFAULT now() NOT NULL,
    created_by integer,
    updated_by integer,
    deleted boolean DEFAULT false NOT NULL
);


--
-- Name: biz_department_shop_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

ALTER TABLE public.biz_department_shop ALTER COLUMN id ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME public.biz_department_shop_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: biz_platform_config; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.biz_platform_config (
    id integer NOT NULL,
    org_id integer NOT NULL,
    shop_id integer NOT NULL,
    platform character varying(32) NOT NULL,
    api_key_secret text,
    api_secret_secret text,
    access_token_secret text,
    api_base_url character varying(512),
    callback_url character varying(512),
    status character varying(16) DEFAULT 'ENABLED'::character varying NOT NULL,
    created_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    updated_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    created_by integer,
    updated_by integer,
    deleted boolean DEFAULT false NOT NULL
);


--
-- Name: biz_platform_config_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

ALTER TABLE public.biz_platform_config ALTER COLUMN id ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME public.biz_platform_config_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: biz_shop; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.biz_shop (
    id integer NOT NULL,
    org_id integer NOT NULL,
    dept_id integer,
    shop_name character varying(128) NOT NULL,
    shop_code character varying(64) NOT NULL,
    platform character varying(32) NOT NULL,
    status character varying(16) DEFAULT 'ENABLED'::character varying NOT NULL,
    created_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    updated_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    created_by integer,
    updated_by integer,
    deleted boolean DEFAULT false NOT NULL
);


--
-- Name: biz_shop_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

ALTER TABLE public.biz_shop ALTER COLUMN id ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME public.biz_shop_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: case_attachment; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.case_attachment (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    org_id uuid NOT NULL,
    case_id uuid NOT NULL,
    file_name character varying(255) NOT NULL,
    mime_type character varying(128) NOT NULL,
    file_size integer NOT NULL,
    file_data bytea NOT NULL,
    uploaded_by uuid NOT NULL,
    is_deleted boolean DEFAULT false NOT NULL,
    create_time timestamp with time zone DEFAULT now() NOT NULL,
    update_time timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT ck_att_mime CHECK (((mime_type)::text = ANY (ARRAY[('application/pdf'::character varying)::text, ('image/jpeg'::character varying)::text, ('image/png'::character varying)::text, ('application/vnd.openxmlformats-officedocument.wordprocessingml.document'::character varying)::text, ('text/plain'::character varying)::text]))),
    CONSTRAINT ck_att_size CHECK (((file_size >= 1) AND (file_size <= 5242880)))
);


--
-- Name: compliance_check; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.compliance_check (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    org_id uuid NOT NULL,
    asset_id uuid NOT NULL,
    scope jsonb,
    result character varying(16),
    detail jsonb,
    checked_by uuid,
    is_deleted boolean DEFAULT false NOT NULL,
    create_time timestamp with time zone DEFAULT now() NOT NULL,
    update_time timestamp with time zone DEFAULT now() NOT NULL
);


--
-- Name: conversation; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.conversation (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    org_id uuid NOT NULL,
    platform character varying(32) NOT NULL,
    store_ref character varying(64) NOT NULL,
    channel character varying(32),
    buyer_ref character varying(64),
    buyer_name character varying(120),
    status character varying(16) DEFAULT 'AI'::character varying NOT NULL,
    last_message_at timestamp with time zone,
    is_deleted boolean DEFAULT false NOT NULL,
    create_time timestamp with time zone DEFAULT now() NOT NULL,
    update_time timestamp with time zone DEFAULT now() NOT NULL
);


--
-- Name: conversation_message; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.conversation_message (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    org_id uuid NOT NULL,
    conversation_id uuid NOT NULL,
    direction public.message_direction_enum NOT NULL,
    client_message_id character varying(64),
    body text NOT NULL,
    language character(5),
    sentiment character varying(16),
    order_no character varying(64),
    delivered_status character varying(16),
    is_deleted boolean DEFAULT false NOT NULL,
    create_time timestamp with time zone DEFAULT now() NOT NULL,
    update_time timestamp with time zone DEFAULT now() NOT NULL
);


--
-- Name: conversation_order_link; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.conversation_order_link (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    org_id uuid NOT NULL,
    conversation_id uuid NOT NULL,
    order_ref character varying(64) NOT NULL,
    evidence_type character varying(32),
    evidence_ref character varying(300),
    buyer_confirmed boolean DEFAULT false NOT NULL,
    verified_by uuid,
    is_deleted boolean DEFAULT false NOT NULL,
    create_time timestamp with time zone DEFAULT now() NOT NULL,
    update_time timestamp with time zone DEFAULT now() NOT NULL
);


--
-- Name: customer_intent_analysis; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.customer_intent_analysis (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    org_id uuid NOT NULL,
    conversation_id uuid NOT NULL,
    message_id uuid,
    intent public.buyer_intent_enum,
    analysis jsonb,
    is_deleted boolean DEFAULT false NOT NULL,
    create_time timestamp with time zone DEFAULT now() NOT NULL,
    update_time timestamp with time zone DEFAULT now() NOT NULL
);


--
-- Name: customer_listing; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.customer_listing (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    org_id uuid NOT NULL,
    store_ref character varying(64),
    sku character varying(80) NOT NULL,
    status character varying(16),
    verified_by uuid,
    verified_at timestamp with time zone,
    is_deleted boolean DEFAULT false NOT NULL,
    create_time timestamp with time zone DEFAULT now() NOT NULL,
    update_time timestamp with time zone DEFAULT now() NOT NULL
);


--
-- Name: customer_recommended_product; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.customer_recommended_product (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    org_id uuid NOT NULL,
    store_ref character varying(64) NOT NULL,
    sku character varying(80) NOT NULL,
    title character varying(300) NOT NULL,
    price numeric(14,2),
    purpose character varying(200),
    audience character varying(200),
    platform_domain character varying(120),
    active boolean DEFAULT true NOT NULL,
    index_status character varying(16) DEFAULT 'INDEXING'::character varying NOT NULL,
    indexed_at timestamp with time zone,
    error_message text,
    is_deleted boolean DEFAULT false NOT NULL,
    create_time timestamp with time zone DEFAULT now() NOT NULL,
    update_time timestamp with time zone DEFAULT now() NOT NULL
);


--
-- Name: customer_reply_draft; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.customer_reply_draft (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    org_id uuid NOT NULL,
    conversation_id uuid NOT NULL,
    zh_text text,
    en_text text,
    status character varying(16) DEFAULT 'DRAFT'::character varying NOT NULL,
    confirmed_by uuid,
    idempotency_key character varying(64),
    is_deleted boolean DEFAULT false NOT NULL,
    create_time timestamp with time zone DEFAULT now() NOT NULL,
    update_time timestamp with time zone DEFAULT now() NOT NULL
);


--
-- Name: demand_profile; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.demand_profile (
    profile_id character varying(36) NOT NULL,
    org_id character varying(36) NOT NULL,
    sku_id character varying(36) NOT NULL,
    as_of_date date NOT NULL,
    metrics json NOT NULL,
    recommended_model_code character varying(64),
    reason json NOT NULL,
    conditions json NOT NULL,
    profile_hash character varying(64) NOT NULL,
    version integer NOT NULL,
    created_at timestamp with time zone NOT NULL,
    updated_at timestamp with time zone NOT NULL
);


--
-- Name: forecast_actual_override; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.forecast_actual_override (
    override_id character varying(36) NOT NULL,
    org_id character varying(36) NOT NULL,
    run_id character varying(36) NOT NULL,
    target_date date NOT NULL,
    old_actual_qty numeric(14,2) NOT NULL,
    new_actual_qty numeric(14,2) NOT NULL,
    reason character varying(500) NOT NULL,
    actor_id character varying(36) NOT NULL,
    version integer NOT NULL,
    created_at timestamp with time zone NOT NULL
);


--
-- Name: forecast_audit_log; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.forecast_audit_log (
    audit_id character varying(36) NOT NULL,
    org_id character varying(36) NOT NULL,
    actor_id character varying(36),
    action character varying(64) NOT NULL,
    resource_type character varying(64) NOT NULL,
    resource_id character varying(36),
    trace_id character varying(64) NOT NULL,
    detail json NOT NULL,
    created_at timestamp with time zone NOT NULL
);


--
-- Name: forecast_backtest_point; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.forecast_backtest_point (
    point_id character varying(36) NOT NULL,
    run_id character varying(36) NOT NULL,
    target_date date NOT NULL,
    predicted_qty numeric(14,2) NOT NULL,
    actual_qty numeric(14,2) NOT NULL,
    stockout_flag boolean NOT NULL,
    included_in_metrics boolean NOT NULL,
    version integer NOT NULL,
    created_at timestamp with time zone NOT NULL
);


--
-- Name: forecast_evaluation; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.forecast_evaluation (
    evaluation_id character varying(36) NOT NULL,
    run_id character varying(36) NOT NULL,
    wape numeric(14,4),
    bias numeric(14,4),
    mae numeric(14,4),
    rmse numeric(14,4),
    coverage_rate numeric(14,4),
    metric_reason_code character varying(64),
    point_count integer NOT NULL,
    excluded_stockout_count integer NOT NULL,
    evaluated_at timestamp with time zone NOT NULL
);


--
-- Name: forecast_idempotency_record; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.forecast_idempotency_record (
    org_id character varying(36) NOT NULL,
    idempotency_key character varying(128) NOT NULL,
    request_hash character varying(64) NOT NULL,
    run_id character varying(36),
    expires_at timestamp with time zone NOT NULL,
    created_at timestamp with time zone NOT NULL
);


--
-- Name: forecast_model_definition; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.forecast_model_definition (
    model_id character varying(36) NOT NULL,
    org_id character varying(36) NOT NULL,
    model_code character varying(64) NOT NULL,
    model_version character varying(64) NOT NULL,
    status character varying(16) NOT NULL,
    parameter_schema json NOT NULL,
    version integer NOT NULL,
    created_at timestamp with time zone NOT NULL,
    updated_at timestamp with time zone NOT NULL
);


--
-- Name: forecast_point; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.forecast_point (
    point_id character varying(36) NOT NULL,
    run_id character varying(36) NOT NULL,
    target_date date NOT NULL,
    predicted_qty numeric(14,2) NOT NULL,
    band_lower numeric(14,2),
    band_upper numeric(14,2),
    band_method character varying(64) NOT NULL,
    replenishment_reference_qty numeric(14,2),
    created_at timestamp with time zone NOT NULL
);


--
-- Name: forecast_run; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.forecast_run (
    run_id character varying(36) NOT NULL,
    org_id character varying(36) NOT NULL,
    sku_id character varying(36) NOT NULL,
    status character varying(16) NOT NULL,
    horizon_days integer NOT NULL,
    as_of_date date NOT NULL,
    request_hash character varying(64) NOT NULL,
    model_snapshot json NOT NULL,
    profile_snapshot json NOT NULL,
    data_range json NOT NULL,
    gate_report json NOT NULL,
    request_payload json NOT NULL,
    publication_status character varying(16) NOT NULL,
    data_version character varying(64) NOT NULL,
    failure_code character varying(32),
    failure_message text,
    created_at timestamp with time zone NOT NULL,
    started_at timestamp with time zone,
    finished_at timestamp with time zone
);


--
-- Name: generation_asset; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.generation_asset (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    org_id uuid NOT NULL,
    job_id uuid NOT NULL,
    asset_type character varying(16) NOT NULL,
    content jsonb,
    selected boolean DEFAULT false NOT NULL,
    is_deleted boolean DEFAULT false NOT NULL,
    create_time timestamp with time zone DEFAULT now() NOT NULL,
    update_time timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT ck_asset_type CHECK (((asset_type)::text = ANY (ARRAY[('TEXT'::character varying)::text, ('IMAGE'::character varying)::text, ('VIDEO'::character varying)::text])))
);


--
-- Name: generation_job; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.generation_job (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    org_id uuid NOT NULL,
    product_id uuid,
    workflow_id uuid,
    mode character varying(16) NOT NULL,
    status character varying(16) DEFAULT 'QUEUED'::character varying NOT NULL,
    idempotency_key character varying(64),
    params jsonb,
    progress integer,
    prompt_id character varying(64),
    error_detail text,
    submitted_by uuid,
    is_deleted boolean DEFAULT false NOT NULL,
    create_time timestamp with time zone DEFAULT now() NOT NULL,
    update_time timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT ck_job_mode CHECK (((mode)::text = ANY (ARRAY[('CONTENT'::character varying)::text, ('IMAGE'::character varying)::text, ('VIDEO'::character varying)::text]))),
    CONSTRAINT ck_job_progress CHECK (((progress IS NULL) OR ((progress >= 0) AND (progress <= 100))))
);


--
-- Name: generation_media; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.generation_media (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    org_id uuid NOT NULL,
    asset_id uuid NOT NULL,
    mime_type character varying(128) NOT NULL,
    file_name character varying(255),
    file_size integer,
    file_data bytea NOT NULL,
    is_deleted boolean DEFAULT false NOT NULL,
    create_time timestamp with time zone DEFAULT now() NOT NULL,
    update_time timestamp with time zone DEFAULT now() NOT NULL
);


--
-- Name: import_jobs; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.import_jobs (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    org_id uuid NOT NULL,
    source_id uuid,
    source_type public.source_type_enum NOT NULL,
    status public.import_job_status_enum DEFAULT 'QUEUED'::public.import_job_status_enum NOT NULL,
    file_name character varying(255) NOT NULL,
    file_size bigint NOT NULL,
    file_sha256 character(64) NOT NULL,
    storage_key character varying(300) NOT NULL,
    row_total integer,
    row_ok integer,
    row_bad integer,
    resume_offset integer DEFAULT 0 NOT NULL,
    error_summary text,
    error_detail jsonb,
    overwrite_target uuid,
    started_at timestamp with time zone,
    finished_at timestamp with time zone,
    created_by uuid NOT NULL,
    is_deleted boolean DEFAULT false NOT NULL,
    create_time timestamp with time zone DEFAULT now() NOT NULL,
    update_time timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT ck_job_rows CHECK ((((row_total IS NULL) OR (row_total >= 0)) AND ((row_ok IS NULL) OR (row_ok >= 0)) AND ((row_bad IS NULL) OR (row_bad >= 0)) AND ((row_total IS NULL) OR (row_ok IS NULL) OR (row_bad IS NULL) OR ((row_ok + row_bad) <= row_total)))),
    CONSTRAINT ck_job_size CHECK (((file_size >= 1) AND (file_size <= 26214400)))
);


--
-- Name: inventory_position; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.inventory_position (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    org_id uuid NOT NULL,
    sku character varying(80) NOT NULL,
    warehouse_ref character varying(64) DEFAULT 'DEFAULT'::character varying NOT NULL,
    available_qty integer,
    in_transit_qty integer,
    sync_status character varying(16) DEFAULT 'UNKNOWN'::character varying NOT NULL,
    as_of timestamp with time zone,
    is_deleted boolean DEFAULT false NOT NULL,
    create_time timestamp with time zone DEFAULT now() NOT NULL,
    update_time timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT ck_inv_qty CHECK ((((available_qty IS NULL) OR (available_qty >= 0)) AND ((in_transit_qty IS NULL) OR (in_transit_qty >= 0))))
);


--
-- Name: logistics_voucher; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.logistics_voucher (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    org_id uuid NOT NULL,
    plan_id uuid NOT NULL,
    voucher_type character varying(16) NOT NULL,
    voucher_no character varying(64),
    voucher_key character varying(300),
    recorded_by uuid,
    recorded_at timestamp with time zone DEFAULT now() NOT NULL,
    is_deleted boolean DEFAULT false NOT NULL,
    create_time timestamp with time zone DEFAULT now() NOT NULL,
    update_time timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT ck_voucher_type CHECK (((voucher_type)::text = ANY (ARRAY[('PURCHASE'::character varying)::text, ('INSPECTION'::character varying)::text, ('SHIPMENT'::character varying)::text])))
);


--
-- Name: outbox_event; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.outbox_event (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    org_id uuid NOT NULL,
    event_type character varying(64) NOT NULL,
    aggregate_type character varying(32) NOT NULL,
    aggregate_id uuid NOT NULL,
    payload jsonb NOT NULL,
    status public.outbox_status_enum DEFAULT 'PENDING'::public.outbox_status_enum NOT NULL,
    retry_count integer DEFAULT 0 NOT NULL,
    next_retry_at timestamp with time zone DEFAULT now() NOT NULL,
    last_error text,
    published_at timestamp with time zone,
    is_deleted boolean DEFAULT false NOT NULL,
    create_time timestamp with time zone DEFAULT now() NOT NULL,
    update_time timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT ck_outbox_retry CHECK ((retry_count >= 0)),
    CONSTRAINT ck_outbox_sent CHECK (((status <> 'SENT'::public.outbox_status_enum) OR (published_at IS NOT NULL)))
);


--
-- Name: pcc_agent_run; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.pcc_agent_run (
    id bigint NOT NULL,
    org_id character varying(64) NOT NULL,
    job_id bigint NOT NULL,
    parent_run_id bigint,
    step character varying(64) NOT NULL,
    input_snapshot jsonb DEFAULT '{}'::jsonb NOT NULL,
    output_snapshot jsonb DEFAULT '{}'::jsonb NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    org_tenant_id integer GENERATED ALWAYS AS (
CASE
    WHEN ((org_id)::text ~ '^[0-9]+$'::text) THEN (org_id)::integer
    ELSE NULL::integer
END) STORED
);


--
-- Name: pcc_agent_run_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.pcc_agent_run_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: pcc_agent_run_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.pcc_agent_run_id_seq OWNED BY public.pcc_agent_run.id;


--
-- Name: pcc_asset_reference; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.pcc_asset_reference (
    id bigint NOT NULL,
    org_id character varying(64) NOT NULL,
    source_asset_id bigint,
    source_media_id bigint,
    target_job_id bigint NOT NULL,
    reference_version integer DEFAULT 1 NOT NULL,
    actor character varying(64) NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    org_tenant_id integer GENERATED ALWAYS AS (
CASE
    WHEN ((org_id)::text ~ '^[0-9]+$'::text) THEN (org_id)::integer
    ELSE NULL::integer
END) STORED,
    CONSTRAINT ck_pcc_asset_reference_one_source CHECK ((((source_asset_id IS NOT NULL) AND (source_media_id IS NULL)) OR ((source_asset_id IS NULL) AND (source_media_id IS NOT NULL)))),
    CONSTRAINT pcc_asset_reference_reference_version_check CHECK ((reference_version > 0))
);


--
-- Name: pcc_asset_reference_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.pcc_asset_reference_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: pcc_asset_reference_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.pcc_asset_reference_id_seq OWNED BY public.pcc_asset_reference.id;


--
-- Name: pcc_compliance_check; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.pcc_compliance_check (
    id bigint NOT NULL,
    org_id character varying(64) NOT NULL,
    job_id bigint NOT NULL,
    asset_id bigint NOT NULL,
    check_type character varying(16) NOT NULL,
    segments jsonb DEFAULT '[]'::jsonb NOT NULL,
    hits jsonb DEFAULT '[]'::jsonb NOT NULL,
    risk_level character varying(16),
    result character varying(16) NOT NULL,
    rule_version character varying(64),
    actor character varying(64) NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    org_tenant_id integer GENERATED ALWAYS AS (
CASE
    WHEN ((org_id)::text ~ '^[0-9]+$'::text) THEN (org_id)::integer
    ELSE NULL::integer
END) STORED,
    CONSTRAINT pcc_compliance_check_check_type_check CHECK (((check_type)::text = ANY ((ARRAY['TERM'::character varying, 'EXCLUDE'::character varying, 'PLATFORM'::character varying])::text[]))),
    CONSTRAINT pcc_compliance_check_result_check CHECK (((result)::text = ANY ((ARRAY['PASS'::character varying, 'HIT'::character varying, 'NO_RULE'::character varying])::text[]))),
    CONSTRAINT pcc_compliance_check_risk_level_check CHECK (((risk_level)::text = ANY ((ARRAY['LOW'::character varying, 'MEDIUM'::character varying, 'HIGH'::character varying])::text[])))
);


--
-- Name: pcc_compliance_check_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.pcc_compliance_check_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: pcc_compliance_check_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.pcc_compliance_check_id_seq OWNED BY public.pcc_compliance_check.id;


--
-- Name: pcc_content_approval; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.pcc_content_approval (
    id bigint NOT NULL,
    org_id character varying(64) NOT NULL,
    job_id bigint NOT NULL,
    decision character varying(16) NOT NULL,
    opinion text,
    delivery_manifest jsonb,
    delivered_at timestamp with time zone,
    actor character varying(64) NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    org_tenant_id integer GENERATED ALWAYS AS (
CASE
    WHEN ((org_id)::text ~ '^[0-9]+$'::text) THEN (org_id)::integer
    ELSE NULL::integer
END) STORED,
    CONSTRAINT pcc_content_approval_decision_check CHECK (((decision)::text = ANY ((ARRAY['APPROVED'::character varying, 'REJECTED'::character varying])::text[])))
);


--
-- Name: pcc_content_approval_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.pcc_content_approval_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: pcc_content_approval_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.pcc_content_approval_id_seq OWNED BY public.pcc_content_approval.id;


--
-- Name: pcc_generation_asset; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.pcc_generation_asset (
    id bigint NOT NULL,
    org_id character varying(64) NOT NULL,
    job_id bigint NOT NULL,
    asset_type character varying(16) DEFAULT 'COPY'::character varying NOT NULL,
    variant_index integer,
    content jsonb NOT NULL,
    review_flags jsonb DEFAULT '{}'::jsonb NOT NULL,
    char_stats jsonb DEFAULT '{}'::jsonb NOT NULL,
    selected boolean DEFAULT false NOT NULL,
    selected_by character varying(64),
    selected_at timestamp with time zone,
    version integer DEFAULT 1 NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    org_tenant_id integer GENERATED ALWAYS AS (
CASE
    WHEN ((org_id)::text ~ '^[0-9]+$'::text) THEN (org_id)::integer
    ELSE NULL::integer
END) STORED,
    CONSTRAINT pcc_generation_asset_asset_type_check CHECK (((asset_type)::text = ANY ((ARRAY['COPY'::character varying, 'IMAGE'::character varying, 'VIDEO'::character varying])::text[]))),
    CONSTRAINT pcc_generation_asset_content_check CHECK ((jsonb_typeof(content) = 'object'::text)),
    CONSTRAINT pcc_generation_asset_version_check CHECK ((version > 0))
);


--
-- Name: pcc_generation_asset_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.pcc_generation_asset_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: pcc_generation_asset_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.pcc_generation_asset_id_seq OWNED BY public.pcc_generation_asset.id;


--
-- Name: pcc_generation_job; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.pcc_generation_job (
    id bigint NOT NULL,
    org_id character varying(64) NOT NULL,
    workflow_template_id bigint NOT NULL,
    idempotency_key character varying(128) NOT NULL,
    job_type character varying(16) NOT NULL,
    status character varying(16) DEFAULT 'QUEUED'::character varying NOT NULL,
    platform character varying(64) NOT NULL,
    language character varying(32) NOT NULL,
    quantity integer NOT NULL,
    fact_snapshot jsonb DEFAULT '{}'::jsonb NOT NULL,
    params_snapshot jsonb DEFAULT '{}'::jsonb NOT NULL,
    external_run_id character varying(128),
    error_code character varying(64),
    error_detail text,
    progress smallint DEFAULT 0 NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    org_tenant_id integer GENERATED ALWAYS AS (
CASE
    WHEN ((org_id)::text ~ '^[0-9]+$'::text) THEN (org_id)::integer
    ELSE NULL::integer
END) STORED,
    CONSTRAINT ck_pcc_generation_job_failed_has_error CHECK ((((status)::text <> 'FAILED'::text) OR (error_code IS NOT NULL))),
    CONSTRAINT pcc_generation_job_job_type_check CHECK (((job_type)::text = ANY ((ARRAY['COPY'::character varying, 'IMAGE'::character varying, 'VIDEO'::character varying])::text[]))),
    CONSTRAINT pcc_generation_job_progress_check CHECK (((progress >= 0) AND (progress <= 100))),
    CONSTRAINT pcc_generation_job_quantity_check CHECK ((quantity > 0)),
    CONSTRAINT pcc_generation_job_status_check CHECK (((status)::text = ANY ((ARRAY['QUEUED'::character varying, 'RUNNING'::character varying, 'SUCCEEDED'::character varying, 'FAILED'::character varying])::text[])))
);


--
-- Name: pcc_generation_job_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.pcc_generation_job_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: pcc_generation_job_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.pcc_generation_job_id_seq OWNED BY public.pcc_generation_job.id;


--
-- Name: pcc_generation_media; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.pcc_generation_media (
    id bigint NOT NULL,
    org_id character varying(64) NOT NULL,
    job_id bigint NOT NULL,
    asset_id bigint,
    file_name character varying(255) NOT NULL,
    mime_type character varying(64) NOT NULL,
    byte_size bigint NOT NULL,
    file_data bytea NOT NULL,
    version integer DEFAULT 1 NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    org_tenant_id integer GENERATED ALWAYS AS (
CASE
    WHEN ((org_id)::text ~ '^[0-9]+$'::text) THEN (org_id)::integer
    ELSE NULL::integer
END) STORED,
    CONSTRAINT ck_pcc_generation_media_byte_size CHECK ((byte_size = octet_length(file_data))),
    CONSTRAINT pcc_generation_media_byte_size_check CHECK ((byte_size > 0)),
    CONSTRAINT pcc_generation_media_mime_type_check CHECK ((((mime_type)::text ~~ 'image/%'::text) OR ((mime_type)::text ~~ 'video/%'::text))),
    CONSTRAINT pcc_generation_media_version_check CHECK ((version > 0))
);


--
-- Name: pcc_generation_media_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.pcc_generation_media_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: pcc_generation_media_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.pcc_generation_media_id_seq OWNED BY public.pcc_generation_media.id;


--
-- Name: pcc_workflow_template; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.pcc_workflow_template (
    id bigint NOT NULL,
    org_id character varying(64) NOT NULL,
    code character varying(64) NOT NULL,
    purpose character varying(16) NOT NULL,
    platform character varying(64),
    status character varying(16) DEFAULT 'DRAFT'::character varying NOT NULL,
    version integer DEFAULT 1 NOT NULL,
    config jsonb DEFAULT '{}'::jsonb NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    org_tenant_id integer GENERATED ALWAYS AS (
CASE
    WHEN ((org_id)::text ~ '^[0-9]+$'::text) THEN (org_id)::integer
    ELSE NULL::integer
END) STORED,
    CONSTRAINT pcc_workflow_template_purpose_check CHECK (((purpose)::text = ANY ((ARRAY['COPY'::character varying, 'IMAGE'::character varying, 'VIDEO'::character varying])::text[]))),
    CONSTRAINT pcc_workflow_template_status_check CHECK (((status)::text = ANY ((ARRAY['DRAFT'::character varying, 'PUBLISHED'::character varying, 'DISABLED'::character varying])::text[]))),
    CONSTRAINT pcc_workflow_template_version_check CHECK ((version > 0))
);


--
-- Name: pcc_workflow_template_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.pcc_workflow_template_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: pcc_workflow_template_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.pcc_workflow_template_id_seq OWNED BY public.pcc_workflow_template.id;


--
-- Name: product; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.product (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    org_id uuid NOT NULL,
    sku character varying(80) NOT NULL,
    title character varying(300),
    category character varying(200),
    attributes jsonb,
    sales_30d numeric(14,2),
    status character varying(16),
    is_deleted boolean DEFAULT false NOT NULL,
    create_time timestamp with time zone DEFAULT now() NOT NULL,
    update_time timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT ck_product_sales CHECK (((sales_30d IS NULL) OR (sales_30d >= (0)::numeric)))
);


--
-- Name: product_sourcing; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.product_sourcing (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    org_id uuid NOT NULL,
    product_id uuid,
    sku character varying(80) NOT NULL,
    supplier_ref character varying(120),
    lead_time_days integer,
    moq integer,
    unit_price numeric(14,4),
    currency character(3),
    is_default boolean DEFAULT false NOT NULL,
    is_deleted boolean DEFAULT false NOT NULL,
    create_time timestamp with time zone DEFAULT now() NOT NULL,
    update_time timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT ck_sourcing_lead CHECK (((lead_time_days IS NULL) OR (lead_time_days >= 0))),
    CONSTRAINT ck_sourcing_moq CHECK (((moq IS NULL) OR (moq > 0))),
    CONSTRAINT ck_sourcing_price CHECK (((unit_price IS NULL) OR (unit_price >= (0)::numeric)))
);


--
-- Name: purchases; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.purchases (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    org_id uuid NOT NULL,
    source_id uuid NOT NULL,
    po_no character varying(64) NOT NULL,
    amount numeric(14,2) NOT NULL,
    currency character(3) NOT NULL,
    voucher_key character varying(300),
    valid_from date NOT NULL,
    valid_to date,
    remark text,
    is_deleted boolean DEFAULT false NOT NULL,
    create_time timestamp with time zone DEFAULT now() NOT NULL,
    update_time timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT ck_purchase_amount CHECK ((amount >= (0)::numeric)),
    CONSTRAINT ck_purchase_valid CHECK (((valid_to IS NULL) OR (valid_to >= valid_from)))
);


--
-- Name: receipt_batch; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.receipt_batch (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    org_id uuid NOT NULL,
    plan_id uuid NOT NULL,
    batch_no integer NOT NULL,
    qty integer,
    received_at timestamp with time zone,
    inspected_result character varying(16),
    recorded_by uuid,
    is_deleted boolean DEFAULT false NOT NULL,
    create_time timestamp with time zone DEFAULT now() NOT NULL,
    update_time timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT ck_batch_no CHECK ((batch_no >= 1)),
    CONSTRAINT ck_batch_qty CHECK (((qty IS NULL) OR (qty > 0)))
);


--
-- Name: replenishment_cost_card; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.replenishment_cost_card (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    org_id uuid NOT NULL,
    sku character varying(80) NOT NULL,
    version integer DEFAULT 1 NOT NULL,
    cost_items jsonb NOT NULL,
    valid_from date NOT NULL,
    valid_to date,
    is_deleted boolean DEFAULT false NOT NULL,
    create_time timestamp with time zone DEFAULT now() NOT NULL,
    update_time timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT ck_card_valid CHECK (((valid_to IS NULL) OR (valid_to >= valid_from)))
);


--
-- Name: replenishment_event; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.replenishment_event (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    org_id uuid NOT NULL,
    plan_id uuid NOT NULL,
    event_type character varying(32) NOT NULL,
    payload jsonb,
    actor_id uuid,
    is_deleted boolean DEFAULT false NOT NULL,
    create_time timestamp with time zone DEFAULT now() NOT NULL,
    update_time timestamp with time zone DEFAULT now() NOT NULL
);


--
-- Name: replenishment_plan; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.replenishment_plan (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    org_id uuid NOT NULL,
    product_id uuid,
    sku character varying(80) NOT NULL,
    planning_mode character varying(16) NOT NULL,
    status public.plan_status_enum DEFAULT 'READY_FOR_REVIEW'::public.plan_status_enum NOT NULL,
    expected_qty integer,
    snapshot jsonb NOT NULL,
    fact_signature character varying(128),
    idempotency_key character varying(64),
    submitted_by uuid NOT NULL,
    approved_by uuid,
    approved_at timestamp with time zone,
    version integer DEFAULT 1 NOT NULL,
    is_deleted boolean DEFAULT false NOT NULL,
    create_time timestamp with time zone DEFAULT now() NOT NULL,
    update_time timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT ck_plan_mode CHECK (((planning_mode)::text = ANY (ARRAY[('NORMAL'::character varying)::text, ('INTELLIGENT'::character varying)::text]))),
    CONSTRAINT ck_plan_sep CHECK (((approved_by IS NULL) OR (approved_by <> submitted_by)))
);


--
-- Name: reviews; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.reviews (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    org_id uuid NOT NULL,
    study_id uuid NOT NULL,
    reviewer_id uuid NOT NULL,
    submitted_by uuid NOT NULL,
    decision public.review_decision_enum NOT NULL,
    reason text,
    gate_snapshot jsonb NOT NULL,
    idempotency_key character varying(64),
    reviewed_at timestamp with time zone DEFAULT now() NOT NULL,
    is_deleted boolean DEFAULT false NOT NULL,
    create_time timestamp with time zone DEFAULT now() NOT NULL,
    update_time timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT ck_review_reason CHECK (((decision <> 'REJECTED'::public.review_decision_enum) OR (length(COALESCE(reason, ''::text)) > 0))),
    CONSTRAINT ck_review_sep CHECK ((reviewer_id <> submitted_by))
);


--
-- Name: sales_order; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.sales_order (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    org_id uuid NOT NULL,
    order_no character varying(64) NOT NULL,
    platform character varying(32) NOT NULL,
    store_ref character varying(64),
    order_date date NOT NULL,
    status character varying(16),
    currency character(3),
    total_amount numeric(14,2),
    is_deleted boolean DEFAULT false NOT NULL,
    create_time timestamp with time zone DEFAULT now() NOT NULL,
    update_time timestamp with time zone DEFAULT now() NOT NULL
);


--
-- Name: sales_order_item; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.sales_order_item (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    org_id uuid NOT NULL,
    order_id uuid NOT NULL,
    sku character varying(80) NOT NULL,
    qty integer NOT NULL,
    amount numeric(14,2),
    item_status character varying(16),
    is_deleted boolean DEFAULT false NOT NULL,
    create_time timestamp with time zone DEFAULT now() NOT NULL,
    update_time timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT ck_item_qty CHECK ((qty > 0))
);


--
-- Name: sources; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.sources (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    org_id uuid NOT NULL,
    source_type public.source_type_enum NOT NULL,
    data_nature public.data_nature_enum NOT NULL,
    name character varying(120) NOT NULL,
    vendor character varying(120),
    credential_ref character varying(200),
    field_mapping jsonb DEFAULT '{}'::jsonb NOT NULL,
    active boolean DEFAULT true NOT NULL,
    remark text,
    version integer DEFAULT 1 NOT NULL,
    is_deleted boolean DEFAULT false NOT NULL,
    create_time timestamp with time zone DEFAULT now() NOT NULL,
    update_time timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT ck_sources_vendor CHECK (((source_type <> 'VENDOR'::public.source_type_enum) OR ((vendor IS NOT NULL) AND (credential_ref IS NOT NULL))))
);


--
-- Name: studies; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.studies (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    org_id uuid NOT NULL,
    sku character varying(80) NOT NULL,
    platform character varying(32) NOT NULL,
    region character varying(16) NOT NULL,
    title character varying(300),
    category_path character varying(300),
    data_nature public.data_nature_enum NOT NULL,
    status public.study_status_enum NOT NULL,
    calc_state public.study_calc_state_enum DEFAULT 'NONE'::public.study_calc_state_enum NOT NULL,
    missing_items jsonb DEFAULT '[]'::jsonb NOT NULL,
    week_count integer DEFAULT 0 NOT NULL,
    rank_score numeric(8,4),
    score_detail jsonb,
    created_by uuid NOT NULL,
    submitted_by uuid,
    rejected_from uuid,
    version integer DEFAULT 1 NOT NULL,
    is_deleted boolean DEFAULT false NOT NULL,
    create_time timestamp with time zone DEFAULT now() NOT NULL,
    update_time timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT ck_study_weeks CHECK ((week_count >= 0))
);


--
-- Name: study_sources; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.study_sources (
    study_id uuid NOT NULL,
    source_id uuid NOT NULL,
    org_id uuid NOT NULL,
    added_at timestamp with time zone DEFAULT now() NOT NULL,
    is_deleted boolean DEFAULT false NOT NULL,
    create_time timestamp with time zone DEFAULT now() NOT NULL,
    update_time timestamp with time zone DEFAULT now() NOT NULL
);


--
-- Name: sys_department_permission; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.sys_department_permission (
    id integer NOT NULL,
    org_id integer NOT NULL,
    dept_id integer NOT NULL,
    perm_id integer NOT NULL,
    created_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    updated_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    created_by integer,
    updated_by integer,
    deleted boolean DEFAULT false NOT NULL
);


--
-- Name: sys_department_permission_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

ALTER TABLE public.sys_department_permission ALTER COLUMN id ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME public.sys_department_permission_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: sys_org; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.sys_org (
    id integer NOT NULL,
    org_code character varying(64) NOT NULL,
    org_name character varying(128) NOT NULL,
    domain character varying(128),
    package_code character varying(64),
    data_region character varying(64),
    status character varying(16) DEFAULT 'ACTIVE'::character varying NOT NULL,
    expire_at timestamp without time zone,
    created_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    updated_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    created_by integer,
    updated_by integer,
    deleted boolean DEFAULT false NOT NULL
);


--
-- Name: sys_org_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

ALTER TABLE public.sys_org ALTER COLUMN id ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME public.sys_org_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: sys_permission; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.sys_permission (
    id integer NOT NULL,
    perm_name character varying(128) NOT NULL,
    perm_key character varying(128) NOT NULL,
    perm_type character varying(16) DEFAULT 'API'::character varying NOT NULL,
    status character varying(16) DEFAULT 'ENABLED'::character varying NOT NULL,
    created_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    updated_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    created_by integer,
    updated_by integer,
    deleted boolean DEFAULT false NOT NULL,
    description character varying(512),
    module_name character varying(64) DEFAULT '未分类'::character varying NOT NULL,
    parent_id integer
);


--
-- Name: COLUMN sys_permission.module_name; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.sys_permission.module_name IS '项目权限表所属 Agent 模块或系统管理分类';


--
-- Name: sys_permission_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

ALTER TABLE public.sys_permission ALTER COLUMN id ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME public.sys_permission_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: sys_role; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.sys_role (
    id integer NOT NULL,
    org_id integer NOT NULL,
    role_name character varying(64) NOT NULL,
    role_code character varying(64) NOT NULL,
    description character varying(512),
    data_scope character varying(32) DEFAULT 'SELF'::character varying NOT NULL,
    sort integer DEFAULT 0 NOT NULL,
    status character varying(16) DEFAULT 'ENABLED'::character varying NOT NULL,
    created_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    updated_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    created_by integer,
    updated_by integer,
    deleted boolean DEFAULT false NOT NULL
);


--
-- Name: sys_role_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

ALTER TABLE public.sys_role ALTER COLUMN id ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME public.sys_role_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: sys_role_permission; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.sys_role_permission (
    id integer NOT NULL,
    role_id integer NOT NULL,
    perm_id integer NOT NULL,
    created_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    updated_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    created_by integer,
    updated_by integer,
    deleted boolean DEFAULT false NOT NULL
);


--
-- Name: sys_role_permission_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

ALTER TABLE public.sys_role_permission ALTER COLUMN id ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME public.sys_role_permission_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: sys_user; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.sys_user (
    id integer NOT NULL,
    org_id integer NOT NULL,
    dept_id integer,
    username character varying(64) NOT NULL,
    password_hash character varying(255) NOT NULL,
    real_name character varying(64) NOT NULL,
    email character varying(128),
    phone character varying(32),
    data_scope character varying(32) DEFAULT 'SELF'::character varying NOT NULL,
    status character varying(16) DEFAULT 'ENABLED'::character varying NOT NULL,
    last_login_at timestamp without time zone,
    created_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    updated_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    created_by integer,
    updated_by integer,
    deleted boolean DEFAULT false NOT NULL
);


--
-- Name: sys_user_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

ALTER TABLE public.sys_user ALTER COLUMN id ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME public.sys_user_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: sys_user_role; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.sys_user_role (
    id integer NOT NULL,
    org_id integer NOT NULL,
    user_id integer NOT NULL,
    role_id integer NOT NULL,
    created_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    updated_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    created_by integer,
    updated_by integer,
    deleted boolean DEFAULT false NOT NULL
);


--
-- Name: sys_user_role_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

ALTER TABLE public.sys_user_role ALTER COLUMN id ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME public.sys_user_role_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: sys_user_shop; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.sys_user_shop (
    id integer NOT NULL,
    org_id integer NOT NULL,
    user_id integer NOT NULL,
    shop_id integer NOT NULL,
    created_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    updated_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    created_by integer,
    updated_by integer,
    deleted boolean DEFAULT false NOT NULL
);


--
-- Name: sys_user_shop_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

ALTER TABLE public.sys_user_shop ALTER COLUMN id ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME public.sys_user_shop_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: trials; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.trials (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    org_id uuid NOT NULL,
    study_id uuid NOT NULL,
    round_no integer NOT NULL,
    status public.trial_status_enum DEFAULT 'PLANNED'::public.trial_status_enum NOT NULL,
    target_units integer,
    target_price numeric(14,4),
    budget numeric(14,2),
    start_date date,
    end_date date,
    actual_units integer,
    actual_revenue numeric(14,2),
    actual_profit numeric(14,2),
    suggestion public.trial_suggestion_enum,
    suggestion_basis jsonb,
    decided_at timestamp with time zone,
    decided_by uuid,
    reason text,
    frozen boolean DEFAULT false NOT NULL,
    version integer DEFAULT 1 NOT NULL,
    is_deleted boolean DEFAULT false NOT NULL,
    create_time timestamp with time zone DEFAULT now() NOT NULL,
    update_time timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT ck_trial_actual CHECK ((((actual_units IS NULL) OR (actual_units >= 0)) AND ((actual_revenue IS NULL) OR (actual_revenue >= (0)::numeric)))),
    CONSTRAINT ck_trial_decide CHECK (((decided_at IS NULL) OR ((decided_by IS NOT NULL) AND (length(COALESCE(reason, ''::text)) > 0)))),
    CONSTRAINT ck_trial_plan CHECK ((((target_units IS NULL) OR (target_units > 0)) AND ((target_price IS NULL) OR (target_price > (0)::numeric)) AND ((budget IS NULL) OR (budget > (0)::numeric)))),
    CONSTRAINT ck_trial_range CHECK (((end_date IS NULL) OR (start_date IS NULL) OR (end_date >= start_date))),
    CONSTRAINT ck_trial_round CHECK ((round_no >= 1))
);


--
-- Name: weekly_facts; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.weekly_facts (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    org_id uuid NOT NULL,
    study_id uuid NOT NULL,
    week_start date NOT NULL,
    paid_units integer,
    refund_units integer,
    gross_sales numeric(14,2),
    discount numeric(14,2),
    refund_amount numeric(14,2),
    unit_cost numeric(14,4),
    freight_cost numeric(14,4),
    platform_fee numeric(14,2),
    fulfillment_fee numeric(14,2),
    return_fee numeric(14,2),
    storage_fee numeric(14,2),
    ad_fee numeric(14,2),
    currency character(3) NOT NULL,
    source_job_id uuid,
    raw_row_snapshot jsonb,
    calc_version integer DEFAULT 1 NOT NULL,
    updated_by uuid,
    is_deleted boolean DEFAULT false NOT NULL,
    create_time timestamp with time zone DEFAULT now() NOT NULL,
    update_time timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT ck_fact_monday CHECK ((EXTRACT(isodow FROM week_start) = (1)::numeric)),
    CONSTRAINT ck_fact_money CHECK ((((gross_sales IS NULL) OR (gross_sales >= (0)::numeric)) AND ((discount IS NULL) OR (discount >= (0)::numeric)) AND ((refund_amount IS NULL) OR (refund_amount >= (0)::numeric)) AND ((unit_cost IS NULL) OR (unit_cost >= (0)::numeric)) AND ((freight_cost IS NULL) OR (freight_cost >= (0)::numeric)) AND ((platform_fee IS NULL) OR (platform_fee >= (0)::numeric)) AND ((fulfillment_fee IS NULL) OR (fulfillment_fee >= (0)::numeric)) AND ((return_fee IS NULL) OR (return_fee >= (0)::numeric)) AND ((storage_fee IS NULL) OR (storage_fee >= (0)::numeric)) AND ((ad_fee IS NULL) OR (ad_fee >= (0)::numeric)))),
    CONSTRAINT ck_fact_units CHECK ((((paid_units IS NULL) OR (paid_units >= 0)) AND ((refund_units IS NULL) OR (refund_units >= 0))))
);


--
-- Name: workflow_template; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.workflow_template (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    org_id uuid NOT NULL,
    purpose character varying(16) NOT NULL,
    platform character varying(32),
    status character varying(16) DEFAULT 'DRAFT'::character varying NOT NULL,
    api_graph jsonb,
    version integer DEFAULT 1 NOT NULL,
    is_deleted boolean DEFAULT false NOT NULL,
    create_time timestamp with time zone DEFAULT now() NOT NULL,
    update_time timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT ck_wf_purpose CHECK (((purpose)::text = ANY (ARRAY[('CONTENT'::character varying)::text, ('IMAGE'::character varying)::text, ('VIDEO'::character varying)::text])))
);


--
-- Name: audit_log id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.audit_log ALTER COLUMN id SET DEFAULT nextval('public.audit_log_id_seq'::regclass);


--
-- Name: bi_approval_flow id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.bi_approval_flow ALTER COLUMN id SET DEFAULT nextval('public.bi_approval_flow_id_seq'::regclass);


--
-- Name: bi_dashboard_access_request id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.bi_dashboard_access_request ALTER COLUMN id SET DEFAULT nextval('public.bi_dashboard_access_request_id_seq'::regclass);


--
-- Name: bi_dashboard_designs id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.bi_dashboard_designs ALTER COLUMN id SET DEFAULT nextval('public.bi_dashboard_designs_id_seq'::regclass);


--
-- Name: bi_operation_log id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.bi_operation_log ALTER COLUMN id SET DEFAULT nextval('public.bi_operation_log_id_seq'::regclass);


--
-- Name: bi_publish_approvals id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.bi_publish_approvals ALTER COLUMN id SET DEFAULT nextval('public.bi_publish_approvals_id_seq'::regclass);


--
-- Name: pcc_agent_run id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.pcc_agent_run ALTER COLUMN id SET DEFAULT nextval('public.pcc_agent_run_id_seq'::regclass);


--
-- Name: pcc_asset_reference id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.pcc_asset_reference ALTER COLUMN id SET DEFAULT nextval('public.pcc_asset_reference_id_seq'::regclass);


--
-- Name: pcc_compliance_check id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.pcc_compliance_check ALTER COLUMN id SET DEFAULT nextval('public.pcc_compliance_check_id_seq'::regclass);


--
-- Name: pcc_content_approval id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.pcc_content_approval ALTER COLUMN id SET DEFAULT nextval('public.pcc_content_approval_id_seq'::regclass);


--
-- Name: pcc_generation_asset id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.pcc_generation_asset ALTER COLUMN id SET DEFAULT nextval('public.pcc_generation_asset_id_seq'::regclass);


--
-- Name: pcc_generation_job id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.pcc_generation_job ALTER COLUMN id SET DEFAULT nextval('public.pcc_generation_job_id_seq'::regclass);


--
-- Name: pcc_generation_media id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.pcc_generation_media ALTER COLUMN id SET DEFAULT nextval('public.pcc_generation_media_id_seq'::regclass);


--
-- Name: pcc_workflow_template id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.pcc_workflow_template ALTER COLUMN id SET DEFAULT nextval('public.pcc_workflow_template_id_seq'::regclass);


--
-- Name: after_sales_case after_sales_case_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.after_sales_case
    ADD CONSTRAINT after_sales_case_pkey PRIMARY KEY (id);


--
-- Name: agent_run agent_run_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.agent_run
    ADD CONSTRAINT agent_run_pkey PRIMARY KEY (id);


--
-- Name: ai_call_log ai_call_log_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.ai_call_log
    ADD CONSTRAINT ai_call_log_pkey PRIMARY KEY (id);


--
-- Name: alembic_version alembic_version_pkc; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.alembic_version
    ADD CONSTRAINT alembic_version_pkc PRIMARY KEY (version_num);


--
-- Name: audit_log audit_log_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.audit_log
    ADD CONSTRAINT audit_log_pkey PRIMARY KEY (id);


--
-- Name: bi_approval_flow bi_approval_flow_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.bi_approval_flow
    ADD CONSTRAINT bi_approval_flow_pkey PRIMARY KEY (id);


--
-- Name: bi_conversation_turn bi_conversation_turn_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.bi_conversation_turn
    ADD CONSTRAINT bi_conversation_turn_pkey PRIMARY KEY (id);


--
-- Name: bi_dashboard_access_request bi_dashboard_access_request_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.bi_dashboard_access_request
    ADD CONSTRAINT bi_dashboard_access_request_pkey PRIMARY KEY (id);


--
-- Name: bi_dashboard_access_request bi_dashboard_access_request_request_no_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.bi_dashboard_access_request
    ADD CONSTRAINT bi_dashboard_access_request_request_no_key UNIQUE (request_no);


--
-- Name: bi_dashboard_design bi_dashboard_design_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.bi_dashboard_design
    ADD CONSTRAINT bi_dashboard_design_pkey PRIMARY KEY (id);


--
-- Name: bi_dashboard_designs bi_dashboard_designs_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.bi_dashboard_designs
    ADD CONSTRAINT bi_dashboard_designs_pkey PRIMARY KEY (id);


--
-- Name: bi_operation_log bi_operation_log_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.bi_operation_log
    ADD CONSTRAINT bi_operation_log_pkey PRIMARY KEY (id);


--
-- Name: bi_publish_approvals bi_publish_approvals_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.bi_publish_approvals
    ADD CONSTRAINT bi_publish_approvals_pkey PRIMARY KEY (id);


--
-- Name: biz_department_closure biz_department_closure_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.biz_department_closure
    ADD CONSTRAINT biz_department_closure_pkey PRIMARY KEY (org_id, ancestor_id, descendant_id);


--
-- Name: biz_department_manager_history biz_department_manager_history_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.biz_department_manager_history
    ADD CONSTRAINT biz_department_manager_history_pkey PRIMARY KEY (id);


--
-- Name: biz_department biz_department_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.biz_department
    ADD CONSTRAINT biz_department_pkey PRIMARY KEY (id);


--
-- Name: biz_department_shop biz_department_shop_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.biz_department_shop
    ADD CONSTRAINT biz_department_shop_pkey PRIMARY KEY (id);


--
-- Name: biz_platform_config biz_platform_config_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.biz_platform_config
    ADD CONSTRAINT biz_platform_config_pkey PRIMARY KEY (id);


--
-- Name: biz_shop biz_shop_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.biz_shop
    ADD CONSTRAINT biz_shop_pkey PRIMARY KEY (id);


--
-- Name: case_attachment case_attachment_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.case_attachment
    ADD CONSTRAINT case_attachment_pkey PRIMARY KEY (id);


--
-- Name: compliance_check compliance_check_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.compliance_check
    ADD CONSTRAINT compliance_check_pkey PRIMARY KEY (id);


--
-- Name: conversation_message conversation_message_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.conversation_message
    ADD CONSTRAINT conversation_message_pkey PRIMARY KEY (id);


--
-- Name: conversation_order_link conversation_order_link_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.conversation_order_link
    ADD CONSTRAINT conversation_order_link_pkey PRIMARY KEY (id);


--
-- Name: conversation conversation_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.conversation
    ADD CONSTRAINT conversation_pkey PRIMARY KEY (id);


--
-- Name: customer_intent_analysis customer_intent_analysis_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.customer_intent_analysis
    ADD CONSTRAINT customer_intent_analysis_pkey PRIMARY KEY (id);


--
-- Name: customer_listing customer_listing_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.customer_listing
    ADD CONSTRAINT customer_listing_pkey PRIMARY KEY (id);


--
-- Name: customer_recommended_product customer_recommended_product_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.customer_recommended_product
    ADD CONSTRAINT customer_recommended_product_pkey PRIMARY KEY (id);


--
-- Name: customer_reply_draft customer_reply_draft_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.customer_reply_draft
    ADD CONSTRAINT customer_reply_draft_pkey PRIMARY KEY (id);


--
-- Name: demand_profile demand_profile_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.demand_profile
    ADD CONSTRAINT demand_profile_pkey PRIMARY KEY (profile_id);


--
-- Name: forecast_actual_override forecast_actual_override_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.forecast_actual_override
    ADD CONSTRAINT forecast_actual_override_pkey PRIMARY KEY (override_id);


--
-- Name: forecast_audit_log forecast_audit_log_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.forecast_audit_log
    ADD CONSTRAINT forecast_audit_log_pkey PRIMARY KEY (audit_id);


--
-- Name: forecast_backtest_point forecast_backtest_point_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.forecast_backtest_point
    ADD CONSTRAINT forecast_backtest_point_pkey PRIMARY KEY (point_id);


--
-- Name: forecast_evaluation forecast_evaluation_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.forecast_evaluation
    ADD CONSTRAINT forecast_evaluation_pkey PRIMARY KEY (evaluation_id);


--
-- Name: forecast_idempotency_record forecast_idempotency_record_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.forecast_idempotency_record
    ADD CONSTRAINT forecast_idempotency_record_pkey PRIMARY KEY (org_id, idempotency_key);


--
-- Name: forecast_model_definition forecast_model_definition_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.forecast_model_definition
    ADD CONSTRAINT forecast_model_definition_pkey PRIMARY KEY (model_id);


--
-- Name: forecast_point forecast_point_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.forecast_point
    ADD CONSTRAINT forecast_point_pkey PRIMARY KEY (point_id);


--
-- Name: forecast_run forecast_run_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.forecast_run
    ADD CONSTRAINT forecast_run_pkey PRIMARY KEY (run_id);


--
-- Name: generation_asset generation_asset_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.generation_asset
    ADD CONSTRAINT generation_asset_pkey PRIMARY KEY (id);


--
-- Name: generation_job generation_job_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.generation_job
    ADD CONSTRAINT generation_job_pkey PRIMARY KEY (id);


--
-- Name: generation_media generation_media_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.generation_media
    ADD CONSTRAINT generation_media_pkey PRIMARY KEY (id);


--
-- Name: import_jobs import_jobs_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.import_jobs
    ADD CONSTRAINT import_jobs_pkey PRIMARY KEY (id);


--
-- Name: inventory_position inventory_position_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.inventory_position
    ADD CONSTRAINT inventory_position_pkey PRIMARY KEY (id);


--
-- Name: logistics_voucher logistics_voucher_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.logistics_voucher
    ADD CONSTRAINT logistics_voucher_pkey PRIMARY KEY (id);


--
-- Name: outbox_event outbox_event_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.outbox_event
    ADD CONSTRAINT outbox_event_pkey PRIMARY KEY (id);


--
-- Name: pcc_agent_run pcc_agent_run_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.pcc_agent_run
    ADD CONSTRAINT pcc_agent_run_pkey PRIMARY KEY (id);


--
-- Name: pcc_asset_reference pcc_asset_reference_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.pcc_asset_reference
    ADD CONSTRAINT pcc_asset_reference_pkey PRIMARY KEY (id);


--
-- Name: pcc_compliance_check pcc_compliance_check_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.pcc_compliance_check
    ADD CONSTRAINT pcc_compliance_check_pkey PRIMARY KEY (id);


--
-- Name: pcc_content_approval pcc_content_approval_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.pcc_content_approval
    ADD CONSTRAINT pcc_content_approval_pkey PRIMARY KEY (id);


--
-- Name: pcc_generation_asset pcc_generation_asset_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.pcc_generation_asset
    ADD CONSTRAINT pcc_generation_asset_pkey PRIMARY KEY (id);


--
-- Name: pcc_generation_job pcc_generation_job_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.pcc_generation_job
    ADD CONSTRAINT pcc_generation_job_pkey PRIMARY KEY (id);


--
-- Name: pcc_generation_media pcc_generation_media_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.pcc_generation_media
    ADD CONSTRAINT pcc_generation_media_pkey PRIMARY KEY (id);


--
-- Name: pcc_workflow_template pcc_workflow_template_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.pcc_workflow_template
    ADD CONSTRAINT pcc_workflow_template_pkey PRIMARY KEY (id);


--
-- Name: product product_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.product
    ADD CONSTRAINT product_pkey PRIMARY KEY (id);


--
-- Name: product_sourcing product_sourcing_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.product_sourcing
    ADD CONSTRAINT product_sourcing_pkey PRIMARY KEY (id);


--
-- Name: purchases purchases_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.purchases
    ADD CONSTRAINT purchases_pkey PRIMARY KEY (id);


--
-- Name: receipt_batch receipt_batch_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.receipt_batch
    ADD CONSTRAINT receipt_batch_pkey PRIMARY KEY (id);


--
-- Name: replenishment_cost_card replenishment_cost_card_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.replenishment_cost_card
    ADD CONSTRAINT replenishment_cost_card_pkey PRIMARY KEY (id);


--
-- Name: replenishment_event replenishment_event_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.replenishment_event
    ADD CONSTRAINT replenishment_event_pkey PRIMARY KEY (id);


--
-- Name: replenishment_plan replenishment_plan_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.replenishment_plan
    ADD CONSTRAINT replenishment_plan_pkey PRIMARY KEY (id);


--
-- Name: reviews reviews_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.reviews
    ADD CONSTRAINT reviews_pkey PRIMARY KEY (id);


--
-- Name: sales_order_item sales_order_item_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.sales_order_item
    ADD CONSTRAINT sales_order_item_pkey PRIMARY KEY (id);


--
-- Name: sales_order sales_order_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.sales_order
    ADD CONSTRAINT sales_order_pkey PRIMARY KEY (id);


--
-- Name: sources sources_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.sources
    ADD CONSTRAINT sources_pkey PRIMARY KEY (id);


--
-- Name: studies studies_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.studies
    ADD CONSTRAINT studies_pkey PRIMARY KEY (id);


--
-- Name: study_sources study_sources_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.study_sources
    ADD CONSTRAINT study_sources_pkey PRIMARY KEY (study_id, source_id);


--
-- Name: sys_department_permission sys_department_permission_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.sys_department_permission
    ADD CONSTRAINT sys_department_permission_pkey PRIMARY KEY (id);


--
-- Name: sys_org sys_org_org_code_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.sys_org
    ADD CONSTRAINT sys_org_org_code_key UNIQUE (org_code);


--
-- Name: sys_org sys_org_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.sys_org
    ADD CONSTRAINT sys_org_pkey PRIMARY KEY (id);


--
-- Name: sys_permission sys_permission_perm_key_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.sys_permission
    ADD CONSTRAINT sys_permission_perm_key_key UNIQUE (perm_key);


--
-- Name: sys_permission sys_permission_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.sys_permission
    ADD CONSTRAINT sys_permission_pkey PRIMARY KEY (id);


--
-- Name: sys_role_permission sys_role_permission_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.sys_role_permission
    ADD CONSTRAINT sys_role_permission_pkey PRIMARY KEY (id);


--
-- Name: sys_role sys_role_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.sys_role
    ADD CONSTRAINT sys_role_pkey PRIMARY KEY (id);


--
-- Name: sys_user sys_user_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.sys_user
    ADD CONSTRAINT sys_user_pkey PRIMARY KEY (id);


--
-- Name: sys_user_role sys_user_role_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.sys_user_role
    ADD CONSTRAINT sys_user_role_pkey PRIMARY KEY (id);


--
-- Name: sys_user_shop sys_user_shop_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.sys_user_shop
    ADD CONSTRAINT sys_user_shop_pkey PRIMARY KEY (id);


--
-- Name: trials trials_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.trials
    ADD CONSTRAINT trials_pkey PRIMARY KEY (id);


--
-- Name: forecast_backtest_point uq_backtest_run_date; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.forecast_backtest_point
    ADD CONSTRAINT uq_backtest_run_date UNIQUE (run_id, target_date);


--
-- Name: bi_dashboard_designs uq_bdd_org_dashboard; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.bi_dashboard_designs
    ADD CONSTRAINT uq_bdd_org_dashboard UNIQUE (org_id, dashboard_id);


--
-- Name: bi_publish_approvals uq_bpa_approval_no; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.bi_publish_approvals
    ADD CONSTRAINT uq_bpa_approval_no UNIQUE (approval_no);


--
-- Name: biz_department uq_department_org_code; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.biz_department
    ADD CONSTRAINT uq_department_org_code UNIQUE (org_id, dept_code);


--
-- Name: sys_department_permission uq_department_permission; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.sys_department_permission
    ADD CONSTRAINT uq_department_permission UNIQUE (org_id, dept_id, perm_id);


--
-- Name: biz_department_shop uq_dept_shop; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.biz_department_shop
    ADD CONSTRAINT uq_dept_shop UNIQUE (org_id, dept_id, shop_id);


--
-- Name: forecast_point uq_forecast_point_run_date; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.forecast_point
    ADD CONSTRAINT uq_forecast_point_run_date UNIQUE (run_id, target_date);


--
-- Name: forecast_model_definition uq_model_org_code_version; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.forecast_model_definition
    ADD CONSTRAINT uq_model_org_code_version UNIQUE (org_id, model_code, model_version);


--
-- Name: forecast_actual_override uq_override_run_date_version; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.forecast_actual_override
    ADD CONSTRAINT uq_override_run_date_version UNIQUE (run_id, target_date, version);


--
-- Name: pcc_agent_run uq_pcc_agent_run_id_org; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.pcc_agent_run
    ADD CONSTRAINT uq_pcc_agent_run_id_org UNIQUE (id, org_id);


--
-- Name: pcc_generation_asset uq_pcc_generation_asset_id_org; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.pcc_generation_asset
    ADD CONSTRAINT uq_pcc_generation_asset_id_org UNIQUE (id, org_id);


--
-- Name: pcc_generation_job uq_pcc_generation_job_id_org; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.pcc_generation_job
    ADD CONSTRAINT uq_pcc_generation_job_id_org UNIQUE (id, org_id);


--
-- Name: pcc_generation_job uq_pcc_generation_job_idem; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.pcc_generation_job
    ADD CONSTRAINT uq_pcc_generation_job_idem UNIQUE (org_id, idempotency_key);


--
-- Name: pcc_generation_media uq_pcc_generation_media_file; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.pcc_generation_media
    ADD CONSTRAINT uq_pcc_generation_media_file UNIQUE (org_id, job_id, mime_type, file_name);


--
-- Name: pcc_generation_media uq_pcc_generation_media_id_org; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.pcc_generation_media
    ADD CONSTRAINT uq_pcc_generation_media_id_org UNIQUE (id, org_id);


--
-- Name: pcc_workflow_template uq_pcc_workflow_template_code_version; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.pcc_workflow_template
    ADD CONSTRAINT uq_pcc_workflow_template_code_version UNIQUE (org_id, code, version);


--
-- Name: pcc_workflow_template uq_pcc_workflow_template_id_org; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.pcc_workflow_template
    ADD CONSTRAINT uq_pcc_workflow_template_id_org UNIQUE (id, org_id);


--
-- Name: biz_platform_config uq_platform_config_shop; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.biz_platform_config
    ADD CONSTRAINT uq_platform_config_shop UNIQUE (org_id, shop_id);


--
-- Name: demand_profile uq_profile_org_sku_date; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.demand_profile
    ADD CONSTRAINT uq_profile_org_sku_date UNIQUE (org_id, sku_id, as_of_date);


--
-- Name: sys_role uq_role_org_code; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.sys_role
    ADD CONSTRAINT uq_role_org_code UNIQUE (org_id, role_code);


--
-- Name: sys_role_permission uq_role_permission; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.sys_role_permission
    ADD CONSTRAINT uq_role_permission UNIQUE (role_id, perm_id);


--
-- Name: biz_shop uq_shop_org_code; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.biz_shop
    ADD CONSTRAINT uq_shop_org_code UNIQUE (org_id, shop_code);


--
-- Name: sys_user uq_user_org_email; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.sys_user
    ADD CONSTRAINT uq_user_org_email UNIQUE (org_id, email);


--
-- Name: sys_user uq_user_org_username; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.sys_user
    ADD CONSTRAINT uq_user_org_username UNIQUE (org_id, username);


--
-- Name: sys_user_role uq_user_role; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.sys_user_role
    ADD CONSTRAINT uq_user_role UNIQUE (user_id, role_id);


--
-- Name: sys_user_shop uq_user_shop; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.sys_user_shop
    ADD CONSTRAINT uq_user_shop UNIQUE (user_id, shop_id);


--
-- Name: weekly_facts weekly_facts_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.weekly_facts
    ADD CONSTRAINT weekly_facts_pkey PRIMARY KEY (id);


--
-- Name: workflow_template workflow_template_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.workflow_template
    ADD CONSTRAINT workflow_template_pkey PRIMARY KEY (id);


--
-- Name: idx_bdar_approve; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_bdar_approve ON public.bi_dashboard_access_request USING btree (org_id, target_dept_id, status, created_at DESC);


--
-- Name: idx_bdar_requester; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_bdar_requester ON public.bi_dashboard_access_request USING btree (org_id, requester_id, created_at DESC);


--
-- Name: idx_bdd_gin_draft; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_bdd_gin_draft ON public.bi_dashboard_designs USING gin (draft_layout);


--
-- Name: idx_bdd_org_status; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_bdd_org_status ON public.bi_dashboard_designs USING btree (org_id, board_status);


--
-- Name: idx_bol_dash_time; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_bol_dash_time ON public.bi_operation_log USING btree (org_id, dashboard_id, created_at DESC);


--
-- Name: idx_bol_scope; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_bol_scope ON public.bi_operation_log USING btree (org_id, scope_level, dept_id, created_at DESC);


--
-- Name: idx_bpa_one_pending; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX idx_bpa_one_pending ON public.bi_publish_approvals USING btree (org_id, dashboard_id) WHERE ((status)::text = 'pending'::text);


--
-- Name: idx_bpa_scope_pending; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_bpa_scope_pending ON public.bi_publish_approvals USING btree (org_id, scope_level, dept_id, status) WHERE ((status)::text = 'pending'::text);


--
-- Name: idx_dept_shop_dept; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_dept_shop_dept ON public.biz_department_shop USING btree (dept_id) WHERE (deleted = false);


--
-- Name: idx_dept_shop_shop; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_dept_shop_shop ON public.biz_department_shop USING btree (shop_id) WHERE (deleted = false);


--
-- Name: ix_agent_run_job; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ix_agent_run_job ON public.agent_run USING btree (job_id) WHERE (is_deleted = false);


--
-- Name: ix_ai_log_degraded; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ix_ai_log_degraded ON public.ai_call_log USING btree (org_id, degraded, create_time DESC);


--
-- Name: ix_ai_log_fp; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ix_ai_log_fp ON public.ai_call_log USING btree (org_id, input_fingerprint);


--
-- Name: ix_ai_log_study; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ix_ai_log_study ON public.ai_call_log USING btree (study_id, create_time DESC);


--
-- Name: ix_asset_job; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ix_asset_job ON public.generation_asset USING btree (job_id) WHERE (is_deleted = false);


--
-- Name: ix_att_case; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ix_att_case ON public.case_attachment USING btree (case_id) WHERE (is_deleted = false);


--
-- Name: ix_att_org; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ix_att_org ON public.case_attachment USING btree (org_id);


--
-- Name: ix_audit_log_request_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ix_audit_log_request_id ON public.audit_log USING btree (request_id);


--
-- Name: ix_bi_approval_flow_org_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ix_bi_approval_flow_org_id ON public.bi_approval_flow USING btree (org_id);


--
-- Name: ix_bi_dashboard_access_request_org_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ix_bi_dashboard_access_request_org_id ON public.bi_dashboard_access_request USING btree (org_id);


--
-- Name: ix_bi_dashboard_designs_org_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ix_bi_dashboard_designs_org_id ON public.bi_dashboard_designs USING btree (org_id);


--
-- Name: ix_bi_operation_log_org_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ix_bi_operation_log_org_id ON public.bi_operation_log USING btree (org_id);


--
-- Name: ix_bi_publish_approvals_org_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ix_bi_publish_approvals_org_id ON public.bi_publish_approvals USING btree (org_id);


--
-- Name: ix_biz_department_manager; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ix_biz_department_manager ON public.biz_department USING btree (manager_id) WHERE (deleted = false);


--
-- Name: ix_biz_department_org_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ix_biz_department_org_id ON public.biz_department USING btree (org_id);


--
-- Name: ix_biz_department_parent_fk; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ix_biz_department_parent_fk ON public.biz_department USING btree (parent_fk_id) WHERE (deleted = false);


--
-- Name: ix_biz_platform_config_org_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ix_biz_platform_config_org_id ON public.biz_platform_config USING btree (org_id);


--
-- Name: ix_biz_shop_org_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ix_biz_shop_org_id ON public.biz_shop USING btree (org_id);


--
-- Name: ix_case_order; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ix_case_order ON public.after_sales_case USING btree (org_id, order_ref);


--
-- Name: ix_case_org; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ix_case_org ON public.after_sales_case USING btree (org_id, status, create_time DESC) WHERE (is_deleted = false);


--
-- Name: ix_compliance_asset; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ix_compliance_asset ON public.compliance_check USING btree (asset_id, create_time DESC);


--
-- Name: ix_conv_msg_conv; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ix_conv_msg_conv ON public.conversation_message USING btree (conversation_id, create_time);


--
-- Name: ix_conversation_org; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ix_conversation_org ON public.conversation USING btree (org_id, last_message_at DESC) WHERE (is_deleted = false);


--
-- Name: ix_crp_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ix_crp_index ON public.customer_recommended_product USING btree (org_id, store_ref, index_status) WHERE (is_deleted = false);


--
-- Name: ix_demand_profile_org_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ix_demand_profile_org_id ON public.demand_profile USING btree (org_id);


--
-- Name: ix_demand_profile_sku_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ix_demand_profile_sku_id ON public.demand_profile USING btree (sku_id);


--
-- Name: ix_facts_job; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ix_facts_job ON public.weekly_facts USING btree (source_job_id);


--
-- Name: ix_facts_org; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ix_facts_org ON public.weekly_facts USING btree (org_id, week_start DESC) WHERE (is_deleted = false);


--
-- Name: ix_facts_window; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ix_facts_window ON public.weekly_facts USING btree (study_id, week_start DESC);


--
-- Name: ix_forecast_actual_override_org_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ix_forecast_actual_override_org_id ON public.forecast_actual_override USING btree (org_id);


--
-- Name: ix_forecast_actual_override_run_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ix_forecast_actual_override_run_id ON public.forecast_actual_override USING btree (run_id);


--
-- Name: ix_forecast_audit_log_action; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ix_forecast_audit_log_action ON public.forecast_audit_log USING btree (action);


--
-- Name: ix_forecast_audit_log_created_at; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ix_forecast_audit_log_created_at ON public.forecast_audit_log USING btree (created_at);


--
-- Name: ix_forecast_audit_log_org_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ix_forecast_audit_log_org_id ON public.forecast_audit_log USING btree (org_id);


--
-- Name: ix_forecast_audit_log_trace_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ix_forecast_audit_log_trace_id ON public.forecast_audit_log USING btree (trace_id);


--
-- Name: ix_forecast_backtest_point_run_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ix_forecast_backtest_point_run_id ON public.forecast_backtest_point USING btree (run_id);


--
-- Name: ix_forecast_evaluation_run_id; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX ix_forecast_evaluation_run_id ON public.forecast_evaluation USING btree (run_id);


--
-- Name: ix_forecast_idempotency_record_expires_at; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ix_forecast_idempotency_record_expires_at ON public.forecast_idempotency_record USING btree (expires_at);


--
-- Name: ix_forecast_model_definition_org_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ix_forecast_model_definition_org_id ON public.forecast_model_definition USING btree (org_id);


--
-- Name: ix_forecast_point_run_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ix_forecast_point_run_id ON public.forecast_point USING btree (run_id);


--
-- Name: ix_forecast_run_created_at; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ix_forecast_run_created_at ON public.forecast_run USING btree (created_at);


--
-- Name: ix_forecast_run_org_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ix_forecast_run_org_id ON public.forecast_run USING btree (org_id);


--
-- Name: ix_forecast_run_publication_status; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ix_forecast_run_publication_status ON public.forecast_run USING btree (publication_status);


--
-- Name: ix_forecast_run_request_hash; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ix_forecast_run_request_hash ON public.forecast_run USING btree (request_hash);


--
-- Name: ix_forecast_run_sku_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ix_forecast_run_sku_id ON public.forecast_run USING btree (sku_id);


--
-- Name: ix_forecast_run_status; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ix_forecast_run_status ON public.forecast_run USING btree (status);


--
-- Name: ix_gen_job; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ix_gen_job ON public.generation_job USING btree (org_id, status, create_time DESC) WHERE (is_deleted = false);


--
-- Name: ix_intent_conv; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ix_intent_conv ON public.customer_intent_analysis USING btree (conversation_id, create_time DESC);


--
-- Name: ix_item_order; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ix_item_order ON public.sales_order_item USING btree (order_id);


--
-- Name: ix_item_sku; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ix_item_sku ON public.sales_order_item USING btree (org_id, sku);


--
-- Name: ix_jobs_list; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ix_jobs_list ON public.import_jobs USING btree (org_id, create_time DESC) WHERE (is_deleted = false);


--
-- Name: ix_jobs_source; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ix_jobs_source ON public.import_jobs USING btree (source_id, create_time DESC);


--
-- Name: ix_listing_sku; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ix_listing_sku ON public.customer_listing USING btree (org_id, store_ref, sku) WHERE (is_deleted = false);


--
-- Name: ix_order_date; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ix_order_date ON public.sales_order USING btree (org_id, order_date DESC);


--
-- Name: ix_outbox_agg; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ix_outbox_agg ON public.outbox_event USING btree (aggregate_id, create_time DESC);


--
-- Name: ix_outbox_pending; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ix_outbox_pending ON public.outbox_event USING btree (next_retry_at) WHERE ((published_at IS NULL) AND (is_deleted = false));


--
-- Name: ix_plan_list; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ix_plan_list ON public.replenishment_plan USING btree (org_id, planning_mode, status, create_time DESC) WHERE (is_deleted = false);


--
-- Name: ix_product_category; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ix_product_category ON public.product USING btree (org_id, category) WHERE (is_deleted = false);


--
-- Name: ix_purchases_source; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ix_purchases_source ON public.purchases USING btree (source_id, valid_to DESC NULLS LAST) WHERE (is_deleted = false);


--
-- Name: ix_qa_turn_cleanup; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ix_qa_turn_cleanup ON public.bi_conversation_turn USING btree (create_time);


--
-- Name: ix_qa_turn_session; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ix_qa_turn_session ON public.bi_conversation_turn USING btree (org_id, session_id, create_time);


--
-- Name: ix_reply_conv; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ix_reply_conv ON public.customer_reply_draft USING btree (conversation_id, create_time DESC);


--
-- Name: ix_reviews_org; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ix_reviews_org ON public.reviews USING btree (org_id, reviewed_at DESC) WHERE (is_deleted = false);


--
-- Name: ix_reviews_study; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ix_reviews_study ON public.reviews USING btree (study_id, reviewed_at DESC);


--
-- Name: ix_sources_active; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ix_sources_active ON public.sources USING btree (org_id, active) WHERE (is_deleted = false);


--
-- Name: ix_sourcing_sku; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ix_sourcing_sku ON public.product_sourcing USING btree (org_id, sku) WHERE (is_deleted = false);


--
-- Name: ix_ss_org; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ix_ss_org ON public.study_sources USING btree (org_id, study_id);


--
-- Name: ix_ss_source; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ix_ss_source ON public.study_sources USING btree (source_id) WHERE (is_deleted = false);


--
-- Name: ix_studies_calc; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ix_studies_calc ON public.studies USING btree (org_id, calc_state, week_count DESC) WHERE (is_deleted = false);


--
-- Name: ix_studies_list; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ix_studies_list ON public.studies USING btree (org_id, status, create_time DESC) WHERE (is_deleted = false);


--
-- Name: ix_sys_department_permission_org_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ix_sys_department_permission_org_id ON public.sys_department_permission USING btree (org_id);


--
-- Name: ix_sys_role_org_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ix_sys_role_org_id ON public.sys_role USING btree (org_id);


--
-- Name: ix_sys_user_org_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ix_sys_user_org_id ON public.sys_user USING btree (org_id);


--
-- Name: ix_sys_user_role_org_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ix_sys_user_role_org_id ON public.sys_user_role USING btree (org_id);


--
-- Name: ix_sys_user_shop_org_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ix_sys_user_shop_org_id ON public.sys_user_shop USING btree (org_id);


--
-- Name: ix_trials_list; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ix_trials_list ON public.trials USING btree (org_id, status, create_time DESC) WHERE (is_deleted = false);


--
-- Name: ix_trials_study; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ix_trials_study ON public.trials USING btree (study_id, round_no DESC);


--
-- Name: ix_voucher_plan; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ix_voucher_plan ON public.logistics_voucher USING btree (plan_id, voucher_type) WHERE (is_deleted = false);


--
-- Name: ix_wf_org; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ix_wf_org ON public.workflow_template USING btree (org_id, purpose, status) WHERE (is_deleted = false);


--
-- Name: uq_af_scope; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX uq_af_scope ON public.bi_approval_flow USING btree (org_id, scope_level, COALESCE(dept_id, 0));


--
-- Name: uq_bdar_active; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX uq_bdar_active ON public.bi_dashboard_access_request USING btree (org_id, dashboard_id, requester_id) WHERE ((status)::text = 'approved'::text);


--
-- Name: uq_bdar_pending; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX uq_bdar_pending ON public.bi_dashboard_access_request USING btree (org_id, dashboard_id, requester_id) WHERE ((status)::text = 'pending'::text);


--
-- Name: uq_bdd_scope_name; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX uq_bdd_scope_name ON public.bi_dashboard_designs USING btree (org_id, scope_level, COALESCE(dept_id, 0), dashboard_name) WHERE (deleted_at IS NULL);


--
-- Name: ux_batch_no; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX ux_batch_no ON public.receipt_batch USING btree (plan_id, batch_no) WHERE (is_deleted = false);


--
-- Name: ux_bi_design_org; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX ux_bi_design_org ON public.bi_dashboard_design USING btree (org_id) WHERE (is_deleted = false);


--
-- Name: ux_biz_department_org_id_id; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX ux_biz_department_org_id_id ON public.biz_department USING btree (org_id, id);


--
-- Name: ux_biz_shop_org_id_id; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX ux_biz_shop_org_id_id ON public.biz_shop USING btree (org_id, id);


--
-- Name: ux_card_ver; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX ux_card_ver ON public.replenishment_cost_card USING btree (org_id, sku, version) WHERE (is_deleted = false);


--
-- Name: ux_conv_msg_client; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX ux_conv_msg_client ON public.conversation_message USING btree (org_id, client_message_id) WHERE ((client_message_id IS NOT NULL) AND (is_deleted = false));


--
-- Name: ux_conversation_ref; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX ux_conversation_ref ON public.conversation USING btree (org_id, platform, store_ref, buyer_ref) WHERE ((buyer_ref IS NOT NULL) AND (is_deleted = false));


--
-- Name: ux_crp_key; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX ux_crp_key ON public.customer_recommended_product USING btree (org_id, store_ref, sku) WHERE (is_deleted = false);


--
-- Name: ux_event_type; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX ux_event_type ON public.replenishment_event USING btree (plan_id, event_type) WHERE (is_deleted = false);


--
-- Name: ux_facts_key; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX ux_facts_key ON public.weekly_facts USING btree (study_id, week_start) WHERE (is_deleted = false);


--
-- Name: ux_gen_idem; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX ux_gen_idem ON public.generation_job USING btree (org_id, idempotency_key) WHERE ((idempotency_key IS NOT NULL) AND (is_deleted = false));


--
-- Name: ux_inv_key; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX ux_inv_key ON public.inventory_position USING btree (org_id, sku, warehouse_ref) WHERE (is_deleted = false);


--
-- Name: ux_jobs_sha; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX ux_jobs_sha ON public.import_jobs USING btree (org_id, file_sha256) WHERE ((overwrite_target IS NULL) AND (is_deleted = false));


--
-- Name: ux_media_asset; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX ux_media_asset ON public.generation_media USING btree (asset_id) WHERE (is_deleted = false);


--
-- Name: ux_order_link; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX ux_order_link ON public.conversation_order_link USING btree (conversation_id, order_ref) WHERE (is_deleted = false);


--
-- Name: ux_order_no; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX ux_order_no ON public.sales_order USING btree (org_id, platform, order_no) WHERE (is_deleted = false);


--
-- Name: ux_plan_idem; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX ux_plan_idem ON public.replenishment_plan USING btree (org_id, idempotency_key) WHERE ((idempotency_key IS NOT NULL) AND (is_deleted = false));


--
-- Name: ux_product_sku; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX ux_product_sku ON public.product USING btree (org_id, sku) WHERE (is_deleted = false);


--
-- Name: ux_purchases_po; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX ux_purchases_po ON public.purchases USING btree (org_id, po_no) WHERE (is_deleted = false);


--
-- Name: ux_reply_idem; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX ux_reply_idem ON public.customer_reply_draft USING btree (org_id, idempotency_key) WHERE ((idempotency_key IS NOT NULL) AND (is_deleted = false));


--
-- Name: ux_reviews_idem; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX ux_reviews_idem ON public.reviews USING btree (org_id, idempotency_key) WHERE ((idempotency_key IS NOT NULL) AND (is_deleted = false));


--
-- Name: ux_sources_key; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX ux_sources_key ON public.sources USING btree (org_id, source_type, COALESCE(vendor, ''::character varying), name) WHERE (is_deleted = false);


--
-- Name: ux_studies_key; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX ux_studies_key ON public.studies USING btree (org_id, sku, platform, region) WHERE (is_deleted = false);


--
-- Name: ux_sys_role_org_id_id; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX ux_sys_role_org_id_id ON public.sys_role USING btree (org_id, id);


--
-- Name: ux_sys_user_org_id_id; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX ux_sys_user_org_id_id ON public.sys_user USING btree (org_id, id);


--
-- Name: ux_trials_round; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX ux_trials_round ON public.trials USING btree (study_id, round_no) WHERE (is_deleted = false);


--
-- Name: sys_user trg_clear_inactive_department_manager; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_clear_inactive_department_manager AFTER DELETE OR UPDATE ON public.sys_user FOR EACH ROW EXECUTE FUNCTION public.trg_clear_inactive_department_manager();


--
-- Name: biz_department trg_department_parent_org; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_department_parent_org BEFORE INSERT OR UPDATE OF parent_id, org_id ON public.biz_department FOR EACH ROW EXECUTE FUNCTION public.check_department_parent_org();


--
-- Name: biz_department trg_record_department_manager_history; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_record_department_manager_history AFTER INSERT OR UPDATE ON public.biz_department FOR EACH ROW EXECUTE FUNCTION public.trg_record_department_manager_history();


--
-- Name: after_sales_case after_sales_case_conversation_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.after_sales_case
    ADD CONSTRAINT after_sales_case_conversation_id_fkey FOREIGN KEY (conversation_id) REFERENCES public.conversation(id) ON DELETE SET NULL;


--
-- Name: agent_run agent_run_job_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.agent_run
    ADD CONSTRAINT agent_run_job_id_fkey FOREIGN KEY (job_id) REFERENCES public.generation_job(id) ON DELETE CASCADE;


--
-- Name: ai_call_log ai_call_log_study_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.ai_call_log
    ADD CONSTRAINT ai_call_log_study_id_fkey FOREIGN KEY (study_id) REFERENCES public.studies(id) ON DELETE SET NULL;


--
-- Name: biz_department biz_department_org_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.biz_department
    ADD CONSTRAINT biz_department_org_id_fkey FOREIGN KEY (org_id) REFERENCES public.sys_org(id);


--
-- Name: biz_platform_config biz_platform_config_org_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.biz_platform_config
    ADD CONSTRAINT biz_platform_config_org_id_fkey FOREIGN KEY (org_id) REFERENCES public.sys_org(id);


--
-- Name: biz_platform_config biz_platform_config_shop_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.biz_platform_config
    ADD CONSTRAINT biz_platform_config_shop_id_fkey FOREIGN KEY (shop_id) REFERENCES public.biz_shop(id) ON DELETE CASCADE;


--
-- Name: biz_shop biz_shop_dept_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.biz_shop
    ADD CONSTRAINT biz_shop_dept_id_fkey FOREIGN KEY (dept_id) REFERENCES public.biz_department(id);


--
-- Name: biz_shop biz_shop_org_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.biz_shop
    ADD CONSTRAINT biz_shop_org_id_fkey FOREIGN KEY (org_id) REFERENCES public.sys_org(id);


--
-- Name: case_attachment case_attachment_case_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.case_attachment
    ADD CONSTRAINT case_attachment_case_id_fkey FOREIGN KEY (case_id) REFERENCES public.after_sales_case(id) ON DELETE CASCADE;


--
-- Name: compliance_check compliance_check_asset_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.compliance_check
    ADD CONSTRAINT compliance_check_asset_id_fkey FOREIGN KEY (asset_id) REFERENCES public.generation_asset(id) ON DELETE CASCADE;


--
-- Name: conversation_message conversation_message_conversation_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.conversation_message
    ADD CONSTRAINT conversation_message_conversation_id_fkey FOREIGN KEY (conversation_id) REFERENCES public.conversation(id) ON DELETE CASCADE;


--
-- Name: conversation_order_link conversation_order_link_conversation_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.conversation_order_link
    ADD CONSTRAINT conversation_order_link_conversation_id_fkey FOREIGN KEY (conversation_id) REFERENCES public.conversation(id) ON DELETE CASCADE;


--
-- Name: customer_intent_analysis customer_intent_analysis_conversation_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.customer_intent_analysis
    ADD CONSTRAINT customer_intent_analysis_conversation_id_fkey FOREIGN KEY (conversation_id) REFERENCES public.conversation(id) ON DELETE CASCADE;


--
-- Name: customer_intent_analysis customer_intent_analysis_message_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.customer_intent_analysis
    ADD CONSTRAINT customer_intent_analysis_message_id_fkey FOREIGN KEY (message_id) REFERENCES public.conversation_message(id) ON DELETE CASCADE;


--
-- Name: customer_reply_draft customer_reply_draft_conversation_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.customer_reply_draft
    ADD CONSTRAINT customer_reply_draft_conversation_id_fkey FOREIGN KEY (conversation_id) REFERENCES public.conversation(id) ON DELETE CASCADE;


--
-- Name: bi_approval_flow fk_baf_dept; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.bi_approval_flow
    ADD CONSTRAINT fk_baf_dept FOREIGN KEY (org_id, dept_id) REFERENCES public.biz_department(org_id, id);


--
-- Name: bi_approval_flow fk_baf_org; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.bi_approval_flow
    ADD CONSTRAINT fk_baf_org FOREIGN KEY (org_id) REFERENCES public.sys_org(id);


--
-- Name: biz_department_manager_history fk_bd_history_dept; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.biz_department_manager_history
    ADD CONSTRAINT fk_bd_history_dept FOREIGN KEY (org_id, dept_id) REFERENCES public.biz_department(org_id, id);


--
-- Name: biz_department_manager_history fk_bd_history_user; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.biz_department_manager_history
    ADD CONSTRAINT fk_bd_history_user FOREIGN KEY (org_id, user_id) REFERENCES public.sys_user(org_id, id);


--
-- Name: bi_dashboard_access_request fk_bdar_dashboard; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.bi_dashboard_access_request
    ADD CONSTRAINT fk_bdar_dashboard FOREIGN KEY (org_id, dashboard_id) REFERENCES public.bi_dashboard_designs(org_id, dashboard_id);


--
-- Name: bi_dashboard_access_request fk_bdar_org; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.bi_dashboard_access_request
    ADD CONSTRAINT fk_bdar_org FOREIGN KEY (org_id) REFERENCES public.sys_org(id);


--
-- Name: bi_dashboard_access_request fk_bdar_requester_dept; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.bi_dashboard_access_request
    ADD CONSTRAINT fk_bdar_requester_dept FOREIGN KEY (org_id, requester_dept_id) REFERENCES public.biz_department(org_id, id);


--
-- Name: bi_dashboard_access_request fk_bdar_target_dept; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.bi_dashboard_access_request
    ADD CONSTRAINT fk_bdar_target_dept FOREIGN KEY (org_id, target_dept_id) REFERENCES public.biz_department(org_id, id);


--
-- Name: biz_department_closure fk_bdc_ancestor; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.biz_department_closure
    ADD CONSTRAINT fk_bdc_ancestor FOREIGN KEY (org_id, ancestor_id) REFERENCES public.biz_department(org_id, id);


--
-- Name: biz_department_closure fk_bdc_descendant; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.biz_department_closure
    ADD CONSTRAINT fk_bdc_descendant FOREIGN KEY (org_id, descendant_id) REFERENCES public.biz_department(org_id, id);


--
-- Name: bi_dashboard_designs fk_bdd_dept; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.bi_dashboard_designs
    ADD CONSTRAINT fk_bdd_dept FOREIGN KEY (org_id, dept_id) REFERENCES public.biz_department(org_id, id);


--
-- Name: bi_dashboard_designs fk_bdd_org; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.bi_dashboard_designs
    ADD CONSTRAINT fk_bdd_org FOREIGN KEY (org_id) REFERENCES public.sys_org(id);


--
-- Name: biz_department fk_biz_department_manager_user; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.biz_department
    ADD CONSTRAINT fk_biz_department_manager_user FOREIGN KEY (org_id, manager_id) REFERENCES public.sys_user(org_id, id);


--
-- Name: biz_department fk_biz_department_parent; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.biz_department
    ADD CONSTRAINT fk_biz_department_parent FOREIGN KEY (org_id, parent_fk_id) REFERENCES public.biz_department(org_id, id);


--
-- Name: biz_platform_config fk_biz_platform_config_shop_id_org; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.biz_platform_config
    ADD CONSTRAINT fk_biz_platform_config_shop_id_org FOREIGN KEY (org_id, shop_id) REFERENCES public.biz_shop(org_id, id) ON DELETE CASCADE;


--
-- Name: biz_shop fk_biz_shop_dept_id_org; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.biz_shop
    ADD CONSTRAINT fk_biz_shop_dept_id_org FOREIGN KEY (org_id, dept_id) REFERENCES public.biz_department(org_id, id);


--
-- Name: bi_operation_log fk_bol_dashboard; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.bi_operation_log
    ADD CONSTRAINT fk_bol_dashboard FOREIGN KEY (org_id, dashboard_id) REFERENCES public.bi_dashboard_designs(org_id, dashboard_id);


--
-- Name: bi_operation_log fk_bol_dept; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.bi_operation_log
    ADD CONSTRAINT fk_bol_dept FOREIGN KEY (org_id, dept_id) REFERENCES public.biz_department(org_id, id);


--
-- Name: bi_operation_log fk_bol_org; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.bi_operation_log
    ADD CONSTRAINT fk_bol_org FOREIGN KEY (org_id) REFERENCES public.sys_org(id);


--
-- Name: bi_publish_approvals fk_bpa_dashboard; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.bi_publish_approvals
    ADD CONSTRAINT fk_bpa_dashboard FOREIGN KEY (org_id, dashboard_id) REFERENCES public.bi_dashboard_designs(org_id, dashboard_id);


--
-- Name: bi_publish_approvals fk_bpa_dept; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.bi_publish_approvals
    ADD CONSTRAINT fk_bpa_dept FOREIGN KEY (org_id, dept_id) REFERENCES public.biz_department(org_id, id);


--
-- Name: bi_publish_approvals fk_bpa_flow; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.bi_publish_approvals
    ADD CONSTRAINT fk_bpa_flow FOREIGN KEY (flow_id) REFERENCES public.bi_approval_flow(id);


--
-- Name: bi_publish_approvals fk_bpa_org; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.bi_publish_approvals
    ADD CONSTRAINT fk_bpa_org FOREIGN KEY (org_id) REFERENCES public.sys_org(id);


--
-- Name: biz_department_shop fk_dept_shop_dept; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.biz_department_shop
    ADD CONSTRAINT fk_dept_shop_dept FOREIGN KEY (dept_id) REFERENCES public.biz_department(id);


--
-- Name: biz_department_shop fk_dept_shop_org; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.biz_department_shop
    ADD CONSTRAINT fk_dept_shop_org FOREIGN KEY (org_id) REFERENCES public.sys_org(id);


--
-- Name: biz_department_shop fk_dept_shop_org_dept; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.biz_department_shop
    ADD CONSTRAINT fk_dept_shop_org_dept FOREIGN KEY (org_id, dept_id) REFERENCES public.biz_department(org_id, id);


--
-- Name: biz_department_shop fk_dept_shop_org_shop; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.biz_department_shop
    ADD CONSTRAINT fk_dept_shop_org_shop FOREIGN KEY (org_id, shop_id) REFERENCES public.biz_shop(org_id, id) ON DELETE CASCADE;


--
-- Name: biz_department_shop fk_dept_shop_shop; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.biz_department_shop
    ADD CONSTRAINT fk_dept_shop_shop FOREIGN KEY (shop_id) REFERENCES public.biz_shop(id) ON DELETE CASCADE;


--
-- Name: pcc_agent_run fk_pcc_agent_run_job; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.pcc_agent_run
    ADD CONSTRAINT fk_pcc_agent_run_job FOREIGN KEY (job_id, org_id) REFERENCES public.pcc_generation_job(id, org_id) ON DELETE CASCADE;


--
-- Name: pcc_agent_run fk_pcc_agent_run_parent; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.pcc_agent_run
    ADD CONSTRAINT fk_pcc_agent_run_parent FOREIGN KEY (parent_run_id, org_id) REFERENCES public.pcc_agent_run(id, org_id) ON DELETE CASCADE;


--
-- Name: pcc_agent_run fk_pcc_ar_org; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.pcc_agent_run
    ADD CONSTRAINT fk_pcc_ar_org FOREIGN KEY (org_tenant_id) REFERENCES public.sys_org(id);


--
-- Name: pcc_asset_reference fk_pcc_aref_org; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.pcc_asset_reference
    ADD CONSTRAINT fk_pcc_aref_org FOREIGN KEY (org_tenant_id) REFERENCES public.sys_org(id);


--
-- Name: pcc_asset_reference fk_pcc_asset_reference_source_asset; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.pcc_asset_reference
    ADD CONSTRAINT fk_pcc_asset_reference_source_asset FOREIGN KEY (source_asset_id, org_id) REFERENCES public.pcc_generation_asset(id, org_id) ON DELETE RESTRICT;


--
-- Name: pcc_asset_reference fk_pcc_asset_reference_source_media; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.pcc_asset_reference
    ADD CONSTRAINT fk_pcc_asset_reference_source_media FOREIGN KEY (source_media_id, org_id) REFERENCES public.pcc_generation_media(id, org_id) ON DELETE RESTRICT;


--
-- Name: pcc_asset_reference fk_pcc_asset_reference_target_job; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.pcc_asset_reference
    ADD CONSTRAINT fk_pcc_asset_reference_target_job FOREIGN KEY (target_job_id, org_id) REFERENCES public.pcc_generation_job(id, org_id) ON DELETE CASCADE;


--
-- Name: pcc_content_approval fk_pcc_ca_org; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.pcc_content_approval
    ADD CONSTRAINT fk_pcc_ca_org FOREIGN KEY (org_tenant_id) REFERENCES public.sys_org(id);


--
-- Name: pcc_compliance_check fk_pcc_cc_org; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.pcc_compliance_check
    ADD CONSTRAINT fk_pcc_cc_org FOREIGN KEY (org_tenant_id) REFERENCES public.sys_org(id);


--
-- Name: pcc_compliance_check fk_pcc_compliance_check_asset; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.pcc_compliance_check
    ADD CONSTRAINT fk_pcc_compliance_check_asset FOREIGN KEY (asset_id, org_id) REFERENCES public.pcc_generation_asset(id, org_id) ON DELETE CASCADE;


--
-- Name: pcc_compliance_check fk_pcc_compliance_check_job; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.pcc_compliance_check
    ADD CONSTRAINT fk_pcc_compliance_check_job FOREIGN KEY (job_id, org_id) REFERENCES public.pcc_generation_job(id, org_id) ON DELETE CASCADE;


--
-- Name: pcc_content_approval fk_pcc_content_approval_job; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.pcc_content_approval
    ADD CONSTRAINT fk_pcc_content_approval_job FOREIGN KEY (job_id, org_id) REFERENCES public.pcc_generation_job(id, org_id) ON DELETE CASCADE;


--
-- Name: pcc_generation_asset fk_pcc_ga_org; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.pcc_generation_asset
    ADD CONSTRAINT fk_pcc_ga_org FOREIGN KEY (org_tenant_id) REFERENCES public.sys_org(id);


--
-- Name: pcc_generation_asset fk_pcc_generation_asset_job; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.pcc_generation_asset
    ADD CONSTRAINT fk_pcc_generation_asset_job FOREIGN KEY (job_id, org_id) REFERENCES public.pcc_generation_job(id, org_id) ON DELETE CASCADE;


--
-- Name: pcc_generation_job fk_pcc_generation_job_template; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.pcc_generation_job
    ADD CONSTRAINT fk_pcc_generation_job_template FOREIGN KEY (workflow_template_id, org_id) REFERENCES public.pcc_workflow_template(id, org_id);


--
-- Name: pcc_generation_media fk_pcc_generation_media_asset; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.pcc_generation_media
    ADD CONSTRAINT fk_pcc_generation_media_asset FOREIGN KEY (asset_id, org_id) REFERENCES public.pcc_generation_asset(id, org_id) ON DELETE SET NULL (asset_id);


--
-- Name: pcc_generation_media fk_pcc_generation_media_job; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.pcc_generation_media
    ADD CONSTRAINT fk_pcc_generation_media_job FOREIGN KEY (job_id, org_id) REFERENCES public.pcc_generation_job(id, org_id) ON DELETE CASCADE;


--
-- Name: pcc_generation_job fk_pcc_gj_org; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.pcc_generation_job
    ADD CONSTRAINT fk_pcc_gj_org FOREIGN KEY (org_tenant_id) REFERENCES public.sys_org(id);


--
-- Name: pcc_generation_media fk_pcc_gm_org; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.pcc_generation_media
    ADD CONSTRAINT fk_pcc_gm_org FOREIGN KEY (org_tenant_id) REFERENCES public.sys_org(id);


--
-- Name: pcc_workflow_template fk_pcc_wt_org; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.pcc_workflow_template
    ADD CONSTRAINT fk_pcc_wt_org FOREIGN KEY (org_tenant_id) REFERENCES public.sys_org(id);


--
-- Name: sys_department_permission fk_sys_department_permission_dept_id_org; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.sys_department_permission
    ADD CONSTRAINT fk_sys_department_permission_dept_id_org FOREIGN KEY (org_id, dept_id) REFERENCES public.biz_department(org_id, id) ON DELETE CASCADE;


--
-- Name: sys_user fk_sys_user_dept_id_org; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.sys_user
    ADD CONSTRAINT fk_sys_user_dept_id_org FOREIGN KEY (org_id, dept_id) REFERENCES public.biz_department(org_id, id);


--
-- Name: sys_user_role fk_sys_user_role_role_id_org; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.sys_user_role
    ADD CONSTRAINT fk_sys_user_role_role_id_org FOREIGN KEY (org_id, role_id) REFERENCES public.sys_role(org_id, id) ON DELETE CASCADE;


--
-- Name: sys_user_role fk_sys_user_role_user_id_org; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.sys_user_role
    ADD CONSTRAINT fk_sys_user_role_user_id_org FOREIGN KEY (org_id, user_id) REFERENCES public.sys_user(org_id, id) ON DELETE CASCADE;


--
-- Name: sys_user_shop fk_sys_user_shop_shop_id_org; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.sys_user_shop
    ADD CONSTRAINT fk_sys_user_shop_shop_id_org FOREIGN KEY (org_id, shop_id) REFERENCES public.biz_shop(org_id, id) ON DELETE CASCADE;


--
-- Name: sys_user_shop fk_sys_user_shop_user_id_org; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.sys_user_shop
    ADD CONSTRAINT fk_sys_user_shop_user_id_org FOREIGN KEY (org_id, user_id) REFERENCES public.sys_user(org_id, id) ON DELETE CASCADE;


--
-- Name: forecast_actual_override forecast_actual_override_run_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.forecast_actual_override
    ADD CONSTRAINT forecast_actual_override_run_id_fkey FOREIGN KEY (run_id) REFERENCES public.forecast_run(run_id) ON DELETE CASCADE;


--
-- Name: forecast_backtest_point forecast_backtest_point_run_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.forecast_backtest_point
    ADD CONSTRAINT forecast_backtest_point_run_id_fkey FOREIGN KEY (run_id) REFERENCES public.forecast_run(run_id) ON DELETE CASCADE;


--
-- Name: forecast_evaluation forecast_evaluation_run_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.forecast_evaluation
    ADD CONSTRAINT forecast_evaluation_run_id_fkey FOREIGN KEY (run_id) REFERENCES public.forecast_run(run_id) ON DELETE CASCADE;


--
-- Name: forecast_idempotency_record forecast_idempotency_record_run_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.forecast_idempotency_record
    ADD CONSTRAINT forecast_idempotency_record_run_id_fkey FOREIGN KEY (run_id) REFERENCES public.forecast_run(run_id);


--
-- Name: forecast_point forecast_point_run_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.forecast_point
    ADD CONSTRAINT forecast_point_run_id_fkey FOREIGN KEY (run_id) REFERENCES public.forecast_run(run_id) ON DELETE CASCADE;


--
-- Name: generation_asset generation_asset_job_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.generation_asset
    ADD CONSTRAINT generation_asset_job_id_fkey FOREIGN KEY (job_id) REFERENCES public.generation_job(id) ON DELETE CASCADE;


--
-- Name: generation_job generation_job_product_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.generation_job
    ADD CONSTRAINT generation_job_product_id_fkey FOREIGN KEY (product_id) REFERENCES public.product(id) ON DELETE SET NULL;


--
-- Name: generation_job generation_job_workflow_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.generation_job
    ADD CONSTRAINT generation_job_workflow_id_fkey FOREIGN KEY (workflow_id) REFERENCES public.workflow_template(id) ON DELETE SET NULL;


--
-- Name: generation_media generation_media_asset_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.generation_media
    ADD CONSTRAINT generation_media_asset_id_fkey FOREIGN KEY (asset_id) REFERENCES public.generation_asset(id) ON DELETE CASCADE;


--
-- Name: import_jobs import_jobs_overwrite_target_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.import_jobs
    ADD CONSTRAINT import_jobs_overwrite_target_fkey FOREIGN KEY (overwrite_target) REFERENCES public.import_jobs(id);


--
-- Name: import_jobs import_jobs_source_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.import_jobs
    ADD CONSTRAINT import_jobs_source_id_fkey FOREIGN KEY (source_id) REFERENCES public.sources(id) ON DELETE SET NULL;


--
-- Name: logistics_voucher logistics_voucher_plan_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.logistics_voucher
    ADD CONSTRAINT logistics_voucher_plan_id_fkey FOREIGN KEY (plan_id) REFERENCES public.replenishment_plan(id) ON DELETE CASCADE;


--
-- Name: product_sourcing product_sourcing_product_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.product_sourcing
    ADD CONSTRAINT product_sourcing_product_id_fkey FOREIGN KEY (product_id) REFERENCES public.product(id) ON DELETE CASCADE;


--
-- Name: purchases purchases_source_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.purchases
    ADD CONSTRAINT purchases_source_id_fkey FOREIGN KEY (source_id) REFERENCES public.sources(id) ON DELETE RESTRICT;


--
-- Name: receipt_batch receipt_batch_plan_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.receipt_batch
    ADD CONSTRAINT receipt_batch_plan_id_fkey FOREIGN KEY (plan_id) REFERENCES public.replenishment_plan(id) ON DELETE CASCADE;


--
-- Name: replenishment_event replenishment_event_plan_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.replenishment_event
    ADD CONSTRAINT replenishment_event_plan_id_fkey FOREIGN KEY (plan_id) REFERENCES public.replenishment_plan(id) ON DELETE CASCADE;


--
-- Name: replenishment_plan replenishment_plan_product_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.replenishment_plan
    ADD CONSTRAINT replenishment_plan_product_id_fkey FOREIGN KEY (product_id) REFERENCES public.product(id) ON DELETE SET NULL;


--
-- Name: reviews reviews_study_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.reviews
    ADD CONSTRAINT reviews_study_id_fkey FOREIGN KEY (study_id) REFERENCES public.studies(id) ON DELETE CASCADE;


--
-- Name: sales_order_item sales_order_item_order_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.sales_order_item
    ADD CONSTRAINT sales_order_item_order_id_fkey FOREIGN KEY (order_id) REFERENCES public.sales_order(id) ON DELETE CASCADE;


--
-- Name: studies studies_rejected_from_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.studies
    ADD CONSTRAINT studies_rejected_from_fkey FOREIGN KEY (rejected_from) REFERENCES public.studies(id);


--
-- Name: study_sources study_sources_source_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.study_sources
    ADD CONSTRAINT study_sources_source_id_fkey FOREIGN KEY (source_id) REFERENCES public.sources(id) ON DELETE RESTRICT;


--
-- Name: study_sources study_sources_study_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.study_sources
    ADD CONSTRAINT study_sources_study_id_fkey FOREIGN KEY (study_id) REFERENCES public.studies(id) ON DELETE CASCADE;


--
-- Name: sys_department_permission sys_department_permission_dept_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.sys_department_permission
    ADD CONSTRAINT sys_department_permission_dept_id_fkey FOREIGN KEY (dept_id) REFERENCES public.biz_department(id) ON DELETE CASCADE;


--
-- Name: sys_department_permission sys_department_permission_org_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.sys_department_permission
    ADD CONSTRAINT sys_department_permission_org_id_fkey FOREIGN KEY (org_id) REFERENCES public.sys_org(id);


--
-- Name: sys_department_permission sys_department_permission_perm_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.sys_department_permission
    ADD CONSTRAINT sys_department_permission_perm_id_fkey FOREIGN KEY (perm_id) REFERENCES public.sys_permission(id) ON DELETE CASCADE;


--
-- Name: sys_permission sys_permission_parent_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.sys_permission
    ADD CONSTRAINT sys_permission_parent_id_fkey FOREIGN KEY (parent_id) REFERENCES public.sys_permission(id);


--
-- Name: sys_role sys_role_org_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.sys_role
    ADD CONSTRAINT sys_role_org_id_fkey FOREIGN KEY (org_id) REFERENCES public.sys_org(id);


--
-- Name: sys_role_permission sys_role_permission_perm_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.sys_role_permission
    ADD CONSTRAINT sys_role_permission_perm_id_fkey FOREIGN KEY (perm_id) REFERENCES public.sys_permission(id) ON DELETE CASCADE;


--
-- Name: sys_role_permission sys_role_permission_role_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.sys_role_permission
    ADD CONSTRAINT sys_role_permission_role_id_fkey FOREIGN KEY (role_id) REFERENCES public.sys_role(id) ON DELETE CASCADE;


--
-- Name: sys_user sys_user_dept_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.sys_user
    ADD CONSTRAINT sys_user_dept_id_fkey FOREIGN KEY (dept_id) REFERENCES public.biz_department(id);


--
-- Name: sys_user sys_user_org_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.sys_user
    ADD CONSTRAINT sys_user_org_id_fkey FOREIGN KEY (org_id) REFERENCES public.sys_org(id);


--
-- Name: sys_user_role sys_user_role_org_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.sys_user_role
    ADD CONSTRAINT sys_user_role_org_id_fkey FOREIGN KEY (org_id) REFERENCES public.sys_org(id);


--
-- Name: sys_user_role sys_user_role_role_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.sys_user_role
    ADD CONSTRAINT sys_user_role_role_id_fkey FOREIGN KEY (role_id) REFERENCES public.sys_role(id) ON DELETE CASCADE;


--
-- Name: sys_user_role sys_user_role_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.sys_user_role
    ADD CONSTRAINT sys_user_role_user_id_fkey FOREIGN KEY (user_id) REFERENCES public.sys_user(id) ON DELETE CASCADE;


--
-- Name: sys_user_shop sys_user_shop_org_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.sys_user_shop
    ADD CONSTRAINT sys_user_shop_org_id_fkey FOREIGN KEY (org_id) REFERENCES public.sys_org(id);


--
-- Name: sys_user_shop sys_user_shop_shop_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.sys_user_shop
    ADD CONSTRAINT sys_user_shop_shop_id_fkey FOREIGN KEY (shop_id) REFERENCES public.biz_shop(id) ON DELETE CASCADE;


--
-- Name: sys_user_shop sys_user_shop_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.sys_user_shop
    ADD CONSTRAINT sys_user_shop_user_id_fkey FOREIGN KEY (user_id) REFERENCES public.sys_user(id) ON DELETE CASCADE;


--
-- Name: trials trials_study_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.trials
    ADD CONSTRAINT trials_study_id_fkey FOREIGN KEY (study_id) REFERENCES public.studies(id) ON DELETE CASCADE;


--
-- Name: weekly_facts weekly_facts_source_job_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.weekly_facts
    ADD CONSTRAINT weekly_facts_source_job_id_fkey FOREIGN KEY (source_job_id) REFERENCES public.import_jobs(id) ON DELETE SET NULL;


--
-- Name: weekly_facts weekly_facts_study_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.weekly_facts
    ADD CONSTRAINT weekly_facts_study_id_fkey FOREIGN KEY (study_id) REFERENCES public.studies(id) ON DELETE CASCADE;


--
-- PostgreSQL database dump complete
--



--
-- PostgreSQL database dump
--


-- Dumped from database version 18.7
-- Dumped by pg_dump version 18.7 (Debian 18.7-1.pgdg13+5)

SET statement_timeout = 0;
SET lock_timeout = 0;
SET idle_in_transaction_session_timeout = 0;
SET transaction_timeout = 0;
SET client_encoding = 'UTF8';
SET standard_conforming_strings = on;
SELECT pg_catalog.set_config('search_path', 'public, pg_catalog', false);
SET check_function_bodies = false;
SET xmloption = content;
SET client_min_messages = warning;
SET row_security = off;

--
-- Data for Name: conversation; Type: TABLE DATA; Schema: public; Owner: -
--

SET SESSION AUTHORIZATION DEFAULT;

ALTER TABLE public.conversation DISABLE TRIGGER ALL;



ALTER TABLE public.conversation ENABLE TRIGGER ALL;

--
-- Data for Name: after_sales_case; Type: TABLE DATA; Schema: public; Owner: -
--

ALTER TABLE public.after_sales_case DISABLE TRIGGER ALL;



ALTER TABLE public.after_sales_case ENABLE TRIGGER ALL;

--
-- Data for Name: product; Type: TABLE DATA; Schema: public; Owner: -
--

ALTER TABLE public.product DISABLE TRIGGER ALL;



ALTER TABLE public.product ENABLE TRIGGER ALL;

--
-- Data for Name: workflow_template; Type: TABLE DATA; Schema: public; Owner: -
--

ALTER TABLE public.workflow_template DISABLE TRIGGER ALL;



ALTER TABLE public.workflow_template ENABLE TRIGGER ALL;

--
-- Data for Name: generation_job; Type: TABLE DATA; Schema: public; Owner: -
--

ALTER TABLE public.generation_job DISABLE TRIGGER ALL;



ALTER TABLE public.generation_job ENABLE TRIGGER ALL;

--
-- Data for Name: agent_run; Type: TABLE DATA; Schema: public; Owner: -
--

ALTER TABLE public.agent_run DISABLE TRIGGER ALL;



ALTER TABLE public.agent_run ENABLE TRIGGER ALL;

--
-- Data for Name: studies; Type: TABLE DATA; Schema: public; Owner: -
--

ALTER TABLE public.studies DISABLE TRIGGER ALL;



ALTER TABLE public.studies ENABLE TRIGGER ALL;

--
-- Data for Name: ai_call_log; Type: TABLE DATA; Schema: public; Owner: -
--

ALTER TABLE public.ai_call_log DISABLE TRIGGER ALL;



ALTER TABLE public.ai_call_log ENABLE TRIGGER ALL;

--
-- Data for Name: alembic_version; Type: TABLE DATA; Schema: public; Owner: -
--

ALTER TABLE public.alembic_version DISABLE TRIGGER ALL;

INSERT INTO public.alembic_version (version_num) VALUES ('0008_bi_dashboard_tables');


ALTER TABLE public.alembic_version ENABLE TRIGGER ALL;

--
-- Data for Name: audit_log; Type: TABLE DATA; Schema: public; Owner: -
--

ALTER TABLE public.audit_log DISABLE TRIGGER ALL;

INSERT INTO public.audit_log (id, request_id, method, path, client_ip, "user", status, cost_ms, created_at) VALUES (2, 'b4a2c23b-265c-44b3-b426-ff8632ce72b1', 'POST', '/api/v1/auth/register', '127.0.0.1', NULL, 404, 2262.3, '2026-11-24 15:17:37.644151');
INSERT INTO public.audit_log (id, request_id, method, path, client_ip, "user", status, cost_ms, created_at) VALUES (3, '80a9aea6-cf7e-40fd-ab08-0b0fb9a038a4', 'POST', '/api/v1/auth/register', '127.0.0.1', NULL, 404, 645.16, '2026-11-24 15:18:53.787332');
INSERT INTO public.audit_log (id, request_id, method, path, client_ip, "user", status, cost_ms, created_at) VALUES (4, 'd52430e2-7b1e-49ec-aef4-2b54b261fc49', 'POST', '/api/v1/auth/register', '127.0.0.1', NULL, 409, 900.97, '2026-11-24 15:19:32.094338');
INSERT INTO public.audit_log (id, request_id, method, path, client_ip, "user", status, cost_ms, created_at) VALUES (5, '1a454314-6cce-4436-802f-93fd90d02fc8', 'POST', '/api/v1/auth/register', '127.0.0.1', NULL, 201, 1911.62, '2026-11-24 15:24:46.26994');
INSERT INTO public.audit_log (id, request_id, method, path, client_ip, "user", status, cost_ms, created_at) VALUES (6, 'fd547c47-f7f7-4f01-acba-0248428e9353', 'POST', '/api/v1/auth/login', '127.0.0.1', NULL, 401, 283.11, '2026-11-24 15:25:02.122562');
INSERT INTO public.audit_log (id, request_id, method, path, client_ip, "user", status, cost_ms, created_at) VALUES (7, '5dc642bc-b7af-43aa-96d6-ba4a51a7b322', 'POST', '/api/v1/auth/login', '127.0.0.1', NULL, 401, 451.87, '2026-11-24 15:25:09.417998');
INSERT INTO public.audit_log (id, request_id, method, path, client_ip, "user", status, cost_ms, created_at) VALUES (8, 'f9fd3976-3a20-4943-984a-962908a7ee60', 'POST', '/api/v1/auth/login', '127.0.0.1', NULL, 401, 791.49, '2026-11-24 15:25:13.164104');
INSERT INTO public.audit_log (id, request_id, method, path, client_ip, "user", status, cost_ms, created_at) VALUES (9, '2e1e9ef0-44ea-4c1a-98ab-e2c7e19f41e0', 'POST', '/api/v1/auth/login', '127.0.0.1', NULL, 200, 815.65, '2026-11-24 15:25:30.104987');
INSERT INTO public.audit_log (id, request_id, method, path, client_ip, "user", status, cost_ms, created_at) VALUES (10, '8f34e320-df6e-4da7-b960-19b923514412', 'PUT', '/api/v1/rbac/users/174/roles', '127.0.0.1', NULL, 200, 808.56, '2026-11-24 15:27:10.468208');
INSERT INTO public.audit_log (id, request_id, method, path, client_ip, "user", status, cost_ms, created_at) VALUES (11, '7a04bbb9-00ab-4aca-af0d-6015f061def5', 'POST', '/api/v1/auth/login', '127.0.0.1', NULL, 401, 272.57, '2026-11-24 15:27:19.134629');
INSERT INTO public.audit_log (id, request_id, method, path, client_ip, "user", status, cost_ms, created_at) VALUES (12, '6ec6478a-4088-471d-bc1d-4d875ea01b6b', 'POST', '/api/v1/auth/login', '127.0.0.1', NULL, 401, 472.51, '2026-11-24 15:27:26.403918');
INSERT INTO public.audit_log (id, request_id, method, path, client_ip, "user", status, cost_ms, created_at) VALUES (13, '8d0c89c4-1271-4811-b7d7-18146d8abc4e', 'POST', '/api/v1/auth/login', '127.0.0.1', NULL, 401, 419.5, '2026-11-24 15:27:35.607044');
INSERT INTO public.audit_log (id, request_id, method, path, client_ip, "user", status, cost_ms, created_at) VALUES (14, '0a73dcb4-45d3-47e4-ab3d-0e843e4b8ad3', 'POST', '/api/v1/auth/login', '127.0.0.1', NULL, 200, 846.11, '2026-11-24 15:28:25.261739');
INSERT INTO public.audit_log (id, request_id, method, path, client_ip, "user", status, cost_ms, created_at) VALUES (15, '93e9ca67-adcd-447e-bff7-e1a633981587', 'POST', '/api/v1/rbac/users/174/reset-password', '127.0.0.1', NULL, 200, 1156.44, '2026-11-24 15:33:44.917747');
INSERT INTO public.audit_log (id, request_id, method, path, client_ip, "user", status, cost_ms, created_at) VALUES (16, 'c5194066-9691-4825-97f5-11582b9281b7', 'POST', '/api/v1/auth/login', '127.0.0.1', NULL, 401, 288.47, '2026-11-24 15:33:59.523295');
INSERT INTO public.audit_log (id, request_id, method, path, client_ip, "user", status, cost_ms, created_at) VALUES (17, 'a331b785-84af-449f-a812-ff4a57c36bd8', 'POST', '/api/v1/auth/login', '127.0.0.1', NULL, 401, 514.85, '2026-11-24 15:34:02.058209');
INSERT INTO public.audit_log (id, request_id, method, path, client_ip, "user", status, cost_ms, created_at) VALUES (18, 'aab6d583-9177-40e5-bba5-fdf1d3bd9a58', 'POST', '/api/v1/auth/login', '127.0.0.1', NULL, 401, 252.75, '2026-11-24 15:34:23.281597');
INSERT INTO public.audit_log (id, request_id, method, path, client_ip, "user", status, cost_ms, created_at) VALUES (19, '31957e7f-d896-41d7-9c68-90476a255f87', 'POST', '/api/v1/auth/login', '127.0.0.1', NULL, 401, 281.29, '2026-11-24 15:34:45.337333');
INSERT INTO public.audit_log (id, request_id, method, path, client_ip, "user", status, cost_ms, created_at) VALUES (20, 'bce07f5f-cdc8-45b8-993d-5d1a44eceaeb', 'POST', '/api/v1/auth/login', '127.0.0.1', NULL, 200, 1110.77, '2026-11-24 15:41:35.428834');
INSERT INTO public.audit_log (id, request_id, method, path, client_ip, "user", status, cost_ms, created_at) VALUES (21, 'c30db59f-6d7c-4960-9a0d-6c00eae57b94', 'POST', '/api/v1/auth/login', '127.0.0.1', NULL, 200, 1026.54, '2026-11-24 15:41:36.837815');
INSERT INTO public.audit_log (id, request_id, method, path, client_ip, "user", status, cost_ms, created_at) VALUES (22, '17791d03-5f31-40f0-ab97-dbf803339df0', 'POST', '/api/v1/bi/dashboards', '127.0.0.1', NULL, 401, 3.31, '2026-11-24 16:29:14.491603');
INSERT INTO public.audit_log (id, request_id, method, path, client_ip, "user", status, cost_ms, created_at) VALUES (23, '8d5edfdd-291b-4044-814f-d7429e7b7fee', 'POST', '/api/v1/bi/dashboards', '127.0.0.1', NULL, 201, 455.31, '2026-11-24 16:29:28.749613');
INSERT INTO public.audit_log (id, request_id, method, path, client_ip, "user", status, cost_ms, created_at) VALUES (24, 'cab01dd9-abf8-4fb9-9f4d-7dbb42b07613', 'PUT', '/api/v1/bi/dashboards/bid_e354ce00f490408a/draft', '127.0.0.1', NULL, 200, 750.72, '2026-11-24 16:29:30.047557');
INSERT INTO public.audit_log (id, request_id, method, path, client_ip, "user", status, cost_ms, created_at) VALUES (25, 'a3ca2bc8-2670-4758-b29e-b6ecd2583c82', 'PUT', '/api/v1/bi/dashboards/bid_e354ce00f490408a/draft', '127.0.0.1', NULL, 200, 336.64, '2026-11-24 16:29:30.555741');
INSERT INTO public.audit_log (id, request_id, method, path, client_ip, "user", status, cost_ms, created_at) VALUES (26, '54f40c01-117c-474f-9078-c0e10a929dc7', 'DELETE', '/api/v1/bi/dashboards/bid_e354ce00f490408a', '127.0.0.1', NULL, 200, 422.8, '2026-11-24 16:29:32.942962');
INSERT INTO public.audit_log (id, request_id, method, path, client_ip, "user", status, cost_ms, created_at) VALUES (27, 'c817ad72-beac-4797-a73f-0daccb383c10', 'POST', '/api/v1/bi/dashboards', '127.0.0.1', NULL, 201, 428.57, '2026-11-24 16:30:00.318422');
INSERT INTO public.audit_log (id, request_id, method, path, client_ip, "user", status, cost_ms, created_at) VALUES (28, '234ac042-1a56-4413-82b3-da59faa68ccc', 'PUT', '/api/v1/bi/dashboards/bid_e3a9cd9c98c34129/draft', '127.0.0.1', NULL, 200, 532.9, '2026-11-24 16:30:01.378115');
INSERT INTO public.audit_log (id, request_id, method, path, client_ip, "user", status, cost_ms, created_at) VALUES (29, 'c7a9c749-a195-4ac8-a427-db741a003a8f', 'PUT', '/api/v1/bi/dashboards/bid_e3a9cd9c98c34129/draft', '127.0.0.1', NULL, 200, 327.39, '2026-11-24 16:30:01.883636');
INSERT INTO public.audit_log (id, request_id, method, path, client_ip, "user", status, cost_ms, created_at) VALUES (30, '9adbf592-8592-41d5-9569-98ebd5dbe615', 'PUT', '/api/v1/bi/dashboards/bid_e3a9cd9c98c34129/draft', '127.0.0.1', NULL, 200, 529.44, '2026-11-24 16:30:02.578985');
INSERT INTO public.audit_log (id, request_id, method, path, client_ip, "user", status, cost_ms, created_at) VALUES (31, '0a17c33a-f1dd-44da-a97c-165f575123c9', 'PUT', '/api/v1/bi/dashboards/bid_e3a9cd9c98c34129/draft', '127.0.0.1', NULL, 422, 331.8, '2026-11-24 16:30:03.099948');
INSERT INTO public.audit_log (id, request_id, method, path, client_ip, "user", status, cost_ms, created_at) VALUES (32, '3f168048-287f-4eb8-a138-6016618761de', 'PUT', '/api/v1/bi/dashboards/bid_e3a9cd9c98c34129/draft', '127.0.0.1', NULL, 422, 333.37, '2026-11-24 16:30:03.610131');
INSERT INTO public.audit_log (id, request_id, method, path, client_ip, "user", status, cost_ms, created_at) VALUES (33, '65ed4975-3b68-427f-827b-5e8c3e257151', 'DELETE', '/api/v1/bi/dashboards/bid_e3a9cd9c98c34129', '127.0.0.1', NULL, 200, 409.28, '2026-11-24 16:30:04.597121');
INSERT INTO public.audit_log (id, request_id, method, path, client_ip, "user", status, cost_ms, created_at) VALUES (34, '723cf94c-b1f5-472b-9484-c7ae6b592955', 'POST', '/api/v1/bi/dashboards', '127.0.0.1', NULL, 201, 432.71, '2026-11-24 16:30:32.61272');
INSERT INTO public.audit_log (id, request_id, method, path, client_ip, "user", status, cost_ms, created_at) VALUES (35, '16c3f115-013e-4f44-bfad-f8e170092c88', 'PUT', '/api/v1/bi/dashboards/bid_b822c9bb043645c1/draft', '127.0.0.1', NULL, 200, 600.2, '2026-11-24 16:30:33.753686');
INSERT INTO public.audit_log (id, request_id, method, path, client_ip, "user", status, cost_ms, created_at) VALUES (36, '8abf9f06-0186-4186-bc58-a207790bdfc0', 'PUT', '/api/v1/bi/dashboards/bid_b822c9bb043645c1/draft', '127.0.0.1', NULL, 200, 331.79, '2026-11-24 16:30:34.267045');
INSERT INTO public.audit_log (id, request_id, method, path, client_ip, "user", status, cost_ms, created_at) VALUES (37, 'd36c94b0-0a56-4d21-8ab0-b00138d06b77', 'PUT', '/api/v1/bi/dashboards/bid_b822c9bb043645c1/draft', '127.0.0.1', NULL, 200, 330.41, '2026-11-24 16:30:34.790525');
INSERT INTO public.audit_log (id, request_id, method, path, client_ip, "user", status, cost_ms, created_at) VALUES (38, 'f12396e8-9ff7-4d8f-88aa-9340fea6c818', 'PUT', '/api/v1/bi/dashboards/bid_b822c9bb043645c1/draft', '127.0.0.1', NULL, 409, 348.67, '2026-11-24 16:30:35.308437');
INSERT INTO public.audit_log (id, request_id, method, path, client_ip, "user", status, cost_ms, created_at) VALUES (39, '47d35f33-8f15-4e17-b39c-e37f63c635ca', 'PUT', '/api/v1/bi/dashboards/bid_b822c9bb043645c1/draft', '127.0.0.1', NULL, 409, 332.69, '2026-11-24 16:30:35.811496');
INSERT INTO public.audit_log (id, request_id, method, path, client_ip, "user", status, cost_ms, created_at) VALUES (40, '05497091-3d7e-45a2-ae18-1395fadc3fe1', 'DELETE', '/api/v1/bi/dashboards/bid_b822c9bb043645c1', '127.0.0.1', NULL, 200, 416.56, '2026-11-24 16:30:36.805175');
INSERT INTO public.audit_log (id, request_id, method, path, client_ip, "user", status, cost_ms, created_at) VALUES (41, 'ec2b3e08-10a5-419d-8913-054ea94e224a', 'POST', '/api/v1/bi/dashboards', '127.0.0.1', NULL, 201, 435.47, '2026-11-24 16:30:50.297774');
INSERT INTO public.audit_log (id, request_id, method, path, client_ip, "user", status, cost_ms, created_at) VALUES (42, 'b99cee0e-be48-468f-a3f5-c409cf41548b', 'PUT', '/api/v1/bi/dashboards/bid_f0a92d0b44604570/draft', '127.0.0.1', NULL, 200, 513.5, '2026-11-24 16:30:51.016864');
INSERT INTO public.audit_log (id, request_id, method, path, client_ip, "user", status, cost_ms, created_at) VALUES (43, '5648209c-0bd0-4526-8b5b-4795d07be2f6', 'PUT', '/api/v1/bi/dashboards/bid_f0a92d0b44604570/draft', '127.0.0.1', NULL, 409, 378.61, '2026-11-24 16:30:51.568535');
INSERT INTO public.audit_log (id, request_id, method, path, client_ip, "user", status, cost_ms, created_at) VALUES (44, 'ee7eecf5-63c3-4e06-aaaf-56294c679585', 'POST', '/api/v1/bi/dashboards', '127.0.0.1', NULL, 201, 438.86, '2026-11-24 16:31:17.217799');
INSERT INTO public.audit_log (id, request_id, method, path, client_ip, "user", status, cost_ms, created_at) VALUES (45, 'daa4a753-4eea-40ad-ba82-d37b18232172', 'PUT', '/api/v1/bi/dashboards/bid_294051dddc2e4d8b/draft', '127.0.0.1', NULL, 200, 722.95, '2026-11-24 16:31:18.491911');
INSERT INTO public.audit_log (id, request_id, method, path, client_ip, "user", status, cost_ms, created_at) VALUES (46, '8cbaba44-a036-496a-8ace-2b4e907430d1', 'PUT', '/api/v1/bi/dashboards/bid_294051dddc2e4d8b/draft', '127.0.0.1', NULL, 200, 331.42, '2026-11-24 16:31:19.01365');
INSERT INTO public.audit_log (id, request_id, method, path, client_ip, "user", status, cost_ms, created_at) VALUES (47, 'f8c5eaf1-a176-48f9-8ad3-25596f600859', 'PUT', '/api/v1/bi/dashboards/bid_294051dddc2e4d8b/draft', '127.0.0.1', NULL, 409, 375.3, '2026-11-24 16:31:19.581078');
INSERT INTO public.audit_log (id, request_id, method, path, client_ip, "user", status, cost_ms, created_at) VALUES (48, '82506bee-147e-4bed-a923-2946f086bd94', 'PUT', '/api/v1/bi/dashboards/bid_294051dddc2e4d8b/draft', '127.0.0.1', NULL, 422, 365.86, '2026-11-24 16:31:20.140372');
INSERT INTO public.audit_log (id, request_id, method, path, client_ip, "user", status, cost_ms, created_at) VALUES (49, 'a65ad66a-8e2b-40ef-a385-741bdefda460', 'PUT', '/api/v1/bi/dashboards/bid_294051dddc2e4d8b/draft', '127.0.0.1', NULL, 422, 336.87, '2026-11-24 16:31:20.649372');
INSERT INTO public.audit_log (id, request_id, method, path, client_ip, "user", status, cost_ms, created_at) VALUES (50, '96a3ff21-223f-4568-b33b-79c52c5eab61', 'DELETE', '/api/v1/bi/dashboards/bid_294051dddc2e4d8b', '127.0.0.1', NULL, 200, 422.47, '2026-11-24 16:31:21.647131');
INSERT INTO public.audit_log (id, request_id, method, path, client_ip, "user", status, cost_ms, created_at) VALUES (51, '48144893-0677-4941-b65b-ceb318cc117e', 'POST', '/api/v1/bi/dashboards', '127.0.0.1', NULL, 201, 1349.61, '2026-11-24 16:34:42.311277');
INSERT INTO public.audit_log (id, request_id, method, path, client_ip, "user", status, cost_ms, created_at) VALUES (52, '0832db07-c560-4a43-a841-b878653bc18e', 'PUT', '/api/v1/bi/dashboards/bid_cff6db1e95114d1b/draft', '127.0.0.1', NULL, 200, 738.62, '2026-11-24 16:34:43.23456');
INSERT INTO public.audit_log (id, request_id, method, path, client_ip, "user", status, cost_ms, created_at) VALUES (53, 'dda66db5-69a4-41a6-b914-a7d2989a107b', 'POST', '/api/v1/bi/dashboards/bid_cff6db1e95114d1b/publish', '127.0.0.1', NULL, 201, 740.06, '2026-11-24 16:34:44.146686');
INSERT INTO public.audit_log (id, request_id, method, path, client_ip, "user", status, cost_ms, created_at) VALUES (54, 'f97b8f2b-70c9-40a2-a699-f1502df29e8a', 'POST', '/api/v1/bi/dashboards/bid_cff6db1e95114d1b/publish', '127.0.0.1', NULL, 409, 384.44, '2026-11-24 16:34:44.713933');
INSERT INTO public.audit_log (id, request_id, method, path, client_ip, "user", status, cost_ms, created_at) VALUES (55, '91c1a7e3-7bb2-45d6-87b1-1bb1d309d254', 'POST', '/api/v1/bi/approvals/AP-2026-0001/approve', '127.0.0.1', NULL, 403, 469.84, '2026-11-24 16:34:45.356452');
INSERT INTO public.audit_log (id, request_id, method, path, client_ip, "user", status, cost_ms, created_at) VALUES (56, '40ca1b47-76a2-4e4e-9bdd-d10dd87b5fd7', 'POST', '/api/v1/bi/approvals/AP-2026-0001/approve', '127.0.0.1', NULL, 200, 758.54, '2026-11-24 16:34:46.678631');
INSERT INTO public.audit_log (id, request_id, method, path, client_ip, "user", status, cost_ms, created_at) VALUES (57, 'c0a9f8ce-5f52-4350-8e00-cf10b9ccdd6c', 'POST', '/api/v1/bi/dashboards', '127.0.0.1', NULL, 201, 473.34, '2026-11-24 16:35:00.728586');
INSERT INTO public.audit_log (id, request_id, method, path, client_ip, "user", status, cost_ms, created_at) VALUES (58, '49cfa8b1-ee31-41ff-8f16-0697aea537b9', 'PUT', '/api/v1/bi/dashboards/bid_23bfc1503c8f4684/draft', '127.0.0.1', NULL, 200, 517.1, '2026-11-24 16:35:01.430929');
INSERT INTO public.audit_log (id, request_id, method, path, client_ip, "user", status, cost_ms, created_at) VALUES (59, '230adfca-5e07-4654-99cb-40659304e6a9', 'POST', '/api/v1/bi/dashboards/bid_23bfc1503c8f4684/publish', '127.0.0.1', NULL, 201, 744.08, '2026-11-24 16:35:02.350708');
INSERT INTO public.audit_log (id, request_id, method, path, client_ip, "user", status, cost_ms, created_at) VALUES (60, 'f6a8ac38-a42a-4ce7-9801-e49f2e5a97a2', 'POST', '/api/v1/bi/dashboards/bid_23bfc1503c8f4684/publish', '127.0.0.1', NULL, 409, 383.98, '2026-11-24 16:35:02.90771');
INSERT INTO public.audit_log (id, request_id, method, path, client_ip, "user", status, cost_ms, created_at) VALUES (61, '1c27f443-873a-4cde-a244-27b822d9510e', 'POST', '/api/v1/bi/approvals/AP-2026-0002/approve', '127.0.0.1', NULL, 403, 467.85, '2026-11-24 16:35:03.56597');
INSERT INTO public.audit_log (id, request_id, method, path, client_ip, "user", status, cost_ms, created_at) VALUES (62, 'dd107403-1a7f-492a-8292-10b09ff06766', 'POST', '/api/v1/bi/approvals/AP-2026-0002/approve', '127.0.0.1', NULL, 200, 638.31, '2026-11-24 16:35:04.743919');
INSERT INTO public.audit_log (id, request_id, method, path, client_ip, "user", status, cost_ms, created_at) VALUES (63, '64f540ec-c2f3-4b40-a445-a2e56006893d', 'POST', '/api/v1/bi/dashboards/bid_23bfc1503c8f4684/access-requests', '127.0.0.1', NULL, 201, 772.34, '2026-11-24 16:35:08.625978');
INSERT INTO public.audit_log (id, request_id, method, path, client_ip, "user", status, cost_ms, created_at) VALUES (64, 'cff7e02f-be1e-4778-a6b7-0dac59e36d51', 'POST', '/api/v1/bi/dashboards/bid_23bfc1503c8f4684/access-requests', '127.0.0.1', NULL, 409, 469.64, '2026-11-24 16:35:09.284649');
INSERT INTO public.audit_log (id, request_id, method, path, client_ip, "user", status, cost_ms, created_at) VALUES (65, 'c6535ab3-e286-40ed-9286-da1a3772adeb', 'POST', '/api/v1/bi/access-requests/AR-2026-0001/approve', '127.0.0.1', NULL, 403, 431.22, '2026-11-24 16:35:09.909748');
INSERT INTO public.audit_log (id, request_id, method, path, client_ip, "user", status, cost_ms, created_at) VALUES (66, '40b59f1c-5822-429b-b2eb-0a4dd916afd4', 'POST', '/api/v1/bi/access-requests/AR-2026-0001/approve', '127.0.0.1', NULL, 200, 804.51, '2026-11-24 16:35:10.898789');
INSERT INTO public.audit_log (id, request_id, method, path, client_ip, "user", status, cost_ms, created_at) VALUES (67, '243c3032-3481-495a-9003-2034aad8b9b3', 'POST', '/api/v1/bi/approval-flows', '127.0.0.1', NULL, 201, 477.94, '2026-11-24 16:35:12.815363');
INSERT INTO public.audit_log (id, request_id, method, path, client_ip, "user", status, cost_ms, created_at) VALUES (68, '88b02853-12aa-4321-a08f-da6d97f7b184', 'PUT', '/api/v1/bi/approval-flows/2', '127.0.0.1', NULL, 200, 469.75, '2026-11-24 16:35:13.477968');
INSERT INTO public.audit_log (id, request_id, method, path, client_ip, "user", status, cost_ms, created_at) VALUES (69, 'd2b7c885-df5b-415c-be80-75dd537ced0b', 'DELETE', '/api/v1/bi/dashboards/bid_23bfc1503c8f4684', '127.0.0.1', NULL, 422, 341.65, '2026-11-24 16:35:13.993004');
INSERT INTO public.audit_log (id, request_id, method, path, client_ip, "user", status, cost_ms, created_at) VALUES (70, '4fadead3-eb83-4da9-85ce-8f842f848ac5', 'POST', '/api/v1/bi/dashboards', '127.0.0.1', NULL, 201, 1219.21, '2026-11-24 16:35:49.54308');
INSERT INTO public.audit_log (id, request_id, method, path, client_ip, "user", status, cost_ms, created_at) VALUES (71, '722d925e-0006-4504-9ace-9e62c87088a2', 'PUT', '/api/v1/bi/dashboards/bid_6968701e73d64e8b/draft', '127.0.0.1', NULL, 200, 722.19, '2026-11-24 16:35:50.451077');
INSERT INTO public.audit_log (id, request_id, method, path, client_ip, "user", status, cost_ms, created_at) VALUES (72, '4942c77b-8e5c-4345-9bf5-55c26f9f60e0', 'POST', '/api/v1/bi/dashboards/bid_6968701e73d64e8b/publish', '127.0.0.1', NULL, 201, 607.75, '2026-11-24 16:35:51.22046');
INSERT INTO public.audit_log (id, request_id, method, path, client_ip, "user", status, cost_ms, created_at) VALUES (73, '3c47f3b6-52cf-48aa-8bff-e88783bec68b', 'POST', '/api/v1/bi/dashboards/bid_6968701e73d64e8b/publish', '127.0.0.1', NULL, 409, 374.32, '2026-11-24 16:35:51.774364');
INSERT INTO public.audit_log (id, request_id, method, path, client_ip, "user", status, cost_ms, created_at) VALUES (74, 'd53fe756-9139-423e-b3fa-f0c452328f20', 'POST', '/api/v1/bi/approvals/AP-2026-0003/approve', '127.0.0.1', NULL, 403, 441.63, '2026-11-24 16:35:52.392716');
INSERT INTO public.audit_log (id, request_id, method, path, client_ip, "user", status, cost_ms, created_at) VALUES (75, 'e97d7602-7af8-41ad-9f10-a59ac4d10a64', 'POST', '/api/v1/bi/approvals/AP-2026-0003/approve', '127.0.0.1', NULL, 200, 599.94, '2026-11-24 16:35:53.493558');
INSERT INTO public.audit_log (id, request_id, method, path, client_ip, "user", status, cost_ms, created_at) VALUES (76, '911d2e7f-5665-49b6-a368-74910f750381', 'POST', '/api/v1/bi/dashboards/bid_6968701e73d64e8b/access-requests', '127.0.0.1', NULL, 201, 752.02, '2026-11-24 16:35:57.42824');
INSERT INTO public.audit_log (id, request_id, method, path, client_ip, "user", status, cost_ms, created_at) VALUES (77, '63bc7c0a-cdcd-4d1c-9ec3-d28f382aaae3', 'POST', '/api/v1/bi/dashboards/bid_6968701e73d64e8b/access-requests', '127.0.0.1', NULL, 409, 439.86, '2026-11-24 16:35:58.048809');
INSERT INTO public.audit_log (id, request_id, method, path, client_ip, "user", status, cost_ms, created_at) VALUES (78, 'bba8f973-c328-4c04-b864-49799acf9f11', 'POST', '/api/v1/bi/access-requests/AR-2026-0002/approve', '127.0.0.1', NULL, 403, 406.51, '2026-11-24 16:35:58.633777');
INSERT INTO public.audit_log (id, request_id, method, path, client_ip, "user", status, cost_ms, created_at) VALUES (79, 'cba6d22b-fc8b-4e26-8b28-c5beb35f4882', 'POST', '/api/v1/bi/access-requests/AR-2026-0002/approve', '127.0.0.1', NULL, 200, 722.94, '2026-11-24 16:35:59.53786');
INSERT INTO public.audit_log (id, request_id, method, path, client_ip, "user", status, cost_ms, created_at) VALUES (80, '1807b366-8573-45bd-ad1a-35480f69a01a', 'POST', '/api/v1/bi/approval-flows', '127.0.0.1', NULL, 409, 358.58, '2026-11-24 16:36:01.109866');
INSERT INTO public.audit_log (id, request_id, method, path, client_ip, "user", status, cost_ms, created_at) VALUES (81, 'e61ea899-a662-4406-ac9a-f9b5d9a65282', 'POST', '/api/v1/bi/dashboards', '127.0.0.1', NULL, 201, 472.82, '2026-11-24 16:42:38.62553');
INSERT INTO public.audit_log (id, request_id, method, path, client_ip, "user", status, cost_ms, created_at) VALUES (82, '9614cb67-8680-4f16-82cd-694888e81b23', 'PUT', '/api/v1/bi/dashboards/bid_5f395a80cf81431c/draft', '127.0.0.1', NULL, 200, 752.24, '2026-11-24 16:42:40.345206');
INSERT INTO public.audit_log (id, request_id, method, path, client_ip, "user", status, cost_ms, created_at) VALUES (83, 'f2b19617-dd2c-42ec-9fe8-088067ec23ef', 'PUT', '/api/v1/bi/dashboards/bid_5f395a80cf81431c/draft', '127.0.0.1', NULL, 409, 385.15, '2026-11-24 16:42:41.285228');
INSERT INTO public.audit_log (id, request_id, method, path, client_ip, "user", status, cost_ms, created_at) VALUES (84, '442bf52a-5a19-4c7b-b9c2-ceb588bcb61f', 'PUT', '/api/v1/bi/dashboards/bid_5f395a80cf81431c/draft', '127.0.0.1', NULL, 422, 405.13, '2026-11-24 16:42:41.883608');
INSERT INTO public.audit_log (id, request_id, method, path, client_ip, "user", status, cost_ms, created_at) VALUES (85, '741a5328-0ddc-4a07-8af0-de12a818c2cb', 'POST', '/api/v1/bi/dashboards/bid_5f395a80cf81431c/publish', '127.0.0.1', NULL, 201, 641.4, '2026-11-24 16:42:42.696185');
INSERT INTO public.audit_log (id, request_id, method, path, client_ip, "user", status, cost_ms, created_at) VALUES (86, 'cb85494c-386d-4644-8e58-97b1c5458f42', 'POST', '/api/v1/bi/dashboards/bid_5f395a80cf81431c/publish', '127.0.0.1', NULL, 409, 379.44, '2026-11-24 16:42:43.258182');
INSERT INTO public.audit_log (id, request_id, method, path, client_ip, "user", status, cost_ms, created_at) VALUES (87, 'ff3e91b2-1ff7-44b1-bd23-f0cecf162b2f', 'POST', '/api/v1/bi/approvals/AP-2026-0004/reject', '127.0.0.1', NULL, 200, 660.04, '2026-11-24 16:42:44.589299');
INSERT INTO public.audit_log (id, request_id, method, path, client_ip, "user", status, cost_ms, created_at) VALUES (88, '7d6dc049-e165-485a-a888-fea45c9541b0', 'DELETE', '/api/v1/bi/dashboards/bid_5f395a80cf81431c', '127.0.0.1', NULL, 200, 424, '2026-11-24 16:42:45.18273');
INSERT INTO public.audit_log (id, request_id, method, path, client_ip, "user", status, cost_ms, created_at) VALUES (89, '2d8d8351-1151-495a-93da-d2ffb77bda84', 'POST', '/api/v1/bi/dashboards', '127.0.0.1', NULL, 201, 464.64, '2026-11-24 16:43:18.624718');
INSERT INTO public.audit_log (id, request_id, method, path, client_ip, "user", status, cost_ms, created_at) VALUES (90, '7e7063e5-d4c4-4cf9-9e0a-e8550fb515fe', 'PUT', '/api/v1/bi/dashboards/bid_6a4bd2f613f84969/draft', '127.0.0.1', NULL, 200, 534.67, '2026-11-24 16:43:19.353305');
INSERT INTO public.audit_log (id, request_id, method, path, client_ip, "user", status, cost_ms, created_at) VALUES (91, '3a76dac0-a339-4235-b344-3e905d80b6eb', 'DELETE', '/api/v1/bi/dashboards/bid_6a4bd2f613f84969', '127.0.0.1', NULL, 200, 408.85, '2026-11-24 16:50:34.501863');
INSERT INTO public.audit_log (id, request_id, method, path, client_ip, "user", status, cost_ms, created_at) VALUES (92, 'd90d5aa4-de5c-4c6c-8b1e-7dbc5c3a44ab', 'DELETE', '/api/v1/bi/dashboards/bid_f0a92d0b44604570', '127.0.0.1', NULL, 200, 432.35, '2026-11-24 16:50:35.099547');
INSERT INTO public.audit_log (id, request_id, method, path, client_ip, "user", status, cost_ms, created_at) VALUES (93, '5aef87fd-c469-4121-a504-8b5b4f88cb9c', 'POST', '/api/v1/bi/dashboards', '127.0.0.1', NULL, 201, 452.31, '2026-11-24 16:51:39.626953');
INSERT INTO public.audit_log (id, request_id, method, path, client_ip, "user", status, cost_ms, created_at) VALUES (94, 'c6fa7dac-dcd4-4f39-a611-08adbaefdad8', 'PUT', '/api/v1/bi/dashboards/bid_fec9a5bf8e424c94/draft', '127.0.0.1', NULL, 200, 695.62, '2026-11-24 16:51:41.225092');
INSERT INTO public.audit_log (id, request_id, method, path, client_ip, "user", status, cost_ms, created_at) VALUES (95, '390590e4-2b73-4423-bdd6-e5ad90ed51f9', 'PUT', '/api/v1/bi/dashboards/bid_fec9a5bf8e424c94/draft', '127.0.0.1', NULL, 409, 386.97, '2026-11-24 16:51:42.138698');
INSERT INTO public.audit_log (id, request_id, method, path, client_ip, "user", status, cost_ms, created_at) VALUES (96, '49e68d21-6592-4f3a-bcf6-4ed18e00724e', 'PUT', '/api/v1/bi/dashboards/bid_fec9a5bf8e424c94/draft', '127.0.0.1', NULL, 422, 384.14, '2026-11-24 16:51:42.686339');
INSERT INTO public.audit_log (id, request_id, method, path, client_ip, "user", status, cost_ms, created_at) VALUES (97, 'd76c6c8f-4161-43e7-b5b8-35cb04e162e9', 'POST', '/api/v1/bi/dashboards/bid_fec9a5bf8e424c94/publish', '127.0.0.1', NULL, 201, 611.07, '2026-11-24 16:51:43.477425');
INSERT INTO public.audit_log (id, request_id, method, path, client_ip, "user", status, cost_ms, created_at) VALUES (98, 'cbc17bb4-0e90-4d80-a28b-bfd06c3d8f21', 'POST', '/api/v1/bi/dashboards/bid_fec9a5bf8e424c94/publish', '127.0.0.1', NULL, 409, 365.83, '2026-11-24 16:51:44.022442');
INSERT INTO public.audit_log (id, request_id, method, path, client_ip, "user", status, cost_ms, created_at) VALUES (99, '42dcccc9-3c11-4c34-bf7a-9285843a7560', 'POST', '/api/v1/bi/approvals/AP-2026-0005/reject', '127.0.0.1', NULL, 200, 524.75, '2026-11-24 16:51:45.112182');
INSERT INTO public.audit_log (id, request_id, method, path, client_ip, "user", status, cost_ms, created_at) VALUES (100, '146ed398-cb1b-4103-9a04-96e6ec1f1db9', 'DELETE', '/api/v1/bi/dashboards/bid_fec9a5bf8e424c94', '127.0.0.1', NULL, 200, 401.68, '2026-11-24 16:51:45.693369');
INSERT INTO public.audit_log (id, request_id, method, path, client_ip, "user", status, cost_ms, created_at) VALUES (101, '277dfbf1-0f5f-47e5-979f-b18380a7b297', 'POST', '/api/v1/auth/login', '127.0.0.1', NULL, 200, 1834.56, '2026-11-24 17:41:05.220682');
INSERT INTO public.audit_log (id, request_id, method, path, client_ip, "user", status, cost_ms, created_at) VALUES (102, 'af2cd2d2-7b9d-418e-9886-a7fb7992680a', 'PATCH', '/api/v1/rbac/users/174', '127.0.0.1', NULL, 200, 803.5, '2026-11-24 17:41:06.57984');
INSERT INTO public.audit_log (id, request_id, method, path, client_ip, "user", status, cost_ms, created_at) VALUES (103, '271d1071-a2a9-4ff2-8fe7-885969367b4c', 'POST', '/api/v1/auth/login', '127.0.0.1', NULL, 200, 676.12, '2026-11-24 17:41:26.029115');
INSERT INTO public.audit_log (id, request_id, method, path, client_ip, "user", status, cost_ms, created_at) VALUES (104, '25b5e777-221d-4452-bd0a-55a5738b9c30', 'POST', '/api/v1/auth/login', '127.0.0.1', NULL, 200, 719.04, '2026-11-24 17:49:30.680786');
INSERT INTO public.audit_log (id, request_id, method, path, client_ip, "user", status, cost_ms, created_at) VALUES (105, '84950c99-353f-4386-9943-0554646c0fe9', 'POST', '/api/v1/rbac/users/174/reset-password', '127.0.0.1', NULL, 200, 509.13, '2026-11-24 17:49:54.806143');
INSERT INTO public.audit_log (id, request_id, method, path, client_ip, "user", status, cost_ms, created_at) VALUES (106, '6e78897d-d12f-4d9a-9484-9680bc2e6f50', 'POST', '/api/v1/auth/login', '127.0.0.1', NULL, 200, 1016.45, '2026-11-24 17:50:18.431766');
INSERT INTO public.audit_log (id, request_id, method, path, client_ip, "user", status, cost_ms, created_at) VALUES (107, '2fea42d4-77c4-407f-9e39-9693dcfec89f', 'POST', '/api/v1/auth/login', '127.0.0.1', NULL, 200, 778.54, '2026-11-24 17:50:35.206846');
INSERT INTO public.audit_log (id, request_id, method, path, client_ip, "user", status, cost_ms, created_at) VALUES (108, '63b08de2-c7c7-4465-829e-6e02a83ae8dd', 'POST', '/api/v1/auth/login', '127.0.0.1', NULL, 200, 1585.65, '2026-11-24 17:59:00.958365');
INSERT INTO public.audit_log (id, request_id, method, path, client_ip, "user", status, cost_ms, created_at) VALUES (109, '279cac32-785c-4edf-80bd-56eb7f129e02', 'POST', '/api/v1/bi/dashboards', '127.0.0.1', NULL, 201, 1296.56, '2026-11-24 18:20:57.656181');
INSERT INTO public.audit_log (id, request_id, method, path, client_ip, "user", status, cost_ms, created_at) VALUES (110, '9a636a81-6b7d-48ae-a134-61c7f6d8b952', 'PUT', '/api/v1/bi/dashboards/bid_61ab09b103c0492b/draft', '127.0.0.1', NULL, 200, 716.42, '2026-11-24 18:20:58.539456');
INSERT INTO public.audit_log (id, request_id, method, path, client_ip, "user", status, cost_ms, created_at) VALUES (111, '16aa1bd4-cd68-43f9-ad19-9408a423c66c', 'POST', '/api/v1/bi/approval-flows', '127.0.0.1', NULL, 201, 458.21, '2026-11-24 18:20:59.163404');
INSERT INTO public.audit_log (id, request_id, method, path, client_ip, "user", status, cost_ms, created_at) VALUES (112, '7b5ff0ce-99f2-4fd0-9115-d28a963fa13b', 'POST', '/api/v1/bi/approval-flows', '127.0.0.1', NULL, 422, 367.82, '2026-11-24 18:20:59.696845');
INSERT INTO public.audit_log (id, request_id, method, path, client_ip, "user", status, cost_ms, created_at) VALUES (113, '91710149-17b0-4203-9f56-da9a60c83f09', 'POST', '/api/v1/bi/approval-flows', '127.0.0.1', NULL, 422, 374.04, '2026-11-24 18:21:00.248144');
INSERT INTO public.audit_log (id, request_id, method, path, client_ip, "user", status, cost_ms, created_at) VALUES (114, 'bdec91fd-a968-4b55-bc43-8b5bdcfdc619', 'POST', '/api/v1/bi/dashboards/bid_61ab09b103c0492b/publish', '127.0.0.1', NULL, 201, 664.72, '2026-11-24 18:21:01.087759');
INSERT INTO public.audit_log (id, request_id, method, path, client_ip, "user", status, cost_ms, created_at) VALUES (115, 'dad77d5d-343d-4612-b3fc-39a101ba357b', 'POST', '/api/v1/bi/approvals/AP-2026-0006/approve', '127.0.0.1', NULL, 403, 520.96, '2026-11-24 18:21:01.778472');
INSERT INTO public.audit_log (id, request_id, method, path, client_ip, "user", status, cost_ms, created_at) VALUES (116, '8e2af028-7607-4232-9e9d-3fc57d9ab9ea', 'POST', '/api/v1/bi/approvals/AP-2026-0006/approve', '127.0.0.1', NULL, 200, 578.82, '2026-11-24 18:21:02.525187');
INSERT INTO public.audit_log (id, request_id, method, path, client_ip, "user", status, cost_ms, created_at) VALUES (117, '8f83ab26-372d-428c-b7c1-87d47eb5ec94', 'POST', '/api/v1/bi/approvals/AP-2026-0006/approve', '127.0.0.1', NULL, 403, 453.2, '2026-11-24 18:21:03.144119');
INSERT INTO public.audit_log (id, request_id, method, path, client_ip, "user", status, cost_ms, created_at) VALUES (118, '0005c8c7-6980-4de1-bcdf-966ed91875eb', 'POST', '/api/v1/bi/approvals/AP-2026-0006/approve', '127.0.0.1', NULL, 200, 631.4, '2026-11-24 18:21:03.941777');
INSERT INTO public.audit_log (id, request_id, method, path, client_ip, "user", status, cost_ms, created_at) VALUES (119, 'f52a3c5a-1284-4ebe-bc35-2a85080b4339', 'POST', '/api/v1/bi/dashboards/bid_61ab09b103c0492b/offline', '127.0.0.1', NULL, 403, 411.1, '2026-11-24 18:21:04.51721');
INSERT INTO public.audit_log (id, request_id, method, path, client_ip, "user", status, cost_ms, created_at) VALUES (120, 'e5c79ecb-657f-4fee-9eb5-d09b82679e7d', 'POST', '/api/v1/bi/dashboards/bid_61ab09b103c0492b/offline', '127.0.0.1', NULL, 200, 413.53, '2026-11-24 18:21:05.097874');
INSERT INTO public.audit_log (id, request_id, method, path, client_ip, "user", status, cost_ms, created_at) VALUES (121, '2615c2cb-81bc-4041-89e3-a4d6f6f1b5e7', 'POST', '/api/v1/bi/dashboards/bid_61ab09b103c0492b/offline', '127.0.0.1', NULL, 409, 328.49, '2026-11-24 18:21:05.947959');
INSERT INTO public.audit_log (id, request_id, method, path, client_ip, "user", status, cost_ms, created_at) VALUES (122, '320ffd28-57f7-4bca-8fb2-ed9f7c573f4c', 'PUT', '/api/v1/bi/dashboards/bid_61ab09b103c0492b/draft', '127.0.0.1', NULL, 200, 493.61, '2026-11-24 18:21:10.538902');
INSERT INTO public.audit_log (id, request_id, method, path, client_ip, "user", status, cost_ms, created_at) VALUES (123, '5c94b300-962d-46d1-8479-b5604f135fdd', 'DELETE', '/api/v1/bi/dashboards/bid_61ab09b103c0492b', '127.0.0.1', NULL, 200, 437.59, '2026-11-24 18:21:11.144884');
INSERT INTO public.audit_log (id, request_id, method, path, client_ip, "user", status, cost_ms, created_at) VALUES (124, '3928cd6e-24c4-4ffc-91d4-579270323d5e', 'POST', '/api/v1/auth/register', 'testclient', NULL, 503, 3.41, '2026-11-24 18:21:33.210096');
INSERT INTO public.audit_log (id, request_id, method, path, client_ip, "user", status, cost_ms, created_at) VALUES (125, '9f7a99fe-ef9a-4103-ba66-6a8351d537d8', 'POST', '/api/v1/bi/dashboards', '127.0.0.1', NULL, 201, 1290.78, '2026-11-24 18:25:23.565673');
INSERT INTO public.audit_log (id, request_id, method, path, client_ip, "user", status, cost_ms, created_at) VALUES (126, '6df26a90-8438-4acf-9a7c-e7e439fbb303', 'PUT', '/api/v1/bi/dashboards/bid_f08892604e044011/draft', '127.0.0.1', NULL, 200, 727.6, '2026-11-24 18:25:24.49115');
INSERT INTO public.audit_log (id, request_id, method, path, client_ip, "user", status, cost_ms, created_at) VALUES (127, 'ea738aef-0b24-4557-975f-beabb236b7a3', 'POST', '/api/v1/bi/approval-flows', '127.0.0.1', NULL, 201, 463.12, '2026-11-24 18:25:25.119077');
INSERT INTO public.audit_log (id, request_id, method, path, client_ip, "user", status, cost_ms, created_at) VALUES (128, '27607a32-63a3-404b-8801-e65a4a2e26d5', 'POST', '/api/v1/bi/approval-flows', '127.0.0.1', NULL, 422, 374.89, '2026-11-24 18:25:25.681496');
INSERT INTO public.audit_log (id, request_id, method, path, client_ip, "user", status, cost_ms, created_at) VALUES (129, 'da82ecbb-de0c-4733-8947-f303e67cfcc4', 'POST', '/api/v1/bi/approval-flows', '127.0.0.1', NULL, 422, 369.2, '2026-11-24 18:25:26.2168');
INSERT INTO public.audit_log (id, request_id, method, path, client_ip, "user", status, cost_ms, created_at) VALUES (130, 'faf8dc63-75a5-476b-8b9e-397e6598a138', 'POST', '/api/v1/bi/dashboards/bid_f08892604e044011/publish', '127.0.0.1', NULL, 201, 707.77, '2026-11-24 18:25:27.089945');
INSERT INTO public.audit_log (id, request_id, method, path, client_ip, "user", status, cost_ms, created_at) VALUES (131, '5edc2eb9-c37d-4a1a-8f89-bdcd71988b1f', 'POST', '/api/v1/bi/approvals/AP-2026-0006/approve', '127.0.0.1', NULL, 403, 496.35, '2026-11-24 18:25:27.751848');
INSERT INTO public.audit_log (id, request_id, method, path, client_ip, "user", status, cost_ms, created_at) VALUES (132, '9b6fe4d3-61e4-4347-9fc6-ab1866fdf5bb', 'POST', '/api/v1/bi/approvals/AP-2026-0006/approve', '127.0.0.1', NULL, 200, 577.51, '2026-11-24 18:25:28.516931');
INSERT INTO public.audit_log (id, request_id, method, path, client_ip, "user", status, cost_ms, created_at) VALUES (133, '8345a302-ba52-4a73-b045-49cc81868e68', 'POST', '/api/v1/bi/approvals/AP-2026-0006/approve', '127.0.0.1', NULL, 403, 486.46, '2026-11-24 18:25:29.169473');
INSERT INTO public.audit_log (id, request_id, method, path, client_ip, "user", status, cost_ms, created_at) VALUES (134, 'b08ab681-7118-4a42-b5f3-9838806af0a8', 'POST', '/api/v1/bi/approvals/AP-2026-0006/approve', '127.0.0.1', NULL, 200, 620.08, '2026-11-24 18:25:29.954193');
INSERT INTO public.audit_log (id, request_id, method, path, client_ip, "user", status, cost_ms, created_at) VALUES (135, '6fb6e933-a62a-4c2d-a00b-667ff3314946', 'POST', '/api/v1/bi/dashboards/bid_f08892604e044011/offline', '127.0.0.1', NULL, 403, 411.97, '2026-11-24 18:25:30.531994');
INSERT INTO public.audit_log (id, request_id, method, path, client_ip, "user", status, cost_ms, created_at) VALUES (136, '935dcac3-af53-4c09-aee2-217aeb3b166d', 'POST', '/api/v1/bi/dashboards/bid_f08892604e044011/offline', '127.0.0.1', NULL, 200, 412.81, '2026-11-24 18:25:31.110685');
INSERT INTO public.audit_log (id, request_id, method, path, client_ip, "user", status, cost_ms, created_at) VALUES (137, 'eba4949f-4f05-4f35-aba1-9da09b8c8bb8', 'POST', '/api/v1/bi/dashboards/bid_f08892604e044011/offline', '127.0.0.1', NULL, 409, 328.76, '2026-11-24 18:25:31.939804');
INSERT INTO public.audit_log (id, request_id, method, path, client_ip, "user", status, cost_ms, created_at) VALUES (138, '6fcfadd6-c6a4-423a-8c92-970ad084be2d', 'PUT', '/api/v1/bi/dashboards/bid_f08892604e044011/draft', '127.0.0.1', NULL, 200, 491.86, '2026-11-24 18:25:36.403203');
INSERT INTO public.audit_log (id, request_id, method, path, client_ip, "user", status, cost_ms, created_at) VALUES (139, 'e096683c-4d8a-4ad6-aae1-5bdca47dd18a', 'DELETE', '/api/v1/bi/dashboards/bid_f08892604e044011', '127.0.0.1', NULL, 200, 417.74, '2026-11-24 18:25:36.98792');
INSERT INTO public.audit_log (id, request_id, method, path, client_ip, "user", status, cost_ms, created_at) VALUES (140, '0c1ab40a-8a21-4bb2-b2cd-8aa1898dcefb', 'POST', '/api/v1/auth/login', '127.0.0.1', NULL, 200, 847.38, '2026-11-24 19:34:08.242317');
INSERT INTO public.audit_log (id, request_id, method, path, client_ip, "user", status, cost_ms, created_at) VALUES (141, 'f1ff86d4-4045-4600-9c82-aa54955f95ff', 'PUT', '/api/v1/rbac/departments/2/shops', '127.0.0.1', NULL, 200, 623.65, '2026-11-24 19:36:01.520972');
INSERT INTO public.audit_log (id, request_id, method, path, client_ip, "user", status, cost_ms, created_at) VALUES (142, '83092b9b-0dd9-4197-a2ca-db6be5aa0ba5', 'POST', '/api/v1/auth/login', '127.0.0.1', NULL, 200, 649.28, '2026-11-24 19:41:27.024978');
INSERT INTO public.audit_log (id, request_id, method, path, client_ip, "user", status, cost_ms, created_at) VALUES (143, '694bd400-58ea-419f-9c17-ca8c4aa4c027', 'POST', '/api/v1/auth/register', 'testclient', NULL, 503, 3.17, '2026-11-24 19:49:29.278189');
INSERT INTO public.audit_log (id, request_id, method, path, client_ip, "user", status, cost_ms, created_at) VALUES (144, 'cd2d89e5-861e-4a17-847c-3be28b94f150', 'POST', '/api/v1/auth/register', 'testclient', NULL, 503, 2.97, '2026-11-24 20:02:20.337596');
INSERT INTO public.audit_log (id, request_id, method, path, client_ip, "user", status, cost_ms, created_at) VALUES (145, '220d9b98-5ca6-4289-9477-98fb6450f5ce', 'POST', '/api/v1/auth/register', 'testclient', NULL, 503, 3.02, '2026-11-24 20:02:51.073924');
INSERT INTO public.audit_log (id, request_id, method, path, client_ip, "user", status, cost_ms, created_at) VALUES (146, '2806040f-98e4-4ef0-bfe4-1a599cc4a385', 'PUT', '/api/v1/rbac/departments/1/shops', '127.0.0.1', NULL, 200, 624.28, '2026-11-24 20:07:21.594488');
INSERT INTO public.audit_log (id, request_id, method, path, client_ip, "user", status, cost_ms, created_at) VALUES (147, '4e664cec-348f-4ef3-bcea-44eb5764fcf2', 'PUT', '/api/v1/rbac/departments/7/shops', '127.0.0.1', NULL, 200, 631.88, '2026-11-24 20:08:47.3933');
INSERT INTO public.audit_log (id, request_id, method, path, client_ip, "user", status, cost_ms, created_at) VALUES (148, 'd31964bb-ee74-4e9c-a946-3f57a509fd4f', 'POST', '/api/v1/auth/login', '127.0.0.1', NULL, 200, 1262.63, '2026-11-24 20:31:25.423366');
INSERT INTO public.audit_log (id, request_id, method, path, client_ip, "user", status, cost_ms, created_at) VALUES (149, '2dc15545-b3ca-4208-b69b-bb7d57e14376', 'POST', '/api/v1/auth/login', '127.0.0.1', NULL, 200, 551.88, '2026-11-24 20:31:37.054272');
INSERT INTO public.audit_log (id, request_id, method, path, client_ip, "user", status, cost_ms, created_at) VALUES (150, '3346999f-90a4-481b-8fbc-db0f8dbd3dfe', 'POST', '/api/v1/auth/login', '127.0.0.1', NULL, 200, 467.58, '2026-11-24 20:32:36.467993');
INSERT INTO public.audit_log (id, request_id, method, path, client_ip, "user", status, cost_ms, created_at) VALUES (151, '3660d5a9-b4c3-4805-b85a-dc9ac6570624', 'PUT', '/api/v1/bi/dashboards/bid_6968701e73d64e8b/draft', '127.0.0.1', NULL, 403, 637.48, '2026-11-24 20:32:39.898569');
INSERT INTO public.audit_log (id, request_id, method, path, client_ip, "user", status, cost_ms, created_at) VALUES (152, '0ab4d396-0c8e-4248-814b-1d0af98312cc', 'DELETE', '/api/v1/bi/dashboards/bid_6968701e73d64e8b', '127.0.0.1', NULL, 403, 376.14, '2026-11-24 20:32:40.445894');
INSERT INTO public.audit_log (id, request_id, method, path, client_ip, "user", status, cost_ms, created_at) VALUES (153, 'ae7c4ae7-94d3-4857-93e7-c83a429ad03f', 'POST', '/api/v1/bi/dashboards', '127.0.0.1', NULL, 201, 517.61, '2026-11-24 20:32:41.938013');
INSERT INTO public.audit_log (id, request_id, method, path, client_ip, "user", status, cost_ms, created_at) VALUES (154, 'bd9795f5-5404-4ddc-833c-95248cc8f0b4', 'POST', '/api/v1/bi/dashboards', '127.0.0.1', NULL, 422, 393.51, '2026-11-24 20:32:42.50667');
INSERT INTO public.audit_log (id, request_id, method, path, client_ip, "user", status, cost_ms, created_at) VALUES (155, '017f9e6d-8da8-437e-88fd-e231fdd20e72', 'PUT', '/api/v1/bi/dashboards/bid_72a019edbc5a411e/draft', '127.0.0.1', NULL, 200, 552.68, '2026-11-24 20:32:43.605056');
INSERT INTO public.audit_log (id, request_id, method, path, client_ip, "user", status, cost_ms, created_at) VALUES (156, 'f5776025-21ee-4ad1-aaac-364161019e1a', 'POST', '/api/v1/bi/dashboards/bid_72a019edbc5a411e/publish', '127.0.0.1', NULL, 201, 798.17, '2026-11-24 20:32:44.57842');
INSERT INTO public.audit_log (id, request_id, method, path, client_ip, "user", status, cost_ms, created_at) VALUES (157, 'a831d3cd-5afa-4e42-a3ed-15e239f1d07f', 'POST', '/api/v1/bi/approvals/AP-2026-0006/approve', '127.0.0.1', NULL, 200, 511.49, '2026-11-24 20:32:45.259975');
INSERT INTO public.audit_log (id, request_id, method, path, client_ip, "user", status, cost_ms, created_at) VALUES (158, 'ceb239bb-aafc-4392-872e-2d09fef16384', 'PUT', '/api/v1/bi/dashboards/bid_72a019edbc5a411e/draft', '127.0.0.1', NULL, 200, 549.45, '2026-11-24 20:32:46.326574');
INSERT INTO public.audit_log (id, request_id, method, path, client_ip, "user", status, cost_ms, created_at) VALUES (159, '3978191f-6f14-4bb2-9ccc-f3d1ff17e096', 'POST', '/api/v1/bi/approval-flows', '127.0.0.1', NULL, 422, 297.95, '2026-11-24 20:32:47.137091');
INSERT INTO public.audit_log (id, request_id, method, path, client_ip, "user", status, cost_ms, created_at) VALUES (160, '530ab76f-05f9-4076-b91a-4345e5ac4443', 'POST', '/api/v1/bi/approval-flows', '127.0.0.1', NULL, 201, 466.75, '2026-11-24 20:32:47.773154');
INSERT INTO public.audit_log (id, request_id, method, path, client_ip, "user", status, cost_ms, created_at) VALUES (161, 'bf877a8c-5647-4195-95cd-0c03868d4ce9', 'POST', '/api/v1/bi/dashboards', '127.0.0.1', NULL, 201, 543.44, '2026-11-24 20:32:48.485369');
INSERT INTO public.audit_log (id, request_id, method, path, client_ip, "user", status, cost_ms, created_at) VALUES (162, 'cbdbf477-319c-4ded-99b4-4e91c2994c32', 'PUT', '/api/v1/bi/dashboards/bid_fb2bb975dd5b4fff/draft', '127.0.0.1', NULL, 200, 648.11, '2026-11-24 20:32:49.313262');
INSERT INTO public.audit_log (id, request_id, method, path, client_ip, "user", status, cost_ms, created_at) VALUES (163, '0c963f88-7df8-4826-8a97-f3376e011b76', 'POST', '/api/v1/bi/dashboards/bid_fb2bb975dd5b4fff/publish', '127.0.0.1', NULL, 201, 716.03, '2026-11-24 20:32:50.198948');
INSERT INTO public.audit_log (id, request_id, method, path, client_ip, "user", status, cost_ms, created_at) VALUES (164, '493411c1-3cd6-4622-9723-c1bf0facf4f5', 'PUT', '/api/v1/bi/approval-flows/7', '127.0.0.1', NULL, 200, 460.86, '2026-11-24 20:32:50.828681');
INSERT INTO public.audit_log (id, request_id, method, path, client_ip, "user", status, cost_ms, created_at) VALUES (165, '54a359df-7a58-4d59-907a-2f1213ae65ae', 'POST', '/api/v1/bi/approvals/AP-2026-0007/approve', '127.0.0.1', NULL, 200, 624.32, '2026-11-24 20:32:51.663538');
INSERT INTO public.audit_log (id, request_id, method, path, client_ip, "user", status, cost_ms, created_at) VALUES (166, 'e771b8ec-947f-4f3e-aa2d-48b1d34e92d7', 'POST', '/api/v1/bi/approvals/AP-2026-0007/approve', '127.0.0.1', NULL, 200, 498.59, '2026-11-24 20:32:52.331019');
INSERT INTO public.audit_log (id, request_id, method, path, client_ip, "user", status, cost_ms, created_at) VALUES (167, '7bea9936-f132-490f-a070-7367b34676b9', 'POST', '/api/v1/bi/dashboards', '127.0.0.1', NULL, 201, 555.27, '2026-11-24 20:32:53.238264');
INSERT INTO public.audit_log (id, request_id, method, path, client_ip, "user", status, cost_ms, created_at) VALUES (168, 'dd813164-ac13-436a-a8fb-38dcf3acfcb2', 'PUT', '/api/v1/bi/dashboards/bid_283b88ef242f4aa1/draft', '127.0.0.1', NULL, 200, 550.47, '2026-11-24 20:32:53.958616');
INSERT INTO public.audit_log (id, request_id, method, path, client_ip, "user", status, cost_ms, created_at) VALUES (169, 'e5404081-3d34-4d50-939f-88fe4af83166', 'POST', '/api/v1/bi/dashboards/bid_283b88ef242f4aa1/publish', '127.0.0.1', NULL, 201, 898.61, '2026-11-24 20:32:55.028889');
INSERT INTO public.audit_log (id, request_id, method, path, client_ip, "user", status, cost_ms, created_at) VALUES (170, '00cda5d1-7831-44f6-879f-6c6256738a09', 'POST', '/api/v1/bi/approvals/AP-2026-0008/approve', '127.0.0.1', NULL, 200, 541.91, '2026-11-24 20:32:55.737925');
INSERT INTO public.audit_log (id, request_id, method, path, client_ip, "user", status, cost_ms, created_at) VALUES (171, 'd04bb6bd-1f76-403c-8ce4-c0d4f0bf6cef', 'POST', '/api/v1/bi/dashboards/bid_283b88ef242f4aa1/access-requests', '127.0.0.1', NULL, 403, 336.04, '2026-11-24 20:32:56.950124');
INSERT INTO public.audit_log (id, request_id, method, path, client_ip, "user", status, cost_ms, created_at) VALUES (172, '5096c3ca-9f63-4c11-ae17-aa5d644aa364', 'POST', '/api/v1/bi/access-requests/None/approve', '127.0.0.1', NULL, 404, 360.02, '2026-11-24 20:32:57.478903');
INSERT INTO public.audit_log (id, request_id, method, path, client_ip, "user", status, cost_ms, created_at) VALUES (173, '98a2d15b-53c0-4fd4-bc94-4c4e65ea6802', 'PUT', '/api/v1/bi/dashboards/bid_72a019edbc5a411e/draft', '127.0.0.1', NULL, 428, 407.49, '2026-11-24 20:32:58.51962');
INSERT INTO public.audit_log (id, request_id, method, path, client_ip, "user", status, cost_ms, created_at) VALUES (174, '9765c197-8340-4bf3-90ca-0f267eefc37b', 'POST', '/api/v1/bi/dashboards', '127.0.0.1', NULL, 201, 421.79, '2026-11-24 20:32:59.109163');
INSERT INTO public.audit_log (id, request_id, method, path, client_ip, "user", status, cost_ms, created_at) VALUES (175, 'e798d24a-6285-4887-8485-fe1c7164fa03', 'POST', '/api/v1/bi/dashboards', '127.0.0.1', NULL, 201, 472.13, '2026-11-24 20:32:59.749487');
INSERT INTO public.audit_log (id, request_id, method, path, client_ip, "user", status, cost_ms, created_at) VALUES (176, '7b515548-a530-48da-9b6d-3d09e165c052', 'PUT', '/api/v1/bi/dashboards/bid_afe9906e804344bc/draft', '127.0.0.1', NULL, 409, 517.24, '2026-11-24 20:33:00.437452');
INSERT INTO public.audit_log (id, request_id, method, path, client_ip, "user", status, cost_ms, created_at) VALUES (177, '25408f29-5a0a-418c-a6c3-5a039ca200b3', 'POST', '/api/v1/bi/dashboards/bid_72a019edbc5a411e/offline', '127.0.0.1', NULL, 200, 451.77, '2026-11-24 20:33:01.058654');
INSERT INTO public.audit_log (id, request_id, method, path, client_ip, "user", status, cost_ms, created_at) VALUES (178, 'bce0b6a1-f1d9-4da3-a218-d06ff856a674', 'DELETE', '/api/v1/bi/dashboards/bid_72a019edbc5a411e', '127.0.0.1', NULL, 200, 422.22, '2026-11-24 20:33:01.648055');
INSERT INTO public.audit_log (id, request_id, method, path, client_ip, "user", status, cost_ms, created_at) VALUES (179, '60794d3a-6186-4a6a-8d04-fcde315a0560', 'POST', '/api/v1/bi/dashboards/bid_fb2bb975dd5b4fff/offline', '127.0.0.1', NULL, 200, 418.23, '2026-11-24 20:33:02.247374');
INSERT INTO public.audit_log (id, request_id, method, path, client_ip, "user", status, cost_ms, created_at) VALUES (180, 'eace95a2-3ffe-452f-84c6-8e45772c52c0', 'DELETE', '/api/v1/bi/dashboards/bid_fb2bb975dd5b4fff', '127.0.0.1', NULL, 200, 415.95, '2026-11-24 20:33:02.83151');
INSERT INTO public.audit_log (id, request_id, method, path, client_ip, "user", status, cost_ms, created_at) VALUES (181, 'c564e41f-4caf-488d-a10e-de5b3e3d6438', 'POST', '/api/v1/bi/dashboards/bid_283b88ef242f4aa1/offline', '127.0.0.1', NULL, 200, 422.68, '2026-11-24 20:33:03.422653');
INSERT INTO public.audit_log (id, request_id, method, path, client_ip, "user", status, cost_ms, created_at) VALUES (182, '7e38129b-cdcb-4267-8c2e-8b3701bdba6a', 'DELETE', '/api/v1/bi/dashboards/bid_283b88ef242f4aa1', '127.0.0.1', NULL, 200, 664.23, '2026-11-24 20:33:04.294051');
INSERT INTO public.audit_log (id, request_id, method, path, client_ip, "user", status, cost_ms, created_at) VALUES (183, 'f356d75d-1c6e-4ea3-a46f-768173291cc2', 'POST', '/api/v1/bi/dashboards/bid_afe9906e804344bc/offline', '127.0.0.1', NULL, 409, 392.05, '2026-11-24 20:33:04.868273');
INSERT INTO public.audit_log (id, request_id, method, path, client_ip, "user", status, cost_ms, created_at) VALUES (184, '5bdbcfc8-a0c8-4519-88cb-6e89236a2fb0', 'DELETE', '/api/v1/bi/dashboards/bid_afe9906e804344bc', '127.0.0.1', NULL, 200, 416.99, '2026-11-24 20:33:05.455017');
INSERT INTO public.audit_log (id, request_id, method, path, client_ip, "user", status, cost_ms, created_at) VALUES (185, 'f57c5ba2-d296-4a8c-a0e6-f74091c54422', 'PUT', '/api/v1/bi/dashboards/bid_6968701e73d64e8b/draft', '127.0.0.1', NULL, 403, 423.96, '2026-11-24 20:33:31.902713');
INSERT INTO public.audit_log (id, request_id, method, path, client_ip, "user", status, cost_ms, created_at) VALUES (186, '46b9d694-f19e-4b24-a5c7-0898ed32a4f5', 'DELETE', '/api/v1/bi/dashboards/bid_6968701e73d64e8b', '127.0.0.1', NULL, 403, 376.71, '2026-11-24 20:33:32.462007');
INSERT INTO public.audit_log (id, request_id, method, path, client_ip, "user", status, cost_ms, created_at) VALUES (187, '25266b7b-e2ac-47a7-902c-f1d3bfaa0e02', 'POST', '/api/v1/bi/dashboards', '127.0.0.1', NULL, 201, 513.44, '2026-11-24 20:33:33.94792');
INSERT INTO public.audit_log (id, request_id, method, path, client_ip, "user", status, cost_ms, created_at) VALUES (188, '55b022c4-05bd-4403-ab3f-336bfbd97ac5', 'POST', '/api/v1/bi/dashboards', '127.0.0.1', NULL, 422, 380.9, '2026-11-24 20:33:34.496757');
INSERT INTO public.audit_log (id, request_id, method, path, client_ip, "user", status, cost_ms, created_at) VALUES (189, '66de9816-1cba-48e0-b94e-09aab2256ecb', 'PUT', '/api/v1/bi/dashboards/bid_4e0f3c93522b40d7/draft', '127.0.0.1', NULL, 200, 557.14, '2026-11-24 20:33:35.612351');
INSERT INTO public.audit_log (id, request_id, method, path, client_ip, "user", status, cost_ms, created_at) VALUES (190, '5ea3648c-8795-4a8a-8304-51ba97309d0d', 'POST', '/api/v1/bi/dashboards/bid_4e0f3c93522b40d7/publish', '127.0.0.1', NULL, 201, 808.88, '2026-11-24 20:33:36.590534');
INSERT INTO public.audit_log (id, request_id, method, path, client_ip, "user", status, cost_ms, created_at) VALUES (191, '917e609a-794e-4045-8c4e-2c3ab8f58e1a', 'POST', '/api/v1/bi/approvals/AP-2026-0006/approve', '127.0.0.1', NULL, 200, 502.52, '2026-11-24 20:33:37.327729');
INSERT INTO public.audit_log (id, request_id, method, path, client_ip, "user", status, cost_ms, created_at) VALUES (192, '6457946d-c7b1-44cb-b243-46539fada6e3', 'PUT', '/api/v1/bi/dashboards/bid_4e0f3c93522b40d7/draft', '127.0.0.1', NULL, 200, 546.96, '2026-11-24 20:33:38.453792');
INSERT INTO public.audit_log (id, request_id, method, path, client_ip, "user", status, cost_ms, created_at) VALUES (193, 'd91aa7bf-3bc0-4824-85a8-d0af4d1afe69', 'POST', '/api/v1/bi/approval-flows', '127.0.0.1', NULL, 422, 292.91, '2026-11-24 20:33:39.25541');
INSERT INTO public.audit_log (id, request_id, method, path, client_ip, "user", status, cost_ms, created_at) VALUES (194, '20acb00f-4cc9-4100-8ca9-bb82857d6fe8', 'POST', '/api/v1/bi/approval-flows', '127.0.0.1', NULL, 201, 475.95, '2026-11-24 20:33:39.899196');
INSERT INTO public.audit_log (id, request_id, method, path, client_ip, "user", status, cost_ms, created_at) VALUES (195, '0b6e9b3b-4f0f-429c-98de-3f94256227bf', 'POST', '/api/v1/bi/dashboards', '127.0.0.1', NULL, 201, 506.25, '2026-11-24 20:33:40.574724');
INSERT INTO public.audit_log (id, request_id, method, path, client_ip, "user", status, cost_ms, created_at) VALUES (196, '81d0e97c-eb0d-49db-b48c-ae80852f2de8', 'PUT', '/api/v1/bi/dashboards/bid_c6dfb07a447c4842/draft', '127.0.0.1', NULL, 200, 606.46, '2026-11-24 20:33:41.348817');
INSERT INTO public.audit_log (id, request_id, method, path, client_ip, "user", status, cost_ms, created_at) VALUES (197, '1ae6c03a-6d98-4e65-9062-a2aa6bc3bea8', 'POST', '/api/v1/bi/dashboards/bid_c6dfb07a447c4842/publish', '127.0.0.1', NULL, 201, 722.12, '2026-11-24 20:33:42.240146');
INSERT INTO public.audit_log (id, request_id, method, path, client_ip, "user", status, cost_ms, created_at) VALUES (198, '7c7309ee-a1fd-4353-b970-32d080e961dc', 'PUT', '/api/v1/bi/approval-flows/8', '127.0.0.1', NULL, 200, 473.42, '2026-11-24 20:33:42.883709');
INSERT INTO public.audit_log (id, request_id, method, path, client_ip, "user", status, cost_ms, created_at) VALUES (199, 'd60a4805-c8a2-42ae-bc86-dbc81a710eb6', 'POST', '/api/v1/bi/approvals/AP-2026-0007/approve', '127.0.0.1', NULL, 200, 623.49, '2026-11-24 20:33:43.714925');
INSERT INTO public.audit_log (id, request_id, method, path, client_ip, "user", status, cost_ms, created_at) VALUES (200, '555edc03-e78d-46a6-ad51-f11b90e1553b', 'POST', '/api/v1/bi/approvals/AP-2026-0007/approve', '127.0.0.1', NULL, 200, 504.42, '2026-11-24 20:33:44.387408');
INSERT INTO public.audit_log (id, request_id, method, path, client_ip, "user", status, cost_ms, created_at) VALUES (201, '65ba8940-133d-47d6-8edb-b71ebbc0d1cc', 'POST', '/api/v1/bi/dashboards', '127.0.0.1', NULL, 201, 511.81, '2026-11-24 20:33:45.262661');
INSERT INTO public.audit_log (id, request_id, method, path, client_ip, "user", status, cost_ms, created_at) VALUES (202, 'da21285d-60a0-42af-a937-4234325fb571', 'PUT', '/api/v1/bi/dashboards/bid_2b0934fd04b244d1/draft', '127.0.0.1', NULL, 200, 553.86, '2026-11-24 20:33:45.984709');
INSERT INTO public.audit_log (id, request_id, method, path, client_ip, "user", status, cost_ms, created_at) VALUES (203, '98023204-b8ac-41f0-8163-adff73e011c6', 'POST', '/api/v1/auth/login', '127.0.0.1', NULL, 200, 497.43, '2026-11-24 20:33:46.874728');
INSERT INTO public.audit_log (id, request_id, method, path, client_ip, "user", status, cost_ms, created_at) VALUES (204, '3eb30c2a-8003-48c7-bee9-73ca308a14fa', 'POST', '/api/v1/bi/dashboards/bid_2b0934fd04b244d1/publish', '127.0.0.1', NULL, 201, 797.73, '2026-11-24 20:33:46.952432');
INSERT INTO public.audit_log (id, request_id, method, path, client_ip, "user", status, cost_ms, created_at) VALUES (205, 'ff690c85-3331-4de8-ba7c-03fc150a8302', 'POST', '/api/v1/bi/approvals/AP-2026-0008/approve', '127.0.0.1', NULL, 200, 506.62, '2026-11-24 20:33:47.628654');
INSERT INTO public.audit_log (id, request_id, method, path, client_ip, "user", status, cost_ms, created_at) VALUES (206, '1c7c38bb-861b-4b58-bbd7-5dfc8da178ff', 'POST', '/api/v1/bi/dashboards/bid_2b0934fd04b244d1/access-requests', '127.0.0.1', NULL, 201, 808.38, '2026-11-24 20:33:49.783082');
INSERT INTO public.audit_log (id, request_id, method, path, client_ip, "user", status, cost_ms, created_at) VALUES (207, 'a6c50ba2-0dfb-4534-be47-5100e9394a9d', 'POST', '/api/v1/bi/access-requests/AR-2026-0003/approve', '127.0.0.1', NULL, 200, 754.62, '2026-11-24 20:33:50.708399');
INSERT INTO public.audit_log (id, request_id, method, path, client_ip, "user", status, cost_ms, created_at) VALUES (208, '3d10578d-b4e5-4e8d-adc7-463c05d660c7', 'PUT', '/api/v1/bi/dashboards/bid_4e0f3c93522b40d7/draft', '127.0.0.1', NULL, 428, 395.25, '2026-11-24 20:33:51.857657');
INSERT INTO public.audit_log (id, request_id, method, path, client_ip, "user", status, cost_ms, created_at) VALUES (209, 'a0057a1b-28f8-47a7-a504-5894533ab993', 'POST', '/api/v1/bi/dashboards', '127.0.0.1', NULL, 201, 423.2, '2026-11-24 20:33:52.452927');
INSERT INTO public.audit_log (id, request_id, method, path, client_ip, "user", status, cost_ms, created_at) VALUES (210, 'f379804b-4357-465f-911a-c8649e73ba4d', 'POST', '/api/v1/bi/dashboards', '127.0.0.1', NULL, 201, 421.53, '2026-11-24 20:33:53.044237');
INSERT INTO public.audit_log (id, request_id, method, path, client_ip, "user", status, cost_ms, created_at) VALUES (211, '4da446ed-7857-4791-8e7d-8fb9e5834228', 'PUT', '/api/v1/bi/dashboards/bid_c31fbc99fc2c456c/draft', '127.0.0.1', NULL, 409, 423.39, '2026-11-24 20:33:53.634181');
INSERT INTO public.audit_log (id, request_id, method, path, client_ip, "user", status, cost_ms, created_at) VALUES (212, '6ee67ae4-6028-4403-a1a6-4b7ce2e893c1', 'POST', '/api/v1/bi/dashboards/bid_4e0f3c93522b40d7/offline', '127.0.0.1', NULL, 200, 418.48, '2026-11-24 20:33:54.221713');
INSERT INTO public.audit_log (id, request_id, method, path, client_ip, "user", status, cost_ms, created_at) VALUES (213, 'f524235b-0dfa-4120-9952-a8a4cd183999', 'DELETE', '/api/v1/bi/dashboards/bid_4e0f3c93522b40d7', '127.0.0.1', NULL, 200, 422.77, '2026-11-24 20:33:54.813326');
INSERT INTO public.audit_log (id, request_id, method, path, client_ip, "user", status, cost_ms, created_at) VALUES (214, '14f7c992-7507-492c-a7dc-29fe28ccff4e', 'POST', '/api/v1/bi/dashboards/bid_c6dfb07a447c4842/offline', '127.0.0.1', NULL, 200, 431.33, '2026-11-24 20:33:55.42007');
INSERT INTO public.audit_log (id, request_id, method, path, client_ip, "user", status, cost_ms, created_at) VALUES (215, '1a246c06-2d54-4572-9b0f-f65d9e89a698', 'DELETE', '/api/v1/bi/dashboards/bid_c6dfb07a447c4842', '127.0.0.1', NULL, 200, 447.88, '2026-11-24 20:33:56.04531');
INSERT INTO public.audit_log (id, request_id, method, path, client_ip, "user", status, cost_ms, created_at) VALUES (216, 'd23394ac-852e-4237-b096-ef3e4bea5934', 'POST', '/api/v1/bi/dashboards/bid_2b0934fd04b244d1/offline', '127.0.0.1', NULL, 200, 448.47, '2026-11-24 20:33:56.676722');
INSERT INTO public.audit_log (id, request_id, method, path, client_ip, "user", status, cost_ms, created_at) VALUES (217, '406d30f8-5689-4199-ba22-49abf7337abc', 'DELETE', '/api/v1/bi/dashboards/bid_2b0934fd04b244d1', '127.0.0.1', NULL, 200, 661.32, '2026-11-24 20:33:57.551007');
INSERT INTO public.audit_log (id, request_id, method, path, client_ip, "user", status, cost_ms, created_at) VALUES (218, '2d1d81a3-1e50-48b9-a507-bdf022b59035', 'POST', '/api/v1/bi/dashboards/bid_c31fbc99fc2c456c/offline', '127.0.0.1', NULL, 409, 376.04, '2026-11-24 20:33:58.097598');
INSERT INTO public.audit_log (id, request_id, method, path, client_ip, "user", status, cost_ms, created_at) VALUES (219, '48ec6daf-940e-4077-a009-3dc287238baf', 'DELETE', '/api/v1/bi/dashboards/bid_c31fbc99fc2c456c', '127.0.0.1', NULL, 200, 417.95, '2026-11-24 20:33:58.716693');
INSERT INTO public.audit_log (id, request_id, method, path, client_ip, "user", status, cost_ms, created_at) VALUES (220, '0072955d-baea-4d71-9c37-a2bde5c65f2a', 'PUT', '/api/v1/bi/dashboards/bid_6968701e73d64e8b/draft', '127.0.0.1', NULL, 403, 422.37, '2026-11-24 20:34:12.030668');
INSERT INTO public.audit_log (id, request_id, method, path, client_ip, "user", status, cost_ms, created_at) VALUES (221, '9c3f1f4a-ba2a-45ca-83ca-05403d145990', 'DELETE', '/api/v1/bi/dashboards/bid_6968701e73d64e8b', '127.0.0.1', NULL, 403, 387.57, '2026-11-24 20:34:12.599169');
INSERT INTO public.audit_log (id, request_id, method, path, client_ip, "user", status, cost_ms, created_at) VALUES (222, '35dcb013-86fe-401a-8fdf-9143b15000a2', 'POST', '/api/v1/bi/dashboards', '127.0.0.1', NULL, 201, 507.02, '2026-11-24 20:34:14.08015');
INSERT INTO public.audit_log (id, request_id, method, path, client_ip, "user", status, cost_ms, created_at) VALUES (223, '2ef94982-6ca6-4fdb-94e4-404fac951b49', 'POST', '/api/v1/bi/dashboards', '127.0.0.1', NULL, 422, 381.37, '2026-11-24 20:34:14.63096');
INSERT INTO public.audit_log (id, request_id, method, path, client_ip, "user", status, cost_ms, created_at) VALUES (224, '86c7dd1b-9fec-4be6-8575-b91862885f9d', 'PUT', '/api/v1/bi/dashboards/bid_3c8cef3754554d39/draft', '127.0.0.1', NULL, 200, 542.94, '2026-11-24 20:34:15.725676');
INSERT INTO public.audit_log (id, request_id, method, path, client_ip, "user", status, cost_ms, created_at) VALUES (225, '37d6734a-d84f-4eff-86fb-ba306696475b', 'POST', '/api/v1/bi/dashboards/bid_3c8cef3754554d39/publish', '127.0.0.1', NULL, 201, 754.71, '2026-11-24 20:34:16.648993');
INSERT INTO public.audit_log (id, request_id, method, path, client_ip, "user", status, cost_ms, created_at) VALUES (226, '1d34e7eb-419b-434b-abd3-233e1a7c10c8', 'POST', '/api/v1/bi/approvals/AP-2026-0006/approve', '127.0.0.1', NULL, 200, 514.66, '2026-11-24 20:34:17.359681');
INSERT INTO public.audit_log (id, request_id, method, path, client_ip, "user", status, cost_ms, created_at) VALUES (227, '56473d89-a84e-4644-b88d-2b9f08aa02cf', 'PUT', '/api/v1/bi/dashboards/bid_3c8cef3754554d39/draft', '127.0.0.1', NULL, 200, 551.47, '2026-11-24 20:34:18.442304');
INSERT INTO public.audit_log (id, request_id, method, path, client_ip, "user", status, cost_ms, created_at) VALUES (228, 'a1ba3962-f1d0-4d10-9ac2-27f39e85a511', 'POST', '/api/v1/bi/approval-flows', '127.0.0.1', NULL, 422, 379.75, '2026-11-24 20:34:19.332801');
INSERT INTO public.audit_log (id, request_id, method, path, client_ip, "user", status, cost_ms, created_at) VALUES (229, 'aec3116f-b390-493f-851e-7e77c6e61ce3', 'POST', '/api/v1/bi/approval-flows', '127.0.0.1', NULL, 201, 467.21, '2026-11-24 20:34:19.969745');
INSERT INTO public.audit_log (id, request_id, method, path, client_ip, "user", status, cost_ms, created_at) VALUES (230, '5fb95f07-0c5d-4ad1-9945-be6645aa50f9', 'POST', '/api/v1/bi/dashboards', '127.0.0.1', NULL, 201, 504.24, '2026-11-24 20:34:20.642719');
INSERT INTO public.audit_log (id, request_id, method, path, client_ip, "user", status, cost_ms, created_at) VALUES (231, '3415a9d9-69c8-43e7-89c7-34fc48240d54', 'PUT', '/api/v1/bi/dashboards/bid_4f3ec95775be4da5/draft', '127.0.0.1', NULL, 200, 549.77, '2026-11-24 20:34:21.360588');
INSERT INTO public.audit_log (id, request_id, method, path, client_ip, "user", status, cost_ms, created_at) VALUES (232, 'a5868519-4f8c-42c9-b954-1633dc085a69', 'POST', '/api/v1/bi/dashboards/bid_4f3ec95775be4da5/publish', '127.0.0.1', NULL, 201, 722.85, '2026-11-24 20:34:22.254184');
INSERT INTO public.audit_log (id, request_id, method, path, client_ip, "user", status, cost_ms, created_at) VALUES (233, '28977191-5637-4d82-8c6e-ba0bd0057c04', 'PUT', '/api/v1/bi/approval-flows/9', '127.0.0.1', NULL, 200, 499.23, '2026-11-24 20:34:22.921723');
INSERT INTO public.audit_log (id, request_id, method, path, client_ip, "user", status, cost_ms, created_at) VALUES (234, '06e01bbb-6315-49a5-b321-de43dd909178', 'POST', '/api/v1/bi/approvals/AP-2026-0007/approve', '127.0.0.1', NULL, 200, 620.2, '2026-11-24 20:34:23.751227');
INSERT INTO public.audit_log (id, request_id, method, path, client_ip, "user", status, cost_ms, created_at) VALUES (235, 'd80a1e6c-1cde-4934-9577-42bcfc9da965', 'POST', '/api/v1/bi/approvals/AP-2026-0007/approve', '127.0.0.1', NULL, 200, 501.81, '2026-11-24 20:34:24.424374');
INSERT INTO public.audit_log (id, request_id, method, path, client_ip, "user", status, cost_ms, created_at) VALUES (236, '26941cc5-7917-4e40-b400-3b97315b12c5', 'POST', '/api/v1/bi/dashboards', '127.0.0.1', NULL, 201, 498.29, '2026-11-24 20:34:25.305857');
INSERT INTO public.audit_log (id, request_id, method, path, client_ip, "user", status, cost_ms, created_at) VALUES (237, 'd0f05a65-59f1-49eb-8b94-654d4c941515', 'PUT', '/api/v1/bi/dashboards/bid_62333b92adf74153/draft', '127.0.0.1', NULL, 200, 561.46, '2026-11-24 20:34:26.043968');
INSERT INTO public.audit_log (id, request_id, method, path, client_ip, "user", status, cost_ms, created_at) VALUES (238, '50d9acfc-69f5-40de-abbd-e506b116c744', 'POST', '/api/v1/bi/dashboards/bid_62333b92adf74153/publish', '127.0.0.1', NULL, 201, 750.34, '2026-11-24 20:34:26.964343');
INSERT INTO public.audit_log (id, request_id, method, path, client_ip, "user", status, cost_ms, created_at) VALUES (239, 'f105c62a-8874-4864-b552-8f825f10f033', 'POST', '/api/v1/bi/approvals/AP-2026-0008/approve', '127.0.0.1', NULL, 200, 506.8, '2026-11-24 20:34:27.661903');
INSERT INTO public.audit_log (id, request_id, method, path, client_ip, "user", status, cost_ms, created_at) VALUES (240, 'c7491a7c-a432-46bf-8bc9-24719ace4777', 'POST', '/api/v1/bi/dashboards/bid_62333b92adf74153/access-requests', '127.0.0.1', NULL, 201, 878.81, '2026-11-24 20:34:29.934639');
INSERT INTO public.audit_log (id, request_id, method, path, client_ip, "user", status, cost_ms, created_at) VALUES (241, '4d995345-8327-4136-ab5d-a58c6a7e36a3', 'POST', '/api/v1/bi/access-requests/AR-2026-0003/approve', '127.0.0.1', NULL, 200, 752.55, '2026-11-24 20:34:30.855641');
INSERT INTO public.audit_log (id, request_id, method, path, client_ip, "user", status, cost_ms, created_at) VALUES (242, '0a605886-775b-4bd2-be88-22a5a7dca1c7', 'PUT', '/api/v1/bi/dashboards/bid_3c8cef3754554d39/draft', '127.0.0.1', NULL, 428, 387.92, '2026-11-24 20:34:32.000335');
INSERT INTO public.audit_log (id, request_id, method, path, client_ip, "user", status, cost_ms, created_at) VALUES (243, 'b86dc39b-16fd-4ec0-9923-7ad49a708643', 'POST', '/api/v1/bi/dashboards', '127.0.0.1', NULL, 201, 423.52, '2026-11-24 20:34:32.594937');
INSERT INTO public.audit_log (id, request_id, method, path, client_ip, "user", status, cost_ms, created_at) VALUES (244, '31fe1c8d-9b18-4fcd-88b6-6f2448251d9e', 'POST', '/api/v1/bi/dashboards', '127.0.0.1', NULL, 201, 449.5, '2026-11-24 20:34:33.213351');
INSERT INTO public.audit_log (id, request_id, method, path, client_ip, "user", status, cost_ms, created_at) VALUES (245, '3d5ba10e-cc14-4992-9dc9-8875c8fd95f8', 'PUT', '/api/v1/bi/dashboards/bid_de4571800485474e/draft', '127.0.0.1', NULL, 409, 518.57, '2026-11-24 20:34:33.902414');
INSERT INTO public.audit_log (id, request_id, method, path, client_ip, "user", status, cost_ms, created_at) VALUES (246, 'f63d3849-ff3e-43d8-b48f-07a41d7fd8c9', 'POST', '/api/v1/bi/dashboards/bid_3c8cef3754554d39/offline', '127.0.0.1', NULL, 200, 423.28, '2026-11-24 20:34:34.495844');
INSERT INTO public.audit_log (id, request_id, method, path, client_ip, "user", status, cost_ms, created_at) VALUES (247, '645973b6-7d1a-47db-94d4-bfeaafefd31a', 'DELETE', '/api/v1/bi/dashboards/bid_3c8cef3754554d39', '127.0.0.1', NULL, 200, 447.25, '2026-11-24 20:34:35.115641');
INSERT INTO public.audit_log (id, request_id, method, path, client_ip, "user", status, cost_ms, created_at) VALUES (248, '22815718-195a-4f93-b049-f6868709e82e', 'POST', '/api/v1/bi/dashboards/bid_4f3ec95775be4da5/offline', '127.0.0.1', NULL, 200, 421.33, '2026-11-24 20:34:35.703299');
INSERT INTO public.audit_log (id, request_id, method, path, client_ip, "user", status, cost_ms, created_at) VALUES (249, '9381c4dd-4bef-4955-965c-2f24df0325b0', 'DELETE', '/api/v1/bi/dashboards/bid_4f3ec95775be4da5', '127.0.0.1', NULL, 200, 419.27, '2026-11-24 20:34:36.293318');
INSERT INTO public.audit_log (id, request_id, method, path, client_ip, "user", status, cost_ms, created_at) VALUES (250, 'ab2a6012-dc91-4253-bb15-58871396aa23', 'POST', '/api/v1/bi/dashboards/bid_62333b92adf74153/offline', '127.0.0.1', NULL, 200, 417.48, '2026-11-24 20:34:36.879578');
INSERT INTO public.audit_log (id, request_id, method, path, client_ip, "user", status, cost_ms, created_at) VALUES (251, '70ece5e2-3096-4655-bd87-b01a34ffae11', 'DELETE', '/api/v1/bi/dashboards/bid_62333b92adf74153', '127.0.0.1', NULL, 200, 774.43, '2026-11-24 20:34:37.882571');
INSERT INTO public.audit_log (id, request_id, method, path, client_ip, "user", status, cost_ms, created_at) VALUES (252, 'b85abf2e-49ad-4f82-933d-a775be39f772', 'POST', '/api/v1/bi/dashboards/bid_942481643c5e45c8/offline', '127.0.0.1', NULL, 409, 385.06, '2026-11-24 20:34:38.459115');
INSERT INTO public.audit_log (id, request_id, method, path, client_ip, "user", status, cost_ms, created_at) VALUES (253, '085014a1-a0b0-464f-b79b-2cec70d4e223', 'DELETE', '/api/v1/bi/dashboards/bid_942481643c5e45c8', '127.0.0.1', NULL, 200, 417.33, '2026-11-24 20:34:39.044028');
INSERT INTO public.audit_log (id, request_id, method, path, client_ip, "user", status, cost_ms, created_at) VALUES (254, 'c11e10e6-aa09-4d01-9566-d0749eb4c29b', 'POST', '/api/v1/bi/dashboards/bid_de4571800485474e/offline', '127.0.0.1', NULL, 409, 332.97, '2026-11-24 20:34:39.544677');
INSERT INTO public.audit_log (id, request_id, method, path, client_ip, "user", status, cost_ms, created_at) VALUES (255, 'e5a4cb9d-6610-4633-be7c-0a717445e05d', 'DELETE', '/api/v1/bi/dashboards/bid_de4571800485474e', '127.0.0.1', NULL, 200, 421.89, '2026-11-24 20:34:40.133806');
INSERT INTO public.audit_log (id, request_id, method, path, client_ip, "user", status, cost_ms, created_at) VALUES (256, '7852787d-aa25-4571-89f6-9def36b387ac', 'POST', '/api/v1/auth/login', '127.0.0.1', NULL, 200, 500.37, '2026-11-24 20:38:20.827137');
INSERT INTO public.audit_log (id, request_id, method, path, client_ip, "user", status, cost_ms, created_at) VALUES (257, 'bfe13707-8439-488c-9802-ef70a4eaf75d', 'POST', '/api/v1/product-content-creation/generation-jobs', '127.0.0.1', NULL, 422, 313.2, '2026-11-24 20:39:50.726831');
INSERT INTO public.audit_log (id, request_id, method, path, client_ip, "user", status, cost_ms, created_at) VALUES (258, '4b57dc75-f3ec-4251-9540-90a509857df5', 'POST', '/api/v1/bi/dashboards', '127.0.0.1', NULL, 201, 1141.78, '2026-11-24 20:45:48.088969');
INSERT INTO public.audit_log (id, request_id, method, path, client_ip, "user", status, cost_ms, created_at) VALUES (259, 'bba1c65c-086d-4074-a191-dbfba6fb06c3', 'POST', '/api/v1/bi/approval-flows', '127.0.0.1', NULL, 201, 465.69, '2026-11-24 20:45:54.538725');
INSERT INTO public.audit_log (id, request_id, method, path, client_ip, "user", status, cost_ms, created_at) VALUES (260, '5eebb9f7-6fef-4900-bb10-21618d08629c', 'POST', '/api/v1/bi/dashboards', '127.0.0.1', NULL, 201, 508.63, '2026-11-24 20:45:55.238704');
INSERT INTO public.audit_log (id, request_id, method, path, client_ip, "user", status, cost_ms, created_at) VALUES (261, 'f4030e39-aed0-4431-8fd0-b0cee7104f32', 'PUT', '/api/v1/bi/dashboards/bid_710e915f836849b7/draft', '127.0.0.1', NULL, 200, 799.02, '2026-11-24 20:45:56.22768');
INSERT INTO public.audit_log (id, request_id, method, path, client_ip, "user", status, cost_ms, created_at) VALUES (262, 'bf3d9db3-b97e-4a07-8bba-4dea101dceed', 'POST', '/api/v1/bi/dashboards/bid_710e915f836849b7/publish', '127.0.0.1', NULL, 201, 677.77, '2026-11-24 20:45:57.07371');
INSERT INTO public.audit_log (id, request_id, method, path, client_ip, "user", status, cost_ms, created_at) VALUES (263, '2a0cda43-f388-433c-b8f6-f9775f61fbac', 'POST', '/api/v1/bi/approvals/AP-2026-0006/approve', '127.0.0.1', NULL, 403, 413.65, '2026-11-24 20:45:57.653662');
INSERT INTO public.audit_log (id, request_id, method, path, client_ip, "user", status, cost_ms, created_at) VALUES (264, '2c35663d-2ffc-4f90-a153-e61980697fc4', 'POST', '/api/v1/bi/approvals/AP-2026-0006/approve', '127.0.0.1', NULL, 200, 498.62, '2026-11-24 20:45:58.320358');
INSERT INTO public.audit_log (id, request_id, method, path, client_ip, "user", status, cost_ms, created_at) VALUES (265, 'f9a8cc90-7552-444e-a968-59baca148049', 'POST', '/api/v1/bi/dashboards', '127.0.0.1', NULL, 201, 421.98, '2026-11-24 20:46:00.006831');
INSERT INTO public.audit_log (id, request_id, method, path, client_ip, "user", status, cost_ms, created_at) VALUES (266, '77a58111-2fc3-41bf-8867-51e9d6ca79d8', 'PUT', '/api/v1/bi/dashboards/bid_b4c67819c34e4889/draft', '127.0.0.1', NULL, 200, 547.42, '2026-11-24 20:46:00.720981');
INSERT INTO public.audit_log (id, request_id, method, path, client_ip, "user", status, cost_ms, created_at) VALUES (267, '4fe04245-6858-45b1-b2a2-dc335f2c844d', 'POST', '/api/v1/bi/dashboards/bid_b4c67819c34e4889/publish', '127.0.0.1', NULL, 201, 998.29, '2026-11-24 20:46:01.885434');
INSERT INTO public.audit_log (id, request_id, method, path, client_ip, "user", status, cost_ms, created_at) VALUES (268, '854f32de-1336-4543-a359-c9fc4b19d0b1', 'POST', '/api/v1/bi/dashboards/bid_b4c67819c34e4889/publish', '127.0.0.1', NULL, 201, 39.49, '2026-11-24 20:46:02.092518');
INSERT INTO public.audit_log (id, request_id, method, path, client_ip, "user", status, cost_ms, created_at) VALUES (269, '5ad45383-0b32-429f-b369-98fbd372f301', 'POST', '/api/v1/bi/dashboards/bid_b4c67819c34e4889/publish', '127.0.0.1', NULL, 201, 40.12, '2026-11-24 20:46:02.300678');
INSERT INTO public.audit_log (id, request_id, method, path, client_ip, "user", status, cost_ms, created_at) VALUES (270, 'f6f58797-0147-4de2-83a1-08dd29083c36', 'POST', '/api/v1/bi/dashboards', '127.0.0.1', NULL, 201, 415.56, '2026-11-24 20:46:02.883847');
INSERT INTO public.audit_log (id, request_id, method, path, client_ip, "user", status, cost_ms, created_at) VALUES (271, '98c751ea-e891-4a16-8fb7-315a81ef9cdc', 'PUT', '/api/v1/bi/dashboards/bid_b4c67819c34e4889/draft', '127.0.0.1', NULL, 200, 503.86, '2026-11-24 20:46:03.593161');
INSERT INTO public.audit_log (id, request_id, method, path, client_ip, "user", status, cost_ms, created_at) VALUES (272, '38bb260e-0f01-4129-87a8-a95fd826d606', 'PUT', '/api/v1/bi/dashboards/bid_4be5af6a4f0a46d5/draft', '127.0.0.1', NULL, 200, 732.49, '2026-11-24 20:46:04.491245');
INSERT INTO public.audit_log (id, request_id, method, path, client_ip, "user", status, cost_ms, created_at) VALUES (273, '768f852e-9a44-4e87-947b-d6cba0ddbe4f', 'POST', '/api/v1/bi/approvals/AP-2026-0007/approve', '127.0.0.1', NULL, 409, 537.43, '2026-11-24 20:46:05.194701');
INSERT INTO public.audit_log (id, request_id, method, path, client_ip, "user", status, cost_ms, created_at) VALUES (274, '846c875d-e244-4a6c-bd2a-f22800f1fc13', 'POST', '/api/v1/bi/approvals/AP-2026-0007/approve', '127.0.0.1', NULL, 409, 40.38, '2026-11-24 20:46:05.401491');
INSERT INTO public.audit_log (id, request_id, method, path, client_ip, "user", status, cost_ms, created_at) VALUES (275, 'dc43e434-c84d-4f6a-99a7-3895844aaf1f', 'POST', '/api/v1/bi/dashboards/bid_396ceff32fd543e4/offline', '127.0.0.1', NULL, 409, 337.04, '2026-11-24 20:46:06.114956');
INSERT INTO public.audit_log (id, request_id, method, path, client_ip, "user", status, cost_ms, created_at) VALUES (276, '88cbb785-ecbd-452b-89ac-3b2405551b5c', 'DELETE', '/api/v1/bi/dashboards/bid_396ceff32fd543e4', '127.0.0.1', NULL, 200, 412.82, '2026-11-24 20:46:06.696966');
INSERT INTO public.audit_log (id, request_id, method, path, client_ip, "user", status, cost_ms, created_at) VALUES (277, '5923deb2-14ef-4215-a781-264eedc502cc', 'POST', '/api/v1/bi/dashboards/bid_710e915f836849b7/offline', '127.0.0.1', NULL, 200, 416.25, '2026-11-24 20:46:07.280628');
INSERT INTO public.audit_log (id, request_id, method, path, client_ip, "user", status, cost_ms, created_at) VALUES (278, 'c47df820-f95b-4256-bdf5-762b52e624af', 'DELETE', '/api/v1/bi/dashboards/bid_710e915f836849b7', '127.0.0.1', NULL, 200, 412.12, '2026-11-24 20:46:07.862179');
INSERT INTO public.audit_log (id, request_id, method, path, client_ip, "user", status, cost_ms, created_at) VALUES (279, '18378120-7ce3-41fd-9cb9-de531e516ffb', 'POST', '/api/v1/bi/dashboards/bid_b4c67819c34e4889/offline', '127.0.0.1', NULL, 409, 337.67, '2026-11-24 20:46:08.367228');
INSERT INTO public.audit_log (id, request_id, method, path, client_ip, "user", status, cost_ms, created_at) VALUES (280, '9a22c4e6-54b9-4665-b9e9-af46f3f8321a', 'DELETE', '/api/v1/bi/dashboards/bid_b4c67819c34e4889', '127.0.0.1', NULL, 200, 417.04, '2026-11-24 20:46:08.951524');
INSERT INTO public.audit_log (id, request_id, method, path, client_ip, "user", status, cost_ms, created_at) VALUES (281, '6f23e272-21c3-4098-889b-84e8440786e9', 'POST', '/api/v1/bi/dashboards/bid_4be5af6a4f0a46d5/offline', '127.0.0.1', NULL, 409, 334.17, '2026-11-24 20:46:09.451989');
INSERT INTO public.audit_log (id, request_id, method, path, client_ip, "user", status, cost_ms, created_at) VALUES (282, 'b7be2edd-b793-48d2-92f2-7b54f665cdcd', 'DELETE', '/api/v1/bi/dashboards/bid_4be5af6a4f0a46d5', '127.0.0.1', NULL, 200, 414.76, '2026-11-24 20:46:10.03492');
INSERT INTO public.audit_log (id, request_id, method, path, client_ip, "user", status, cost_ms, created_at) VALUES (283, 'a993548b-8e06-4894-8045-9c4c7fbcf3c6', 'POST', '/api/v1/bi/dashboards', '127.0.0.1', NULL, 201, 419.12, '2026-11-24 20:46:59.888867');
INSERT INTO public.audit_log (id, request_id, method, path, client_ip, "user", status, cost_ms, created_at) VALUES (284, 'f5ddf7f3-7487-4822-918d-b2027d099dbd', 'PUT', '/api/v1/bi/dashboards/bid_92afe9717e78423d/draft', '127.0.0.1', NULL, 200, 505.96, '2026-11-24 20:47:00.566483');
INSERT INTO public.audit_log (id, request_id, method, path, client_ip, "user", status, cost_ms, created_at) VALUES (285, 'd71fda64-ac6d-457a-9bd1-225713a59560', 'POST', '/api/v1/bi/dashboards/bid_92afe9717e78423d/publish', '127.0.0.1', NULL, 201, 998.89, '2026-11-24 20:47:01.732994');
INSERT INTO public.audit_log (id, request_id, method, path, client_ip, "user", status, cost_ms, created_at) VALUES (286, '841b4815-0348-4e73-9973-dbc0fc78af5d', 'POST', '/api/v1/bi/dashboards/bid_92afe9717e78423d/publish', '127.0.0.1', NULL, 201, 39.75, '2026-11-24 20:47:01.94218');
INSERT INTO public.audit_log (id, request_id, method, path, client_ip, "user", status, cost_ms, created_at) VALUES (287, 'd5a577de-734d-47a0-95c4-ab9a01f07be1', 'POST', '/api/v1/bi/dashboards/bid_92afe9717e78423d/publish', '127.0.0.1', NULL, 409, 417.5, '2026-11-24 20:47:02.574855');
INSERT INTO public.audit_log (id, request_id, method, path, client_ip, "user", status, cost_ms, created_at) VALUES (288, '8f657d9d-a92c-4935-9bf4-a3929d8c1ff2', 'POST', '/api/v1/bi/dashboards/bid_92afe9717e78423d/publish', '127.0.0.1', NULL, 409, 333.73, '2026-11-24 20:47:03.079024');
INSERT INTO public.audit_log (id, request_id, method, path, client_ip, "user", status, cost_ms, created_at) VALUES (289, 'f864a275-7472-4a97-af73-b99323f8ef92', 'POST', '/api/v1/bi/dashboards/bid_92afe9717e78423d/publish', '127.0.0.1', NULL, 409, 371.74, '2026-11-24 20:47:03.617347');
INSERT INTO public.audit_log (id, request_id, method, path, client_ip, "user", status, cost_ms, created_at) VALUES (290, '6014cfe9-16a8-4f96-bb58-14225f031c19', 'POST', '/api/v1/bi/approvals/AP-2026-0006/approve', '127.0.0.1', NULL, 200, 726.87, '2026-11-24 20:47:04.512801');
INSERT INTO public.audit_log (id, request_id, method, path, client_ip, "user", status, cost_ms, created_at) VALUES (291, 'a2052482-47c8-437d-b859-8f4608414f6b', 'POST', '/api/v1/bi/approvals/AP-2026-0006/approve', '127.0.0.1', NULL, 200, 39.61, '2026-11-24 20:47:04.719008');
INSERT INTO public.audit_log (id, request_id, method, path, client_ip, "user", status, cost_ms, created_at) VALUES (292, '4fe55a3a-05b4-459b-82a4-bc1ff5b4c02d', 'POST', '/api/v1/bi/dashboards', '127.0.0.1', NULL, 201, 1142.62, '2026-11-24 20:48:47.815564');
INSERT INTO public.audit_log (id, request_id, method, path, client_ip, "user", status, cost_ms, created_at) VALUES (293, '13210e15-9de5-4d28-ab4c-8b0a93f91c36', 'POST', '/api/v1/bi/dashboards', '127.0.0.1', NULL, 201, 454.04, '2026-11-24 20:48:49.272953');
INSERT INTO public.audit_log (id, request_id, method, path, client_ip, "user", status, cost_ms, created_at) VALUES (294, 'ae346e0e-e28c-48da-9949-2090851b38b1', 'POST', '/api/v1/bi/approval-flows', '127.0.0.1', NULL, 201, 525.34, '2026-11-24 20:48:55.546356');
INSERT INTO public.audit_log (id, request_id, method, path, client_ip, "user", status, cost_ms, created_at) VALUES (295, '6b07b575-6c02-4e41-9b7c-e223ea05a9f5', 'POST', '/api/v1/bi/dashboards', '127.0.0.1', NULL, 201, 587.84, '2026-11-24 20:48:56.316315');
INSERT INTO public.audit_log (id, request_id, method, path, client_ip, "user", status, cost_ms, created_at) VALUES (296, '180a9642-576b-411f-973d-6021a3c1f618', 'PUT', '/api/v1/bi/dashboards/bid_8be9601c270a43c4/draft', '127.0.0.1', NULL, 200, 839.38, '2026-11-24 20:48:57.327275');
INSERT INTO public.audit_log (id, request_id, method, path, client_ip, "user", status, cost_ms, created_at) VALUES (297, '9dc1b63a-d739-48d3-9587-e1c89a6793e5', 'POST', '/api/v1/bi/dashboards/bid_8be9601c270a43c4/publish', '127.0.0.1', NULL, 201, 678.93, '2026-11-24 20:48:58.191375');
INSERT INTO public.audit_log (id, request_id, method, path, client_ip, "user", status, cost_ms, created_at) VALUES (298, '4e13ed56-9169-498d-a205-9173f06eeeaa', 'POST', '/api/v1/bi/approvals/AP-2026-0007/approve', '127.0.0.1', NULL, 403, 418.91, '2026-11-24 20:48:58.775771');
INSERT INTO public.audit_log (id, request_id, method, path, client_ip, "user", status, cost_ms, created_at) VALUES (299, '20ae7dac-756b-4594-91de-9ddd6146360f', 'POST', '/api/v1/bi/approvals/AP-2026-0007/approve', '127.0.0.1', NULL, 200, 513.49, '2026-11-24 20:48:59.459715');
INSERT INTO public.audit_log (id, request_id, method, path, client_ip, "user", status, cost_ms, created_at) VALUES (300, '059f6990-75b7-437a-bb2f-88e27e34ab10', 'POST', '/api/v1/bi/dashboards', '127.0.0.1', NULL, 201, 414.15, '2026-11-24 20:49:02.766904');
INSERT INTO public.audit_log (id, request_id, method, path, client_ip, "user", status, cost_ms, created_at) VALUES (301, '6e387749-0750-44f7-9be8-d7bd35e5aad4', 'PUT', '/api/v1/bi/dashboards/bid_e08fb550e0a04a4a/draft', '127.0.0.1', NULL, 200, 494.09, '2026-11-24 20:49:03.429801');
INSERT INTO public.audit_log (id, request_id, method, path, client_ip, "user", status, cost_ms, created_at) VALUES (302, 'd63d7544-09a3-4f58-9418-67db33ac85e4', 'POST', '/api/v1/bi/dashboards/bid_e08fb550e0a04a4a/publish', '127.0.0.1', NULL, 201, 905.88, '2026-11-24 20:49:04.500765');
INSERT INTO public.audit_log (id, request_id, method, path, client_ip, "user", status, cost_ms, created_at) VALUES (303, 'b0c938c5-58d2-409c-a5a5-420d89db8250', 'POST', '/api/v1/bi/dashboards/bid_e08fb550e0a04a4a/publish', '127.0.0.1', NULL, 201, 340.96, '2026-11-24 20:49:05.015266');
INSERT INTO public.audit_log (id, request_id, method, path, client_ip, "user", status, cost_ms, created_at) VALUES (304, 'da900de0-eeb4-4dd5-8f74-535c0df0a451', 'POST', '/api/v1/bi/dashboards/bid_e08fb550e0a04a4a/publish', '127.0.0.1', NULL, 429, 330.27, '2026-11-24 20:49:05.526491');
INSERT INTO public.audit_log (id, request_id, method, path, client_ip, "user", status, cost_ms, created_at) VALUES (305, '7d262bba-f214-4818-8a5a-2d81639337e2', 'POST', '/api/v1/bi/dashboards', '127.0.0.1', NULL, 201, 420.78, '2026-11-24 20:49:06.116438');
INSERT INTO public.audit_log (id, request_id, method, path, client_ip, "user", status, cost_ms, created_at) VALUES (306, '5130abce-d8e3-4a9b-8ab6-2e4f372a8651', 'PUT', '/api/v1/bi/dashboards/bid_e08fb550e0a04a4a/draft', '127.0.0.1', NULL, 200, 508.34, '2026-11-24 20:49:06.788815');
INSERT INTO public.audit_log (id, request_id, method, path, client_ip, "user", status, cost_ms, created_at) VALUES (307, 'a97fc785-012a-4733-985f-57ff677b8473', 'PUT', '/api/v1/bi/dashboards/bid_acd5d09c780a4f17/draft', '127.0.0.1', NULL, 200, 494.27, '2026-11-24 20:49:07.451842');
INSERT INTO public.audit_log (id, request_id, method, path, client_ip, "user", status, cost_ms, created_at) VALUES (308, '09bfee38-c4fd-4ba7-92a4-ce5b58ef731b', 'POST', '/api/v1/bi/approvals/AP-2026-0008/approve', '127.0.0.1', NULL, 409, 408.4, '2026-11-24 20:49:08.030095');
INSERT INTO public.audit_log (id, request_id, method, path, client_ip, "user", status, cost_ms, created_at) VALUES (309, '13069bca-12f7-4734-8d01-281442808343', 'POST', '/api/v1/bi/approvals/AP-2026-0008/approve', '127.0.0.1', NULL, 409, 407.68, '2026-11-24 20:49:08.605409');
INSERT INTO public.audit_log (id, request_id, method, path, client_ip, "user", status, cost_ms, created_at) VALUES (310, '17b194f2-920c-4729-8d71-fc62f3724eee', 'POST', '/api/v1/bi/dashboards/bid_c8a300bcccbf43c5/offline', '127.0.0.1', NULL, 409, 332.82, '2026-11-24 20:49:09.318271');
INSERT INTO public.audit_log (id, request_id, method, path, client_ip, "user", status, cost_ms, created_at) VALUES (311, '62464d60-6b22-457c-bb8b-30d7958b49e5', 'DELETE', '/api/v1/bi/dashboards/bid_c8a300bcccbf43c5', '127.0.0.1', NULL, 200, 412.43, '2026-11-24 20:49:09.894896');
INSERT INTO public.audit_log (id, request_id, method, path, client_ip, "user", status, cost_ms, created_at) VALUES (312, 'd19ae291-c043-48f4-98af-397b6c4cc499', 'POST', '/api/v1/bi/dashboards/bid_f3af93c612ce457e/offline', '127.0.0.1', NULL, 409, 332.44, '2026-11-24 20:49:10.393895');
INSERT INTO public.audit_log (id, request_id, method, path, client_ip, "user", status, cost_ms, created_at) VALUES (313, 'aece61be-ec72-4238-9c4d-330046b44e27', 'DELETE', '/api/v1/bi/dashboards/bid_f3af93c612ce457e', '127.0.0.1', NULL, 200, 408.09, '2026-11-24 20:49:10.96835');
INSERT INTO public.audit_log (id, request_id, method, path, client_ip, "user", status, cost_ms, created_at) VALUES (314, '3c322ae2-deda-4013-bf8f-26f0b66ede47', 'POST', '/api/v1/bi/dashboards/bid_8be9601c270a43c4/offline', '127.0.0.1', NULL, 200, 411.56, '2026-11-24 20:49:11.554629');
INSERT INTO public.audit_log (id, request_id, method, path, client_ip, "user", status, cost_ms, created_at) VALUES (315, '52392c0f-3d4b-43e4-8466-366c7247e2e7', 'DELETE', '/api/v1/bi/dashboards/bid_8be9601c270a43c4', '127.0.0.1', NULL, 200, 449.69, '2026-11-24 20:49:12.184074');
INSERT INTO public.audit_log (id, request_id, method, path, client_ip, "user", status, cost_ms, created_at) VALUES (316, '7bcd682f-54c8-43e2-af21-65bff3f4666c', 'POST', '/api/v1/bi/dashboards/bid_e08fb550e0a04a4a/offline', '127.0.0.1', NULL, 409, 327.73, '2026-11-24 20:49:12.678152');
INSERT INTO public.audit_log (id, request_id, method, path, client_ip, "user", status, cost_ms, created_at) VALUES (317, 'cc3d1079-d213-4045-8292-a1217b97d2f7', 'DELETE', '/api/v1/bi/dashboards/bid_e08fb550e0a04a4a', '127.0.0.1', NULL, 200, 472.8, '2026-11-24 20:49:13.318772');
INSERT INTO public.audit_log (id, request_id, method, path, client_ip, "user", status, cost_ms, created_at) VALUES (318, 'bcc3ce99-4eb9-495a-b05d-026f0c6380a0', 'POST', '/api/v1/bi/dashboards/bid_acd5d09c780a4f17/offline', '127.0.0.1', NULL, 409, 330.61, '2026-11-24 20:49:13.816087');
INSERT INTO public.audit_log (id, request_id, method, path, client_ip, "user", status, cost_ms, created_at) VALUES (319, 'e793cdaa-727d-49b5-931b-427553170b31', 'DELETE', '/api/v1/bi/dashboards/bid_acd5d09c780a4f17', '127.0.0.1', NULL, 200, 415.28, '2026-11-24 20:49:14.396124');
INSERT INTO public.audit_log (id, request_id, method, path, client_ip, "user", status, cost_ms, created_at) VALUES (320, '02c32466-4e9a-43f8-a0c1-08ec7e7d9651', 'POST', '/api/v1/bi/dashboards', '127.0.0.1', NULL, 201, 437.64, '2026-11-24 20:49:37.788716');
INSERT INTO public.audit_log (id, request_id, method, path, client_ip, "user", status, cost_ms, created_at) VALUES (321, 'ecc1e183-25c0-4803-81ad-2042247a5ba5', 'PUT', '/api/v1/bi/dashboards/bid_9a42aedd47e24a57/draft', '127.0.0.1', NULL, 200, 416.1, '2026-11-24 20:49:38.370952');
INSERT INTO public.audit_log (id, request_id, method, path, client_ip, "user", status, cost_ms, created_at) VALUES (322, 'b773072b-58e7-4300-af91-60dbb4c278ea', 'POST', '/api/v1/bi/dashboards/bid_9a42aedd47e24a57/publish', '127.0.0.1', NULL, 201, 955.4, '2026-11-24 20:49:39.493532');
INSERT INTO public.audit_log (id, request_id, method, path, client_ip, "user", status, cost_ms, created_at) VALUES (323, 'bdea584c-34b6-4e45-ae35-649d01404038', 'POST', '/api/v1/bi/dashboards/bid_9a42aedd47e24a57/publish', '127.0.0.1', NULL, 201, 334.62, '2026-11-24 20:49:40.417984');
INSERT INTO public.audit_log (id, request_id, method, path, client_ip, "user", status, cost_ms, created_at) VALUES (324, 'fc0e3a98-6436-4e84-9079-c90188b92cdf', 'POST', '/api/v1/bi/approvals/AP-2026-0007/approve', '127.0.0.1', NULL, 200, 581.61, '2026-11-24 20:49:41.207853');
INSERT INTO public.audit_log (id, request_id, method, path, client_ip, "user", status, cost_ms, created_at) VALUES (325, '5896d5bd-671e-4be6-9946-7728cd70b92b', 'POST', '/api/v1/bi/approvals/AP-2026-0007/approve', '127.0.0.1', NULL, 200, 327.46, '2026-11-24 20:49:41.700177');
INSERT INTO public.audit_log (id, request_id, method, path, client_ip, "user", status, cost_ms, created_at) VALUES (326, '002c43f2-db2b-4eb8-8a62-3ebcda028092', 'POST', '/api/v1/bi/dashboards', '127.0.0.1', NULL, 201, 412.4, '2026-11-24 20:49:51.579435');
INSERT INTO public.audit_log (id, request_id, method, path, client_ip, "user", status, cost_ms, created_at) VALUES (327, '1bf2fe40-4873-4f76-816f-c894409fd770', 'POST', '/api/v1/bi/dashboards', '127.0.0.1', NULL, 201, 470.52, '2026-11-24 20:49:53.049759');
INSERT INTO public.audit_log (id, request_id, method, path, client_ip, "user", status, cost_ms, created_at) VALUES (328, '2cf24977-33c5-4812-b02d-4a1c24439876', 'POST', '/api/v1/bi/approval-flows', '127.0.0.1', NULL, 201, 451.73, '2026-11-24 20:49:59.543801');
INSERT INTO public.audit_log (id, request_id, method, path, client_ip, "user", status, cost_ms, created_at) VALUES (329, 'f6b7e446-6b6c-43de-90ba-e6f053a9011c', 'POST', '/api/v1/bi/dashboards', '127.0.0.1', NULL, 201, 501.05, '2026-11-24 20:50:00.211202');
INSERT INTO public.audit_log (id, request_id, method, path, client_ip, "user", status, cost_ms, created_at) VALUES (330, 'a97c8e2e-b458-44c2-ac62-9cec45795a1b', 'PUT', '/api/v1/bi/dashboards/bid_9d19d8eb7f3a4294/draft', '127.0.0.1', NULL, 200, 531.45, '2026-11-24 20:50:00.908288');
INSERT INTO public.audit_log (id, request_id, method, path, client_ip, "user", status, cost_ms, created_at) VALUES (331, '6c5c010c-157c-40b0-a8ae-076d8a93abbd', 'POST', '/api/v1/bi/dashboards/bid_9d19d8eb7f3a4294/publish', '127.0.0.1', NULL, 201, 661.81, '2026-11-24 20:50:01.734439');
INSERT INTO public.audit_log (id, request_id, method, path, client_ip, "user", status, cost_ms, created_at) VALUES (332, '374e3416-81a7-4512-a165-10ab7a51b257', 'POST', '/api/v1/bi/approvals/AP-2026-0008/approve', '127.0.0.1', NULL, 403, 413.31, '2026-11-24 20:50:02.310815');
INSERT INTO public.audit_log (id, request_id, method, path, client_ip, "user", status, cost_ms, created_at) VALUES (333, 'e78d07d6-365d-4866-84ac-da4f9bf32828', 'POST', '/api/v1/bi/approvals/AP-2026-0008/approve', '127.0.0.1', NULL, 200, 491.71, '2026-11-24 20:50:02.966013');
INSERT INTO public.audit_log (id, request_id, method, path, client_ip, "user", status, cost_ms, created_at) VALUES (334, '87ede574-ddc7-4036-8c4d-b7ebbf5efd9c', 'POST', '/api/v1/bi/dashboards', '127.0.0.1', NULL, 201, 422.11, '2026-11-24 20:50:06.708043');
INSERT INTO public.audit_log (id, request_id, method, path, client_ip, "user", status, cost_ms, created_at) VALUES (335, '61ad0df5-6354-40a0-9cdc-57f08ea419fa', 'PUT', '/api/v1/bi/dashboards/bid_bcc3c6d67be24bdd/draft', '127.0.0.1', NULL, 200, 489.74, '2026-11-24 20:50:07.362535');
INSERT INTO public.audit_log (id, request_id, method, path, client_ip, "user", status, cost_ms, created_at) VALUES (336, '165e516a-e00b-41e6-8587-24b8b171ff04', 'POST', '/api/v1/bi/dashboards/bid_bcc3c6d67be24bdd/publish', '127.0.0.1', NULL, 201, 956.88, '2026-11-24 20:50:08.484206');
INSERT INTO public.audit_log (id, request_id, method, path, client_ip, "user", status, cost_ms, created_at) VALUES (337, '3fa80f81-b221-4f91-9ba3-ec8e6adb7570', 'POST', '/api/v1/bi/dashboards/bid_bcc3c6d67be24bdd/publish', '127.0.0.1', NULL, 201, 323.07, '2026-11-24 20:50:08.971141');
INSERT INTO public.audit_log (id, request_id, method, path, client_ip, "user", status, cost_ms, created_at) VALUES (338, 'd0b23b8e-e235-4771-9290-5cb9e30349d5', 'POST', '/api/v1/bi/dashboards/bid_bcc3c6d67be24bdd/publish', '127.0.0.1', NULL, 429, 325.33, '2026-11-24 20:50:09.458795');
INSERT INTO public.audit_log (id, request_id, method, path, client_ip, "user", status, cost_ms, created_at) VALUES (339, 'e0a971ef-f163-4b42-bcd0-12cee3fede26', 'POST', '/api/v1/bi/dashboards', '127.0.0.1', NULL, 201, 407.31, '2026-11-24 20:50:10.028759');
INSERT INTO public.audit_log (id, request_id, method, path, client_ip, "user", status, cost_ms, created_at) VALUES (340, '27584510-7ea1-42aa-b789-d3e35623203c', 'PUT', '/api/v1/bi/dashboards/bid_bcc3c6d67be24bdd/draft', '127.0.0.1', NULL, 200, 489.52, '2026-11-24 20:50:10.68194');
INSERT INTO public.audit_log (id, request_id, method, path, client_ip, "user", status, cost_ms, created_at) VALUES (341, 'db4caaca-784b-499f-824e-848773e5aa4e', 'PUT', '/api/v1/bi/dashboards/bid_a87160272a9944bb/draft', '127.0.0.1', NULL, 200, 490.01, '2026-11-24 20:50:11.336333');
INSERT INTO public.audit_log (id, request_id, method, path, client_ip, "user", status, cost_ms, created_at) VALUES (342, 'a2b41b73-7b84-4dfe-9356-8e0be87b42f4', 'POST', '/api/v1/bi/approvals/AP-2026-0009/approve', '127.0.0.1', NULL, 409, 406.19, '2026-11-24 20:50:11.906906');
INSERT INTO public.audit_log (id, request_id, method, path, client_ip, "user", status, cost_ms, created_at) VALUES (343, '1f26179e-8061-4437-a7ac-63a63e1f89e9', 'POST', '/api/v1/bi/approvals/AP-2026-0009/approve', '127.0.0.1', NULL, 409, 406.82, '2026-11-24 20:50:12.477652');
INSERT INTO public.audit_log (id, request_id, method, path, client_ip, "user", status, cost_ms, created_at) VALUES (344, 'e4201d06-42e5-4485-a3f3-82bc4e871dd6', 'POST', '/api/v1/bi/dashboards/bid_09ae461fedc54075/offline', '127.0.0.1', NULL, 409, 328.21, '2026-11-24 20:50:13.192271');
INSERT INTO public.audit_log (id, request_id, method, path, client_ip, "user", status, cost_ms, created_at) VALUES (345, '542d7e17-9de3-4307-a6cb-cc719162cbc3', 'DELETE', '/api/v1/bi/dashboards/bid_09ae461fedc54075', '127.0.0.1', NULL, 200, 515.07, '2026-11-24 20:50:13.869267');
INSERT INTO public.audit_log (id, request_id, method, path, client_ip, "user", status, cost_ms, created_at) VALUES (346, '72785974-cbf4-42c5-9607-a79adf046456', 'POST', '/api/v1/bi/dashboards/bid_66c9abcb2aeb4510/offline', '127.0.0.1', NULL, 409, 326.81, '2026-11-24 20:50:14.359002');
INSERT INTO public.audit_log (id, request_id, method, path, client_ip, "user", status, cost_ms, created_at) VALUES (347, '8ba505f4-d47b-444a-8ed3-32d7d05469e7', 'DELETE', '/api/v1/bi/dashboards/bid_66c9abcb2aeb4510', '127.0.0.1', NULL, 200, 406.37, '2026-11-24 20:50:14.931276');
INSERT INTO public.audit_log (id, request_id, method, path, client_ip, "user", status, cost_ms, created_at) VALUES (348, '0b783d18-a429-480f-a533-09c441be073f', 'POST', '/api/v1/bi/dashboards/bid_9d19d8eb7f3a4294/offline', '127.0.0.1', NULL, 200, 411.52, '2026-11-24 20:50:15.506536');
INSERT INTO public.audit_log (id, request_id, method, path, client_ip, "user", status, cost_ms, created_at) VALUES (349, 'a6f6a542-de2e-4ec9-8ac0-60ec64800404', 'DELETE', '/api/v1/bi/dashboards/bid_9d19d8eb7f3a4294', '127.0.0.1', NULL, 200, 411.3, '2026-11-24 20:50:16.083129');
INSERT INTO public.audit_log (id, request_id, method, path, client_ip, "user", status, cost_ms, created_at) VALUES (350, '8fca1a8d-433c-46e0-a063-85546453680a', 'POST', '/api/v1/bi/dashboards/bid_bcc3c6d67be24bdd/offline', '127.0.0.1', NULL, 409, 329.63, '2026-11-24 20:50:16.576767');
INSERT INTO public.audit_log (id, request_id, method, path, client_ip, "user", status, cost_ms, created_at) VALUES (351, '291a9254-51ee-48c0-9c3e-fdf4fe934548', 'DELETE', '/api/v1/bi/dashboards/bid_bcc3c6d67be24bdd', '127.0.0.1', NULL, 200, 411.76, '2026-11-24 20:50:17.153622');
INSERT INTO public.audit_log (id, request_id, method, path, client_ip, "user", status, cost_ms, created_at) VALUES (352, '554c32ec-6ac8-434d-a9b2-ac9bf5019a6b', 'POST', '/api/v1/bi/dashboards/bid_a87160272a9944bb/offline', '127.0.0.1', NULL, 409, 329.09, '2026-11-24 20:50:17.646774');
INSERT INTO public.audit_log (id, request_id, method, path, client_ip, "user", status, cost_ms, created_at) VALUES (353, '34e0ff6a-7764-445a-b90b-eabac5b0f129', 'DELETE', '/api/v1/bi/dashboards/bid_a87160272a9944bb', '127.0.0.1', NULL, 200, 410.12, '2026-11-24 20:50:18.221071');
INSERT INTO public.audit_log (id, request_id, method, path, client_ip, "user", status, cost_ms, created_at) VALUES (354, '40b1960c-397b-4cd1-ada7-cb70a4fea7cc', 'POST', '/api/v1/bi/dashboards', '127.0.0.1', NULL, 201, 415.98, '2026-11-24 20:50:40.892621');
INSERT INTO public.audit_log (id, request_id, method, path, client_ip, "user", status, cost_ms, created_at) VALUES (355, '85c81c3b-2056-4cf0-b279-9ac5823f0b0a', 'PUT', '/api/v1/bi/dashboards/bid_613ff2f2be6f4d37/draft', '127.0.0.1', NULL, 200, 494.52, '2026-11-24 20:50:41.552813');
INSERT INTO public.audit_log (id, request_id, method, path, client_ip, "user", status, cost_ms, created_at) VALUES (356, '4bd82c8d-65cf-422b-9263-9844731ae0f5', 'POST', '/api/v1/bi/dashboards/bid_613ff2f2be6f4d37/publish', '127.0.0.1', NULL, 201, 908.99, '2026-11-24 20:50:42.628216');
INSERT INTO public.audit_log (id, request_id, method, path, client_ip, "user", status, cost_ms, created_at) VALUES (357, '93d637bc-2c12-4d07-9ed8-c90cb820d5ee', 'POST', '/api/v1/bi/dashboards/bid_613ff2f2be6f4d37/publish', '127.0.0.1', NULL, 201, 330.15, '2026-11-24 20:50:43.124634');
INSERT INTO public.audit_log (id, request_id, method, path, client_ip, "user", status, cost_ms, created_at) VALUES (358, '1c37be83-c9c7-4126-ad6b-b8cb00aece18', 'POST', '/api/v1/bi/approvals/AP-2026-0008/approve', '127.0.0.1', NULL, 200, 635.19, '2026-11-24 20:50:43.938744');
INSERT INTO public.audit_log (id, request_id, method, path, client_ip, "user", status, cost_ms, created_at) VALUES (359, '28641921-3e9e-40f5-80a4-1d56cd2cd0e8', 'POST', '/api/v1/bi/approvals/AP-2026-0008/approve', '127.0.0.1', NULL, 200, 326.23, '2026-11-24 20:50:44.433022');
INSERT INTO public.audit_log (id, request_id, method, path, client_ip, "user", status, cost_ms, created_at) VALUES (360, '9d379dfa-5d66-43fd-8d1b-71e060fb92d1', 'POST', '/api/v1/bi/dashboards', '127.0.0.1', NULL, 201, 418.28, '2026-11-24 20:50:57.891015');
INSERT INTO public.audit_log (id, request_id, method, path, client_ip, "user", status, cost_ms, created_at) VALUES (361, 'cf038342-e79e-472a-8251-1cb18d5b29d7', 'POST', '/api/v1/bi/dashboards', '127.0.0.1', NULL, 201, 456.43, '2026-11-24 20:50:59.347842');
INSERT INTO public.audit_log (id, request_id, method, path, client_ip, "user", status, cost_ms, created_at) VALUES (362, '11f9a388-733d-46a9-bbe1-c79e128539ae', 'POST', '/api/v1/bi/approval-flows', '127.0.0.1', NULL, 201, 451.33, '2026-11-24 20:51:06.590237');
INSERT INTO public.audit_log (id, request_id, method, path, client_ip, "user", status, cost_ms, created_at) VALUES (363, '6c40eb25-632a-4129-a7a1-2b78ba3043db', 'POST', '/api/v1/bi/dashboards', '127.0.0.1', NULL, 201, 496.5, '2026-11-24 20:51:07.253653');
INSERT INTO public.audit_log (id, request_id, method, path, client_ip, "user", status, cost_ms, created_at) VALUES (364, '6c317483-5779-49a2-a34e-f4d1e12e3310', 'PUT', '/api/v1/bi/dashboards/bid_1da190d0249e4e09/draft', '127.0.0.1', NULL, 200, 539.07, '2026-11-24 20:51:07.957218');
INSERT INTO public.audit_log (id, request_id, method, path, client_ip, "user", status, cost_ms, created_at) VALUES (365, '4b22bd90-3e26-4791-8290-32760e678bb8', 'POST', '/api/v1/bi/dashboards/bid_1da190d0249e4e09/publish', '127.0.0.1', NULL, 201, 660.78, '2026-11-24 20:51:08.783339');
INSERT INTO public.audit_log (id, request_id, method, path, client_ip, "user", status, cost_ms, created_at) VALUES (366, '6d7a3561-cb1b-4932-b2bf-458afa026869', 'POST', '/api/v1/bi/approvals/AP-2026-0009/approve', '127.0.0.1', NULL, 403, 422.77, '2026-11-24 20:51:09.371203');
INSERT INTO public.audit_log (id, request_id, method, path, client_ip, "user", status, cost_ms, created_at) VALUES (367, 'fa6500f9-ac12-43ae-a630-beae48559e9c', 'POST', '/api/v1/bi/approvals/AP-2026-0009/approve', '127.0.0.1', NULL, 200, 489.03, '2026-11-24 20:51:10.023254');
INSERT INTO public.audit_log (id, request_id, method, path, client_ip, "user", status, cost_ms, created_at) VALUES (368, '3f523319-ec41-4973-b367-6336540afde1', 'POST', '/api/v1/bi/dashboards', '127.0.0.1', NULL, 201, 439.94, '2026-11-24 20:51:14.254111');
INSERT INTO public.audit_log (id, request_id, method, path, client_ip, "user", status, cost_ms, created_at) VALUES (369, 'e45d932e-2826-4998-ac7b-7e4f85f85dc5', 'PUT', '/api/v1/bi/dashboards/bid_995fd570fa264f09/draft', '127.0.0.1', NULL, 200, 495.21, '2026-11-24 20:51:14.914231');
INSERT INTO public.audit_log (id, request_id, method, path, client_ip, "user", status, cost_ms, created_at) VALUES (370, 'ca4a3413-e7dd-4459-bc0a-205aa1e8fe51', 'POST', '/api/v1/bi/dashboards/bid_995fd570fa264f09/publish', '127.0.0.1', NULL, 201, 955.46, '2026-11-24 20:51:16.033824');
INSERT INTO public.audit_log (id, request_id, method, path, client_ip, "user", status, cost_ms, created_at) VALUES (371, '4db75fd6-e6e6-4207-b4be-9ea50c266025', 'POST', '/api/v1/bi/dashboards/bid_995fd570fa264f09/publish', '127.0.0.1', NULL, 201, 331.67, '2026-11-24 20:51:16.531444');
INSERT INTO public.audit_log (id, request_id, method, path, client_ip, "user", status, cost_ms, created_at) VALUES (372, '47dba8ad-5686-4390-995d-5cbb159b3cc8', 'POST', '/api/v1/bi/dashboards/bid_995fd570fa264f09/publish', '127.0.0.1', NULL, 429, 327.94, '2026-11-24 20:51:17.024375');
INSERT INTO public.audit_log (id, request_id, method, path, client_ip, "user", status, cost_ms, created_at) VALUES (373, 'd4410068-ba4b-420a-9f06-5f13bf126bb7', 'POST', '/api/v1/bi/dashboards', '127.0.0.1', NULL, 201, 417.69, '2026-11-24 20:51:17.608215');
INSERT INTO public.audit_log (id, request_id, method, path, client_ip, "user", status, cost_ms, created_at) VALUES (374, 'b48df83b-8188-42f3-a5bd-a8c38d60df96', 'PUT', '/api/v1/bi/dashboards/bid_995fd570fa264f09/draft', '127.0.0.1', NULL, 200, 495.65, '2026-11-24 20:51:18.271214');
INSERT INTO public.audit_log (id, request_id, method, path, client_ip, "user", status, cost_ms, created_at) VALUES (375, 'f9ab56cc-8f34-47bc-8b12-1b8fb046171a', 'PUT', '/api/v1/bi/dashboards/bid_df23abb154d24029/draft', '127.0.0.1', NULL, 200, 497.55, '2026-11-24 20:51:18.933765');
INSERT INTO public.audit_log (id, request_id, method, path, client_ip, "user", status, cost_ms, created_at) VALUES (376, 'a0fa638a-6f9c-4646-b603-949fb0e0e687', 'POST', '/api/v1/bi/approvals/AP-2026-0010/approve', '127.0.0.1', NULL, 409, 413.31, '2026-11-24 20:51:19.513906');
INSERT INTO public.audit_log (id, request_id, method, path, client_ip, "user", status, cost_ms, created_at) VALUES (377, '8fa045b0-b078-4553-8a29-5baf4f3a1f72', 'POST', '/api/v1/bi/approvals/AP-2026-0010/approve', '127.0.0.1', NULL, 409, 408.05, '2026-11-24 20:51:20.092776');
INSERT INTO public.audit_log (id, request_id, method, path, client_ip, "user", status, cost_ms, created_at) VALUES (378, '2104a330-b147-4bfc-aa8f-b583e0587a69', 'POST', '/api/v1/bi/dashboards/bid_6f840ae967c34471/offline', '127.0.0.1', NULL, 409, 331.09, '2026-11-24 20:51:20.800835');
INSERT INTO public.audit_log (id, request_id, method, path, client_ip, "user", status, cost_ms, created_at) VALUES (379, '36584e90-1466-4d03-a9b1-c1452cb33377', 'DELETE', '/api/v1/bi/dashboards/bid_6f840ae967c34471', '127.0.0.1', NULL, 200, 410.39, '2026-11-24 20:51:21.38878');
INSERT INTO public.audit_log (id, request_id, method, path, client_ip, "user", status, cost_ms, created_at) VALUES (380, '4d733381-19a3-4ce3-b956-a63a26be38e1', 'POST', '/api/v1/bi/dashboards/bid_cb9b2b288c4449a6/offline', '127.0.0.1', NULL, 409, 333.18, '2026-11-24 20:51:21.886834');
INSERT INTO public.audit_log (id, request_id, method, path, client_ip, "user", status, cost_ms, created_at) VALUES (381, '6362f771-694d-4566-842d-9e4e456448e0', 'DELETE', '/api/v1/bi/dashboards/bid_cb9b2b288c4449a6', '127.0.0.1', NULL, 200, 415.27, '2026-11-24 20:51:22.469788');
INSERT INTO public.audit_log (id, request_id, method, path, client_ip, "user", status, cost_ms, created_at) VALUES (382, '9f09921a-9577-4514-a85d-a6bf7b2d67e6', 'POST', '/api/v1/bi/dashboards/bid_1da190d0249e4e09/offline', '127.0.0.1', NULL, 200, 410.62, '2026-11-24 20:51:23.046765');
INSERT INTO public.audit_log (id, request_id, method, path, client_ip, "user", status, cost_ms, created_at) VALUES (383, '73f7e85f-15bd-43ce-a0f0-c69e21773b6d', 'DELETE', '/api/v1/bi/dashboards/bid_1da190d0249e4e09', '127.0.0.1', NULL, 200, 406.9, '2026-11-24 20:51:23.618351');
INSERT INTO public.audit_log (id, request_id, method, path, client_ip, "user", status, cost_ms, created_at) VALUES (384, '3998cfd9-c353-42ef-adaa-2e93a7135fb8', 'POST', '/api/v1/bi/dashboards/bid_995fd570fa264f09/offline', '127.0.0.1', NULL, 409, 327.79, '2026-11-24 20:51:24.112907');
INSERT INTO public.audit_log (id, request_id, method, path, client_ip, "user", status, cost_ms, created_at) VALUES (385, '942d153b-9344-4777-a0f1-473edbeb2b6a', 'DELETE', '/api/v1/bi/dashboards/bid_995fd570fa264f09', '127.0.0.1', NULL, 200, 410.29, '2026-11-24 20:51:24.689097');
INSERT INTO public.audit_log (id, request_id, method, path, client_ip, "user", status, cost_ms, created_at) VALUES (386, 'dd14fa2f-7e01-4942-ae82-b2119434f313', 'POST', '/api/v1/bi/dashboards/bid_df23abb154d24029/offline', '127.0.0.1', NULL, 409, 329.85, '2026-11-24 20:51:25.181872');
INSERT INTO public.audit_log (id, request_id, method, path, client_ip, "user", status, cost_ms, created_at) VALUES (387, 'c09854c0-da08-4d70-96b4-ae60e0f285f4', 'DELETE', '/api/v1/bi/dashboards/bid_df23abb154d24029', '127.0.0.1', NULL, 200, 405.33, '2026-11-24 20:51:25.749481');
INSERT INTO public.audit_log (id, request_id, method, path, client_ip, "user", status, cost_ms, created_at) VALUES (388, '80319aef-3789-407e-8ac3-00d45f2f9d08', 'POST', '/api/v1/bi/dashboards', '127.0.0.1', NULL, 201, 1158.77, '2026-11-24 20:52:03.478086');
INSERT INTO public.audit_log (id, request_id, method, path, client_ip, "user", status, cost_ms, created_at) VALUES (389, '2247653f-fd03-4b32-8bcb-07664c439bea', 'POST', '/api/v1/bi/dashboards', '127.0.0.1', NULL, 201, 503.02, '2026-11-24 20:52:05.002398');
INSERT INTO public.audit_log (id, request_id, method, path, client_ip, "user", status, cost_ms, created_at) VALUES (390, '09ea9274-62f5-4a6a-b663-09c298456ed4', 'POST', '/api/v1/bi/approval-flows', '127.0.0.1', NULL, 201, 459.26, '2026-11-24 20:52:12.498644');
INSERT INTO public.audit_log (id, request_id, method, path, client_ip, "user", status, cost_ms, created_at) VALUES (391, '4a24bd4a-b1fb-49db-9875-8ab9334e623a', 'POST', '/api/v1/bi/dashboards', '127.0.0.1', NULL, 201, 505.62, '2026-11-24 20:52:13.171137');
INSERT INTO public.audit_log (id, request_id, method, path, client_ip, "user", status, cost_ms, created_at) VALUES (392, 'b45cec71-5bdb-4879-8816-391ecef8b88f', 'PUT', '/api/v1/bi/dashboards/bid_ba1e98cff5464bda/draft', '127.0.0.1', NULL, 200, 772.38, '2026-11-24 20:52:14.112565');
INSERT INTO public.audit_log (id, request_id, method, path, client_ip, "user", status, cost_ms, created_at) VALUES (393, '0239682e-e079-421e-b612-b1b15cf1dec9', 'POST', '/api/v1/bi/dashboards/bid_ba1e98cff5464bda/publish', '127.0.0.1', NULL, 201, 735.11, '2026-11-24 20:52:15.018106');
INSERT INTO public.audit_log (id, request_id, method, path, client_ip, "user", status, cost_ms, created_at) VALUES (394, '88bcf1d1-d2e5-49ca-83ec-ff77bd4dcee8', 'POST', '/api/v1/bi/approvals/AP-2026-0009/approve', '127.0.0.1', NULL, 403, 422.68, '2026-11-24 20:52:15.618837');
INSERT INTO public.audit_log (id, request_id, method, path, client_ip, "user", status, cost_ms, created_at) VALUES (395, '7b10c5f4-b8da-4f38-a647-d858c1c32056', 'POST', '/api/v1/bi/approvals/AP-2026-0009/approve', '127.0.0.1', NULL, 200, 523.07, '2026-11-24 20:52:16.312108');
INSERT INTO public.audit_log (id, request_id, method, path, client_ip, "user", status, cost_ms, created_at) VALUES (396, '4df98f19-d518-48e8-9c94-4d10b0b1a973', 'POST', '/api/v1/bi/dashboards', '127.0.0.1', NULL, 201, 416.94, '2026-11-24 20:52:20.590007');
INSERT INTO public.audit_log (id, request_id, method, path, client_ip, "user", status, cost_ms, created_at) VALUES (397, '5032e7f7-4888-4d37-b5c3-d8024d686bc6', 'PUT', '/api/v1/bi/dashboards/bid_3913cf7c831145da/draft', '127.0.0.1', NULL, 200, 502.63, '2026-11-24 20:52:21.260447');
INSERT INTO public.audit_log (id, request_id, method, path, client_ip, "user", status, cost_ms, created_at) VALUES (398, '09d3538d-1694-4704-b226-ea69f25ebbfc', 'POST', '/api/v1/bi/dashboards/bid_3913cf7c831145da/publish', '127.0.0.1', NULL, 201, 938.45, '2026-11-24 20:52:22.363748');
INSERT INTO public.audit_log (id, request_id, method, path, client_ip, "user", status, cost_ms, created_at) VALUES (399, 'ef31cd41-7e1f-4fde-b90e-d2fbc4dc0b97', 'POST', '/api/v1/bi/dashboards/bid_3913cf7c831145da/publish', '127.0.0.1', NULL, 201, 335.47, '2026-11-24 20:52:22.893719');
INSERT INTO public.audit_log (id, request_id, method, path, client_ip, "user", status, cost_ms, created_at) VALUES (400, '3370e146-45b1-4b58-9ca0-293c98db1e27', 'POST', '/api/v1/bi/dashboards/bid_3913cf7c831145da/publish', '127.0.0.1', NULL, 429, 336.31, '2026-11-24 20:52:23.414272');
INSERT INTO public.audit_log (id, request_id, method, path, client_ip, "user", status, cost_ms, created_at) VALUES (401, '65bc82e3-82d2-4179-af88-d50d34e088a4', 'POST', '/api/v1/bi/dashboards', '127.0.0.1', NULL, 201, 415.49, '2026-11-24 20:52:23.996791');
INSERT INTO public.audit_log (id, request_id, method, path, client_ip, "user", status, cost_ms, created_at) VALUES (402, '7aadf20a-36b1-471a-9936-435941135c69', 'POST', '/api/v1/bi/dashboards', '127.0.0.1', NULL, 201, 417.96, '2026-11-24 20:52:24.583994');
INSERT INTO public.audit_log (id, request_id, method, path, client_ip, "user", status, cost_ms, created_at) VALUES (403, '06c9217d-a7c6-4ae1-894c-906f7702d905', 'PUT', '/api/v1/bi/dashboards/bid_b243ff8e38e94e47/draft', '127.0.0.1', NULL, 200, 508.71, '2026-11-24 20:52:25.261233');
INSERT INTO public.audit_log (id, request_id, method, path, client_ip, "user", status, cost_ms, created_at) VALUES (404, '4a45fd2e-3b0c-4f23-85e4-1cabbe4bfac6', 'PUT', '/api/v1/bi/dashboards/bid_8f370632e5cf45b9/draft', '127.0.0.1', NULL, 200, 499.51, '2026-11-24 20:52:25.927755');
INSERT INTO public.audit_log (id, request_id, method, path, client_ip, "user", status, cost_ms, created_at) VALUES (405, '7f84d94f-02d7-4b71-933f-65a666cceb5b', 'POST', '/api/v1/bi/approvals/AP-2026-0010/approve', '127.0.0.1', NULL, 200, 594.77, '2026-11-24 20:52:26.692367');
INSERT INTO public.audit_log (id, request_id, method, path, client_ip, "user", status, cost_ms, created_at) VALUES (406, '15a4f62d-d900-4c76-a3b6-7300f1c3e1aa', 'POST', '/api/v1/bi/approvals/AP-2026-0010/approve', '127.0.0.1', NULL, 200, 499.08, '2026-11-24 20:52:27.399915');
INSERT INTO public.audit_log (id, request_id, method, path, client_ip, "user", status, cost_ms, created_at) VALUES (407, 'f46fbacf-dfe9-4ece-af62-3b0110496e12', 'POST', '/api/v1/bi/dashboards/bid_eb6f7c1295234222/offline', '127.0.0.1', NULL, 409, 340.54, '2026-11-24 20:52:28.129143');
INSERT INTO public.audit_log (id, request_id, method, path, client_ip, "user", status, cost_ms, created_at) VALUES (408, '4c4abd77-0e9d-45ad-96d4-999a1e5d0a33', 'DELETE', '/api/v1/bi/dashboards/bid_eb6f7c1295234222', '127.0.0.1', NULL, 200, 413.7, '2026-11-24 20:52:28.708546');
INSERT INTO public.audit_log (id, request_id, method, path, client_ip, "user", status, cost_ms, created_at) VALUES (409, '9db0bbfa-796d-41da-9ce2-3ba526ed9b1c', 'POST', '/api/v1/bi/dashboards/bid_b4f629e5188e45d1/offline', '127.0.0.1', NULL, 409, 338.53, '2026-11-24 20:52:29.215504');
INSERT INTO public.audit_log (id, request_id, method, path, client_ip, "user", status, cost_ms, created_at) VALUES (410, 'b1676a09-2b95-41da-b84d-0da49743c64d', 'DELETE', '/api/v1/bi/dashboards/bid_b4f629e5188e45d1', '127.0.0.1', NULL, 200, 420.99, '2026-11-24 20:52:29.807223');
INSERT INTO public.audit_log (id, request_id, method, path, client_ip, "user", status, cost_ms, created_at) VALUES (411, '9e92e664-a509-4e33-b959-f2d0882308ab', 'POST', '/api/v1/bi/dashboards/bid_ba1e98cff5464bda/offline', '127.0.0.1', NULL, 200, 422.85, '2026-11-24 20:52:30.399333');
INSERT INTO public.audit_log (id, request_id, method, path, client_ip, "user", status, cost_ms, created_at) VALUES (412, '6101efa7-caf5-48f6-94bb-384c691f1233', 'DELETE', '/api/v1/bi/dashboards/bid_ba1e98cff5464bda', '127.0.0.1', NULL, 200, 431.5, '2026-11-24 20:52:30.997951');
INSERT INTO public.audit_log (id, request_id, method, path, client_ip, "user", status, cost_ms, created_at) VALUES (413, 'be62fb34-35f4-4db2-8fc4-4099c0ed31aa', 'POST', '/api/v1/bi/dashboards/bid_3913cf7c831145da/offline', '127.0.0.1', NULL, 200, 416.51, '2026-11-24 20:52:31.597736');
INSERT INTO public.audit_log (id, request_id, method, path, client_ip, "user", status, cost_ms, created_at) VALUES (414, '2125e9a2-0684-4548-a466-a9f9c657c232', 'DELETE', '/api/v1/bi/dashboards/bid_3913cf7c831145da', '127.0.0.1', NULL, 200, 418.36, '2026-11-24 20:52:32.183232');
INSERT INTO public.audit_log (id, request_id, method, path, client_ip, "user", status, cost_ms, created_at) VALUES (415, '28af0182-a663-4dfa-942e-c1e1187f55d3', 'POST', '/api/v1/bi/dashboards/bid_b243ff8e38e94e47/offline', '127.0.0.1', NULL, 409, 575.47, '2026-11-24 20:52:32.966533');
INSERT INTO public.audit_log (id, request_id, method, path, client_ip, "user", status, cost_ms, created_at) VALUES (416, '6525d829-7b26-4d1c-8c9f-da1e9b98bebd', 'DELETE', '/api/v1/bi/dashboards/bid_b243ff8e38e94e47', '127.0.0.1', NULL, 200, 523.19, '2026-11-24 20:52:33.656211');
INSERT INTO public.audit_log (id, request_id, method, path, client_ip, "user", status, cost_ms, created_at) VALUES (417, '83432c01-ab1b-4e58-a65a-829dadb6192f', 'POST', '/api/v1/bi/dashboards/bid_8f370632e5cf45b9/offline', '127.0.0.1', NULL, 409, 346.62, '2026-11-24 20:52:34.172767');
INSERT INTO public.audit_log (id, request_id, method, path, client_ip, "user", status, cost_ms, created_at) VALUES (418, '59526472-c2b4-4e55-8cf9-855ca30d92c5', 'DELETE', '/api/v1/bi/dashboards/bid_8f370632e5cf45b9', '127.0.0.1', NULL, 200, 422.1, '2026-11-24 20:52:34.76263');
INSERT INTO public.audit_log (id, request_id, method, path, client_ip, "user", status, cost_ms, created_at) VALUES (419, '75a4cc39-c75c-4dda-a45a-7cfb79431a54', 'POST', '/api/v1/bi/dashboards', '127.0.0.1', NULL, 201, 505.61, '2026-11-24 20:53:49.873156');
INSERT INTO public.audit_log (id, request_id, method, path, client_ip, "user", status, cost_ms, created_at) VALUES (420, '3eba4b21-1d41-4ab8-818d-a870c56fb013', 'PUT', '/api/v1/bi/dashboards/bid_eaea5affa1c14b93/draft', '127.0.0.1', NULL, 200, 547.27, '2026-11-24 20:53:50.594057');
INSERT INTO public.audit_log (id, request_id, method, path, client_ip, "user", status, cost_ms, created_at) VALUES (421, 'f68a7e1b-2f3e-4a81-8787-e06807f08cb5', 'POST', '/api/v1/bi/dashboards/bid_eaea5affa1c14b93/publish', '127.0.0.1', NULL, 201, 859.54, '2026-11-24 20:53:51.660954');
INSERT INTO public.audit_log (id, request_id, method, path, client_ip, "user", status, cost_ms, created_at) VALUES (422, '6326a359-fada-4075-aff0-39e0ae592757', 'PUT', '/api/v1/bi/dashboards/bid_6968701e73d64e8b/draft', '127.0.0.1', NULL, 403, 433.09, '2026-11-24 20:57:40.059834');
INSERT INTO public.audit_log (id, request_id, method, path, client_ip, "user", status, cost_ms, created_at) VALUES (423, 'cd63fca4-82cb-4bd7-8473-8fecc8a1f0c6', 'DELETE', '/api/v1/bi/dashboards/bid_6968701e73d64e8b', '127.0.0.1', NULL, 403, 383.58, '2026-11-24 20:57:40.611783');
INSERT INTO public.audit_log (id, request_id, method, path, client_ip, "user", status, cost_ms, created_at) VALUES (424, 'eb2099cc-169c-47f4-8b91-618812ce8f30', 'POST', '/api/v1/bi/dashboards', '127.0.0.1', NULL, 201, 503.76, '2026-11-24 20:57:42.084231');
INSERT INTO public.audit_log (id, request_id, method, path, client_ip, "user", status, cost_ms, created_at) VALUES (425, '18bd8a44-b7b1-49e0-9073-24e3692f01db', 'POST', '/api/v1/bi/dashboards', '127.0.0.1', NULL, 422, 414.2, '2026-11-24 20:57:42.665415');
INSERT INTO public.audit_log (id, request_id, method, path, client_ip, "user", status, cost_ms, created_at) VALUES (426, '838dcf38-9cea-4d4f-9f49-c92c903f210e', 'PUT', '/api/v1/bi/dashboards/bid_f8738e7dc5e6407b/draft', '127.0.0.1', NULL, 200, 538.68, '2026-11-24 20:57:43.748748');
INSERT INTO public.audit_log (id, request_id, method, path, client_ip, "user", status, cost_ms, created_at) VALUES (427, '3cf1fa85-ab47-4149-98d8-61cce936486c', 'POST', '/api/v1/bi/dashboards/bid_f8738e7dc5e6407b/publish', '127.0.0.1', NULL, 201, 755.57, '2026-11-24 20:57:44.672447');
INSERT INTO public.audit_log (id, request_id, method, path, client_ip, "user", status, cost_ms, created_at) VALUES (428, 'c50062d0-0f0a-4c1b-b50d-d0dff97f7721', 'POST', '/api/v1/bi/approvals/AP-2026-0006/approve', '127.0.0.1', NULL, 200, 498.29, '2026-11-24 20:57:45.339434');
INSERT INTO public.audit_log (id, request_id, method, path, client_ip, "user", status, cost_ms, created_at) VALUES (429, 'bb7d546b-26ea-4a62-b77b-a7c8e668132e', 'PUT', '/api/v1/bi/dashboards/bid_f8738e7dc5e6407b/draft', '127.0.0.1', NULL, 200, 579.01, '2026-11-24 20:57:46.450794');
INSERT INTO public.audit_log (id, request_id, method, path, client_ip, "user", status, cost_ms, created_at) VALUES (430, 'a21febe1-10f4-4649-a98e-165060bc70ed', 'POST', '/api/v1/bi/approval-flows', '127.0.0.1', NULL, 422, 376.79, '2026-11-24 20:57:47.334252');
INSERT INTO public.audit_log (id, request_id, method, path, client_ip, "user", status, cost_ms, created_at) VALUES (431, '0d4f95b6-fbc0-4ffe-be08-dc48d41eae46', 'POST', '/api/v1/bi/approval-flows', '127.0.0.1', NULL, 201, 477.66, '2026-11-24 20:57:47.97768');
INSERT INTO public.audit_log (id, request_id, method, path, client_ip, "user", status, cost_ms, created_at) VALUES (432, 'a81a1ae9-a088-4c22-85ab-4c921daa3248', 'POST', '/api/v1/bi/dashboards', '127.0.0.1', NULL, 201, 500.15, '2026-11-24 20:57:48.646529');
INSERT INTO public.audit_log (id, request_id, method, path, client_ip, "user", status, cost_ms, created_at) VALUES (433, '6887a468-80d1-42b6-a2a0-42a9db270c88', 'PUT', '/api/v1/bi/dashboards/bid_2f8f04c1beea4151/draft', '127.0.0.1', NULL, 200, 543.05, '2026-11-24 20:57:49.356405');
INSERT INTO public.audit_log (id, request_id, method, path, client_ip, "user", status, cost_ms, created_at) VALUES (434, 'cbf7e29a-7164-441f-9a30-c4b1ba9cfef6', 'POST', '/api/v1/bi/dashboards/bid_2f8f04c1beea4151/publish', '127.0.0.1', NULL, 201, 711.39, '2026-11-24 20:57:50.235059');
INSERT INTO public.audit_log (id, request_id, method, path, client_ip, "user", status, cost_ms, created_at) VALUES (435, '904b283c-2b78-4940-8881-99ccdf12e137', 'PUT', '/api/v1/bi/approval-flows/15', '127.0.0.1', NULL, 200, 459.07, '2026-11-24 20:57:50.863234');
INSERT INTO public.audit_log (id, request_id, method, path, client_ip, "user", status, cost_ms, created_at) VALUES (436, 'ffea58f4-7b13-4952-96f2-8a48480bbbd8', 'POST', '/api/v1/bi/approvals/AP-2026-0007/approve', '127.0.0.1', NULL, 200, 630.7, '2026-11-24 20:57:51.700612');
INSERT INTO public.audit_log (id, request_id, method, path, client_ip, "user", status, cost_ms, created_at) VALUES (437, '332b210d-ba34-43f8-a136-faf08ae54efd', 'POST', '/api/v1/bi/approvals/AP-2026-0007/approve', '127.0.0.1', NULL, 200, 497.61, '2026-11-24 20:57:52.368684');
INSERT INTO public.audit_log (id, request_id, method, path, client_ip, "user", status, cost_ms, created_at) VALUES (438, '8a06e3fc-1c0d-4c5b-a046-39694dbe0af6', 'POST', '/api/v1/bi/dashboards', '127.0.0.1', NULL, 201, 542.31, '2026-11-24 20:57:53.290333');
INSERT INTO public.audit_log (id, request_id, method, path, client_ip, "user", status, cost_ms, created_at) VALUES (439, '87225ef0-e634-4b99-b3bb-7619d8a0dc52', 'PUT', '/api/v1/bi/dashboards/bid_a11fa0aa55644610/draft', '127.0.0.1', NULL, 200, 537.74, '2026-11-24 20:57:53.99628');
INSERT INTO public.audit_log (id, request_id, method, path, client_ip, "user", status, cost_ms, created_at) VALUES (440, '974c96b5-b07f-4b6e-b342-7ed7ef269a5c', 'POST', '/api/v1/bi/dashboards/bid_a11fa0aa55644610/publish', '127.0.0.1', NULL, 201, 751.28, '2026-11-24 20:57:54.92025');
INSERT INTO public.audit_log (id, request_id, method, path, client_ip, "user", status, cost_ms, created_at) VALUES (441, 'c5007c18-5194-441f-96c1-1c26848dc243', 'POST', '/api/v1/bi/approvals/AP-2026-0008/approve', '127.0.0.1', NULL, 200, 494.9, '2026-11-24 20:57:55.581058');
INSERT INTO public.audit_log (id, request_id, method, path, client_ip, "user", status, cost_ms, created_at) VALUES (442, '9c10f4b9-63fd-41b9-b588-eef89be337cb', 'POST', '/api/v1/bi/dashboards/bid_a11fa0aa55644610/access-requests', '127.0.0.1', NULL, 201, 801.09, '2026-11-24 20:57:57.719691');
INSERT INTO public.audit_log (id, request_id, method, path, client_ip, "user", status, cost_ms, created_at) VALUES (443, '52a862cd-fcb8-490c-9e6c-7961405bce3f', 'POST', '/api/v1/bi/access-requests/AR-2026-0003/approve', '127.0.0.1', NULL, 200, 758.14, '2026-11-24 20:57:58.646564');
INSERT INTO public.audit_log (id, request_id, method, path, client_ip, "user", status, cost_ms, created_at) VALUES (444, '2d9a2aad-adb6-49a5-b625-897dda600b03', 'PUT', '/api/v1/bi/dashboards/bid_f8738e7dc5e6407b/draft', '127.0.0.1', NULL, 428, 393.03, '2026-11-24 20:57:59.790213');
INSERT INTO public.audit_log (id, request_id, method, path, client_ip, "user", status, cost_ms, created_at) VALUES (445, '16c342ec-f0ce-4e6c-9fca-33418e9e1a92', 'POST', '/api/v1/bi/dashboards', '127.0.0.1', NULL, 201, 421.79, '2026-11-24 20:58:00.378911');
INSERT INTO public.audit_log (id, request_id, method, path, client_ip, "user", status, cost_ms, created_at) VALUES (446, '61b9f6b7-5adf-4c68-927c-ed25fe0c7970', 'POST', '/api/v1/bi/dashboards', '127.0.0.1', NULL, 201, 417.69, '2026-11-24 20:58:00.963027');
INSERT INTO public.audit_log (id, request_id, method, path, client_ip, "user", status, cost_ms, created_at) VALUES (447, '02c2c2e0-3a39-4c39-9f8c-506802beb06f', 'PUT', '/api/v1/bi/dashboards/bid_b3482a0a75244dc7/draft', '127.0.0.1', NULL, 409, 430.24, '2026-11-24 20:58:01.562134');
INSERT INTO public.audit_log (id, request_id, method, path, client_ip, "user", status, cost_ms, created_at) VALUES (448, 'e2c14dd2-7eb9-4b4c-8ec9-50177fdf6a9d', 'POST', '/api/v1/bi/dashboards/bid_f8738e7dc5e6407b/offline', '127.0.0.1', NULL, 200, 417.58, '2026-11-24 20:58:02.148072');
INSERT INTO public.audit_log (id, request_id, method, path, client_ip, "user", status, cost_ms, created_at) VALUES (449, '77434bfa-7bb3-4de7-a687-319209f5a39a', 'DELETE', '/api/v1/bi/dashboards/bid_f8738e7dc5e6407b', '127.0.0.1', NULL, 200, 417.42, '2026-11-24 20:58:02.733869');
INSERT INTO public.audit_log (id, request_id, method, path, client_ip, "user", status, cost_ms, created_at) VALUES (450, '04588e3c-ff0b-462a-8d0e-a4c787139939', 'POST', '/api/v1/bi/dashboards/bid_2f8f04c1beea4151/offline', '127.0.0.1', NULL, 200, 439.4, '2026-11-24 20:58:03.342325');
INSERT INTO public.audit_log (id, request_id, method, path, client_ip, "user", status, cost_ms, created_at) VALUES (451, 'fe6d8eed-37f8-4723-a07c-49438f93bfbd', 'DELETE', '/api/v1/bi/dashboards/bid_2f8f04c1beea4151', '127.0.0.1', NULL, 200, 422.83, '2026-11-24 20:58:03.931757');
INSERT INTO public.audit_log (id, request_id, method, path, client_ip, "user", status, cost_ms, created_at) VALUES (452, '40f70045-8da1-42f4-aa5f-d42dc83dddf8', 'POST', '/api/v1/bi/dashboards/bid_a11fa0aa55644610/offline', '127.0.0.1', NULL, 200, 416.16, '2026-11-24 20:58:04.515842');
INSERT INTO public.audit_log (id, request_id, method, path, client_ip, "user", status, cost_ms, created_at) VALUES (453, '3d417d3f-84b4-4bdb-a2c9-5e84579f13e6', 'DELETE', '/api/v1/bi/dashboards/bid_a11fa0aa55644610', '127.0.0.1', NULL, 200, 658.86, '2026-11-24 20:58:05.383467');
INSERT INTO public.audit_log (id, request_id, method, path, client_ip, "user", status, cost_ms, created_at) VALUES (454, 'b22d91a2-753b-4b07-81b9-558e17e142da', 'POST', '/api/v1/bi/dashboards/bid_31fd4e80dd4b4614/offline', '127.0.0.1', NULL, 409, 376.86, '2026-11-24 20:58:05.925426');
INSERT INTO public.audit_log (id, request_id, method, path, client_ip, "user", status, cost_ms, created_at) VALUES (455, '14c6dd74-53b6-45fc-a499-19bcf5ebc594', 'DELETE', '/api/v1/bi/dashboards/bid_31fd4e80dd4b4614', '127.0.0.1', NULL, 200, 414.74, '2026-11-24 20:58:06.507735');
INSERT INTO public.audit_log (id, request_id, method, path, client_ip, "user", status, cost_ms, created_at) VALUES (456, '075ab082-1811-4d51-bca4-b5d1d9462e20', 'POST', '/api/v1/bi/dashboards/bid_b3482a0a75244dc7/offline', '127.0.0.1', NULL, 409, 330.42, '2026-11-24 20:58:07.004973');
INSERT INTO public.audit_log (id, request_id, method, path, client_ip, "user", status, cost_ms, created_at) VALUES (457, 'c7b67635-9fed-4ffe-9e59-06b2e64850c6', 'DELETE', '/api/v1/bi/dashboards/bid_b3482a0a75244dc7', '127.0.0.1', NULL, 200, 422, '2026-11-24 20:58:07.5955');
INSERT INTO public.audit_log (id, request_id, method, path, client_ip, "user", status, cost_ms, created_at) VALUES (458, '097480c8-184d-47f3-9b8e-03e06f6d2bb2', 'POST', '/api/v1/auth/login', '127.0.0.1', NULL, 200, 1181.09, '2026-11-24 21:45:58.881711');
INSERT INTO public.audit_log (id, request_id, method, path, client_ip, "user", status, cost_ms, created_at) VALUES (459, '471517ce-480d-4f32-a92e-79573a553bcf', 'POST', '/api/v1/auth/login', '127.0.0.1', NULL, 200, 1120.85, '2026-11-24 21:51:20.34581');
INSERT INTO public.audit_log (id, request_id, method, path, client_ip, "user", status, cost_ms, created_at) VALUES (460, '454e6eef-91c1-4c30-8bd7-c9849fca11ff', 'POST', '/api/v1/auth/login', '127.0.0.1', NULL, 200, 506.9, '2026-11-24 21:51:26.78883');
INSERT INTO public.audit_log (id, request_id, method, path, client_ip, "user", status, cost_ms, created_at) VALUES (461, '0e87a79c-f6be-457b-b045-9f55860838e9', 'POST', '/api/v1/auth/login', '127.0.0.1', NULL, 200, 491.35, '2026-11-24 21:51:32.140506');
INSERT INTO public.audit_log (id, request_id, method, path, client_ip, "user", status, cost_ms, created_at) VALUES (462, '4478bdb8-1c3f-48d8-b206-fac340b59b49', 'POST', '/api/v1/auth/login', '127.0.0.1', NULL, 200, 477.03, '2026-11-24 21:51:36.518124');
INSERT INTO public.audit_log (id, request_id, method, path, client_ip, "user", status, cost_ms, created_at) VALUES (463, '6d6ae489-1532-4850-b6ce-7b59d723c07a', 'POST', '/api/v1/auth/login', '127.0.0.1', NULL, 200, 496.08, '2026-11-24 21:52:48.381325');
INSERT INTO public.audit_log (id, request_id, method, path, client_ip, "user", status, cost_ms, created_at) VALUES (464, '39f959f9-7701-4a14-9e0a-ac6385ce4634', 'POST', '/api/v1/auth/login', '127.0.0.1', NULL, 200, 508.79, '2026-11-24 21:53:28.792983');
INSERT INTO public.audit_log (id, request_id, method, path, client_ip, "user", status, cost_ms, created_at) VALUES (465, '08fef993-ce8c-4bb5-a1ff-e772bfa57ecc', 'POST', '/api/v1/bi/dashboards', '127.0.0.1', NULL, 201, 544.44, '2026-11-24 21:59:11.861369');
INSERT INTO public.audit_log (id, request_id, method, path, client_ip, "user", status, cost_ms, created_at) VALUES (466, 'c23f6c99-f46c-4a0d-864d-d9159d834ed7', 'POST', '/api/v1/bi/dashboards/bid_12f57749a8d94933/compose', '127.0.0.1', NULL, 200, 456.19, '2026-11-24 21:59:12.504412');
INSERT INTO public.audit_log (id, request_id, method, path, client_ip, "user", status, cost_ms, created_at) VALUES (467, '383d48b6-cfbd-4291-b64e-a850f351808b', 'POST', '/api/v1/bi/dashboards/bid_12f57749a8d94933/compose', '127.0.0.1', NULL, 200, 412.06, '2026-11-24 21:59:13.102325');
INSERT INTO public.audit_log (id, request_id, method, path, client_ip, "user", status, cost_ms, created_at) VALUES (468, '4b73738e-2130-4e67-8061-2d0a0481180e', 'POST', '/api/v1/bi/dashboards/bid_12f57749a8d94933/compose', '127.0.0.1', NULL, 422, 409.91, '2026-11-24 21:59:13.694434');
INSERT INTO public.audit_log (id, request_id, method, path, client_ip, "user", status, cost_ms, created_at) VALUES (469, '87a5fb1f-c6d0-449d-9d23-6e95a1e5eeaf', 'POST', '/api/v1/bi/dashboards/bid_not_exist/compose', '127.0.0.1', NULL, 404, 415.8, '2026-11-24 21:59:14.296228');
INSERT INTO public.audit_log (id, request_id, method, path, client_ip, "user", status, cost_ms, created_at) VALUES (470, '63f2b3bc-dde5-4915-af7a-0f94a85fa0d7', 'POST', '/api/v1/bi/dashboards/bid_12f57749a8d94933/compose', '127.0.0.1', NULL, 200, 414.13, '2026-11-24 21:59:14.89332');
INSERT INTO public.audit_log (id, request_id, method, path, client_ip, "user", status, cost_ms, created_at) VALUES (471, '12b353fd-c25b-465a-9807-1b048530b5ab', 'POST', '/api/v1/bi/dashboards/bid_12f57749a8d94933/compose', '127.0.0.1', NULL, 200, 409.43, '2026-11-24 21:59:15.487764');
INSERT INTO public.audit_log (id, request_id, method, path, client_ip, "user", status, cost_ms, created_at) VALUES (472, '4e2097d2-6ed7-49e9-ae57-55456c3c89fe', 'POST', '/api/v1/bi/dashboards/bid_12f57749a8d94933/compose', '127.0.0.1', NULL, 422, 410.98, '2026-11-24 21:59:16.088795');
INSERT INTO public.audit_log (id, request_id, method, path, client_ip, "user", status, cost_ms, created_at) VALUES (473, '25edfdc5-1bd5-45a5-9d66-9aa568180b48', 'POST', '/api/v1/bi/dashboards/bid_12f57749a8d94933/preview', '127.0.0.1', NULL, 200, 441.31, '2026-11-24 21:59:17.800489');
INSERT INTO public.audit_log (id, request_id, method, path, client_ip, "user", status, cost_ms, created_at) VALUES (474, 'cb994210-cc9e-44ba-8d25-33a1d7bc9475', 'POST', '/api/v1/bi/dashboards/bid_12f57749a8d94933/preview', '127.0.0.1', NULL, 422, 408.04, '2026-11-24 21:59:18.846796');
INSERT INTO public.audit_log (id, request_id, method, path, client_ip, "user", status, cost_ms, created_at) VALUES (475, '4500fdd7-9065-449e-9a8c-276820298251', 'POST', '/api/v1/bi/dashboards/bid_12f57749a8d94933/preview', '127.0.0.1', NULL, 422, 418.44, '2026-11-24 21:59:19.44915');
INSERT INTO public.audit_log (id, request_id, method, path, client_ip, "user", status, cost_ms, created_at) VALUES (476, 'c2ba9d07-18d1-4ef7-baa5-9dfa5fd38544', 'POST', '/api/v1/bi/dashboards', '127.0.0.1', NULL, 201, 552.37, '2026-11-24 21:59:20.185169');
INSERT INTO public.audit_log (id, request_id, method, path, client_ip, "user", status, cost_ms, created_at) VALUES (477, '1f91f207-f0af-4f1b-b50f-62be5e3df5db', 'POST', '/api/v1/bi/dashboards/bid_3476d57b0a7547ed/preview', '127.0.0.1', NULL, 403, 318.67, '2026-11-24 21:59:20.689981');
INSERT INTO public.audit_log (id, request_id, method, path, client_ip, "user", status, cost_ms, created_at) VALUES (478, 'e0df1d94-38a4-41cd-84fd-71ac82b1d609', 'POST', '/api/v1/bi/dashboards/bid_3476d57b0a7547ed/compose', '127.0.0.1', NULL, 403, 510.63, '2026-11-24 21:59:21.38519');
INSERT INTO public.audit_log (id, request_id, method, path, client_ip, "user", status, cost_ms, created_at) VALUES (479, '5e15e776-a3f3-4994-8c37-3987ab3fe265', 'POST', '/api/v1/bi/dashboards/bid_3476d57b0a7547ed/preview', '127.0.0.1', NULL, 200, 411.08, '2026-11-24 21:59:21.98059');
INSERT INTO public.audit_log (id, request_id, method, path, client_ip, "user", status, cost_ms, created_at) VALUES (480, 'b63d58ee-8e60-40d8-bf18-fc85d6d60716', 'POST', '/api/v1/bi/describe', '127.0.0.1', NULL, 200, 380.79, '2026-11-24 21:59:22.558512');
INSERT INTO public.audit_log (id, request_id, method, path, client_ip, "user", status, cost_ms, created_at) VALUES (481, '9ff0a864-555e-483c-9f84-b181210f9012', 'POST', '/api/v1/bi/describe', '127.0.0.1', NULL, 200, 371.92, '2026-11-24 21:59:23.113957');
INSERT INTO public.audit_log (id, request_id, method, path, client_ip, "user", status, cost_ms, created_at) VALUES (482, '2737860c-6d67-4bb2-8900-60ce65fd5ffd', 'POST', '/api/v1/bi/describe', '127.0.0.1', NULL, 200, 360.98, '2026-11-24 21:59:23.660416');
INSERT INTO public.audit_log (id, request_id, method, path, client_ip, "user", status, cost_ms, created_at) VALUES (483, 'b30cc641-3546-4960-b574-3386798268bf', 'POST', '/api/v1/bi/describe', '127.0.0.1', NULL, 200, 369.05, '2026-11-24 21:59:24.211626');
INSERT INTO public.audit_log (id, request_id, method, path, client_ip, "user", status, cost_ms, created_at) VALUES (484, '5245cc02-d531-46dc-8d26-694da49971cd', 'POST', '/api/v1/bi/describe', '127.0.0.1', NULL, 422, 364.57, '2026-11-24 21:59:24.766199');
INSERT INTO public.audit_log (id, request_id, method, path, client_ip, "user", status, cost_ms, created_at) VALUES (485, '553a5cab-f4be-4419-ac7d-d1981e0ee14d', 'POST', '/api/v1/bi/describe', '127.0.0.1', NULL, 200, 361.54, '2026-11-24 21:59:25.314533');
INSERT INTO public.audit_log (id, request_id, method, path, client_ip, "user", status, cost_ms, created_at) VALUES (486, '8d062b5f-bf47-437b-bf5c-cbff19d9daa7', 'POST', '/api/v1/bi/dashboards/bid_12f57749a8d94933/compose', '127.0.0.1', NULL, 200, 415.36, '2026-11-24 21:59:26.884648');
INSERT INTO public.audit_log (id, request_id, method, path, client_ip, "user", status, cost_ms, created_at) VALUES (487, '101b6cd0-ed97-4225-9856-950aca6c9282', 'POST', '/api/v1/bi/dashboards/bid_12f57749a8d94933/compose', '127.0.0.1', NULL, 200, 413.08, '2026-11-24 21:59:27.481252');
INSERT INTO public.audit_log (id, request_id, method, path, client_ip, "user", status, cost_ms, created_at) VALUES (488, 'e829fd89-c63a-43e4-97ed-674a534bd1c0', 'POST', '/api/v1/bi/dashboards/bid_12f57749a8d94933/compose', '127.0.0.1', NULL, 200, 452.99, '2026-11-24 21:59:28.116496');
INSERT INTO public.audit_log (id, request_id, method, path, client_ip, "user", status, cost_ms, created_at) VALUES (489, '6108dce2-1f6a-4132-b7dd-c8a3666e9d58', 'POST', '/api/v1/bi/dashboards/bid_12f57749a8d94933/compose', '127.0.0.1', NULL, 200, 403.59, '2026-11-24 21:59:28.704174');
INSERT INTO public.audit_log (id, request_id, method, path, client_ip, "user", status, cost_ms, created_at) VALUES (490, '3c423b33-caf4-483e-917b-a01fe656044f', 'POST', '/api/v1/bi/dashboards/bid_12f57749a8d94933/compose', '127.0.0.1', NULL, 200, 411.51, '2026-11-24 21:59:29.29807');
INSERT INTO public.audit_log (id, request_id, method, path, client_ip, "user", status, cost_ms, created_at) VALUES (491, 'ef557f91-e4b7-430f-9617-8399c4672813', 'POST', '/api/v1/bi/dashboards/bid_12f57749a8d94933/compose', '127.0.0.1', NULL, 200, 404.41, '2026-11-24 21:59:29.88844');
INSERT INTO public.audit_log (id, request_id, method, path, client_ip, "user", status, cost_ms, created_at) VALUES (492, 'fd2fe736-1c02-4793-932f-7c8202607c05', 'POST', '/api/v1/bi/dashboards/bid_12f57749a8d94933/compose', '127.0.0.1', NULL, 200, 411.18, '2026-11-24 21:59:30.481068');
INSERT INTO public.audit_log (id, request_id, method, path, client_ip, "user", status, cost_ms, created_at) VALUES (493, '68307f82-4a52-4ea6-816b-20edaeab2207', 'POST', '/api/v1/bi/dashboards/bid_12f57749a8d94933/compose', '127.0.0.1', NULL, 200, 407.71, '2026-11-24 21:59:31.072804');
INSERT INTO public.audit_log (id, request_id, method, path, client_ip, "user", status, cost_ms, created_at) VALUES (494, '84c5247a-d868-48e8-bcd0-dbf9cbf77352', 'POST', '/api/v1/bi/dashboards/bid_12f57749a8d94933/compose', '127.0.0.1', NULL, 200, 410.47, '2026-11-24 21:59:31.666803');
INSERT INTO public.audit_log (id, request_id, method, path, client_ip, "user", status, cost_ms, created_at) VALUES (495, '97f8ed84-61a8-47de-adf9-64eab983a243', 'POST', '/api/v1/bi/dashboards/bid_12f57749a8d94933/compose', '127.0.0.1', NULL, 200, 408.14, '2026-11-24 21:59:32.258348');
INSERT INTO public.audit_log (id, request_id, method, path, client_ip, "user", status, cost_ms, created_at) VALUES (496, '06d9f5c2-8c1e-489b-9979-e8c3c3a0b232', 'POST', '/api/v1/bi/dashboards/bid_12f57749a8d94933/compose', '127.0.0.1', NULL, 429, 359.36, '2026-11-24 21:59:32.804733');
INSERT INTO public.audit_log (id, request_id, method, path, client_ip, "user", status, cost_ms, created_at) VALUES (497, '2caa5619-f9c4-4774-b29f-8bf878fdbaac', 'POST', '/api/v1/bi/dashboards', '127.0.0.1', NULL, 201, 503.22, '2026-11-24 21:59:45.703318');
INSERT INTO public.audit_log (id, request_id, method, path, client_ip, "user", status, cost_ms, created_at) VALUES (498, '725adbe3-9c4f-4a6c-bed1-d30c0cd28fd7', 'POST', '/api/v1/bi/dashboards/bid_c618841866b644bc/compose', '127.0.0.1', NULL, 200, 408.01, '2026-11-24 21:59:46.294754');
INSERT INTO public.audit_log (id, request_id, method, path, client_ip, "user", status, cost_ms, created_at) VALUES (499, 'caba2054-dad3-4b07-ad71-2287b65464dc', 'POST', '/api/v1/bi/dashboards/bid_c618841866b644bc/compose', '127.0.0.1', NULL, 200, 414.11, '2026-11-24 21:59:46.893402');
INSERT INTO public.audit_log (id, request_id, method, path, client_ip, "user", status, cost_ms, created_at) VALUES (500, '29342726-8bfc-4ec3-864d-e698f2b99852', 'POST', '/api/v1/bi/dashboards/bid_c618841866b644bc/compose', '127.0.0.1', NULL, 429, 373.08, '2026-11-24 21:59:47.449556');
INSERT INTO public.audit_log (id, request_id, method, path, client_ip, "user", status, cost_ms, created_at) VALUES (501, '077a5930-1960-4f30-9a10-99efdac7a048', 'POST', '/api/v1/bi/dashboards/bid_not_exist/compose', '127.0.0.1', NULL, 429, 366.46, '2026-11-24 21:59:47.999032');
INSERT INTO public.audit_log (id, request_id, method, path, client_ip, "user", status, cost_ms, created_at) VALUES (502, 'a2e51679-7845-4e6f-ba4c-c3bb7336e32d', 'POST', '/api/v1/bi/dashboards/bid_c618841866b644bc/compose', '127.0.0.1', NULL, 429, 373.93, '2026-11-24 21:59:48.567067');
INSERT INTO public.audit_log (id, request_id, method, path, client_ip, "user", status, cost_ms, created_at) VALUES (503, '466a36a7-ce9c-4703-9fae-5769eb21cfd0', 'POST', '/api/v1/bi/dashboards/bid_c618841866b644bc/compose', '127.0.0.1', NULL, 429, 375.92, '2026-11-24 21:59:49.125849');
INSERT INTO public.audit_log (id, request_id, method, path, client_ip, "user", status, cost_ms, created_at) VALUES (504, 'b54dab3b-d736-4cf3-b9a6-6bfd175162d1', 'POST', '/api/v1/bi/dashboards/bid_c618841866b644bc/compose', '127.0.0.1', NULL, 429, 371.23, '2026-11-24 21:59:49.67982');
INSERT INTO public.audit_log (id, request_id, method, path, client_ip, "user", status, cost_ms, created_at) VALUES (505, 'e8cf01d6-fb4b-41ae-b76f-394d8c3429ed', 'POST', '/api/v1/bi/dashboards/bid_c618841866b644bc/preview', '127.0.0.1', NULL, 200, 411.5, '2026-11-24 21:59:51.309332');
INSERT INTO public.audit_log (id, request_id, method, path, client_ip, "user", status, cost_ms, created_at) VALUES (506, '42a89b47-f709-4816-adbb-80bb42f5a24d', 'POST', '/api/v1/bi/dashboards/bid_c618841866b644bc/preview', '127.0.0.1', NULL, 422, 412.1, '2026-11-24 21:59:52.356355');
INSERT INTO public.audit_log (id, request_id, method, path, client_ip, "user", status, cost_ms, created_at) VALUES (507, '1abbd0a7-e94f-4fdd-b18f-0b10c7e6e41d', 'POST', '/api/v1/bi/dashboards/bid_c618841866b644bc/preview', '127.0.0.1', NULL, 422, 409.82, '2026-11-24 21:59:52.950852');
INSERT INTO public.audit_log (id, request_id, method, path, client_ip, "user", status, cost_ms, created_at) VALUES (508, '2133d489-aa93-41ba-b249-e228ef928011', 'POST', '/api/v1/bi/dashboards', '127.0.0.1', NULL, 201, 574.17, '2026-11-24 21:59:53.724799');
INSERT INTO public.audit_log (id, request_id, method, path, client_ip, "user", status, cost_ms, created_at) VALUES (509, 'ac548847-b7a0-4aab-b432-ab531b72186c', 'POST', '/api/v1/bi/dashboards/bid_5fe095aa598f437c/preview', '127.0.0.1', NULL, 403, 499.44, '2026-11-24 21:59:54.409085');
INSERT INTO public.audit_log (id, request_id, method, path, client_ip, "user", status, cost_ms, created_at) VALUES (510, 'd5a4bcd6-d484-4c46-a84d-735032e049d0', 'POST', '/api/v1/bi/dashboards/bid_5fe095aa598f437c/compose', '127.0.0.1', NULL, 429, 380.13, '2026-11-24 21:59:54.974446');
INSERT INTO public.audit_log (id, request_id, method, path, client_ip, "user", status, cost_ms, created_at) VALUES (511, '8e3ea2c4-d3f4-454c-a3e7-2cd9d9223930', 'POST', '/api/v1/bi/dashboards/bid_5fe095aa598f437c/preview', '127.0.0.1', NULL, 200, 410.84, '2026-11-24 21:59:55.569536');
INSERT INTO public.audit_log (id, request_id, method, path, client_ip, "user", status, cost_ms, created_at) VALUES (512, 'f19ebf3e-738d-4f0c-84d5-abd677864de5', 'POST', '/api/v1/bi/describe', '127.0.0.1', NULL, 200, 371.1, '2026-11-24 21:59:56.124874');
INSERT INTO public.audit_log (id, request_id, method, path, client_ip, "user", status, cost_ms, created_at) VALUES (513, 'c1962d88-f8f6-40f0-98ea-0ee62b1df5ee', 'POST', '/api/v1/bi/describe', '127.0.0.1', NULL, 200, 372.07, '2026-11-24 21:59:56.682411');
INSERT INTO public.audit_log (id, request_id, method, path, client_ip, "user", status, cost_ms, created_at) VALUES (514, 'bfb7547e-2bf3-4786-b207-49f23b53a26d', 'POST', '/api/v1/bi/describe', '127.0.0.1', NULL, 200, 368.63, '2026-11-24 21:59:57.23422');
INSERT INTO public.audit_log (id, request_id, method, path, client_ip, "user", status, cost_ms, created_at) VALUES (515, 'beaf027f-169f-4e6c-ba2a-dccd50146b22', 'POST', '/api/v1/bi/describe', '127.0.0.1', NULL, 200, 363.84, '2026-11-24 21:59:57.783426');
INSERT INTO public.audit_log (id, request_id, method, path, client_ip, "user", status, cost_ms, created_at) VALUES (516, '500b0d36-8543-454d-9fd6-09c622605bdf', 'POST', '/api/v1/bi/describe', '127.0.0.1', NULL, 429, 370.31, '2026-11-24 21:59:58.336215');
INSERT INTO public.audit_log (id, request_id, method, path, client_ip, "user", status, cost_ms, created_at) VALUES (517, '9736ca0f-382e-40c5-bcf8-f234b3f8286c', 'POST', '/api/v1/bi/describe', '127.0.0.1', NULL, 429, 407.86, '2026-11-24 21:59:58.927855');
INSERT INTO public.audit_log (id, request_id, method, path, client_ip, "user", status, cost_ms, created_at) VALUES (518, '1e490e67-df4c-4704-961f-51c560109a63', 'POST', '/api/v1/bi/dashboards/bid_c618841866b644bc/compose', '127.0.0.1', NULL, 200, 408.99, '2026-11-24 22:00:00.558724');
INSERT INTO public.audit_log (id, request_id, method, path, client_ip, "user", status, cost_ms, created_at) VALUES (519, '24039962-7b1d-4325-9dfa-1ee1daa741d7', 'POST', '/api/v1/bi/dashboards/bid_c618841866b644bc/compose', '127.0.0.1', NULL, 200, 404.34, '2026-11-24 22:00:01.159142');
INSERT INTO public.audit_log (id, request_id, method, path, client_ip, "user", status, cost_ms, created_at) VALUES (520, '04be9b2b-2fcc-4ea0-8b25-ac95933c0b0c', 'POST', '/api/v1/bi/dashboards/bid_c618841866b644bc/compose', '127.0.0.1', NULL, 200, 410.03, '2026-11-24 22:00:01.759851');
INSERT INTO public.audit_log (id, request_id, method, path, client_ip, "user", status, cost_ms, created_at) VALUES (521, '362fbf42-9535-431b-8cfd-abba70c5278c', 'POST', '/api/v1/bi/dashboards/bid_c618841866b644bc/compose', '127.0.0.1', NULL, 200, 405.95, '2026-11-24 22:00:02.348325');
INSERT INTO public.audit_log (id, request_id, method, path, client_ip, "user", status, cost_ms, created_at) VALUES (522, '9321ce2e-a3b6-47eb-b357-d4b1beb88ad5', 'POST', '/api/v1/bi/dashboards/bid_c618841866b644bc/compose', '127.0.0.1', NULL, 200, 408.85, '2026-11-24 22:00:02.940132');
INSERT INTO public.audit_log (id, request_id, method, path, client_ip, "user", status, cost_ms, created_at) VALUES (523, 'c0142503-51fa-47b9-9f27-5c1b63e8b450', 'POST', '/api/v1/bi/dashboards/bid_c618841866b644bc/compose', '127.0.0.1', NULL, 200, 404.5, '2026-11-24 22:00:03.529096');
INSERT INTO public.audit_log (id, request_id, method, path, client_ip, "user", status, cost_ms, created_at) VALUES (524, '606e6731-a814-40c2-80be-1920319e02c3', 'POST', '/api/v1/bi/dashboards/bid_c618841866b644bc/compose', '127.0.0.1', NULL, 200, 421.07, '2026-11-24 22:00:04.133822');
INSERT INTO public.audit_log (id, request_id, method, path, client_ip, "user", status, cost_ms, created_at) VALUES (525, '88fd673a-8f79-49bc-8e54-765d172e955d', 'POST', '/api/v1/bi/dashboards/bid_c618841866b644bc/compose', '127.0.0.1', NULL, 200, 411.29, '2026-11-24 22:00:04.758822');
INSERT INTO public.audit_log (id, request_id, method, path, client_ip, "user", status, cost_ms, created_at) VALUES (526, 'ebb931f3-56a7-4dfe-8f4c-47fad1df3009', 'POST', '/api/v1/bi/dashboards/bid_c618841866b644bc/compose', '127.0.0.1', NULL, 200, 405.4, '2026-11-24 22:00:05.344786');
INSERT INTO public.audit_log (id, request_id, method, path, client_ip, "user", status, cost_ms, created_at) VALUES (527, 'b2c60bb6-42b3-43a8-91fd-9deb51b4fb7f', 'POST', '/api/v1/bi/dashboards/bid_c618841866b644bc/compose', '127.0.0.1', NULL, 200, 408.78, '2026-11-24 22:00:05.937297');
INSERT INTO public.audit_log (id, request_id, method, path, client_ip, "user", status, cost_ms, created_at) VALUES (528, '805cfbc8-571b-4072-a16d-c58dc43c8c32', 'POST', '/api/v1/bi/dashboards/bid_c618841866b644bc/compose', '127.0.0.1', NULL, 429, 358.71, '2026-11-24 22:00:06.478862');
INSERT INTO public.audit_log (id, request_id, method, path, client_ip, "user", status, cost_ms, created_at) VALUES (529, 'c8c4e19a-4621-44f7-98e8-c17cffcf2e47', 'POST', '/api/v1/bi/dashboards', '127.0.0.1', NULL, 201, 506.5, '2026-11-24 22:00:18.524028');
INSERT INTO public.audit_log (id, request_id, method, path, client_ip, "user", status, cost_ms, created_at) VALUES (530, 'b293588b-91d4-44c3-b227-ebdbfdac2875', 'POST', '/api/v1/bi/dashboards/bid_18c77ba4df964ba5/compose', '127.0.0.1', NULL, 200, 415.32, '2026-11-24 22:00:19.12844');
INSERT INTO public.audit_log (id, request_id, method, path, client_ip, "user", status, cost_ms, created_at) VALUES (531, '39abbcb5-c496-4762-9e80-039df923c945', 'POST', '/api/v1/bi/dashboards/bid_18c77ba4df964ba5/compose', '127.0.0.1', NULL, 200, 425.28, '2026-11-24 22:00:19.736459');
INSERT INTO public.audit_log (id, request_id, method, path, client_ip, "user", status, cost_ms, created_at) VALUES (532, 'f6621a69-d568-4758-8555-1eba3457035a', 'POST', '/api/v1/bi/dashboards/bid_18c77ba4df964ba5/compose', '127.0.0.1', NULL, 422, 412.73, '2026-11-24 22:00:20.335259');
INSERT INTO public.audit_log (id, request_id, method, path, client_ip, "user", status, cost_ms, created_at) VALUES (533, 'ff5fb0c3-13f5-4dcc-b107-d4e20c224f33', 'POST', '/api/v1/bi/dashboards/bid_not_exist/compose', '127.0.0.1', NULL, 404, 404.43, '2026-11-24 22:00:20.922947');
INSERT INTO public.audit_log (id, request_id, method, path, client_ip, "user", status, cost_ms, created_at) VALUES (534, '26e6c01a-c34e-433f-aa10-56915edd34f8', 'POST', '/api/v1/bi/dashboards/bid_18c77ba4df964ba5/compose', '127.0.0.1', NULL, 200, 426.19, '2026-11-24 22:00:21.533837');
INSERT INTO public.audit_log (id, request_id, method, path, client_ip, "user", status, cost_ms, created_at) VALUES (535, '96a084c5-d62a-438b-9077-091f893ac016', 'POST', '/api/v1/bi/dashboards/bid_18c77ba4df964ba5/compose', '127.0.0.1', NULL, 200, 410.73, '2026-11-24 22:00:22.129022');
INSERT INTO public.audit_log (id, request_id, method, path, client_ip, "user", status, cost_ms, created_at) VALUES (536, '844b3def-dcf6-49e1-9c74-03e88d972ad7', 'POST', '/api/v1/bi/dashboards/bid_18c77ba4df964ba5/compose', '127.0.0.1', NULL, 422, 408.85, '2026-11-24 22:00:22.719488');
INSERT INTO public.audit_log (id, request_id, method, path, client_ip, "user", status, cost_ms, created_at) VALUES (537, '2df3f9cc-c774-4d41-999b-796e604aa587', 'POST', '/api/v1/bi/dashboards/bid_18c77ba4df964ba5/preview', '127.0.0.1', NULL, 200, 416.79, '2026-11-24 22:00:24.421734');
INSERT INTO public.audit_log (id, request_id, method, path, client_ip, "user", status, cost_ms, created_at) VALUES (538, 'e4999142-b496-4602-a3cd-475ef988a370', 'POST', '/api/v1/bi/dashboards/bid_18c77ba4df964ba5/preview', '127.0.0.1', NULL, 422, 409.67, '2026-11-24 22:00:25.511502');
INSERT INTO public.audit_log (id, request_id, method, path, client_ip, "user", status, cost_ms, created_at) VALUES (539, '2bb9f6ce-a00e-4682-969c-f5e05eb949d2', 'POST', '/api/v1/bi/dashboards/bid_18c77ba4df964ba5/preview', '127.0.0.1', NULL, 422, 406.14, '2026-11-24 22:00:26.099435');
INSERT INTO public.audit_log (id, request_id, method, path, client_ip, "user", status, cost_ms, created_at) VALUES (540, '19da013a-7d69-4c49-b042-3d600e52699d', 'POST', '/api/v1/bi/dashboards', '127.0.0.1', NULL, 201, 552.45, '2026-11-24 22:00:26.835664');
INSERT INTO public.audit_log (id, request_id, method, path, client_ip, "user", status, cost_ms, created_at) VALUES (541, '28764e5c-4017-44b6-8397-142b2f868c3b', 'POST', '/api/v1/bi/dashboards/bid_3b03d2f0d94a4722/preview', '127.0.0.1', NULL, 403, 509.43, '2026-11-24 22:00:27.528909');
INSERT INTO public.audit_log (id, request_id, method, path, client_ip, "user", status, cost_ms, created_at) VALUES (542, 'b44b5235-443c-4a90-ae35-3d52a8970a11', 'POST', '/api/v1/bi/dashboards/bid_3b03d2f0d94a4722/compose', '127.0.0.1', NULL, 200, 422.94, '2026-11-24 22:00:28.137475');
INSERT INTO public.audit_log (id, request_id, method, path, client_ip, "user", status, cost_ms, created_at) VALUES (543, 'dfaffc6a-b07d-4aae-9333-476690856a84', 'POST', '/api/v1/bi/dashboards/bid_3b03d2f0d94a4722/preview', '127.0.0.1', NULL, 200, 414.15, '2026-11-24 22:00:28.739657');
INSERT INTO public.audit_log (id, request_id, method, path, client_ip, "user", status, cost_ms, created_at) VALUES (544, 'de1043c6-e107-47c1-8d4a-8b2edb3d7464', 'POST', '/api/v1/bi/describe', '127.0.0.1', NULL, 200, 367.54, '2026-11-24 22:00:29.290547');
INSERT INTO public.audit_log (id, request_id, method, path, client_ip, "user", status, cost_ms, created_at) VALUES (545, 'e0e7521a-218c-409b-9959-839d5d8ae9ba', 'POST', '/api/v1/bi/describe', '127.0.0.1', NULL, 200, 393.75, '2026-11-24 22:00:29.865273');
INSERT INTO public.audit_log (id, request_id, method, path, client_ip, "user", status, cost_ms, created_at) VALUES (546, '7371d53d-5784-4e09-a647-f1e33808b736', 'POST', '/api/v1/bi/describe', '127.0.0.1', NULL, 200, 360.83, '2026-11-24 22:00:30.407575');
INSERT INTO public.audit_log (id, request_id, method, path, client_ip, "user", status, cost_ms, created_at) VALUES (547, '8e902394-669c-4d33-8831-aab227be6963', 'POST', '/api/v1/bi/describe', '127.0.0.1', NULL, 200, 367.25, '2026-11-24 22:00:30.961293');
INSERT INTO public.audit_log (id, request_id, method, path, client_ip, "user", status, cost_ms, created_at) VALUES (548, '463d9a95-58c5-4d43-875d-00726948e950', 'POST', '/api/v1/bi/describe', '127.0.0.1', NULL, 422, 360.1, '2026-11-24 22:00:31.509713');
INSERT INTO public.audit_log (id, request_id, method, path, client_ip, "user", status, cost_ms, created_at) VALUES (549, '55c712f2-dc7c-42e3-afba-c50f945dc13f', 'POST', '/api/v1/bi/describe', '127.0.0.1', NULL, 200, 363.79, '2026-11-24 22:00:32.057709');
INSERT INTO public.audit_log (id, request_id, method, path, client_ip, "user", status, cost_ms, created_at) VALUES (550, 'df0b3a48-b34b-4b8c-822c-073a7d3f59f8', 'POST', '/api/v1/bi/dashboards/bid_18c77ba4df964ba5/compose', '127.0.0.1', NULL, 200, 405.79, '2026-11-24 22:00:33.195854');
INSERT INTO public.audit_log (id, request_id, method, path, client_ip, "user", status, cost_ms, created_at) VALUES (551, '1dc55b8a-de70-45f2-a47e-35adc2cbba2b', 'POST', '/api/v1/bi/dashboards/bid_18c77ba4df964ba5/compose', '127.0.0.1', NULL, 200, 409.53, '2026-11-24 22:00:33.788699');
INSERT INTO public.audit_log (id, request_id, method, path, client_ip, "user", status, cost_ms, created_at) VALUES (552, '506b6401-8356-4f51-8424-2e0f766fd622', 'POST', '/api/v1/bi/dashboards/bid_18c77ba4df964ba5/compose', '127.0.0.1', NULL, 200, 425.64, '2026-11-24 22:00:34.397131');
INSERT INTO public.audit_log (id, request_id, method, path, client_ip, "user", status, cost_ms, created_at) VALUES (553, 'd393d0dd-128d-4038-a4fc-113035726c26', 'POST', '/api/v1/bi/dashboards/bid_18c77ba4df964ba5/compose', '127.0.0.1', NULL, 200, 418.16, '2026-11-24 22:00:35.021687');
INSERT INTO public.audit_log (id, request_id, method, path, client_ip, "user", status, cost_ms, created_at) VALUES (554, 'bb68bac5-e54f-4dac-942e-53d7f5d4f332', 'POST', '/api/v1/bi/dashboards/bid_18c77ba4df964ba5/compose', '127.0.0.1', NULL, 200, 425.36, '2026-11-24 22:00:35.666319');
INSERT INTO public.audit_log (id, request_id, method, path, client_ip, "user", status, cost_ms, created_at) VALUES (555, 'aed75865-cb28-4529-9647-355aa48f452c', 'POST', '/api/v1/bi/dashboards/bid_18c77ba4df964ba5/compose', '127.0.0.1', NULL, 200, 412.47, '2026-11-24 22:00:36.259989');
INSERT INTO public.audit_log (id, request_id, method, path, client_ip, "user", status, cost_ms, created_at) VALUES (556, '0dabf14c-6c59-4b01-9d2e-fbcd3b5bfe41', 'POST', '/api/v1/bi/dashboards/bid_18c77ba4df964ba5/compose', '127.0.0.1', NULL, 200, 408.79, '2026-11-24 22:00:36.858972');
INSERT INTO public.audit_log (id, request_id, method, path, client_ip, "user", status, cost_ms, created_at) VALUES (557, '808bc301-9e07-47a7-b269-24ad4f000179', 'POST', '/api/v1/bi/dashboards/bid_18c77ba4df964ba5/compose', '127.0.0.1', NULL, 200, 415.66, '2026-11-24 22:00:37.458515');
INSERT INTO public.audit_log (id, request_id, method, path, client_ip, "user", status, cost_ms, created_at) VALUES (558, '6c0fa399-0c8e-46cd-9823-abe5d4fcff61', 'POST', '/api/v1/bi/dashboards/bid_18c77ba4df964ba5/compose', '127.0.0.1', NULL, 200, 447.02, '2026-11-24 22:00:38.087959');
INSERT INTO public.audit_log (id, request_id, method, path, client_ip, "user", status, cost_ms, created_at) VALUES (559, '83051c01-2689-4ee9-9ae7-f9efa1908187', 'POST', '/api/v1/bi/dashboards/bid_18c77ba4df964ba5/compose', '127.0.0.1', NULL, 200, 402.07, '2026-11-24 22:00:38.672734');
INSERT INTO public.audit_log (id, request_id, method, path, client_ip, "user", status, cost_ms, created_at) VALUES (560, '4ae8d195-6380-46c2-9762-5c8510cc7f1c', 'POST', '/api/v1/bi/dashboards/bid_18c77ba4df964ba5/compose', '127.0.0.1', NULL, 429, 360.99, '2026-11-24 22:00:39.217039');
INSERT INTO public.audit_log (id, request_id, method, path, client_ip, "user", status, cost_ms, created_at) VALUES (561, '91032eba-e855-4980-bdc9-35dfa2500335', 'POST', '/api/v1/bi/dashboards', '127.0.0.1', NULL, 201, 517.09, '2026-11-24 22:02:13.463263');
INSERT INTO public.audit_log (id, request_id, method, path, client_ip, "user", status, cost_ms, created_at) VALUES (562, 'c602cc58-b0b5-41ee-8828-d53bcfb3d820', 'PUT', '/api/v1/bi/dashboards/bid_39fa6d838b9b49d0/draft', '127.0.0.1', NULL, 200, 611.65, '2026-11-24 22:02:14.253841');
INSERT INTO public.audit_log (id, request_id, method, path, client_ip, "user", status, cost_ms, created_at) VALUES (563, '7c770b8a-c9d9-44ae-aa12-aeb9d92317ff', 'POST', '/api/v1/bi/dashboards/bid_39fa6d838b9b49d0/preview', '127.0.0.1', NULL, 200, 380.69, '2026-11-24 22:05:07.70341');
INSERT INTO public.audit_log (id, request_id, method, path, client_ip, "user", status, cost_ms, created_at) VALUES (564, '15a8de75-2a12-45ea-a2e9-f3b272eae174', 'POST', '/api/v1/bi/dashboards/bid_39fa6d838b9b49d0/preview', '127.0.0.1', NULL, 200, 413.31, '2026-11-24 22:05:22.132762');
INSERT INTO public.audit_log (id, request_id, method, path, client_ip, "user", status, cost_ms, created_at) VALUES (565, 'e5e79365-8bd4-42d6-8f81-15c2ad3e438f', 'POST', '/api/v1/bi/describe', '127.0.0.1', NULL, 200, 337.34, '2026-11-24 22:05:22.752313');
INSERT INTO public.audit_log (id, request_id, method, path, client_ip, "user", status, cost_ms, created_at) VALUES (566, 'd82a2c93-92f3-459d-8851-ae1211044b9d', 'POST', '/api/v1/auth/register', 'testclient', NULL, 503, 2.98, '2026-11-24 22:07:19.153485');
INSERT INTO public.audit_log (id, request_id, method, path, client_ip, "user", status, cost_ms, created_at) VALUES (567, '820e974c-662a-4be6-bfc3-9503d36928b0', 'POST', '/api/v1/auth/login', '127.0.0.1', NULL, 401, 433.15, '2026-11-24 22:08:15.432071');
INSERT INTO public.audit_log (id, request_id, method, path, client_ip, "user", status, cost_ms, created_at) VALUES (568, 'c6a327f5-b02f-433f-a7bf-b795d1d206b8', 'POST', '/api/v1/auth/register', 'testclient', NULL, 503, 3.49, '2026-11-24 22:10:08.334469');
INSERT INTO public.audit_log (id, request_id, method, path, client_ip, "user", status, cost_ms, created_at) VALUES (569, '86982491-a6c3-4f0c-8da4-55a9272677e6', 'POST', '/api/v1/bi/dashboards', 'testclient', NULL, 201, 392.46, '2026-11-24 22:12:21.688952');
INSERT INTO public.audit_log (id, request_id, method, path, client_ip, "user", status, cost_ms, created_at) VALUES (570, '0145c03c-8696-4b50-b01b-6f9157abbaf0', 'POST', '/api/v1/bi/dashboards/bid_402a75bd798243d4/compose', 'testclient', NULL, 200, 222.58, '2026-11-24 22:12:22.083079');
INSERT INTO public.audit_log (id, request_id, method, path, client_ip, "user", status, cost_ms, created_at) VALUES (571, '6b51c1f4-e9ad-4ca5-8c97-fb8006986f69', 'POST', '/api/v1/bi/dashboards', 'testclient', NULL, 201, 317.43, '2026-11-24 22:12:22.884693');
INSERT INTO public.audit_log (id, request_id, method, path, client_ip, "user", status, cost_ms, created_at) VALUES (572, '9fb1f31d-545a-4890-976b-e809e3e22b61', 'POST', '/api/v1/bi/dashboards/bid_76a9129d4b874de9/compose', 'testclient', NULL, 422, 207.92, '2026-11-24 22:12:23.257145');
INSERT INTO public.audit_log (id, request_id, method, path, client_ip, "user", status, cost_ms, created_at) VALUES (573, 'a686bbda-70d5-4508-9917-16d9a7ac784b', 'POST', '/api/v1/bi/dashboards', 'testclient', NULL, 201, 295.32, '2026-11-24 22:12:24.000736');
INSERT INTO public.audit_log (id, request_id, method, path, client_ip, "user", status, cost_ms, created_at) VALUES (574, 'efc90a9a-0f27-4157-87a6-e3a2a81f54c7', 'POST', '/api/v1/bi/dashboards/bid_9c7d88fe4edf4aae/compose', 'testclient', NULL, 200, 210.08, '2026-11-24 22:12:24.378527');
INSERT INTO public.audit_log (id, request_id, method, path, client_ip, "user", status, cost_ms, created_at) VALUES (575, 'eba5a03d-aafb-4e73-9e04-4bc0ef202d69', 'POST', '/api/v1/bi/dashboards', 'testclient', NULL, 201, 304.85, '2026-11-24 22:12:25.130747');
INSERT INTO public.audit_log (id, request_id, method, path, client_ip, "user", status, cost_ms, created_at) VALUES (576, '9b3b131f-874a-4a04-9625-6a13fc443d56', 'POST', '/api/v1/bi/dashboards/bid_6d8b4541bc314f68/preview', 'testclient', NULL, 200, 218.68, '2026-11-24 22:12:26.004338');
INSERT INTO public.audit_log (id, request_id, method, path, client_ip, "user", status, cost_ms, created_at) VALUES (577, 'ca048856-fa20-43ef-94d7-6d672ba6f4e4', 'POST', '/api/v1/bi/dashboards', 'testclient', NULL, 201, 296.61, '2026-11-24 22:12:26.982257');
INSERT INTO public.audit_log (id, request_id, method, path, client_ip, "user", status, cost_ms, created_at) VALUES (578, 'd6ac32ff-f459-4d6c-89df-41a076ef1995', 'POST', '/api/v1/bi/dashboards/bid_68e919bc64cb4bb4/preview', 'testclient', NULL, 422, 209.67, '2026-11-24 22:12:27.363425');
INSERT INTO public.audit_log (id, request_id, method, path, client_ip, "user", status, cost_ms, created_at) VALUES (579, 'a4ae58b7-2224-4375-912c-bd29c9e0a53b', 'POST', '/api/v1/bi/describe', 'testclient', NULL, 200, 54.65, '2026-11-24 22:12:28.252037');
INSERT INTO public.audit_log (id, request_id, method, path, client_ip, "user", status, cost_ms, created_at) VALUES (580, 'ef2d693f-80d4-481b-9b3f-c3faa8b3d27e', 'POST', '/api/v1/bi/describe', 'testclient', NULL, 200, 48.65, '2026-11-24 22:12:28.468078');
INSERT INTO public.audit_log (id, request_id, method, path, client_ip, "user", status, cost_ms, created_at) VALUES (581, '09faa4a4-851c-4ad0-a885-b67c8b77d190', 'POST', '/api/v1/bi/describe', 'testclient', NULL, 200, 49.69, '2026-11-24 22:12:28.686883');
INSERT INTO public.audit_log (id, request_id, method, path, client_ip, "user", status, cost_ms, created_at) VALUES (582, '6e5e90c2-b964-4b61-9dde-200d55ce3d54', 'POST', '/api/v1/bi/describe', 'testclient', NULL, 422, 48.38, '2026-11-24 22:12:28.903737');
INSERT INTO public.audit_log (id, request_id, method, path, client_ip, "user", status, cost_ms, created_at) VALUES (583, 'ac29ac0d-7dc2-415c-9b34-aeb93700a2a9', 'POST', '/api/v1/bi/dashboards', 'testclient', NULL, 201, 291.7, '2026-11-24 22:12:29.368965');
INSERT INTO public.audit_log (id, request_id, method, path, client_ip, "user", status, cost_ms, created_at) VALUES (584, '9ac6065b-c8be-4fbf-a8f2-30a573871bb7', 'PUT', '/api/v1/bi/dashboards/bid_b1296c03c60d43fb/draft', 'testclient', NULL, 200, 382.77, '2026-11-24 22:12:29.921109');
INSERT INTO public.audit_log (id, request_id, method, path, client_ip, "user", status, cost_ms, created_at) VALUES (585, 'ce5bd55b-6970-4587-816c-186bc0a34d9a', 'POST', '/api/v1/bi/dashboards', 'testclient', NULL, 201, 295.12, '2026-11-24 22:12:31.266537');
INSERT INTO public.audit_log (id, request_id, method, path, client_ip, "user", status, cost_ms, created_at) VALUES (586, 'cdb67e3a-4bbf-49fe-8017-28b437458670', 'PUT', '/api/v1/bi/dashboards/bid_bce6f96d5a6b4229/draft', 'testclient', NULL, 200, 374.61, '2026-11-24 22:12:31.809661');
INSERT INTO public.audit_log (id, request_id, method, path, client_ip, "user", status, cost_ms, created_at) VALUES (587, '359da0dd-a952-4a68-ae36-c0942a15e7ac', 'PUT', '/api/v1/bi/dashboards/bid_bce6f96d5a6b4229/draft', 'testclient', NULL, 429, 91.91, '2026-11-24 22:12:32.068691');
INSERT INTO public.audit_log (id, request_id, method, path, client_ip, "user", status, cost_ms, created_at) VALUES (588, 'db583840-8236-413d-9727-5a1a80a1ea73', 'POST', '/api/v1/bi/dashboards', 'testclient', NULL, 201, 294.37, '2026-11-24 22:12:33.626659');
INSERT INTO public.audit_log (id, request_id, method, path, client_ip, "user", status, cost_ms, created_at) VALUES (589, '5bcf92e1-cc8e-4c06-b33b-f5ffab6223cb', 'POST', '/api/v1/bi/dashboards/bid_710c49ea413843d3/compose', 'testclient', NULL, 200, 212.68, '2026-11-24 22:12:34.009159');
INSERT INTO public.audit_log (id, request_id, method, path, client_ip, "user", status, cost_ms, created_at) VALUES (590, '40c2dd38-0ed0-4f64-8d26-eb2824b57733', 'POST', '/api/v1/bi/dashboards/bid_710c49ea413843d3/compose', 'testclient', NULL, 200, 212.46, '2026-11-24 22:12:34.389812');
INSERT INTO public.audit_log (id, request_id, method, path, client_ip, "user", status, cost_ms, created_at) VALUES (591, 'a5eb5580-7bc6-4d50-93a8-7f96e1b8255d', 'POST', '/api/v1/bi/dashboards/bid_710c49ea413843d3/compose', 'testclient', NULL, 200, 210.85, '2026-11-24 22:12:34.771063');
INSERT INTO public.audit_log (id, request_id, method, path, client_ip, "user", status, cost_ms, created_at) VALUES (592, 'c2f94c8a-b18f-4c03-90e4-11d7fd1b54e8', 'POST', '/api/v1/bi/dashboards/bid_710c49ea413843d3/compose', 'testclient', NULL, 200, 222.65, '2026-11-24 22:12:35.162299');
INSERT INTO public.audit_log (id, request_id, method, path, client_ip, "user", status, cost_ms, created_at) VALUES (593, 'ff6b2a45-ab62-4b04-b296-1025ab616ece', 'POST', '/api/v1/bi/dashboards/bid_710c49ea413843d3/compose', 'testclient', NULL, 200, 214.7, '2026-11-24 22:12:35.547438');
INSERT INTO public.audit_log (id, request_id, method, path, client_ip, "user", status, cost_ms, created_at) VALUES (594, 'edc460e9-f9f2-4bdf-a37c-5d0eba33b986', 'POST', '/api/v1/bi/dashboards/bid_710c49ea413843d3/compose', 'testclient', NULL, 200, 210.05, '2026-11-24 22:12:35.924418');
INSERT INTO public.audit_log (id, request_id, method, path, client_ip, "user", status, cost_ms, created_at) VALUES (595, 'd8ab3ef0-de3c-4934-ab53-d5e74e8c7e32', 'POST', '/api/v1/bi/dashboards/bid_710c49ea413843d3/compose', 'testclient', NULL, 200, 209.48, '2026-11-24 22:12:36.300677');
INSERT INTO public.audit_log (id, request_id, method, path, client_ip, "user", status, cost_ms, created_at) VALUES (596, '00a557d2-3231-4ce5-a121-1033dc9fec1a', 'POST', '/api/v1/bi/dashboards/bid_710c49ea413843d3/compose', 'testclient', NULL, 200, 211.03, '2026-11-24 22:12:36.679259');
INSERT INTO public.audit_log (id, request_id, method, path, client_ip, "user", status, cost_ms, created_at) VALUES (597, 'b3e1b63e-5522-42dd-a9e6-6c01194fa19a', 'POST', '/api/v1/bi/dashboards/bid_710c49ea413843d3/compose', 'testclient', NULL, 200, 211.22, '2026-11-24 22:12:37.066965');
INSERT INTO public.audit_log (id, request_id, method, path, client_ip, "user", status, cost_ms, created_at) VALUES (598, 'bf20fe9f-9931-4c6f-a41f-6f02e3542f88', 'POST', '/api/v1/bi/dashboards/bid_710c49ea413843d3/compose', 'testclient', NULL, 200, 209.06, '2026-11-24 22:12:37.444566');
INSERT INTO public.audit_log (id, request_id, method, path, client_ip, "user", status, cost_ms, created_at) VALUES (599, '282fcf65-c7ee-40aa-953b-beee7b9a7120', 'POST', '/api/v1/bi/dashboards/bid_710c49ea413843d3/compose', 'testclient', NULL, 429, 48.08, '2026-11-24 22:12:37.65993');
INSERT INTO public.audit_log (id, request_id, method, path, client_ip, "user", status, cost_ms, created_at) VALUES (600, '72ff9b92-ec42-4416-8403-c9704fbe06c9', 'POST', '/api/v1/bi/dashboards', 'testclient', NULL, 201, 315.09, '2026-11-24 22:12:59.434432');
INSERT INTO public.audit_log (id, request_id, method, path, client_ip, "user", status, cost_ms, created_at) VALUES (601, 'ce605cc4-9fb9-4ea1-8918-e92b417e379f', 'PUT', '/api/v1/bi/dashboards/bid_e60bd2f0835d4c33/draft', 'testclient', NULL, 200, 412.48, '2026-11-24 22:13:00.018559');
INSERT INTO public.audit_log (id, request_id, method, path, client_ip, "user", status, cost_ms, created_at) VALUES (602, '86ced516-53c6-4ca0-893a-951bacde84ae', 'PUT', '/api/v1/bi/dashboards/bid_e60bd2f0835d4c33/draft', 'testclient', NULL, 429, 102.35, '2026-11-24 22:13:00.31272');
INSERT INTO public.audit_log (id, request_id, method, path, client_ip, "user", status, cost_ms, created_at) VALUES (603, '0c4a9da4-0e14-4704-a6a1-dd5f8010ec07', 'POST', '/api/v1/bi/dashboards', 'testclient', NULL, 201, 393.37, '2026-11-24 22:13:31.201998');
INSERT INTO public.audit_log (id, request_id, method, path, client_ip, "user", status, cost_ms, created_at) VALUES (604, 'f5a30185-fe93-41ae-9354-eda50878219f', 'POST', '/api/v1/bi/dashboards/bid_68f30a6915994367/compose', 'testclient', NULL, 200, 238.37, '2026-11-24 22:13:31.627538');
INSERT INTO public.audit_log (id, request_id, method, path, client_ip, "user", status, cost_ms, created_at) VALUES (605, 'dfc0b4f3-d824-4013-9e78-53fd7a2b6d2e', 'POST', '/api/v1/bi/dashboards', 'testclient', NULL, 201, 320.97, '2026-11-24 22:13:32.445322');
INSERT INTO public.audit_log (id, request_id, method, path, client_ip, "user", status, cost_ms, created_at) VALUES (606, '398f9211-8333-4a9a-915a-572cb6c49bc8', 'POST', '/api/v1/bi/dashboards/bid_a168288521c649b8/compose', 'testclient', NULL, 422, 227.62, '2026-11-24 22:13:32.857409');
INSERT INTO public.audit_log (id, request_id, method, path, client_ip, "user", status, cost_ms, created_at) VALUES (607, 'e8d0f75e-cefa-4fb5-ad14-c452e08dce71', 'POST', '/api/v1/bi/dashboards', 'testclient', NULL, 201, 319.33, '2026-11-24 22:13:33.669911');
INSERT INTO public.audit_log (id, request_id, method, path, client_ip, "user", status, cost_ms, created_at) VALUES (608, '788baae0-09a4-4408-ba5e-a8df185fa929', 'POST', '/api/v1/bi/dashboards/bid_9ae4f64e99f048f9/compose', 'testclient', NULL, 200, 228.77, '2026-11-24 22:13:34.082782');
INSERT INTO public.audit_log (id, request_id, method, path, client_ip, "user", status, cost_ms, created_at) VALUES (609, '1e1d78b8-90df-4bde-83d3-90d84268ca71', 'POST', '/api/v1/bi/dashboards', 'testclient', NULL, 201, 317.47, '2026-11-24 22:13:34.890311');
INSERT INTO public.audit_log (id, request_id, method, path, client_ip, "user", status, cost_ms, created_at) VALUES (610, '6da9ae6b-760c-4635-b001-a739839124f2', 'POST', '/api/v1/bi/dashboards/bid_266ff3a2ee8241b3/preview', 'testclient', NULL, 200, 228.78, '2026-11-24 22:13:35.870635');
INSERT INTO public.audit_log (id, request_id, method, path, client_ip, "user", status, cost_ms, created_at) VALUES (611, '890fef4a-729b-4082-9242-83d0709dcf0b', 'POST', '/api/v1/bi/dashboards', 'testclient', NULL, 201, 309.5, '2026-11-24 22:13:36.883452');
INSERT INTO public.audit_log (id, request_id, method, path, client_ip, "user", status, cost_ms, created_at) VALUES (612, '6340d36a-5ef9-425d-a1c3-9c7924fd8f0f', 'POST', '/api/v1/bi/dashboards/bid_9b87d7bf53064323/preview', 'testclient', NULL, 422, 225.61, '2026-11-24 22:13:37.286559');
INSERT INTO public.audit_log (id, request_id, method, path, client_ip, "user", status, cost_ms, created_at) VALUES (613, '331c81d6-2a02-4b97-8321-80dc8ccb8531', 'POST', '/api/v1/bi/describe', 'testclient', NULL, 200, 64.85, '2026-11-24 22:13:37.951634');
INSERT INTO public.audit_log (id, request_id, method, path, client_ip, "user", status, cost_ms, created_at) VALUES (614, 'cb7b542e-7b49-4fe4-9ab2-b2fc36551b85', 'POST', '/api/v1/bi/describe', 'testclient', NULL, 200, 50.57, '2026-11-24 22:13:38.181422');
INSERT INTO public.audit_log (id, request_id, method, path, client_ip, "user", status, cost_ms, created_at) VALUES (615, '70f7063d-56cb-42a7-a424-eca266687d01', 'POST', '/api/v1/bi/describe', 'testclient', NULL, 200, 49.05, '2026-11-24 22:13:38.411022');
INSERT INTO public.audit_log (id, request_id, method, path, client_ip, "user", status, cost_ms, created_at) VALUES (616, '7e10eee8-c2b4-4b82-a18f-ca475c1f3e57', 'POST', '/api/v1/bi/describe', 'testclient', NULL, 422, 50.45, '2026-11-24 22:13:38.637301');
INSERT INTO public.audit_log (id, request_id, method, path, client_ip, "user", status, cost_ms, created_at) VALUES (617, '5c7c2683-555d-4585-b7a7-7e98cdb5d0f3', 'POST', '/api/v1/bi/dashboards', 'testclient', NULL, 201, 301.65, '2026-11-24 22:13:39.123182');
INSERT INTO public.audit_log (id, request_id, method, path, client_ip, "user", status, cost_ms, created_at) VALUES (618, '381da812-73a3-40df-a2d5-d3c46b4ba6e8', 'PUT', '/api/v1/bi/dashboards/bid_b80b207615fd4570/draft', 'testclient', NULL, 200, 397.74, '2026-11-24 22:13:39.704923');
INSERT INTO public.audit_log (id, request_id, method, path, client_ip, "user", status, cost_ms, created_at) VALUES (619, 'fb74614d-e04f-4656-8bb0-7b1325bc313f', 'POST', '/api/v1/bi/dashboards', 'testclient', NULL, 201, 320.8, '2026-11-24 22:13:41.096044');
INSERT INTO public.audit_log (id, request_id, method, path, client_ip, "user", status, cost_ms, created_at) VALUES (620, '0f9bf591-5588-444c-9fc1-bad415d753e3', 'PUT', '/api/v1/bi/dashboards/bid_58e1d4dc63784fa7/draft', 'testclient', NULL, 200, 401.16, '2026-11-24 22:13:41.671769');
INSERT INTO public.audit_log (id, request_id, method, path, client_ip, "user", status, cost_ms, created_at) VALUES (621, 'f6ab1c65-4489-46c2-87dc-3539ef0c318c', 'PUT', '/api/v1/bi/dashboards/bid_58e1d4dc63784fa7/draft', 'testclient', NULL, 200, 93.62, '2026-11-24 22:13:41.945012');
INSERT INTO public.audit_log (id, request_id, method, path, client_ip, "user", status, cost_ms, created_at) VALUES (622, '00e3dbd3-8f7c-4c2f-a952-889c136bc028', 'POST', '/api/v1/bi/dashboards', 'testclient', NULL, 201, 305.25, '2026-11-24 22:13:43.504935');
INSERT INTO public.audit_log (id, request_id, method, path, client_ip, "user", status, cost_ms, created_at) VALUES (623, '4d80a62e-ce1d-48eb-9970-6a8b60b1bf34', 'POST', '/api/v1/bi/dashboards/bid_baebc447b40748d7/compose', 'testclient', NULL, 200, 220.62, '2026-11-24 22:13:43.909655');
INSERT INTO public.audit_log (id, request_id, method, path, client_ip, "user", status, cost_ms, created_at) VALUES (624, '945a8fa6-a7da-4301-91e5-623cb5c6ca4a', 'POST', '/api/v1/bi/dashboards/bid_baebc447b40748d7/compose', 'testclient', NULL, 200, 218.79, '2026-11-24 22:13:44.312349');
INSERT INTO public.audit_log (id, request_id, method, path, client_ip, "user", status, cost_ms, created_at) VALUES (625, '3acf44ca-59f3-4420-978e-e1271869d8e9', 'POST', '/api/v1/bi/dashboards/bid_baebc447b40748d7/compose', 'testclient', NULL, 200, 219.26, '2026-11-24 22:13:44.714934');
INSERT INTO public.audit_log (id, request_id, method, path, client_ip, "user", status, cost_ms, created_at) VALUES (626, 'ff9e6549-00d0-46c8-8267-5ade6b7d6eae', 'POST', '/api/v1/bi/dashboards/bid_baebc447b40748d7/compose', 'testclient', NULL, 200, 216.99, '2026-11-24 22:13:45.121778');
INSERT INTO public.audit_log (id, request_id, method, path, client_ip, "user", status, cost_ms, created_at) VALUES (627, '1ad17e63-6b3c-4e09-8283-354c23ccf4ad', 'POST', '/api/v1/bi/dashboards/bid_baebc447b40748d7/compose', 'testclient', NULL, 200, 262.37, '2026-11-24 22:13:45.649516');
INSERT INTO public.audit_log (id, request_id, method, path, client_ip, "user", status, cost_ms, created_at) VALUES (628, '1dcb28f9-7419-4639-a5f7-7d96f568caa3', 'POST', '/api/v1/bi/dashboards/bid_baebc447b40748d7/compose', 'testclient', NULL, 200, 232.08, '2026-11-24 22:13:46.165078');
INSERT INTO public.audit_log (id, request_id, method, path, client_ip, "user", status, cost_ms, created_at) VALUES (629, '8fa2ccc3-bcea-41a9-a8fb-c16df97163d4', 'POST', '/api/v1/bi/dashboards/bid_baebc447b40748d7/compose', 'testclient', NULL, 200, 219.09, '2026-11-24 22:13:46.568645');
INSERT INTO public.audit_log (id, request_id, method, path, client_ip, "user", status, cost_ms, created_at) VALUES (630, '487fd522-8ba1-4bfd-b0f7-5054c56d4aa2', 'POST', '/api/v1/bi/dashboards/bid_baebc447b40748d7/compose', 'testclient', NULL, 200, 219.3, '2026-11-24 22:13:46.96868');
INSERT INTO public.audit_log (id, request_id, method, path, client_ip, "user", status, cost_ms, created_at) VALUES (631, 'c41f4d12-de32-42cc-9bb9-65fb70f0a976', 'POST', '/api/v1/bi/dashboards/bid_baebc447b40748d7/compose', 'testclient', NULL, 200, 217.51, '2026-11-24 22:13:47.369709');
INSERT INTO public.audit_log (id, request_id, method, path, client_ip, "user", status, cost_ms, created_at) VALUES (632, '30a4e776-29b7-45f2-9b68-9c2d0ffe49e0', 'POST', '/api/v1/bi/dashboards/bid_baebc447b40748d7/compose', 'testclient', NULL, 200, 229.07, '2026-11-24 22:13:47.784429');
INSERT INTO public.audit_log (id, request_id, method, path, client_ip, "user", status, cost_ms, created_at) VALUES (633, 'dafb230d-42dd-4d48-a20c-d220d9d95c13', 'POST', '/api/v1/bi/dashboards/bid_baebc447b40748d7/compose', 'testclient', NULL, 429, 53.13, '2026-11-24 22:13:48.015835');
INSERT INTO public.audit_log (id, request_id, method, path, client_ip, "user", status, cost_ms, created_at) VALUES (634, '973a89bb-00f9-4386-9481-7fdfda0293b3', 'POST', '/api/v1/bi/dashboards', 'testclient', NULL, 201, 376.03, '2026-11-24 22:15:43.693292');
INSERT INTO public.audit_log (id, request_id, method, path, client_ip, "user", status, cost_ms, created_at) VALUES (635, '7c8db6a5-a34e-4c40-a47a-4fc7d8f4e176', 'POST', '/api/v1/bi/dashboards/bid_12e22504da0a4527/compose', 'testclient', NULL, 200, 232.56, '2026-11-24 22:15:44.109258');
INSERT INTO public.audit_log (id, request_id, method, path, client_ip, "user", status, cost_ms, created_at) VALUES (636, '3a3c2b8d-086c-4a75-ac16-eb51ba97a415', 'POST', '/api/v1/bi/dashboards', 'testclient', NULL, 201, 311.26, '2026-11-24 22:15:44.933214');
INSERT INTO public.audit_log (id, request_id, method, path, client_ip, "user", status, cost_ms, created_at) VALUES (637, '59da2a44-4664-471d-a511-957577b8219b', 'POST', '/api/v1/bi/dashboards/bid_4d288865982542bb/compose', 'testclient', NULL, 422, 221.24, '2026-11-24 22:15:45.333871');
INSERT INTO public.audit_log (id, request_id, method, path, client_ip, "user", status, cost_ms, created_at) VALUES (638, '28191099-6027-42c1-b160-402b2281b929', 'POST', '/api/v1/bi/dashboards', 'testclient', NULL, 201, 306.53, '2026-11-24 22:15:46.131888');
INSERT INTO public.audit_log (id, request_id, method, path, client_ip, "user", status, cost_ms, created_at) VALUES (639, 'c222a91b-88b5-4b1d-b131-4f9305ad7174', 'POST', '/api/v1/bi/dashboards/bid_32491e1542734af1/compose', 'testclient', NULL, 200, 249.2, '2026-11-24 22:15:46.567462');
INSERT INTO public.audit_log (id, request_id, method, path, client_ip, "user", status, cost_ms, created_at) VALUES (640, '57a49886-3f10-40f1-a50f-ac81ee8dbd69', 'POST', '/api/v1/bi/dashboards', 'testclient', NULL, 201, 310.37, '2026-11-24 22:15:47.354281');
INSERT INTO public.audit_log (id, request_id, method, path, client_ip, "user", status, cost_ms, created_at) VALUES (641, '3fcec419-dbc2-4125-b3da-a847a579c426', 'POST', '/api/v1/bi/dashboards/bid_91ed3193daee4169/preview', 'testclient', NULL, 200, 233.85, '2026-11-24 22:15:48.284151');
INSERT INTO public.audit_log (id, request_id, method, path, client_ip, "user", status, cost_ms, created_at) VALUES (642, '542a5ae0-4f3f-4906-adad-f1b525e5e6b2', 'POST', '/api/v1/bi/dashboards', 'testclient', NULL, 201, 323.15, '2026-11-24 22:15:49.346478');
INSERT INTO public.audit_log (id, request_id, method, path, client_ip, "user", status, cost_ms, created_at) VALUES (643, '04cd8653-e94d-4de8-9224-0635f0d23bcb', 'POST', '/api/v1/bi/dashboards/bid_50ddf9eec75140e6/preview', 'testclient', NULL, 422, 252.55, '2026-11-24 22:15:49.78458');
INSERT INTO public.audit_log (id, request_id, method, path, client_ip, "user", status, cost_ms, created_at) VALUES (644, '61460ace-f184-4862-b0bb-977c22d00c8f', 'POST', '/api/v1/bi/describe', 'testclient', NULL, 200, 62.53, '2026-11-24 22:15:50.442279');
INSERT INTO public.audit_log (id, request_id, method, path, client_ip, "user", status, cost_ms, created_at) VALUES (645, 'a977b570-3a52-43ad-8b6a-9c9defe69aca', 'POST', '/api/v1/bi/describe', 'testclient', NULL, 200, 54.18, '2026-11-24 22:15:50.718126');
INSERT INTO public.audit_log (id, request_id, method, path, client_ip, "user", status, cost_ms, created_at) VALUES (646, 'd674182f-43b2-426d-9157-b4bd258c881e', 'POST', '/api/v1/bi/describe', 'testclient', NULL, 200, 47.99, '2026-11-24 22:15:50.944724');
INSERT INTO public.audit_log (id, request_id, method, path, client_ip, "user", status, cost_ms, created_at) VALUES (647, '6747f25e-6c6f-4ad4-a9ba-2b81a5d4a4a3', 'POST', '/api/v1/bi/describe', 'testclient', NULL, 422, 49.08, '2026-11-24 22:15:51.178643');
INSERT INTO public.audit_log (id, request_id, method, path, client_ip, "user", status, cost_ms, created_at) VALUES (648, '7daa5610-ec45-4b25-9feb-1f72b2755830', 'POST', '/api/v1/bi/dashboards', 'testclient', NULL, 201, 318.57, '2026-11-24 22:15:51.678407');
INSERT INTO public.audit_log (id, request_id, method, path, client_ip, "user", status, cost_ms, created_at) VALUES (649, '0cf921d9-45a9-4f20-a718-ad8770486975', 'PUT', '/api/v1/bi/dashboards/bid_4c4a053dfc4d4532/draft', 'testclient', NULL, 200, 401.22, '2026-11-24 22:15:52.253688');
INSERT INTO public.audit_log (id, request_id, method, path, client_ip, "user", status, cost_ms, created_at) VALUES (650, '5cd81ecd-3ada-490e-98c8-1a95425f0416', 'POST', '/api/v1/bi/dashboards', 'testclient', NULL, 201, 308.83, '2026-11-24 22:15:53.602031');
INSERT INTO public.audit_log (id, request_id, method, path, client_ip, "user", status, cost_ms, created_at) VALUES (651, '5eb0f4cc-1cd3-48b5-801b-bdab0bfe1836', 'PUT', '/api/v1/bi/dashboards/bid_0206726ea3304bf0/draft', 'testclient', NULL, 200, 386.8, '2026-11-24 22:15:54.174748');
INSERT INTO public.audit_log (id, request_id, method, path, client_ip, "user", status, cost_ms, created_at) VALUES (652, '1ef93690-8a82-4ebc-a83a-8c40c6d2aab7', 'PUT', '/api/v1/bi/dashboards/bid_0206726ea3304bf0/draft', 'testclient', NULL, 200, 91.12, '2026-11-24 22:15:54.453171');
INSERT INTO public.audit_log (id, request_id, method, path, client_ip, "user", status, cost_ms, created_at) VALUES (653, '9483b745-9887-484f-bc8a-cad3892a98cf', 'POST', '/api/v1/bi/dashboards', 'testclient', NULL, 201, 319.85, '2026-11-24 22:15:55.947137');
INSERT INTO public.audit_log (id, request_id, method, path, client_ip, "user", status, cost_ms, created_at) VALUES (654, '584b3dec-47dc-4700-b64d-7514bdc032d5', 'POST', '/api/v1/bi/dashboards/bid_ec5db4f8ff554b14/compose', 'testclient', NULL, 200, 230.74, '2026-11-24 22:15:56.35483');
INSERT INTO public.audit_log (id, request_id, method, path, client_ip, "user", status, cost_ms, created_at) VALUES (655, 'c1f12cc9-06cb-4177-9b7c-f981fa525d20', 'POST', '/api/v1/bi/dashboards/bid_ec5db4f8ff554b14/compose', 'testclient', NULL, 200, 236.34, '2026-11-24 22:15:56.768411');
INSERT INTO public.audit_log (id, request_id, method, path, client_ip, "user", status, cost_ms, created_at) VALUES (656, 'dcfa5f4f-7818-4c5b-bcb6-2742749a17b6', 'POST', '/api/v1/bi/dashboards/bid_ec5db4f8ff554b14/compose', 'testclient', NULL, 200, 240.52, '2026-11-24 22:15:57.186838');
INSERT INTO public.audit_log (id, request_id, method, path, client_ip, "user", status, cost_ms, created_at) VALUES (657, '79a1723d-3900-4a18-a89e-6b6abf82af95', 'POST', '/api/v1/bi/dashboards/bid_ec5db4f8ff554b14/compose', 'testclient', NULL, 200, 231.09, '2026-11-24 22:15:57.595724');
INSERT INTO public.audit_log (id, request_id, method, path, client_ip, "user", status, cost_ms, created_at) VALUES (658, 'b1de515f-af65-4aae-8708-4ca1ce62397d', 'POST', '/api/v1/bi/dashboards/bid_ec5db4f8ff554b14/compose', 'testclient', NULL, 200, 225.55, '2026-11-24 22:15:58.037847');
INSERT INTO public.audit_log (id, request_id, method, path, client_ip, "user", status, cost_ms, created_at) VALUES (659, '62527b9e-776f-4d72-ba9c-fe1f3c4823c9', 'POST', '/api/v1/bi/dashboards/bid_ec5db4f8ff554b14/compose', 'testclient', NULL, 200, 230.1, '2026-11-24 22:15:58.444649');
INSERT INTO public.audit_log (id, request_id, method, path, client_ip, "user", status, cost_ms, created_at) VALUES (660, '00323ab9-fa96-4c5b-aab6-60c3d7c2aba0', 'POST', '/api/v1/bi/dashboards/bid_ec5db4f8ff554b14/compose', 'testclient', NULL, 200, 227.26, '2026-11-24 22:15:58.849534');
INSERT INTO public.audit_log (id, request_id, method, path, client_ip, "user", status, cost_ms, created_at) VALUES (661, '40c17a35-313a-4f03-8a8b-f7ad32f61165', 'POST', '/api/v1/bi/dashboards/bid_ec5db4f8ff554b14/compose', 'testclient', NULL, 200, 228.56, '2026-11-24 22:15:59.255795');
INSERT INTO public.audit_log (id, request_id, method, path, client_ip, "user", status, cost_ms, created_at) VALUES (662, 'b1d05ce5-33ad-4b58-8a63-279b2de40226', 'POST', '/api/v1/bi/dashboards/bid_ec5db4f8ff554b14/compose', 'testclient', NULL, 200, 228.39, '2026-11-24 22:15:59.66278');
INSERT INTO public.audit_log (id, request_id, method, path, client_ip, "user", status, cost_ms, created_at) VALUES (663, '3981f900-6eb3-48f2-8dfe-9cb562e12f61', 'POST', '/api/v1/bi/dashboards/bid_ec5db4f8ff554b14/compose', 'testclient', NULL, 200, 257.75, '2026-11-24 22:16:00.097987');
INSERT INTO public.audit_log (id, request_id, method, path, client_ip, "user", status, cost_ms, created_at) VALUES (664, 'f4205d67-a092-455e-bae1-bb7144fca677', 'POST', '/api/v1/bi/dashboards/bid_ec5db4f8ff554b14/compose', 'testclient', NULL, 429, 51.47, '2026-11-24 22:16:00.327515');
INSERT INTO public.audit_log (id, request_id, method, path, client_ip, "user", status, cost_ms, created_at) VALUES (665, '61ae3d1a-d886-4282-9a84-d2c7b9d90abe', 'POST', '/api/v1/auth/register', 'testclient', NULL, 503, 6.46, '2026-11-24 22:16:01.16347');
INSERT INTO public.audit_log (id, request_id, method, path, client_ip, "user", status, cost_ms, created_at) VALUES (666, '0ad32c2b-aa0b-4307-acb9-50787626c47b', 'POST', '/api/v1/auth/register', 'testclient', NULL, 503, 4, '2026-11-24 22:16:18.173748');
INSERT INTO public.audit_log (id, request_id, method, path, client_ip, "user", status, cost_ms, created_at) VALUES (667, '1b2134c7-1f05-4933-803d-c0e95b701231', 'POST', '/api/v1/auth/register', 'testclient', NULL, 503, 4.39, '2026-11-24 22:16:34.061662');
INSERT INTO public.audit_log (id, request_id, method, path, client_ip, "user", status, cost_ms, created_at) VALUES (668, 'd12d2625-94fe-449d-9b96-7d53ecc2ba5f', 'POST', '/api/v1/bi/dashboards', 'testclient', NULL, 201, 379.24, '2026-11-24 22:17:05.870573');
INSERT INTO public.audit_log (id, request_id, method, path, client_ip, "user", status, cost_ms, created_at) VALUES (669, 'b2cef9b4-2334-4655-9cb8-b0b0eb629393', 'POST', '/api/v1/bi/dashboards/bid_31dc5c55d63b4f95/compose', 'testclient', NULL, 200, 240.01, '2026-11-24 22:17:06.297459');
INSERT INTO public.audit_log (id, request_id, method, path, client_ip, "user", status, cost_ms, created_at) VALUES (670, '954fa5dd-a823-4754-ba34-27ccb738cc91', 'POST', '/api/v1/bi/dashboards', 'testclient', NULL, 201, 361.31, '2026-11-24 22:17:07.147534');
INSERT INTO public.audit_log (id, request_id, method, path, client_ip, "user", status, cost_ms, created_at) VALUES (671, 'fbe3fccc-b335-4679-a5c5-157eb837e5e8', 'POST', '/api/v1/bi/dashboards/bid_55e89411046a4c8e/compose', 'testclient', NULL, 422, 227.22, '2026-11-24 22:17:07.555766');
INSERT INTO public.audit_log (id, request_id, method, path, client_ip, "user", status, cost_ms, created_at) VALUES (672, '6748be08-8d58-4dda-8ec6-91128860bbf7', 'POST', '/api/v1/bi/dashboards', 'testclient', NULL, 201, 314.78, '2026-11-24 22:17:08.356472');
INSERT INTO public.audit_log (id, request_id, method, path, client_ip, "user", status, cost_ms, created_at) VALUES (673, 'ceab6849-290e-4e24-bb9d-45b6150d99c2', 'POST', '/api/v1/bi/dashboards/bid_dec313d0cf37439e/compose', 'testclient', NULL, 200, 226.44, '2026-11-24 22:17:08.765937');
INSERT INTO public.audit_log (id, request_id, method, path, client_ip, "user", status, cost_ms, created_at) VALUES (674, 'a1a7036d-f0e9-49bc-8fea-a45c6b6e5a2f', 'POST', '/api/v1/bi/dashboards', 'testclient', NULL, 201, 317.92, '2026-11-24 22:17:09.57223');
INSERT INTO public.audit_log (id, request_id, method, path, client_ip, "user", status, cost_ms, created_at) VALUES (675, '383b7dde-c80b-4446-ae61-94e8be5cc4f5', 'POST', '/api/v1/bi/dashboards/bid_0a8d5d2ec3394f82/preview', 'testclient', NULL, 200, 218.86, '2026-11-24 22:17:10.453739');
INSERT INTO public.audit_log (id, request_id, method, path, client_ip, "user", status, cost_ms, created_at) VALUES (676, '40a15e51-caf0-44b1-a84c-4075c07fabd5', 'POST', '/api/v1/bi/dashboards', 'testclient', NULL, 201, 300.84, '2026-11-24 22:17:11.432464');
INSERT INTO public.audit_log (id, request_id, method, path, client_ip, "user", status, cost_ms, created_at) VALUES (677, '76bf1051-dc6a-4c4b-afe3-cfe9d4afd58b', 'POST', '/api/v1/bi/dashboards/bid_3a852c44508a4c01/preview', 'testclient', NULL, 422, 215.01, '2026-11-24 22:17:11.828216');
INSERT INTO public.audit_log (id, request_id, method, path, client_ip, "user", status, cost_ms, created_at) VALUES (678, '873a95d6-c904-47fa-a10d-98c2f4d350ba', 'POST', '/api/v1/bi/describe', 'testclient', NULL, 200, 65.94, '2026-11-24 22:17:12.528011');
INSERT INTO public.audit_log (id, request_id, method, path, client_ip, "user", status, cost_ms, created_at) VALUES (679, '5047a2d3-8f33-4468-ac0e-c4907ac56d13', 'POST', '/api/v1/bi/describe', 'testclient', NULL, 200, 51.36, '2026-11-24 22:17:12.757118');
INSERT INTO public.audit_log (id, request_id, method, path, client_ip, "user", status, cost_ms, created_at) VALUES (680, '9bcf2083-a270-4e1e-a1d0-ef5c46d5ca52', 'POST', '/api/v1/bi/describe', 'testclient', NULL, 200, 50.6, '2026-11-24 22:17:12.983273');
INSERT INTO public.audit_log (id, request_id, method, path, client_ip, "user", status, cost_ms, created_at) VALUES (681, 'd8210f54-c951-4f67-9416-d5e5fe01437d', 'POST', '/api/v1/bi/describe', 'testclient', NULL, 422, 51.05, '2026-11-24 22:17:13.208481');
INSERT INTO public.audit_log (id, request_id, method, path, client_ip, "user", status, cost_ms, created_at) VALUES (682, 'ff799ac7-b1b1-45b6-ab02-00b0fcf153e9', 'POST', '/api/v1/bi/dashboards', 'testclient', NULL, 201, 342.67, '2026-11-24 22:17:13.750796');
INSERT INTO public.audit_log (id, request_id, method, path, client_ip, "user", status, cost_ms, created_at) VALUES (683, '671b2ac6-3b4e-4abf-b4cc-cc3c26fae5a0', 'PUT', '/api/v1/bi/dashboards/bid_b8ab0821159a4929/draft', 'testclient', NULL, 200, 427.31, '2026-11-24 22:17:14.416419');
INSERT INTO public.audit_log (id, request_id, method, path, client_ip, "user", status, cost_ms, created_at) VALUES (684, 'bb106014-c5c8-444a-aa11-d520b18d1bf5', 'POST', '/api/v1/bi/dashboards', 'testclient', NULL, 201, 316.67, '2026-11-24 22:17:15.740953');
INSERT INTO public.audit_log (id, request_id, method, path, client_ip, "user", status, cost_ms, created_at) VALUES (685, '248d9982-9800-43a0-a091-3199ed56c5d8', 'PUT', '/api/v1/bi/dashboards/bid_e83d219e1237450f/draft', 'testclient', NULL, 200, 399.98, '2026-11-24 22:17:16.308794');
INSERT INTO public.audit_log (id, request_id, method, path, client_ip, "user", status, cost_ms, created_at) VALUES (686, '2294fb55-112e-4368-98eb-7942a6868de8', 'PUT', '/api/v1/bi/dashboards/bid_e83d219e1237450f/draft', 'testclient', NULL, 200, 96.36, '2026-11-24 22:17:16.579193');
INSERT INTO public.audit_log (id, request_id, method, path, client_ip, "user", status, cost_ms, created_at) VALUES (687, '909ccc06-235e-41fb-93c6-413fbc5c0e0c', 'POST', '/api/v1/bi/dashboards', 'testclient', NULL, 201, 300, '2026-11-24 22:17:18.018653');
INSERT INTO public.audit_log (id, request_id, method, path, client_ip, "user", status, cost_ms, created_at) VALUES (688, '34ac8088-3998-4b5b-a78e-10c1b3dc21c1', 'POST', '/api/v1/bi/dashboards/bid_dacd5991598b4231/compose', 'testclient', NULL, 200, 213.25, '2026-11-24 22:17:18.414223');
INSERT INTO public.audit_log (id, request_id, method, path, client_ip, "user", status, cost_ms, created_at) VALUES (689, '0badfb34-567e-42a7-a5f3-ed719c8ab66b', 'POST', '/api/v1/bi/dashboards/bid_dacd5991598b4231/compose', 'testclient', NULL, 200, 213.45, '2026-11-24 22:17:18.810528');
INSERT INTO public.audit_log (id, request_id, method, path, client_ip, "user", status, cost_ms, created_at) VALUES (690, '15a4a043-44a5-443e-820f-d5f01a32ebc9', 'POST', '/api/v1/bi/dashboards/bid_dacd5991598b4231/compose', 'testclient', NULL, 200, 213.54, '2026-11-24 22:17:19.205283');
INSERT INTO public.audit_log (id, request_id, method, path, client_ip, "user", status, cost_ms, created_at) VALUES (691, '66bdad9e-1a89-48c7-94f5-35b857ac9fa7', 'POST', '/api/v1/bi/dashboards/bid_dacd5991598b4231/compose', 'testclient', NULL, 200, 216.69, '2026-11-24 22:17:19.602599');
INSERT INTO public.audit_log (id, request_id, method, path, client_ip, "user", status, cost_ms, created_at) VALUES (692, '68ce86e8-c363-48bb-a9a2-135ac276ec76', 'POST', '/api/v1/bi/dashboards/bid_dacd5991598b4231/compose', 'testclient', NULL, 200, 212.2, '2026-11-24 22:17:20.036047');
INSERT INTO public.audit_log (id, request_id, method, path, client_ip, "user", status, cost_ms, created_at) VALUES (693, '798cbeac-be1c-445b-b48e-ec81a621f2f1', 'POST', '/api/v1/bi/dashboards/bid_dacd5991598b4231/compose', 'testclient', NULL, 200, 213.47, '2026-11-24 22:17:20.430511');
INSERT INTO public.audit_log (id, request_id, method, path, client_ip, "user", status, cost_ms, created_at) VALUES (694, '34fb8a95-780b-4daf-8859-516ca1645dd5', 'POST', '/api/v1/bi/dashboards/bid_dacd5991598b4231/compose', 'testclient', NULL, 200, 213.51, '2026-11-24 22:17:20.824094');
INSERT INTO public.audit_log (id, request_id, method, path, client_ip, "user", status, cost_ms, created_at) VALUES (695, 'aef12674-9746-44c0-82bd-0c894f934748', 'POST', '/api/v1/bi/dashboards/bid_dacd5991598b4231/compose', 'testclient', NULL, 200, 228.78, '2026-11-24 22:17:21.242861');
INSERT INTO public.audit_log (id, request_id, method, path, client_ip, "user", status, cost_ms, created_at) VALUES (696, 'e8af350c-c833-41ee-a219-1bc92365642d', 'POST', '/api/v1/bi/dashboards/bid_dacd5991598b4231/compose', 'testclient', NULL, 200, 217.68, '2026-11-24 22:17:21.642994');
INSERT INTO public.audit_log (id, request_id, method, path, client_ip, "user", status, cost_ms, created_at) VALUES (697, 'bc6146ad-c79f-45aa-a8b4-4fb68fbbfb0d', 'POST', '/api/v1/bi/dashboards/bid_dacd5991598b4231/compose', 'testclient', NULL, 200, 214.55, '2026-11-24 22:17:22.038879');
INSERT INTO public.audit_log (id, request_id, method, path, client_ip, "user", status, cost_ms, created_at) VALUES (698, '0f801970-49d2-4337-aafd-9eb9e026f3e2', 'POST', '/api/v1/bi/dashboards/bid_dacd5991598b4231/compose', 'testclient', NULL, 429, 52.98, '2026-11-24 22:17:22.265436');
INSERT INTO public.audit_log (id, request_id, method, path, client_ip, "user", status, cost_ms, created_at) VALUES (699, '9f3e3573-c373-450f-8084-385c7d8ab8fb', 'POST', '/api/v1/auth/register', 'testclient', NULL, 503, 4.55, '2026-11-24 22:17:23.849783');


ALTER TABLE public.audit_log ENABLE TRIGGER ALL;

--
-- Data for Name: sys_org; Type: TABLE DATA; Schema: public; Owner: -
--

ALTER TABLE public.sys_org DISABLE TRIGGER ALL;

INSERT INTO public.sys_org (id, org_code, org_name, domain, package_code, data_region, status, expire_at, created_at, updated_at, created_by, updated_by, deleted) VALUES (1, 'RBAC_TEST', 'RBAC 权限测试租户', NULL, 'STARTER', 'local', 'ACTIVE', NULL, '2026-11-23 18:07:28.794958', '2026-11-23 18:07:28.794958', NULL, NULL, false);
INSERT INTO public.sys_org (id, org_code, org_name, domain, package_code, data_region, status, expire_at, created_at, updated_at, created_by, updated_by, deleted) VALUES (0, '__GLOBAL_TENANT__', '虚拟全局组织', NULL, NULL, NULL, 'DISABLED', NULL, '2026-11-24 18:11:50.721095', '2026-11-24 18:11:50.721095', NULL, NULL, true);


ALTER TABLE public.sys_org ENABLE TRIGGER ALL;

--
-- Data for Name: biz_department; Type: TABLE DATA; Schema: public; Owner: -
--

ALTER TABLE public.biz_department DISABLE TRIGGER ALL;

INSERT INTO public.biz_department (id, org_id, parent_id, dept_name, dept_code, manager_name, phone, email, sort, status, created_at, updated_at, created_by, updated_by, deleted, manager_id) VALUES (1, 1, 0, '总公司', 'HQ', '黄承翔', '13800138000', NULL, 1, 'ENABLED', '2026-11-23 21:34:16.884045', '2026-11-23 22:12:25.390262', NULL, NULL, false, 1);
INSERT INTO public.biz_department (id, org_id, parent_id, dept_name, dept_code, manager_name, phone, email, sort, status, created_at, updated_at, created_by, updated_by, deleted, manager_id) VALUES (2, 1, 1, '运营部', 'OPS', '张运营', '13800138008', NULL, 2, 'ENABLED', '2026-11-23 21:05:20.792962', '2026-11-23 22:12:25.390262', NULL, NULL, false, 10);
INSERT INTO public.biz_department (id, org_id, parent_id, dept_name, dept_code, manager_name, phone, email, sort, status, created_at, updated_at, created_by, updated_by, deleted, manager_id) VALUES (3, 1, 2, '运营一部', 'OPS_1', '张运营', '13800138008', NULL, 3, 'ENABLED', '2026-11-23 21:34:16.884045', '2026-11-23 22:12:25.390262', NULL, NULL, false, 10);
INSERT INTO public.biz_department (id, org_id, parent_id, dept_name, dept_code, manager_name, phone, email, sort, status, created_at, updated_at, created_by, updated_by, deleted, manager_id) VALUES (4, 1, 2, '运营二部', 'OPS_2', '张运营', '13800138008', NULL, 4, 'ENABLED', '2026-11-23 21:34:16.884045', '2026-11-23 22:12:25.390262', NULL, NULL, false, 10);
INSERT INTO public.biz_department (id, org_id, parent_id, dept_name, dept_code, manager_name, phone, email, sort, status, created_at, updated_at, created_by, updated_by, deleted, manager_id) VALUES (5, 1, 1, '财务部', 'FIN', '李财务', '13800138015', NULL, 5, 'ENABLED', '2026-11-23 21:05:20.792962', '2026-11-23 22:12:25.390262', NULL, NULL, false, 17);
INSERT INTO public.biz_department (id, org_id, parent_id, dept_name, dept_code, manager_name, phone, email, sort, status, created_at, updated_at, created_by, updated_by, deleted, manager_id) VALUES (6, 1, 1, '仓储部', 'WH', '王仓管', '13800138018', NULL, 6, 'ENABLED', '2026-11-23 21:05:20.792962', '2026-11-23 22:12:25.390262', NULL, NULL, false, 20);
INSERT INTO public.biz_department (id, org_id, parent_id, dept_name, dept_code, manager_name, phone, email, sort, status, created_at, updated_at, created_by, updated_by, deleted, manager_id) VALUES (7, 1, 1, '客服部', 'CS', '赵客服', '13800138005', NULL, 7, 'ENABLED', '2026-11-23 21:05:20.792962', '2026-11-23 22:12:25.390262', NULL, NULL, false, 7);


ALTER TABLE public.biz_department ENABLE TRIGGER ALL;

--
-- Data for Name: bi_approval_flow; Type: TABLE DATA; Schema: public; Owner: -
--

ALTER TABLE public.bi_approval_flow DISABLE TRIGGER ALL;

INSERT INTO public.bi_approval_flow (id, org_id, flow_code, flow_name, scope_level, dept_id, nodes, status, version, created_at, updated_at) VALUES (2, 1, 'OPS1_PUBLISH', '运营一部发布流(v2)', 'department', 3, '[{"seq": 1, "name": "部门负责人审核", "node_mode": "any", "approver_ref": null, "approver_type": "dept_leader"}]', 'enabled', 2, '2026-11-24 16:35:12.343661+08', '2026-11-24 16:35:13.191593+08');
INSERT INTO public.bi_approval_flow (id, org_id, flow_code, flow_name, scope_level, dept_id, nodes, status, version, created_at, updated_at) VALUES (4, 1, 'DEFAULT_COMPANY_PUBLISH', '公司级发布默认流', 'company', NULL, '[{"seq": 1, "name": "公司负责人审核", "node_mode": "any", "approver_ref": null, "approver_type": "dept_leader"}]', 'enabled', 1, '2026-11-24 18:19:32.865795+08', '2026-11-24 18:19:32.865795+08');
INSERT INTO public.bi_approval_flow (id, org_id, flow_code, flow_name, scope_level, dept_id, nodes, status, version, created_at, updated_at) VALUES (1, 0, 'DEFAULT_COMPANY_PUBLISH', '公司默认发布审批流', 'company', NULL, '[{"seq": 1, "name": "公司负责人审核", "node_mode": "any", "approver_ref": null, "approver_type": "dept_leader"}]', 'enabled', 1, '2026-11-24 14:50:04.965027+08', '2026-11-24 18:24:53.174011+08');


ALTER TABLE public.bi_approval_flow ENABLE TRIGGER ALL;

--
-- Data for Name: bi_conversation_turn; Type: TABLE DATA; Schema: public; Owner: -
--

ALTER TABLE public.bi_conversation_turn DISABLE TRIGGER ALL;



ALTER TABLE public.bi_conversation_turn ENABLE TRIGGER ALL;

--
-- Data for Name: bi_dashboard_designs; Type: TABLE DATA; Schema: public; Owner: -
--

ALTER TABLE public.bi_dashboard_designs DISABLE TRIGGER ALL;

INSERT INTO public.bi_dashboard_designs (id, org_id, dashboard_name, deleted_at, created_at, updated_at, scope_level, dept_id, dept_name_snapshot, dashboard_id, board_status, draft_layout, published_layout, version, published_at) VALUES (1, 1, '经营总览-smoke', '2026-11-24 16:29:32.649101+08', '2026-11-24 16:29:28.299569+08', '2026-11-24 16:29:32.520735+08', 'company', NULL, NULL, 'bid_e354ce00f490408a', 'draft', '{"theme": "light", "device": "desktop", "widgets": [{"id": "w_01", "grid": {"h": 4, "w": 6, "x": 0, "y": 0}, "type": "kpi", "title": "成交总额", "width": 1, "refresh": "realtime", "data_scope": "company", "metric_key": "GMV", "time_range": "14d"}, {"id": "w_02", "grid": {"h": 6, "w": 12, "x": 0, "y": 4}, "type": "line", "title": "订单趋势", "width": 2, "refresh": "realtime", "data_scope": "company", "metric_key": "ORDER_COUNT", "time_range": "30d"}], "schema_version": 1}', NULL, 2, NULL);
INSERT INTO public.bi_dashboard_designs (id, org_id, dashboard_name, deleted_at, created_at, updated_at, scope_level, dept_id, dept_name_snapshot, dashboard_id, board_status, draft_layout, published_layout, version, published_at) VALUES (2, 1, '经营总览-smoke', '2026-11-24 16:30:04.309576+08', '2026-11-24 16:29:59.891331+08', '2026-11-24 16:30:04.188315+08', 'company', NULL, NULL, 'bid_e3a9cd9c98c34129', 'draft', '{"theme": "light", "device": "desktop", "widgets": [{"id": "w_01", "grid": {"h": 4, "w": 6, "x": 0, "y": 0}, "type": "kpi", "title": "成交总额", "width": 1, "refresh": "realtime", "data_scope": "company", "metric_key": "GMV", "time_range": "14d"}, {"id": "w_02", "grid": {"h": 6, "w": 12, "x": 0, "y": 4}, "type": "line", "title": "订单趋势", "width": 2, "refresh": "realtime", "data_scope": "company", "metric_key": "ORDER_COUNT", "time_range": "30d"}], "schema_version": 1}', NULL, 2, NULL);
INSERT INTO public.bi_dashboard_designs (id, org_id, dashboard_name, deleted_at, created_at, updated_at, scope_level, dept_id, dept_name_snapshot, dashboard_id, board_status, draft_layout, published_layout, version, published_at) VALUES (3, 1, '经营总览-smoke', '2026-11-24 16:30:36.514255+08', '2026-11-24 16:30:32.179768+08', '2026-11-24 16:30:36.388694+08', 'company', NULL, NULL, 'bid_b822c9bb043645c1', 'draft', '{"theme": "light", "device": "desktop", "widgets": [], "schema_version": 1}', NULL, 1, NULL);
INSERT INTO public.bi_dashboard_designs (id, org_id, dashboard_name, deleted_at, created_at, updated_at, scope_level, dept_id, dept_name_snapshot, dashboard_id, board_status, draft_layout, published_layout, version, published_at) VALUES (5, 1, '经营总览-4ee86a', '2026-11-24 16:31:21.352143+08', '2026-11-24 16:31:16.779148+08', '2026-11-24 16:31:21.226609+08', 'company', NULL, NULL, 'bid_294051dddc2e4d8b', 'draft', '{"theme": "light", "device": "desktop", "widgets": [{"id": "w_01", "grid": {"h": 4, "w": 6, "x": 0, "y": 0}, "type": "kpi", "title": "成交总额", "width": 1, "refresh": "realtime", "data_scope": "company", "metric_key": "GMV", "time_range": "14d"}, {"id": "w_02", "grid": {"h": 6, "w": 12, "x": 0, "y": 4}, "type": "line", "title": "订单趋势", "width": 2, "refresh": "realtime", "data_scope": "company", "metric_key": "ORDER_COUNT", "time_range": "30d"}], "schema_version": 1}', NULL, 2, NULL);
INSERT INTO public.bi_dashboard_designs (id, org_id, dashboard_name, deleted_at, created_at, updated_at, scope_level, dept_id, dept_name_snapshot, dashboard_id, board_status, draft_layout, published_layout, version, published_at) VALUES (6, 1, '运营一部日报-d34e41', NULL, '2026-11-24 16:34:41.809955+08', '2026-11-24 16:34:46.391819+08', 'department', 3, '运营一部', 'bid_cff6db1e95114d1b', 'running', '{"theme": "light", "device": "desktop", "widgets": [{"id": "w1", "grid": {"h": 4, "w": 6, "x": 0, "y": 0}, "type": "kpi", "title": "部门成交额", "width": 1, "refresh": "realtime", "data_scope": "department", "metric_key": "GMV", "time_range": "14d"}, {"id": "w2", "grid": {"h": 4, "w": 6, "x": 6, "y": 0}, "type": "bar", "title": "订单量", "width": 1, "refresh": "realtime", "data_scope": "department", "metric_key": "ORDER_COUNT", "time_range": "7d"}, {"id": "w3", "grid": {"h": 5, "w": 12, "x": 0, "y": 4}, "type": "donut", "title": "渠道结构", "width": 2, "refresh": "manual", "data_scope": "department", "metric_key": "GMV", "time_range": "14d"}], "schema_version": 1}', '{"theme": "light", "device": "desktop", "widgets": [{"id": "w1", "grid": {"h": 4, "w": 6, "x": 0, "y": 0}, "type": "kpi", "title": "部门成交额", "width": 1, "refresh": "realtime", "data_scope": "department", "metric_key": "GMV", "time_range": "14d"}, {"id": "w2", "grid": {"h": 4, "w": 6, "x": 6, "y": 0}, "type": "bar", "title": "订单量", "width": 1, "refresh": "realtime", "data_scope": "department", "metric_key": "ORDER_COUNT", "time_range": "7d"}, {"id": "w3", "grid": {"h": 5, "w": 12, "x": 0, "y": 4}, "type": "donut", "title": "渠道结构", "width": 2, "refresh": "manual", "data_scope": "department", "metric_key": "GMV", "time_range": "14d"}], "schema_version": 1}', 2, '2026-11-24 16:34:46.391819+08');
INSERT INTO public.bi_dashboard_designs (id, org_id, dashboard_name, deleted_at, created_at, updated_at, scope_level, dept_id, dept_name_snapshot, dashboard_id, board_status, draft_layout, published_layout, version, published_at) VALUES (4, 1, 'lock-test', '2026-11-24 16:50:34.815975+08', '2026-11-24 16:30:49.848245+08', '2026-11-24 16:50:34.666476+08', 'company', NULL, NULL, 'bid_f0a92d0b44604570', 'draft', '{"theme": "light", "device": "desktop", "widgets": [], "schema_version": 1}', NULL, 2, NULL);
INSERT INTO public.bi_dashboard_designs (id, org_id, dashboard_name, deleted_at, created_at, updated_at, scope_level, dept_id, dept_name_snapshot, dashboard_id, board_status, draft_layout, published_layout, version, published_at) VALUES (7, 1, '运营一部日报-ffef5a', NULL, '2026-11-24 16:35:00.258498+08', '2026-11-24 16:35:04.456982+08', 'department', 3, '运营一部', 'bid_23bfc1503c8f4684', 'running', '{"theme": "light", "device": "desktop", "widgets": [{"id": "w1", "grid": {"h": 4, "w": 6, "x": 0, "y": 0}, "type": "kpi", "title": "部门成交额", "width": 1, "refresh": "realtime", "data_scope": "department", "metric_key": "GMV", "time_range": "14d"}, {"id": "w2", "grid": {"h": 4, "w": 6, "x": 6, "y": 0}, "type": "bar", "title": "订单量", "width": 1, "refresh": "realtime", "data_scope": "department", "metric_key": "ORDER_COUNT", "time_range": "7d"}, {"id": "w3", "grid": {"h": 5, "w": 12, "x": 0, "y": 4}, "type": "donut", "title": "渠道结构", "width": 2, "refresh": "manual", "data_scope": "department", "metric_key": "GMV", "time_range": "14d"}], "schema_version": 1}', '{"theme": "light", "device": "desktop", "widgets": [{"id": "w1", "grid": {"h": 4, "w": 6, "x": 0, "y": 0}, "type": "kpi", "title": "部门成交额", "width": 1, "refresh": "realtime", "data_scope": "department", "metric_key": "GMV", "time_range": "14d"}, {"id": "w2", "grid": {"h": 4, "w": 6, "x": 6, "y": 0}, "type": "bar", "title": "订单量", "width": 1, "refresh": "realtime", "data_scope": "department", "metric_key": "ORDER_COUNT", "time_range": "7d"}, {"id": "w3", "grid": {"h": 5, "w": 12, "x": 0, "y": 4}, "type": "donut", "title": "渠道结构", "width": 2, "refresh": "manual", "data_scope": "department", "metric_key": "GMV", "time_range": "14d"}], "schema_version": 1}', 2, '2026-11-24 16:35:04.456982+08');
INSERT INTO public.bi_dashboard_designs (id, org_id, dashboard_name, deleted_at, created_at, updated_at, scope_level, dept_id, dept_name_snapshot, dashboard_id, board_status, draft_layout, published_layout, version, published_at) VALUES (8, 1, '运营一部日报-6ed5aa', NULL, '2026-11-24 16:35:49.081865+08', '2026-11-24 16:35:53.219791+08', 'department', 3, '运营一部', 'bid_6968701e73d64e8b', 'running', '{"theme": "light", "device": "desktop", "widgets": [{"id": "w1", "grid": {"h": 4, "w": 6, "x": 0, "y": 0}, "type": "kpi", "title": "部门成交额", "width": 1, "refresh": "realtime", "data_scope": "department", "metric_key": "GMV", "time_range": "14d"}, {"id": "w2", "grid": {"h": 4, "w": 6, "x": 6, "y": 0}, "type": "bar", "title": "订单量", "width": 1, "refresh": "realtime", "data_scope": "department", "metric_key": "ORDER_COUNT", "time_range": "7d"}, {"id": "w3", "grid": {"h": 5, "w": 12, "x": 0, "y": 4}, "type": "donut", "title": "渠道结构", "width": 2, "refresh": "manual", "data_scope": "department", "metric_key": "GMV", "time_range": "14d"}], "schema_version": 1}', '{"theme": "light", "device": "desktop", "widgets": [{"id": "w1", "grid": {"h": 4, "w": 6, "x": 0, "y": 0}, "type": "kpi", "title": "部门成交额", "width": 1, "refresh": "realtime", "data_scope": "department", "metric_key": "GMV", "time_range": "14d"}, {"id": "w2", "grid": {"h": 4, "w": 6, "x": 6, "y": 0}, "type": "bar", "title": "订单量", "width": 1, "refresh": "realtime", "data_scope": "department", "metric_key": "ORDER_COUNT", "time_range": "7d"}, {"id": "w3", "grid": {"h": 5, "w": 12, "x": 0, "y": 4}, "type": "donut", "title": "渠道结构", "width": 2, "refresh": "manual", "data_scope": "department", "metric_key": "GMV", "time_range": "14d"}], "schema_version": 1}', 2, '2026-11-24 16:35:53.219791+08');
INSERT INTO public.bi_dashboard_designs (id, org_id, dashboard_name, deleted_at, created_at, updated_at, scope_level, dept_id, dept_name_snapshot, dashboard_id, board_status, draft_layout, published_layout, version, published_at) VALUES (9, 1, '设计页冒烟-668a', '2026-11-24 16:42:44.91178+08', '2026-11-24 16:42:38.152575+08', '2026-11-24 16:42:44.75913+08', 'department', 3, '运营一部', 'bid_5f395a80cf81431c', 'draft', '{"theme": "light", "device": "desktop", "widgets": [{"id": "w_01", "grid": {"h": 3, "w": 3, "x": 0, "y": 0}, "type": "kpi", "title": "成交总额", "width": 1, "refresh": "realtime", "data_scope": "company", "metric_key": "GMV", "time_range": "14d"}, {"id": "w_02", "grid": {"h": 3, "w": 9, "x": 3, "y": 0}, "type": "bar", "title": "订单量趋势", "width": 2, "refresh": "realtime", "data_scope": "department", "metric_key": "ORDER_COUNT", "time_range": "7d"}, {"id": "w_03", "grid": {"h": 4, "w": 4, "x": 0, "y": 3}, "type": "donut", "title": "投放产出结构", "width": 1, "refresh": "manual", "data_scope": "company", "metric_key": "AD_ROI", "time_range": "30d"}], "schema_version": 1}', NULL, 2, NULL);
INSERT INTO public.bi_dashboard_designs (id, org_id, dashboard_name, deleted_at, created_at, updated_at, scope_level, dept_id, dept_name_snapshot, dashboard_id, board_status, draft_layout, published_layout, version, published_at) VALUES (10, 1, '视觉验证·运营一部日报', '2026-11-24 16:50:34.242603+08', '2026-11-24 16:43:18.16191+08', '2026-11-24 16:50:34.091812+08', 'department', 3, '运营一部', 'bid_6a4bd2f613f84969', 'draft', '{"theme": "light", "device": "desktop", "widgets": [{"id": "w_01", "grid": {"h": 3, "w": 3, "x": 0, "y": 0}, "type": "kpi", "title": "成交总额", "width": 1, "refresh": "realtime", "data_scope": "company", "metric_key": "GMV", "time_range": "14d"}, {"id": "w_02", "grid": {"h": 3, "w": 3, "x": 3, "y": 0}, "type": "kpi", "title": "订单量", "width": 1, "refresh": "realtime", "data_scope": "department", "metric_key": "ORDER_COUNT", "time_range": "7d"}, {"id": "w_03", "grid": {"h": 3, "w": 6, "x": 6, "y": 0}, "type": "bar", "title": "支付转化率趋势", "width": 2, "refresh": "realtime", "data_scope": "company", "metric_key": "CONVERSION_RATE", "time_range": "14d"}, {"id": "w_04", "grid": {"h": 4, "w": 4, "x": 0, "y": 3}, "type": "donut", "title": "投放产出结构", "width": 1, "refresh": "manual", "data_scope": "company", "metric_key": "AD_ROI", "time_range": "30d"}, {"id": "w_05", "grid": {"h": 4, "w": 8, "x": 4, "y": 3}, "type": "table", "title": "退货明细", "width": 2, "refresh": "manual", "data_scope": "department", "metric_key": "RETURN_RATE", "time_range": "30d"}], "schema_version": 1}', NULL, 2, NULL);
INSERT INTO public.bi_dashboard_designs (id, org_id, dashboard_name, deleted_at, created_at, updated_at, scope_level, dept_id, dept_name_snapshot, dashboard_id, board_status, draft_layout, published_layout, version, published_at) VALUES (11, 1, '设计页冒烟-ece5', '2026-11-24 16:51:45.439284+08', '2026-11-24 16:51:39.178267+08', '2026-11-24 16:51:45.291393+08', 'department', 3, '运营一部', 'bid_fec9a5bf8e424c94', 'draft', '{"theme": "light", "device": "desktop", "widgets": [{"id": "w_01", "grid": {"h": 3, "w": 3, "x": 0, "y": 0}, "type": "kpi", "title": "成交总额", "width": 1, "refresh": "realtime", "data_scope": "company", "metric_key": "GMV", "time_range": "14d"}, {"id": "w_02", "grid": {"h": 3, "w": 9, "x": 3, "y": 0}, "type": "bar", "title": "订单量趋势", "width": 2, "refresh": "realtime", "data_scope": "department", "metric_key": "ORDER_COUNT", "time_range": "7d"}, {"id": "w_03", "grid": {"h": 4, "w": 4, "x": 0, "y": 3}, "type": "donut", "title": "投放产出结构", "width": 1, "refresh": "manual", "data_scope": "company", "metric_key": "AD_ROI", "time_range": "30d"}], "schema_version": 1}', NULL, 2, NULL);
INSERT INTO public.bi_dashboard_designs (id, org_id, dashboard_name, deleted_at, created_at, updated_at, scope_level, dept_id, dept_name_snapshot, dashboard_id, board_status, draft_layout, published_layout, version, published_at) VALUES (12, 1, '临时-节点审批-13ce4b', '2026-11-24 18:21:10.927953+08', '2026-11-24 18:20:57.154038+08', '2026-11-24 18:21:10.729879+08', 'department', 6, '仓储部', 'bid_61ab09b103c0492b', 'draft', '{"theme": "light", "device": "desktop", "widgets": [{"id": "w1", "grid": {"h": 4, "w": 6, "x": 0, "y": 0}, "type": "kpi", "title": "成交额", "width": 1, "refresh": "realtime", "data_scope": "department", "metric_key": "GMV", "time_range": "14d"}], "schema_version": 1}', '{"theme": "light", "device": "desktop", "widgets": [{"id": "w1", "grid": {"h": 4, "w": 6, "x": 0, "y": 0}, "type": "kpi", "title": "成交额", "width": 1, "refresh": "realtime", "data_scope": "department", "metric_key": "GMV", "time_range": "14d"}], "schema_version": 1}', 3, '2026-11-24 18:21:03.72316+08');
INSERT INTO public.bi_dashboard_designs (id, org_id, dashboard_name, deleted_at, created_at, updated_at, scope_level, dept_id, dept_name_snapshot, dashboard_id, board_status, draft_layout, published_layout, version, published_at) VALUES (13, 1, '临时-节点审批-ca81bf', '2026-11-24 18:25:36.761318+08', '2026-11-24 18:25:23.063518+08', '2026-11-24 18:25:36.56984+08', 'department', 6, '仓储部', 'bid_f08892604e044011', 'draft', '{"theme": "light", "device": "desktop", "widgets": [{"id": "w1", "grid": {"h": 4, "w": 6, "x": 0, "y": 0}, "type": "kpi", "title": "成交额", "width": 1, "refresh": "realtime", "data_scope": "department", "metric_key": "GMV", "time_range": "14d"}], "schema_version": 1}', '{"theme": "light", "device": "desktop", "widgets": [{"id": "w1", "grid": {"h": 4, "w": 6, "x": 0, "y": 0}, "type": "kpi", "title": "成交额", "width": 1, "refresh": "realtime", "data_scope": "department", "metric_key": "GMV", "time_range": "14d"}], "schema_version": 1}', 3, '2026-11-24 18:25:29.735938+08');


ALTER TABLE public.bi_dashboard_designs ENABLE TRIGGER ALL;

--
-- Data for Name: bi_dashboard_access_request; Type: TABLE DATA; Schema: public; Owner: -
--

ALTER TABLE public.bi_dashboard_access_request DISABLE TRIGGER ALL;

INSERT INTO public.bi_dashboard_access_request (id, request_no, org_id, dashboard_id, target_dept_id, requester_id, requester_dept_id, reason, status, approver, approve_at, approve_comment, valid_from, valid_to, grant_ref, created_at, updated_at) VALUES (1, 'AR-2026-0001', 1, 'bid_23bfc1503c8f4684', 3, '9', 1, '需要参考一部的日报做二次分析', 'approved', 'ops_analyst_01(#10)', '2026-11-24 16:35:10.360476+08', '同意，限 7 天', '2026-11-24 16:35:10.360476+08', '2026-12-01 16:35:10.360476+08', NULL, '2026-11-24 16:35:07.854517+08', '2026-11-24 16:35:10.360476+08');
INSERT INTO public.bi_dashboard_access_request (id, request_no, org_id, dashboard_id, target_dept_id, requester_id, requester_dept_id, reason, status, approver, approve_at, approve_comment, valid_from, valid_to, grant_ref, created_at, updated_at) VALUES (2, 'AR-2026-0002', 1, 'bid_6968701e73d64e8b', 3, '9', 1, '需要参考一部的日报做二次分析', 'approved', 'ops_analyst_01(#10)', '2026-11-24 16:35:59.072342+08', '同意，限 7 天', '2026-11-24 16:35:59.072342+08', '2026-12-01 16:35:59.072342+08', NULL, '2026-11-24 16:35:56.676969+08', '2026-11-24 16:35:59.072342+08');


ALTER TABLE public.bi_dashboard_access_request ENABLE TRIGGER ALL;

--
-- Data for Name: bi_dashboard_design; Type: TABLE DATA; Schema: public; Owner: -
--

ALTER TABLE public.bi_dashboard_design DISABLE TRIGGER ALL;



ALTER TABLE public.bi_dashboard_design ENABLE TRIGGER ALL;

--
-- Data for Name: bi_operation_log; Type: TABLE DATA; Schema: public; Owner: -
--

ALTER TABLE public.bi_operation_log DISABLE TRIGGER ALL;

INSERT INTO public.bi_operation_log (id, org_id, created_at, scope_level, dept_id, dashboard_id, action, payload, operator, trace_id) VALUES (1, 1, '2026-11-24 16:29:28.299569+08', 'company', NULL, 'bid_e354ce00f490408a', 'save_draft', '{"op": "create", "dashboard_name": "经营总览-smoke"}', 'bi_designer(#8)', '8d5edfdd-291b-4044-814f-d7429e7b7fee');
INSERT INTO public.bi_operation_log (id, org_id, created_at, scope_level, dept_id, dashboard_id, action, payload, operator, trace_id) VALUES (2, 1, '2026-11-24 16:29:29.297877+08', 'company', NULL, 'bid_e354ce00f490408a', 'save_draft', '{"new_version": 2, "widget_count": 2, "previous_version": 1}', 'bi_designer(#8)', 'cab01dd9-abf8-4fb9-9f4d-7dbb42b07613');
INSERT INTO public.bi_operation_log (id, org_id, created_at, scope_level, dept_id, dashboard_id, action, payload, operator, trace_id) VALUES (3, 1, '2026-11-24 16:29:32.520735+08', 'company', NULL, 'bid_e354ce00f490408a', 'delete_draft', '{"dashboard_name": "经营总览-smoke"}', 'bi_designer(#8)', '54f40c01-117c-474f-9078-c0e10a929dc7');
INSERT INTO public.bi_operation_log (id, org_id, created_at, scope_level, dept_id, dashboard_id, action, payload, operator, trace_id) VALUES (4, 1, '2026-11-24 16:29:59.891331+08', 'company', NULL, 'bid_e3a9cd9c98c34129', 'save_draft', '{"op": "create", "dashboard_name": "经营总览-smoke"}', 'bi_designer(#8)', 'c817ad72-beac-4797-a73f-0daccb383c10');
INSERT INTO public.bi_operation_log (id, org_id, created_at, scope_level, dept_id, dashboard_id, action, payload, operator, trace_id) VALUES (5, 1, '2026-11-24 16:30:02.051737+08', 'company', NULL, 'bid_e3a9cd9c98c34129', 'save_draft', '{"new_version": 2, "widget_count": 2, "previous_version": 1}', 'bi_designer(#8)', '9adbf592-8592-41d5-9569-98ebd5dbe615');
INSERT INTO public.bi_operation_log (id, org_id, created_at, scope_level, dept_id, dashboard_id, action, payload, operator, trace_id) VALUES (6, 1, '2026-11-24 16:30:04.188315+08', 'company', NULL, 'bid_e3a9cd9c98c34129', 'delete_draft', '{"dashboard_name": "经营总览-smoke"}', 'bi_designer(#8)', '65ed4975-3b68-427f-827b-5e8c3e257151');
INSERT INTO public.bi_operation_log (id, org_id, created_at, scope_level, dept_id, dashboard_id, action, payload, operator, trace_id) VALUES (7, 1, '2026-11-24 16:30:32.179768+08', 'company', NULL, 'bid_b822c9bb043645c1', 'save_draft', '{"op": "create", "dashboard_name": "经营总览-smoke"}', 'bi_designer(#8)', '723cf94c-b1f5-472b-9484-c7ae6b592955');
INSERT INTO public.bi_operation_log (id, org_id, created_at, scope_level, dept_id, dashboard_id, action, payload, operator, trace_id) VALUES (8, 1, '2026-11-24 16:30:36.388694+08', 'company', NULL, 'bid_b822c9bb043645c1', 'delete_draft', '{"dashboard_name": "经营总览-smoke"}', 'bi_designer(#8)', '05497091-3d7e-45a2-ae18-1395fadc3fe1');
INSERT INTO public.bi_operation_log (id, org_id, created_at, scope_level, dept_id, dashboard_id, action, payload, operator, trace_id) VALUES (9, 1, '2026-11-24 16:30:49.848245+08', 'company', NULL, 'bid_f0a92d0b44604570', 'save_draft', '{"op": "create", "dashboard_name": "lock-test"}', 'bi_designer(#8)', 'ec2b3e08-10a5-419d-8913-054ea94e224a');
INSERT INTO public.bi_operation_log (id, org_id, created_at, scope_level, dept_id, dashboard_id, action, payload, operator, trace_id) VALUES (10, 1, '2026-11-24 16:30:50.511622+08', 'company', NULL, 'bid_f0a92d0b44604570', 'save_draft', '{"new_version": 2, "widget_count": 0, "previous_version": 1}', 'bi_designer(#8)', 'b99cee0e-be48-468f-a3f5-c409cf41548b');
INSERT INTO public.bi_operation_log (id, org_id, created_at, scope_level, dept_id, dashboard_id, action, payload, operator, trace_id) VALUES (11, 1, '2026-11-24 16:31:16.779148+08', 'company', NULL, 'bid_294051dddc2e4d8b', 'save_draft', '{"op": "create", "dashboard_name": "经营总览-4ee86a"}', 'bi_designer(#8)', 'ee7eecf5-63c3-4e06-aaaf-56294c679585');
INSERT INTO public.bi_operation_log (id, org_id, created_at, scope_level, dept_id, dashboard_id, action, payload, operator, trace_id) VALUES (12, 1, '2026-11-24 16:31:17.769548+08', 'company', NULL, 'bid_294051dddc2e4d8b', 'save_draft', '{"new_version": 2, "widget_count": 2, "previous_version": 1}', 'bi_designer(#8)', 'daa4a753-4eea-40ad-ba82-d37b18232172');
INSERT INTO public.bi_operation_log (id, org_id, created_at, scope_level, dept_id, dashboard_id, action, payload, operator, trace_id) VALUES (13, 1, '2026-11-24 16:31:21.226609+08', 'company', NULL, 'bid_294051dddc2e4d8b', 'delete_draft', '{"dashboard_name": "经营总览-4ee86a"}', 'bi_designer(#8)', '96a3ff21-223f-4568-b33b-79c52c5eab61');
INSERT INTO public.bi_operation_log (id, org_id, created_at, scope_level, dept_id, dashboard_id, action, payload, operator, trace_id) VALUES (14, 1, '2026-11-24 16:34:41.809955+08', 'department', 3, 'bid_cff6db1e95114d1b', 'save_draft', '{"op": "create", "dashboard_name": "运营一部日报-d34e41"}', 'bi_designer(#8)', '48144893-0677-4941-b65b-ceb318cc117e');
INSERT INTO public.bi_operation_log (id, org_id, created_at, scope_level, dept_id, dashboard_id, action, payload, operator, trace_id) VALUES (15, 1, '2026-11-24 16:34:42.498428+08', 'department', 3, 'bid_cff6db1e95114d1b', 'save_draft', '{"new_version": 2, "widget_count": 3, "previous_version": 1}', 'bi_designer(#8)', '0832db07-c560-4a43-a841-b878653bc18e');
INSERT INTO public.bi_operation_log (id, org_id, created_at, scope_level, dept_id, dashboard_id, action, payload, operator, trace_id) VALUES (16, 1, '2026-11-24 16:34:43.40845+08', 'department', 3, 'bid_cff6db1e95114d1b', 'submit_publish', '{"flow_id": 1, "node_count": 1, "approval_no": "AP-2026-0001", "flow_version": 1, "target_version": 2}', 'bi_designer(#8)', 'dda66db5-69a4-41a6-b914-a7d2989a107b');
INSERT INTO public.bi_operation_log (id, org_id, created_at, scope_level, dept_id, dashboard_id, action, payload, operator, trace_id) VALUES (17, 1, '2026-11-24 16:34:45.947832+08', 'department', 3, 'bid_cff6db1e95114d1b', 'approve', '{"final": true, "node_seq": 1, "node_name": "BI审核", "approval_no": "AP-2026-0001", "published_version": 2}', 'ops_analyst_01(#10)', '40ca1b47-76a2-4e4e-9bdd-d10dd87b5fd7');
INSERT INTO public.bi_operation_log (id, org_id, created_at, scope_level, dept_id, dashboard_id, action, payload, operator, trace_id) VALUES (18, 1, '2026-11-24 16:35:00.258498+08', 'department', 3, 'bid_23bfc1503c8f4684', 'save_draft', '{"op": "create", "dashboard_name": "运营一部日报-ffef5a"}', 'bi_designer(#8)', 'c0a9f8ce-5f52-4350-8e00-cf10b9ccdd6c');
INSERT INTO public.bi_operation_log (id, org_id, created_at, scope_level, dept_id, dashboard_id, action, payload, operator, trace_id) VALUES (19, 1, '2026-11-24 16:35:00.914766+08', 'department', 3, 'bid_23bfc1503c8f4684', 'save_draft', '{"new_version": 2, "widget_count": 3, "previous_version": 1}', 'bi_designer(#8)', '49cfa8b1-ee31-41ff-8f16-0697aea537b9');
INSERT INTO public.bi_operation_log (id, org_id, created_at, scope_level, dept_id, dashboard_id, action, payload, operator, trace_id) VALUES (20, 1, '2026-11-24 16:35:01.614051+08', 'department', 3, 'bid_23bfc1503c8f4684', 'submit_publish', '{"flow_id": 1, "node_count": 1, "approval_no": "AP-2026-0002", "flow_version": 1, "target_version": 2}', 'bi_designer(#8)', '230adfca-5e07-4654-99cb-40659304e6a9');
INSERT INTO public.bi_operation_log (id, org_id, created_at, scope_level, dept_id, dashboard_id, action, payload, operator, trace_id) VALUES (21, 1, '2026-11-24 16:35:04.107196+08', 'department', 3, 'bid_23bfc1503c8f4684', 'approve', '{"final": true, "node_seq": 1, "node_name": "BI审核", "approval_no": "AP-2026-0002", "published_version": 2}', 'ops_analyst_01(#10)', 'dd107403-1a7f-492a-8292-10b09ff06766');
INSERT INTO public.bi_operation_log (id, org_id, created_at, scope_level, dept_id, dashboard_id, action, payload, operator, trace_id) VALUES (22, 1, '2026-11-24 16:35:07.854517+08', 'department', 3, 'bid_23bfc1503c8f4684', 'access_submit', '{"reason": "需要参考一部的日报做二次分析", "request_no": "AR-2026-0001"}', 'bi_viewer(#9)', '64f540ec-c2f3-4b40-a445-a2e56006893d');
INSERT INTO public.bi_operation_log (id, org_id, created_at, scope_level, dept_id, dashboard_id, action, payload, operator, trace_id) VALUES (23, 1, '2026-11-24 16:35:10.094341+08', 'department', 3, 'bid_23bfc1503c8f4684', 'access_approve', '{"comment": "同意，限 7 天", "approved": true, "valid_to": "2026-12-01T08:35:10.360476+00:00", "request_no": "AR-2026-0001"}', 'ops_analyst_01(#10)', '40b59f1c-5822-429b-b2eb-0a4dd916afd4');
INSERT INTO public.bi_operation_log (id, org_id, created_at, scope_level, dept_id, dashboard_id, action, payload, operator, trace_id) VALUES (24, 1, '2026-11-24 16:35:12.343661+08', 'department', 3, NULL, 'flow_config', '{"op": "create", "nodes": [{"seq": 1, "name": "部门负责人初审", "node_mode": "any", "approver_ref": null, "approver_type": "dept_leader"}, {"seq": 2, "name": "公司负责人复审", "node_mode": "any", "approver_ref": "bi:dashboard:publish", "approver_type": "role"}], "flow_id": 2}', 'admin(#1)', '243c3032-3481-495a-9003-2034aad8b9b3');
INSERT INTO public.bi_operation_log (id, org_id, created_at, scope_level, dept_id, dashboard_id, action, payload, operator, trace_id) VALUES (25, 1, '2026-11-24 16:35:13.00942+08', 'department', 3, NULL, 'flow_config', '{"op": "update", "nodes": [{"seq": 1, "name": "部门负责人审核", "node_mode": "any", "approver_ref": null, "approver_type": "dept_leader"}], "flow_id": 2, "new_version": 2, "old_version": 1}', 'admin(#1)', '88b02853-12aa-4321-a08f-da6d97f7b184');
INSERT INTO public.bi_operation_log (id, org_id, created_at, scope_level, dept_id, dashboard_id, action, payload, operator, trace_id) VALUES (26, 1, '2026-11-24 16:35:49.081865+08', 'department', 3, 'bid_6968701e73d64e8b', 'save_draft', '{"op": "create", "dashboard_name": "运营一部日报-6ed5aa"}', 'bi_designer(#8)', '4fadead3-eb83-4da9-85ce-8f842f848ac5');
INSERT INTO public.bi_operation_log (id, org_id, created_at, scope_level, dept_id, dashboard_id, action, payload, operator, trace_id) VALUES (27, 1, '2026-11-24 16:35:49.731691+08', 'department', 3, 'bid_6968701e73d64e8b', 'save_draft', '{"new_version": 2, "widget_count": 3, "previous_version": 1}', 'bi_designer(#8)', '722d925e-0006-4504-9ace-9e62c87088a2');
INSERT INTO public.bi_operation_log (id, org_id, created_at, scope_level, dept_id, dashboard_id, action, payload, operator, trace_id) VALUES (28, 1, '2026-11-24 16:35:50.615353+08', 'department', 3, 'bid_6968701e73d64e8b', 'submit_publish', '{"flow_id": 2, "node_count": 1, "approval_no": "AP-2026-0003", "flow_version": 2, "target_version": 2}', 'bi_designer(#8)', '4942c77b-8e5c-4345-9bf5-55c26f9f60e0');
INSERT INTO public.bi_operation_log (id, org_id, created_at, scope_level, dept_id, dashboard_id, action, payload, operator, trace_id) VALUES (29, 1, '2026-11-24 16:35:52.895648+08', 'department', 3, 'bid_6968701e73d64e8b', 'approve', '{"final": true, "node_seq": 1, "node_name": "部门负责人审核", "approval_no": "AP-2026-0003", "published_version": 2}', 'ops_analyst_01(#10)', 'e97d7602-7af8-41ad-9f10-a59ac4d10a64');
INSERT INTO public.bi_operation_log (id, org_id, created_at, scope_level, dept_id, dashboard_id, action, payload, operator, trace_id) VALUES (30, 1, '2026-11-24 16:35:56.676969+08', 'department', 3, 'bid_6968701e73d64e8b', 'access_submit', '{"reason": "需要参考一部的日报做二次分析", "request_no": "AR-2026-0002"}', 'bi_viewer(#9)', '911d2e7f-5665-49b6-a368-74910f750381');
INSERT INTO public.bi_operation_log (id, org_id, created_at, scope_level, dept_id, dashboard_id, action, payload, operator, trace_id) VALUES (31, 1, '2026-11-24 16:35:58.826713+08', 'department', 3, 'bid_6968701e73d64e8b', 'access_approve', '{"comment": "同意，限 7 天", "approved": true, "valid_to": "2026-12-01T08:35:59.072342+00:00", "request_no": "AR-2026-0002"}', 'ops_analyst_01(#10)', 'cba6d22b-fc8b-4e26-8b28-c5beb35f4882');
INSERT INTO public.bi_operation_log (id, org_id, created_at, scope_level, dept_id, dashboard_id, action, payload, operator, trace_id) VALUES (32, 1, '2026-11-24 16:42:38.152575+08', 'department', 3, 'bid_5f395a80cf81431c', 'save_draft', '{"op": "create", "dashboard_name": "设计页冒烟-668a"}', 'bi_designer(#8)', 'e61ea899-a662-4406-ac9a-f9b5d9a65282');
INSERT INTO public.bi_operation_log (id, org_id, created_at, scope_level, dept_id, dashboard_id, action, payload, operator, trace_id) VALUES (33, 1, '2026-11-24 16:42:39.593767+08', 'department', 3, 'bid_5f395a80cf81431c', 'save_draft', '{"new_version": 2, "widget_count": 3, "previous_version": 1}', 'bi_designer(#8)', '9614cb67-8680-4f16-82cd-694888e81b23');
INSERT INTO public.bi_operation_log (id, org_id, created_at, scope_level, dept_id, dashboard_id, action, payload, operator, trace_id) VALUES (34, 1, '2026-11-24 16:42:42.05723+08', 'department', 3, 'bid_5f395a80cf81431c', 'submit_publish', '{"flow_id": 2, "node_count": 1, "approval_no": "AP-2026-0004", "flow_version": 2, "target_version": 2}', 'bi_designer(#8)', '741a5328-0ddc-4a07-8af0-de12a818c2cb');
INSERT INTO public.bi_operation_log (id, org_id, created_at, scope_level, dept_id, dashboard_id, action, payload, operator, trace_id) VALUES (35, 1, '2026-11-24 16:42:43.93013+08', 'department', 3, 'bid_5f395a80cf81431c', 'reject', '{"comment": "冒烟清理", "approval_no": "AP-2026-0004"}', 'ops_analyst_01(#10)', 'ff3e91b2-1ff7-44b1-bd23-f0cecf162b2f');
INSERT INTO public.bi_operation_log (id, org_id, created_at, scope_level, dept_id, dashboard_id, action, payload, operator, trace_id) VALUES (36, 1, '2026-11-24 16:42:44.75913+08', 'department', 3, 'bid_5f395a80cf81431c', 'delete_draft', '{"dashboard_name": "设计页冒烟-668a"}', 'bi_designer(#8)', '7d6dc049-e165-485a-a888-fea45c9541b0');
INSERT INTO public.bi_operation_log (id, org_id, created_at, scope_level, dept_id, dashboard_id, action, payload, operator, trace_id) VALUES (37, 1, '2026-11-24 16:43:18.16191+08', 'department', 3, 'bid_6a4bd2f613f84969', 'save_draft', '{"op": "create", "dashboard_name": "视觉验证·运营一部日报"}', 'bi_designer(#8)', '2d8d8351-1151-495a-93da-d2ffb77bda84');
INSERT INTO public.bi_operation_log (id, org_id, created_at, scope_level, dept_id, dashboard_id, action, payload, operator, trace_id) VALUES (38, 1, '2026-11-24 16:43:18.819466+08', 'department', 3, 'bid_6a4bd2f613f84969', 'save_draft', '{"new_version": 2, "widget_count": 5, "previous_version": 1}', 'bi_designer(#8)', '7e7063e5-d4c4-4cf9-9e0a-e8550fb515fe');
INSERT INTO public.bi_operation_log (id, org_id, created_at, scope_level, dept_id, dashboard_id, action, payload, operator, trace_id) VALUES (39, 1, '2026-11-24 16:50:34.091812+08', 'department', 3, 'bid_6a4bd2f613f84969', 'delete_draft', '{"dashboard_name": "视觉验证·运营一部日报"}', 'bi_designer(#8)', '3a76dac0-a339-4235-b344-3e905d80b6eb');
INSERT INTO public.bi_operation_log (id, org_id, created_at, scope_level, dept_id, dashboard_id, action, payload, operator, trace_id) VALUES (40, 1, '2026-11-24 16:50:34.666476+08', 'company', NULL, 'bid_f0a92d0b44604570', 'delete_draft', '{"dashboard_name": "lock-test"}', 'bi_designer(#8)', 'd90d5aa4-de5c-4c6c-8b1e-7dbc5c3a44ab');
INSERT INTO public.bi_operation_log (id, org_id, created_at, scope_level, dept_id, dashboard_id, action, payload, operator, trace_id) VALUES (41, 1, '2026-11-24 16:51:39.178267+08', 'department', 3, 'bid_fec9a5bf8e424c94', 'save_draft', '{"op": "create", "dashboard_name": "设计页冒烟-ece5"}', 'bi_designer(#8)', '5aef87fd-c469-4121-a504-8b5b4f88cb9c');
INSERT INTO public.bi_operation_log (id, org_id, created_at, scope_level, dept_id, dashboard_id, action, payload, operator, trace_id) VALUES (42, 1, '2026-11-24 16:51:40.530923+08', 'department', 3, 'bid_fec9a5bf8e424c94', 'save_draft', '{"new_version": 2, "widget_count": 3, "previous_version": 1}', 'bi_designer(#8)', 'c6fa7dac-dcd4-4f39-a611-08adbaefdad8');
INSERT INTO public.bi_operation_log (id, org_id, created_at, scope_level, dept_id, dashboard_id, action, payload, operator, trace_id) VALUES (43, 1, '2026-11-24 16:51:42.867923+08', 'department', 3, 'bid_fec9a5bf8e424c94', 'submit_publish', '{"flow_id": 2, "node_count": 1, "approval_no": "AP-2026-0005", "flow_version": 2, "target_version": 2}', 'bi_designer(#8)', 'd76c6c8f-4161-43e7-b5b8-35cb04e162e9');
INSERT INTO public.bi_operation_log (id, org_id, created_at, scope_level, dept_id, dashboard_id, action, payload, operator, trace_id) VALUES (44, 1, '2026-11-24 16:51:44.581227+08', 'department', 3, 'bid_fec9a5bf8e424c94', 'reject', '{"comment": "冒烟清理", "approval_no": "AP-2026-0005"}', 'ops_analyst_01(#10)', '42dcccc9-3c11-4c34-bf7a-9285843a7560');
INSERT INTO public.bi_operation_log (id, org_id, created_at, scope_level, dept_id, dashboard_id, action, payload, operator, trace_id) VALUES (45, 1, '2026-11-24 16:51:45.291393+08', 'department', 3, 'bid_fec9a5bf8e424c94', 'delete_draft', '{"dashboard_name": "设计页冒烟-ece5"}', 'bi_designer(#8)', '146ed398-cb1b-4103-9a04-96e6ec1f1db9');
INSERT INTO public.bi_operation_log (id, org_id, created_at, scope_level, dept_id, dashboard_id, action, payload, operator, trace_id) VALUES (145, 1, '2026-11-24 20:45:54.075517+08', 'department', 1, NULL, 'flow_config', '{"op": "create", "nodes": [{"seq": 1, "name": "指定审批人", "node_mode": "any", "approver_ref": "8", "approver_type": "specific_user"}], "flow_id": 10}', 'admin(#1)', 'bba1c65c-086d-4074-a191-dbfba6fb06c3');
INSERT INTO public.bi_operation_log (id, org_id, created_at, scope_level, dept_id, dashboard_id, action, payload, operator, trace_id) VALUES (47, 1, '2026-11-24 18:20:57.824829+08', 'department', 6, 'bid_61ab09b103c0492b', 'save_draft', '{"new_version": 2, "widget_count": 1, "previous_version": 1}', 'admin(#1)', '9a636a81-6b7d-48ae-a134-61c7f6d8b952');
INSERT INTO public.bi_operation_log (id, org_id, created_at, scope_level, dept_id, dashboard_id, action, payload, operator, trace_id) VALUES (48, 1, '2026-11-24 18:20:58.706745+08', 'department', 6, NULL, 'flow_config', '{"op": "create", "nodes": [{"seq": 1, "name": "指定人审", "node_mode": "any", "approver_ref": "12", "approver_type": "specific_user"}, {"seq": 2, "name": "角色审", "node_mode": "any", "approver_ref": "BI_DESIGNER", "approver_type": "role"}], "flow_id": 5}', 'admin(#1)', '16aa1bd4-cd68-43f9-ad19-9408a423c66c');
INSERT INTO public.bi_operation_log (id, org_id, created_at, scope_level, dept_id, dashboard_id, action, payload, operator, trace_id) VALUES (49, 1, '2026-11-24 18:21:00.428564+08', 'department', 6, 'bid_61ab09b103c0492b', 'submit_publish', '{"flow_id": 5, "node_count": 2, "approval_no": "AP-2026-0006", "flow_version": 1, "target_version": 2}', 'admin(#1)', 'bdec91fd-a968-4b55-bc43-8b5bdcfdc619');
INSERT INTO public.bi_operation_log (id, org_id, created_at, scope_level, dept_id, dashboard_id, action, payload, operator, trace_id) VALUES (50, 1, '2026-11-24 18:21:01.948307+08', 'department', 6, 'bid_61ab09b103c0492b', 'approve', '{"final": false, "node_seq": 1, "node_name": "指定人审", "approval_no": "AP-2026-0006"}', 'metric_admin(#12)', '8e2af028-7607-4232-9e9d-3fc57d9ab9ea');
INSERT INTO public.bi_operation_log (id, org_id, created_at, scope_level, dept_id, dashboard_id, action, payload, operator, trace_id) VALUES (51, 1, '2026-11-24 18:21:03.311786+08', 'department', 6, 'bid_61ab09b103c0492b', 'approve', '{"final": true, "node_seq": 2, "node_name": "角色审", "approval_no": "AP-2026-0006", "published_version": 2}', 'bi_designer(#8)', '0005c8c7-6980-4de1-bcdf-966ed91875eb');
INSERT INTO public.bi_operation_log (id, org_id, created_at, scope_level, dept_id, dashboard_id, action, payload, operator, trace_id) VALUES (53, 1, '2026-11-24 18:21:10.046915+08', 'department', 6, 'bid_61ab09b103c0492b', 'save_draft', '{"new_version": 3, "widget_count": 1, "previous_version": 2}', 'admin(#1)', '320ffd28-57f7-4bca-8fb2-ed9f7c573f4c');
INSERT INTO public.bi_operation_log (id, org_id, created_at, scope_level, dept_id, dashboard_id, action, payload, operator, trace_id) VALUES (232, 1, '2026-11-24 20:52:12.039962+08', 'department', 1, NULL, 'flow_config', '{"op": "create", "nodes": [{"seq": 1, "name": "指定审批人", "node_mode": "any", "approver_ref": "8", "approver_type": "specific_user"}], "flow_id": 14}', 'admin(#1)', '09ea9274-62f5-4a6a-b663-09c298456ed4');
INSERT INTO public.bi_operation_log (id, org_id, created_at, scope_level, dept_id, dashboard_id, action, payload, operator, trace_id) VALUES (56, 1, '2026-11-24 18:25:23.781042+08', 'department', 6, 'bid_f08892604e044011', 'save_draft', '{"new_version": 2, "widget_count": 1, "previous_version": 1}', 'admin(#1)', '6df26a90-8438-4acf-9a7c-e7e439fbb303');
INSERT INTO public.bi_operation_log (id, org_id, created_at, scope_level, dept_id, dashboard_id, action, payload, operator, trace_id) VALUES (57, 1, '2026-11-24 18:25:24.657236+08', 'department', 6, NULL, 'flow_config', '{"op": "create", "nodes": [{"seq": 1, "name": "指定人审", "node_mode": "any", "approver_ref": "12", "approver_type": "specific_user"}, {"seq": 2, "name": "角色审", "node_mode": "any", "approver_ref": "BI_DESIGNER", "approver_type": "role"}], "flow_id": 6}', 'admin(#1)', 'ea738aef-0b24-4557-975f-beabb236b7a3');
INSERT INTO public.bi_operation_log (id, org_id, created_at, scope_level, dept_id, dashboard_id, action, payload, operator, trace_id) VALUES (58, 1, '2026-11-24 18:25:26.384595+08', 'department', 6, 'bid_f08892604e044011', 'submit_publish', '{"flow_id": 6, "node_count": 2, "approval_no": "AP-2026-0006", "flow_version": 1, "target_version": 2}', 'admin(#1)', 'faf8dc63-75a5-476b-8b9e-397e6598a138');
INSERT INTO public.bi_operation_log (id, org_id, created_at, scope_level, dept_id, dashboard_id, action, payload, operator, trace_id) VALUES (59, 1, '2026-11-24 18:25:27.941923+08', 'department', 6, 'bid_f08892604e044011', 'approve', '{"final": false, "node_seq": 1, "node_name": "指定人审", "approval_no": "AP-2026-0006"}', 'metric_admin(#12)', '9b6fe4d3-61e4-4347-9fc6-ab1866fdf5bb');
INSERT INTO public.bi_operation_log (id, org_id, created_at, scope_level, dept_id, dashboard_id, action, payload, operator, trace_id) VALUES (60, 1, '2026-11-24 18:25:29.335619+08', 'department', 6, 'bid_f08892604e044011', 'approve', '{"final": true, "node_seq": 2, "node_name": "角色审", "approval_no": "AP-2026-0006", "published_version": 2}', 'bi_designer(#8)', 'b08ab681-7118-4a42-b5f3-9838806af0a8');
INSERT INTO public.bi_operation_log (id, org_id, created_at, scope_level, dept_id, dashboard_id, action, payload, operator, trace_id) VALUES (62, 1, '2026-11-24 18:25:35.913898+08', 'department', 6, 'bid_f08892604e044011', 'save_draft', '{"new_version": 3, "widget_count": 1, "previous_version": 2}', 'admin(#1)', '6fcfadd6-c6a4-423a-8c92-970ad084be2d');
INSERT INTO public.bi_operation_log (id, org_id, created_at, scope_level, dept_id, dashboard_id, action, payload, operator, trace_id) VALUES (69, 1, '2026-11-24 20:32:47.307856+08', 'department', 1, NULL, 'flow_config', '{"op": "create", "nodes": [{"seq": 1, "name": "一级", "node_mode": "any", "approver_ref": null, "approver_type": "dept_leader"}, {"seq": 2, "name": "二级", "node_mode": "any", "approver_ref": null, "approver_type": "dept_leader"}], "flow_id": 7}', 'admin(#1)', '530ab76f-05f9-4076-b91a-4345e5ac4443');
INSERT INTO public.bi_operation_log (id, org_id, created_at, scope_level, dept_id, dashboard_id, action, payload, operator, trace_id) VALUES (73, 1, '2026-11-24 20:32:50.369002+08', 'department', 1, NULL, 'flow_config', '{"op": "update", "nodes": [{"seq": 1, "name": "唯一级", "node_mode": "any", "approver_ref": null, "approver_type": "dept_leader"}], "flow_id": 7, "new_version": 2, "old_version": 1}', 'admin(#1)', '493411c1-3cd6-4622-9723-c1bf0facf4f5');
INSERT INTO public.bi_operation_log (id, org_id, created_at, scope_level, dept_id, dashboard_id, action, payload, operator, trace_id) VALUES (94, 1, '2026-11-24 20:33:39.425519+08', 'department', 1, NULL, 'flow_config', '{"op": "create", "nodes": [{"seq": 1, "name": "一级", "node_mode": "any", "approver_ref": null, "approver_type": "dept_leader"}, {"seq": 2, "name": "二级", "node_mode": "any", "approver_ref": null, "approver_type": "dept_leader"}], "flow_id": 8}', 'admin(#1)', '20acb00f-4cc9-4100-8ca9-bb82857d6fe8');
INSERT INTO public.bi_operation_log (id, org_id, created_at, scope_level, dept_id, dashboard_id, action, payload, operator, trace_id) VALUES (98, 1, '2026-11-24 20:33:42.410452+08', 'department', 1, NULL, 'flow_config', '{"op": "update", "nodes": [{"seq": 1, "name": "唯一级", "node_mode": "any", "approver_ref": null, "approver_type": "dept_leader"}], "flow_id": 8, "new_version": 2, "old_version": 1}', 'admin(#1)', '7c7309ee-a1fd-4353-b970-32d080e961dc');
INSERT INTO public.bi_operation_log (id, org_id, created_at, scope_level, dept_id, dashboard_id, action, payload, operator, trace_id) VALUES (213, 1, '2026-11-24 20:51:06.140915+08', 'department', 1, NULL, 'flow_config', '{"op": "create", "nodes": [{"seq": 1, "name": "指定审批人", "node_mode": "any", "approver_ref": "8", "approver_type": "specific_user"}], "flow_id": 13}', 'admin(#1)', '11f9a388-733d-46a9-bbe1-c79e128539ae');
INSERT INTO public.bi_operation_log (id, org_id, created_at, scope_level, dept_id, dashboard_id, action, payload, operator, trace_id) VALUES (261, 1, '2026-11-24 20:57:47.503646+08', 'department', 1, NULL, 'flow_config', '{"op": "create", "nodes": [{"seq": 1, "name": "一级", "node_mode": "any", "approver_ref": null, "approver_type": "dept_leader"}, {"seq": 2, "name": "二级", "node_mode": "any", "approver_ref": null, "approver_type": "dept_leader"}], "flow_id": 15}', 'admin(#1)', '0d4f95b6-fbc0-4ffe-be08-dc48d41eae46');
INSERT INTO public.bi_operation_log (id, org_id, created_at, scope_level, dept_id, dashboard_id, action, payload, operator, trace_id) VALUES (265, 1, '2026-11-24 20:57:50.402827+08', 'department', 1, NULL, 'flow_config', '{"op": "update", "nodes": [{"seq": 1, "name": "唯一级", "node_mode": "any", "approver_ref": null, "approver_type": "dept_leader"}], "flow_id": 15, "new_version": 2, "old_version": 1}', 'admin(#1)', '904b283c-2b78-4940-8881-99ccdf12e137');
INSERT INTO public.bi_operation_log (id, org_id, created_at, scope_level, dept_id, dashboard_id, action, payload, operator, trace_id) VALUES (121, 1, '2026-11-24 20:34:19.504041+08', 'department', 1, NULL, 'flow_config', '{"op": "create", "nodes": [{"seq": 1, "name": "一级", "node_mode": "any", "approver_ref": null, "approver_type": "dept_leader"}, {"seq": 2, "name": "二级", "node_mode": "any", "approver_ref": null, "approver_type": "dept_leader"}], "flow_id": 9}', 'admin(#1)', 'aec3116f-b390-493f-851e-7e77c6e61ce3');
INSERT INTO public.bi_operation_log (id, org_id, created_at, scope_level, dept_id, dashboard_id, action, payload, operator, trace_id) VALUES (125, 1, '2026-11-24 20:34:22.423653+08', 'department', 1, NULL, 'flow_config', '{"op": "update", "nodes": [{"seq": 1, "name": "唯一级", "node_mode": "any", "approver_ref": null, "approver_type": "dept_leader"}], "flow_id": 9, "new_version": 2, "old_version": 1}', 'admin(#1)', '28977191-5637-4d82-8c6e-ba0bd0057c04');
INSERT INTO public.bi_operation_log (id, org_id, created_at, scope_level, dept_id, dashboard_id, action, payload, operator, trace_id) VALUES (167, 1, '2026-11-24 20:48:55.028217+08', 'department', 1, NULL, 'flow_config', '{"op": "create", "nodes": [{"seq": 1, "name": "指定审批人", "node_mode": "any", "approver_ref": "8", "approver_type": "specific_user"}], "flow_id": 11}', 'admin(#1)', 'ae346e0e-e28c-48da-9949-2090851b38b1');
INSERT INTO public.bi_operation_log (id, org_id, created_at, scope_level, dept_id, dashboard_id, action, payload, operator, trace_id) VALUES (190, 1, '2026-11-24 20:49:59.092904+08', 'department', 1, NULL, 'flow_config', '{"op": "create", "nodes": [{"seq": 1, "name": "指定审批人", "node_mode": "any", "approver_ref": "8", "approver_type": "specific_user"}], "flow_id": 12}', 'admin(#1)', '2cf24977-33c5-4812-b02d-4a1c24439876');


ALTER TABLE public.bi_operation_log ENABLE TRIGGER ALL;

--
-- Data for Name: bi_publish_approvals; Type: TABLE DATA; Schema: public; Owner: -
--

ALTER TABLE public.bi_publish_approvals DISABLE TRIGGER ALL;

INSERT INTO public.bi_publish_approvals (id, org_id, dashboard_id, status, created_at, scope_level, dept_id, flow_id, flow_version, current_node_seq, submitter_scope_snapshot, approval_no, target_version, type, submitter, submit_at, reviewer, review_at, comment, updated_at) VALUES (1, 1, 'bid_cff6db1e95114d1b', 'approved', '2026-11-24 16:34:43.40845+08', 'department', 3, 1, 1, 1, '{"remark": null, "dept_id": 3, "flow_source": "global_default", "scope_level": "department", "widget_count": 3, "approver_name": "张运营", "approver_dept_id": 3, "approver_user_id": 10, "dept_name_snapshot": "运营一部"}', 'AP-2026-0001', 2, 'new_board', 'bi_designer(#8)', '2026-11-24 16:34:43.855733+08', 'ops_analyst_01(#10)', '2026-11-24 16:34:46.330938+08', '同意发布', '2026-11-24 16:34:46.330938+08');
INSERT INTO public.bi_publish_approvals (id, org_id, dashboard_id, status, created_at, scope_level, dept_id, flow_id, flow_version, current_node_seq, submitter_scope_snapshot, approval_no, target_version, type, submitter, submit_at, reviewer, review_at, comment, updated_at) VALUES (2, 1, 'bid_23bfc1503c8f4684', 'approved', '2026-11-24 16:35:01.614051+08', 'department', 3, 1, 1, 1, '{"remark": null, "dept_id": 3, "flow_source": "global_default", "scope_level": "department", "widget_count": 3, "approver_name": "张运营", "approver_dept_id": 3, "approver_user_id": 10, "dept_name_snapshot": "运营一部"}', 'AP-2026-0002', 2, 'new_board', 'bi_designer(#8)', '2026-11-24 16:35:02.065338+08', 'ops_analyst_01(#10)', '2026-11-24 16:35:04.415477+08', '同意发布', '2026-11-24 16:35:04.415477+08');
INSERT INTO public.bi_publish_approvals (id, org_id, dashboard_id, status, created_at, scope_level, dept_id, flow_id, flow_version, current_node_seq, submitter_scope_snapshot, approval_no, target_version, type, submitter, submit_at, reviewer, review_at, comment, updated_at) VALUES (3, 1, 'bid_6968701e73d64e8b', 'approved', '2026-11-24 16:35:50.615353+08', 'department', 3, 2, 2, 1, '{"remark": null, "dept_id": 3, "flow_source": "org", "scope_level": "department", "widget_count": 3, "approver_name": "张运营", "approver_dept_id": 3, "approver_user_id": 10, "dept_name_snapshot": "运营一部"}', 'AP-2026-0003', 2, 'new_board', 'bi_designer(#8)', '2026-11-24 16:35:50.947116+08', 'ops_analyst_01(#10)', '2026-11-24 16:35:53.179878+08', '同意发布', '2026-11-24 16:35:53.179878+08');
INSERT INTO public.bi_publish_approvals (id, org_id, dashboard_id, status, created_at, scope_level, dept_id, flow_id, flow_version, current_node_seq, submitter_scope_snapshot, approval_no, target_version, type, submitter, submit_at, reviewer, review_at, comment, updated_at) VALUES (4, 1, 'bid_5f395a80cf81431c', 'rejected', '2026-11-24 16:42:42.05723+08', 'department', 3, 2, 2, 1, '{"remark": "设计页冒烟", "dept_id": 3, "flow_source": "org", "scope_level": "department", "widget_count": 3, "approver_name": "张运营", "approver_dept_id": 3, "approver_user_id": 10, "dept_name_snapshot": "运营一部"}', 'AP-2026-0004', 2, 'new_board', 'bi_designer(#8)', '2026-11-24 16:42:42.423189+08', 'ops_analyst_01(#10)', '2026-11-24 16:42:44.279164+08', '冒烟清理', '2026-11-24 16:42:44.279164+08');
INSERT INTO public.bi_publish_approvals (id, org_id, dashboard_id, status, created_at, scope_level, dept_id, flow_id, flow_version, current_node_seq, submitter_scope_snapshot, approval_no, target_version, type, submitter, submit_at, reviewer, review_at, comment, updated_at) VALUES (5, 1, 'bid_fec9a5bf8e424c94', 'rejected', '2026-11-24 16:51:42.867923+08', 'department', 3, 2, 2, 1, '{"remark": "设计页冒烟", "dept_id": 3, "flow_source": "org", "scope_level": "department", "widget_count": 3, "approver_name": "张运营", "approver_dept_id": 3, "approver_user_id": 10, "dept_name_snapshot": "运营一部"}', 'AP-2026-0005', 2, 'new_board', 'bi_designer(#8)', '2026-11-24 16:51:43.22374+08', 'ops_analyst_01(#10)', '2026-11-24 16:51:44.852094+08', '冒烟清理', '2026-11-24 16:51:44.852094+08');


ALTER TABLE public.bi_publish_approvals ENABLE TRIGGER ALL;

--
-- Data for Name: biz_department_closure; Type: TABLE DATA; Schema: public; Owner: -
--

ALTER TABLE public.biz_department_closure DISABLE TRIGGER ALL;

INSERT INTO public.biz_department_closure (org_id, ancestor_id, descendant_id, depth) VALUES (1, 1, 1, 0);
INSERT INTO public.biz_department_closure (org_id, ancestor_id, descendant_id, depth) VALUES (1, 2, 2, 0);
INSERT INTO public.biz_department_closure (org_id, ancestor_id, descendant_id, depth) VALUES (1, 3, 3, 0);
INSERT INTO public.biz_department_closure (org_id, ancestor_id, descendant_id, depth) VALUES (1, 4, 4, 0);
INSERT INTO public.biz_department_closure (org_id, ancestor_id, descendant_id, depth) VALUES (1, 5, 5, 0);
INSERT INTO public.biz_department_closure (org_id, ancestor_id, descendant_id, depth) VALUES (1, 6, 6, 0);
INSERT INTO public.biz_department_closure (org_id, ancestor_id, descendant_id, depth) VALUES (1, 7, 7, 0);
INSERT INTO public.biz_department_closure (org_id, ancestor_id, descendant_id, depth) VALUES (1, 1, 7, 1);
INSERT INTO public.biz_department_closure (org_id, ancestor_id, descendant_id, depth) VALUES (1, 1, 6, 1);
INSERT INTO public.biz_department_closure (org_id, ancestor_id, descendant_id, depth) VALUES (1, 1, 5, 1);
INSERT INTO public.biz_department_closure (org_id, ancestor_id, descendant_id, depth) VALUES (1, 1, 2, 1);
INSERT INTO public.biz_department_closure (org_id, ancestor_id, descendant_id, depth) VALUES (1, 2, 4, 1);
INSERT INTO public.biz_department_closure (org_id, ancestor_id, descendant_id, depth) VALUES (1, 2, 3, 1);
INSERT INTO public.biz_department_closure (org_id, ancestor_id, descendant_id, depth) VALUES (1, 1, 4, 2);
INSERT INTO public.biz_department_closure (org_id, ancestor_id, descendant_id, depth) VALUES (1, 1, 3, 2);


ALTER TABLE public.biz_department_closure ENABLE TRIGGER ALL;

--
-- Data for Name: sys_user; Type: TABLE DATA; Schema: public; Owner: -
--

ALTER TABLE public.sys_user DISABLE TRIGGER ALL;

INSERT INTO public.sys_user (id, org_id, dept_id, username, password_hash, real_name, email, phone, data_scope, status, last_login_at, created_at, updated_at, created_by, updated_by, deleted) VALUES (4, 1, 7, 'mock_buyer', '$argon2id$v=19$m=65536,t=3,p=4$FtL3KnuqhlCVZnVfZyaAwg$mP7rGkMjprfNFec6kv+sUJgyhaknXNmVnWUZQ4vfB9A', '演示买家', 'mock_buyer@company.com', '13800138002', 'SELF', 'ENABLED', NULL, '2026-11-23 20:32:56.747365', '2026-11-23 23:58:36.893526', NULL, NULL, false);
INSERT INTO public.sys_user (id, org_id, dept_id, username, password_hash, real_name, email, phone, data_scope, status, last_login_at, created_at, updated_at, created_by, updated_by, deleted) VALUES (5, 1, 7, 'customer_service', '$argon2id$v=19$m=65536,t=3,p=4$3tbwUOKgEqP412RPiDUPOg$pbs4325xc3UUq/SfbgFEmUnKOjWYeKhKZrLVSg8yCnA', '客服专员', 'customer_service@company.com', '13800138003', 'SELF', 'ENABLED', NULL, '2026-11-23 20:32:56.747365', '2026-11-23 23:58:36.893526', NULL, NULL, false);
INSERT INTO public.sys_user (id, org_id, dept_id, username, password_hash, real_name, email, phone, data_scope, status, last_login_at, created_at, updated_at, created_by, updated_by, deleted) VALUES (6, 1, 7, 'after_sales', '$argon2id$v=19$m=65536,t=3,p=4$mSz9gVefS3NapCsUIXE5fQ$8Qs3k45pqvD7V3i1G+rguO3fnVsopN0Ebh11gGxJIe8', '售后专员', 'after_sales@company.com', '13800138004', 'SELF', 'ENABLED', NULL, '2026-11-23 20:32:56.747365', '2026-11-23 23:58:36.893526', NULL, NULL, false);
INSERT INTO public.sys_user (id, org_id, dept_id, username, password_hash, real_name, email, phone, data_scope, status, last_login_at, created_at, updated_at, created_by, updated_by, deleted) VALUES (7, 1, 7, 'after_sales_mgr', '$argon2id$v=19$m=65536,t=3,p=4$udNa9b44z2QnzOAE/vgtDQ$mAg2GFcdLgU1+TMoxUlH1f2kgNwu50BG31tXFN/sOAw', '赵客服', 'after_sales_mgr@company.com', '13800138005', 'SELF', 'ENABLED', NULL, '2026-11-23 20:32:56.747365', '2026-11-23 23:58:36.893526', NULL, NULL, false);
INSERT INTO public.sys_user (id, org_id, dept_id, username, password_hash, real_name, email, phone, data_scope, status, last_login_at, created_at, updated_at, created_by, updated_by, deleted) VALUES (8, 1, 1, 'bi_designer', '$argon2id$v=19$m=65536,t=3,p=4$rBQiUcg9YhRSRzX4MHTXfw$9/tufn9WnI30A1dcigYYH1+Og7wFlBXckhqZVwUCI7o', 'BI 设计师', 'bi_designer@company.com', '13800138006', 'SELF', 'ENABLED', NULL, '2026-11-23 20:32:56.747365', '2026-11-23 23:58:36.893526', NULL, NULL, false);
INSERT INTO public.sys_user (id, org_id, dept_id, username, password_hash, real_name, email, phone, data_scope, status, last_login_at, created_at, updated_at, created_by, updated_by, deleted) VALUES (9, 1, 1, 'bi_viewer', '$argon2id$v=19$m=65536,t=3,p=4$wV53AkblmlWyaPwUiKOq0Q$6vzMQGlc6d3pbm1IwEIYuDxQMDoOG3xyI4WfFvSSVn8', 'BI 浏览人员', 'bi_viewer@company.com', '13800138007', 'SELF', 'ENABLED', NULL, '2026-11-23 20:32:56.747365', '2026-11-23 23:58:36.893526', NULL, NULL, false);
INSERT INTO public.sys_user (id, org_id, dept_id, username, password_hash, real_name, email, phone, data_scope, status, last_login_at, created_at, updated_at, created_by, updated_by, deleted) VALUES (10, 1, 3, 'ops_analyst_01', '$argon2id$v=19$m=65536,t=3,p=4$8nSHJgPCLKLZ6FnF8Luc7A$b52Ablj5aGor2dxZmQReXTluZSvhWjE7kcZhX+lSyLQ', '张运营', 'ops_analyst_01@company.com', '13800138008', 'SELF', 'ENABLED', '2026-11-23 12:34:13.518544', '2026-11-23 20:32:56.747365', '2026-11-23 23:58:36.893526', NULL, NULL, false);
INSERT INTO public.sys_user (id, org_id, dept_id, username, password_hash, real_name, email, phone, data_scope, status, last_login_at, created_at, updated_at, created_by, updated_by, deleted) VALUES (11, 1, 4, 'ops_analyst_02', '$argon2id$v=19$m=65536,t=3,p=4$YWIDhScZB9ahNAA1AhkoHA$GLX0IY7/0qOWAlfBWggyV7MH2g57yuaFp9juvTjq4fc', '运营分析员二', 'ops_analyst_02@company.com', '13800138009', 'SELF', 'ENABLED', NULL, '2026-11-23 20:32:56.747365', '2026-11-23 23:58:36.893526', NULL, NULL, false);
INSERT INTO public.sys_user (id, org_id, dept_id, username, password_hash, real_name, email, phone, data_scope, status, last_login_at, created_at, updated_at, created_by, updated_by, deleted) VALUES (12, 1, 1, 'metric_admin', '$argon2id$v=19$m=65536,t=3,p=4$z3Fj+jkAEH7rSYctm9K7YQ$fCk8jH5QkplEHJrHF4KbE5wdgV05/KecrjR7sjxZALA', '指标知识管理员', 'metric_admin@company.com', '13800138010', 'SELF', 'ENABLED', NULL, '2026-11-23 20:32:56.747365', '2026-11-23 23:58:36.893526', NULL, NULL, false);
INSERT INTO public.sys_user (id, org_id, dept_id, username, password_hash, real_name, email, phone, data_scope, status, last_login_at, created_at, updated_at, created_by, updated_by, deleted) VALUES (13, 1, 1, 'algorithm_owner', '$argon2id$v=19$m=65536,t=3,p=4$BLW0fjEoDIwPqdj9BLVdmQ$fjsJwQht5wt9MIQeXtEeyu3cz4gK1KikBX6aiDqcmhs', '算法负责人', 'algorithm_owner@company.com', '13800138011', 'SELF', 'ENABLED', NULL, '2026-11-23 20:32:56.747365', '2026-11-23 23:58:36.893526', NULL, NULL, false);
INSERT INTO public.sys_user (id, org_id, dept_id, username, password_hash, real_name, email, phone, data_scope, status, last_login_at, created_at, updated_at, created_by, updated_by, deleted) VALUES (3, 1, 3, 'goods_operator', '$argon2id$v=19$m=65536,t=3,p=4$X/vmivglPArhA5rbxE0HoQ$SFZeQ02BbR+PFOk455vjVVD/m897GWbbjZ0BYo81Kf4', '商品运营专员', 'goods_operator@company.com', '13800138001', 'SELF', 'ENABLED', '2026-11-24 01:45:46.354812', '2026-11-23 20:32:56.747365', '2026-11-24 09:45:46.277848', NULL, NULL, false);
INSERT INTO public.sys_user (id, org_id, dept_id, username, password_hash, real_name, email, phone, data_scope, status, last_login_at, created_at, updated_at, created_by, updated_by, deleted) VALUES (172, 1, 7, '123', '$argon2id$v=19$m=65536,t=3,p=4$aUAn1F7JGHrHtW3P4xVpZQ$hfPngLx9L2n0dYKhDCq4mE6a2DTflQqyXrnHBxNNR2Y', '黎明', '123@company.com', '12345678901', 'SELF', 'ENABLED', '2026-11-24 02:15:17.348514', '2026-11-23 23:33:59.615596', '2026-11-24 10:15:17.192271', 1, 1, false);
INSERT INTO public.sys_user (id, org_id, dept_id, username, password_hash, real_name, email, phone, data_scope, status, last_login_at, created_at, updated_at, created_by, updated_by, deleted) VALUES (173, 1, 7, 'sss', '$argon2id$v=19$m=65536,t=3,p=4$fYBBvoywqqMGZeQs5VtsQw$Vaa23IHCEKg6N6x1wFXI07BNMuN6HtDnIhNzFpfJ3DM', 'asdfghj', '', '', 'SELF', 'ENABLED', '2026-11-24 02:41:29.174005', '2026-11-24 10:29:55.930481', '2026-11-24 10:41:29.077467', 1, 1, false);
INSERT INTO public.sys_user (id, org_id, dept_id, username, password_hash, real_name, email, phone, data_scope, status, last_login_at, created_at, updated_at, created_by, updated_by, deleted) VALUES (17, 1, 5, 'cost_verifier', '$argon2id$v=19$m=65536,t=3,p=4$c/FgVIHOxr0DXuN1FFvuCw$93GKhSOuMMUvh/gwB6OcNOrYnEOVXEhRIl3jvEZZnB8', '李财务', 'cost_verifier@company.com', '13800138015', 'SELF', 'ENABLED', NULL, '2026-11-23 20:32:56.747365', '2026-11-23 23:58:36.893526', NULL, NULL, false);
INSERT INTO public.sys_user (id, org_id, dept_id, username, password_hash, real_name, email, phone, data_scope, status, last_login_at, created_at, updated_at, created_by, updated_by, deleted) VALUES (18, 1, 5, 'replenish_auditor', '$argon2id$v=19$m=65536,t=3,p=4$BBu00GVoDd118whkAuPirw$D3xjVCzOkObxpUS0eK55axeSmEbMuSR14XB7KACOMgk', '补货审批专员', 'replenish_auditor@company.com', '13800138016', 'SELF', 'ENABLED', NULL, '2026-11-23 20:32:56.747365', '2026-11-23 23:58:36.893526', NULL, NULL, false);
INSERT INTO public.sys_user (id, org_id, dept_id, username, password_hash, real_name, email, phone, data_scope, status, last_login_at, created_at, updated_at, created_by, updated_by, deleted) VALUES (19, 1, 6, 'purchaser', '$argon2id$v=19$m=65536,t=3,p=4$I19IXLp7CKGmmMZrg5dr4w$AvdUPuphquKOP1ctJw9IjeKet7toM6Qn+NTj5M6lHgA', '采购专员', 'purchaser@company.com', '13800138017', 'SELF', 'ENABLED', NULL, '2026-11-23 20:32:56.747365', '2026-11-23 23:58:36.893526', NULL, NULL, false);
INSERT INTO public.sys_user (id, org_id, dept_id, username, password_hash, real_name, email, phone, data_scope, status, last_login_at, created_at, updated_at, created_by, updated_by, deleted) VALUES (20, 1, 6, 'warehouse_inspector', '$argon2id$v=19$m=65536,t=3,p=4$kh+hkfzeHFwWYBb7mwRARw$XZjmyGP0nIPv9xdupu+Xtz8ol4JlEanAK56G9I032SQ', '王仓管', 'warehouse_inspector@company.com', '13800138018', 'SELF', 'ENABLED', NULL, '2026-11-23 20:32:56.747365', '2026-11-23 23:58:36.893526', NULL, NULL, false);
INSERT INTO public.sys_user (id, org_id, dept_id, username, password_hash, real_name, email, phone, data_scope, status, last_login_at, created_at, updated_at, created_by, updated_by, deleted) VALUES (21, 1, 6, 'logistics_operator', '$argon2id$v=19$m=65536,t=3,p=4$BaWBePNJqCnviPaQLQvpWQ$nAdas+zV2PGiT9hLCMuA/UOsKCTtgO7FsSxLlg8FJPA', '物流专员', 'logistics_operator@company.com', '13800138019', 'SELF', 'ENABLED', NULL, '2026-11-23 20:32:56.747365', '2026-11-23 23:58:36.893526', NULL, NULL, false);
INSERT INTO public.sys_user (id, org_id, dept_id, username, password_hash, real_name, email, phone, data_scope, status, last_login_at, created_at, updated_at, created_by, updated_by, deleted) VALUES (22, 1, 1, 'audit_analyst', '$argon2id$v=19$m=65536,t=3,p=4$aSHEgB0iyeUeIhJIGl1pJg$183Y5g76opHPNbaI7zGiRM5LPY6bcdi7ScrzQ7QIIfg', '审计复盘分析员', 'audit_analyst@company.com', '13800138020', 'SELF', 'ENABLED', NULL, '2026-11-23 20:32:56.747365', '2026-11-23 23:58:36.893526', NULL, NULL, false);
INSERT INTO public.sys_user (id, org_id, dept_id, username, password_hash, real_name, email, phone, data_scope, status, last_login_at, created_at, updated_at, created_by, updated_by, deleted) VALUES (14, 1, 3, 'data_operator', '$argon2id$v=19$m=65536,t=3,p=4$8lj3Qt4pk3sXJpOY5CyEtA$FZGUvaT0eeHI0FYu/mIEn06ZkkmTM21hJ6m3aCVyQjM', '数据运营专员', 'data_operator@company.com', '13800138012', 'SELF', 'ENABLED', NULL, '2026-11-23 20:32:56.747365', '2026-11-23 23:58:36.893526', NULL, NULL, false);
INSERT INTO public.sys_user (id, org_id, dept_id, username, password_hash, real_name, email, phone, data_scope, status, last_login_at, created_at, updated_at, created_by, updated_by, deleted) VALUES (15, 1, 4, 'selection_auditor', '$argon2id$v=19$m=65536,t=3,p=4$WGJDTEBHYlxf0Yk2rjbwNg$2iEWBodeqK+6YccifVkrxv3VvTOkAHnsTK2NVRuQpJo', '选品审批专员', 'selection_auditor@company.com', '13800138013', 'SELF', 'ENABLED', NULL, '2026-11-23 20:32:56.747365', '2026-11-23 23:58:36.893526', NULL, NULL, false);
INSERT INTO public.sys_user (id, org_id, dept_id, username, password_hash, real_name, email, phone, data_scope, status, last_login_at, created_at, updated_at, created_by, updated_by, deleted) VALUES (16, 1, 4, 'replenish_planner', '$argon2id$v=19$m=65536,t=3,p=4$tMBlPxcsaIIYN4UKsaQUDw$FGho/Rv2PTILH9lZr5Gs4Ek8ujyNihuv9yOJrsl12nE', '运营计划员', 'replenish_planner@company.com', '13800138014', 'SELF', 'ENABLED', NULL, '2026-11-23 20:32:56.747365', '2026-11-23 23:58:36.893526', NULL, NULL, false);
INSERT INTO public.sys_user (id, org_id, dept_id, username, password_hash, real_name, email, phone, data_scope, status, last_login_at, created_at, updated_at, created_by, updated_by, deleted) VALUES (1, 1, 1, 'admin', '$argon2id$v=19$m=65536,t=3,p=4$akQMitilmve63u7wjDXRAA$8jE0ADbTbLRA8KSu4LbREFaGs0QmHswvIuOytwxMGUQ', '黄承翔', 'admin@company.com', '13800138000', 'ALL', 'ENABLED', '2026-11-24 13:53:29.619036', '2026-11-23 19:46:31.313005', '2026-11-24 21:53:28.28402', NULL, NULL, false);
INSERT INTO public.sys_user (id, org_id, dept_id, username, password_hash, real_name, email, phone, data_scope, status, last_login_at, created_at, updated_at, created_by, updated_by, deleted) VALUES (174, 1, NULL, 'aaa', '$argon2id$v=19$m=65536,t=3,p=4$gkS23SgVZ+J1SUjLzxA3pQ$YlePjrqEvZYDCkJLz/vzRoQtNzF74vlkmu5A0f2iYCg', '黎明', NULL, NULL, 'SELF', 'ENABLED', '2026-11-24 09:50:18.293104', '2026-11-24 15:24:45.646516', '2026-11-24 17:50:17.451124', 174, 1, false);


ALTER TABLE public.sys_user ENABLE TRIGGER ALL;

--
-- Data for Name: biz_department_manager_history; Type: TABLE DATA; Schema: public; Owner: -
--

ALTER TABLE public.biz_department_manager_history DISABLE TRIGGER ALL;

INSERT INTO public.biz_department_manager_history (id, org_id, dept_id, user_id, manager_name, change_type, start_at, end_at, created_by, created_at) VALUES (1, 1, 1, 1, '黄承翔', 'ASSIGN', '2026-11-24 17:57:41.461792', NULL, NULL, '2026-11-24 17:57:41.461792');
INSERT INTO public.biz_department_manager_history (id, org_id, dept_id, user_id, manager_name, change_type, start_at, end_at, created_by, created_at) VALUES (2, 1, 2, 10, '张运营', 'ASSIGN', '2026-11-24 17:57:41.461792', NULL, NULL, '2026-11-24 17:57:41.461792');
INSERT INTO public.biz_department_manager_history (id, org_id, dept_id, user_id, manager_name, change_type, start_at, end_at, created_by, created_at) VALUES (3, 1, 3, 10, '张运营', 'ASSIGN', '2026-11-24 17:57:41.461792', NULL, NULL, '2026-11-24 17:57:41.461792');
INSERT INTO public.biz_department_manager_history (id, org_id, dept_id, user_id, manager_name, change_type, start_at, end_at, created_by, created_at) VALUES (4, 1, 4, 10, '张运营', 'ASSIGN', '2026-11-24 17:57:41.461792', NULL, NULL, '2026-11-24 17:57:41.461792');
INSERT INTO public.biz_department_manager_history (id, org_id, dept_id, user_id, manager_name, change_type, start_at, end_at, created_by, created_at) VALUES (5, 1, 5, 17, '李财务', 'ASSIGN', '2026-11-24 17:57:41.461792', NULL, NULL, '2026-11-24 17:57:41.461792');
INSERT INTO public.biz_department_manager_history (id, org_id, dept_id, user_id, manager_name, change_type, start_at, end_at, created_by, created_at) VALUES (6, 1, 6, 20, '王仓管', 'ASSIGN', '2026-11-24 17:57:41.461792', NULL, NULL, '2026-11-24 17:57:41.461792');
INSERT INTO public.biz_department_manager_history (id, org_id, dept_id, user_id, manager_name, change_type, start_at, end_at, created_by, created_at) VALUES (7, 1, 7, 7, '赵客服', 'ASSIGN', '2026-11-24 17:57:41.461792', NULL, NULL, '2026-11-24 17:57:41.461792');


ALTER TABLE public.biz_department_manager_history ENABLE TRIGGER ALL;

--
-- Data for Name: biz_shop; Type: TABLE DATA; Schema: public; Owner: -
--

ALTER TABLE public.biz_shop DISABLE TRIGGER ALL;

INSERT INTO public.biz_shop (id, org_id, dept_id, shop_name, shop_code, platform, status, created_at, updated_at, created_by, updated_by, deleted) VALUES (3, 1, 6, 'TikTok Shop 美国站演示店', 'TIKTOK_US_DEMO', 'TIKTOK_SHOP', 'ENABLED', '2026-11-23 20:52:05.140717', '2026-11-23 20:52:05.140717', NULL, NULL, false);
INSERT INTO public.biz_shop (id, org_id, dept_id, shop_name, shop_code, platform, status, created_at, updated_at, created_by, updated_by, deleted) VALUES (1, 1, 2, 'Amazon 美国站演示店', 'AMAZON_US_DEMO', 'AMAZON', 'ENABLED', '2026-11-23 20:52:05.140717', '2026-11-24 10:45:48.876525', NULL, 1, false);
INSERT INTO public.biz_shop (id, org_id, dept_id, shop_name, shop_code, platform, status, created_at, updated_at, created_by, updated_by, deleted) VALUES (2, 1, NULL, 'Shopee 新加坡站演示店', 'SHOPEE_SG_DEMO', 'SHOPEE', 'ENABLED', '2026-11-23 20:52:05.140717', '2026-11-24 19:36:00.956339', NULL, 1, false);


ALTER TABLE public.biz_shop ENABLE TRIGGER ALL;

--
-- Data for Name: biz_department_shop; Type: TABLE DATA; Schema: public; Owner: -
--

ALTER TABLE public.biz_department_shop DISABLE TRIGGER ALL;

INSERT INTO public.biz_department_shop (id, org_id, dept_id, shop_id, created_at, updated_at, created_by, updated_by, deleted) VALUES (1, 1, 6, 3, '2026-11-24 20:00:24.530258', '2026-11-24 20:00:24.530258', NULL, NULL, false);
INSERT INTO public.biz_department_shop (id, org_id, dept_id, shop_id, created_at, updated_at, created_by, updated_by, deleted) VALUES (2, 1, 2, 1, '2026-11-24 20:00:24.530258', '2026-11-24 20:00:24.530258', NULL, NULL, false);
INSERT INTO public.biz_department_shop (id, org_id, dept_id, shop_id, created_at, updated_at, created_by, updated_by, deleted) VALUES (6, 1, 1, 1, '2026-11-24 20:07:20.982236', '2026-11-24 20:07:20.982236', 1, 1, false);
INSERT INTO public.biz_department_shop (id, org_id, dept_id, shop_id, created_at, updated_at, created_by, updated_by, deleted) VALUES (7, 1, 1, 2, '2026-11-24 20:07:20.982236', '2026-11-24 20:07:20.982236', 1, 1, false);
INSERT INTO public.biz_department_shop (id, org_id, dept_id, shop_id, created_at, updated_at, created_by, updated_by, deleted) VALUES (8, 1, 7, 3, '2026-11-24 20:08:46.789354', '2026-11-24 20:08:46.789354', 1, 1, false);


ALTER TABLE public.biz_department_shop ENABLE TRIGGER ALL;

--
-- Data for Name: biz_platform_config; Type: TABLE DATA; Schema: public; Owner: -
--

ALTER TABLE public.biz_platform_config DISABLE TRIGGER ALL;



ALTER TABLE public.biz_platform_config ENABLE TRIGGER ALL;

--
-- Data for Name: case_attachment; Type: TABLE DATA; Schema: public; Owner: -
--

ALTER TABLE public.case_attachment DISABLE TRIGGER ALL;



ALTER TABLE public.case_attachment ENABLE TRIGGER ALL;

--
-- Data for Name: generation_asset; Type: TABLE DATA; Schema: public; Owner: -
--

ALTER TABLE public.generation_asset DISABLE TRIGGER ALL;



ALTER TABLE public.generation_asset ENABLE TRIGGER ALL;

--
-- Data for Name: compliance_check; Type: TABLE DATA; Schema: public; Owner: -
--

ALTER TABLE public.compliance_check DISABLE TRIGGER ALL;



ALTER TABLE public.compliance_check ENABLE TRIGGER ALL;

--
-- Data for Name: conversation_message; Type: TABLE DATA; Schema: public; Owner: -
--

ALTER TABLE public.conversation_message DISABLE TRIGGER ALL;



ALTER TABLE public.conversation_message ENABLE TRIGGER ALL;

--
-- Data for Name: conversation_order_link; Type: TABLE DATA; Schema: public; Owner: -
--

ALTER TABLE public.conversation_order_link DISABLE TRIGGER ALL;



ALTER TABLE public.conversation_order_link ENABLE TRIGGER ALL;

--
-- Data for Name: customer_intent_analysis; Type: TABLE DATA; Schema: public; Owner: -
--

ALTER TABLE public.customer_intent_analysis DISABLE TRIGGER ALL;



ALTER TABLE public.customer_intent_analysis ENABLE TRIGGER ALL;

--
-- Data for Name: customer_listing; Type: TABLE DATA; Schema: public; Owner: -
--

ALTER TABLE public.customer_listing DISABLE TRIGGER ALL;



ALTER TABLE public.customer_listing ENABLE TRIGGER ALL;

--
-- Data for Name: customer_recommended_product; Type: TABLE DATA; Schema: public; Owner: -
--

ALTER TABLE public.customer_recommended_product DISABLE TRIGGER ALL;



ALTER TABLE public.customer_recommended_product ENABLE TRIGGER ALL;

--
-- Data for Name: customer_reply_draft; Type: TABLE DATA; Schema: public; Owner: -
--

ALTER TABLE public.customer_reply_draft DISABLE TRIGGER ALL;



ALTER TABLE public.customer_reply_draft ENABLE TRIGGER ALL;

--
-- Data for Name: demand_profile; Type: TABLE DATA; Schema: public; Owner: -
--

ALTER TABLE public.demand_profile DISABLE TRIGGER ALL;



ALTER TABLE public.demand_profile ENABLE TRIGGER ALL;

--
-- Data for Name: forecast_run; Type: TABLE DATA; Schema: public; Owner: -
--

ALTER TABLE public.forecast_run DISABLE TRIGGER ALL;



ALTER TABLE public.forecast_run ENABLE TRIGGER ALL;

--
-- Data for Name: forecast_actual_override; Type: TABLE DATA; Schema: public; Owner: -
--

ALTER TABLE public.forecast_actual_override DISABLE TRIGGER ALL;



ALTER TABLE public.forecast_actual_override ENABLE TRIGGER ALL;

--
-- Data for Name: forecast_audit_log; Type: TABLE DATA; Schema: public; Owner: -
--

ALTER TABLE public.forecast_audit_log DISABLE TRIGGER ALL;



ALTER TABLE public.forecast_audit_log ENABLE TRIGGER ALL;

--
-- Data for Name: forecast_backtest_point; Type: TABLE DATA; Schema: public; Owner: -
--

ALTER TABLE public.forecast_backtest_point DISABLE TRIGGER ALL;



ALTER TABLE public.forecast_backtest_point ENABLE TRIGGER ALL;

--
-- Data for Name: forecast_evaluation; Type: TABLE DATA; Schema: public; Owner: -
--

ALTER TABLE public.forecast_evaluation DISABLE TRIGGER ALL;



ALTER TABLE public.forecast_evaluation ENABLE TRIGGER ALL;

--
-- Data for Name: forecast_idempotency_record; Type: TABLE DATA; Schema: public; Owner: -
--

ALTER TABLE public.forecast_idempotency_record DISABLE TRIGGER ALL;



ALTER TABLE public.forecast_idempotency_record ENABLE TRIGGER ALL;

--
-- Data for Name: forecast_model_definition; Type: TABLE DATA; Schema: public; Owner: -
--

ALTER TABLE public.forecast_model_definition DISABLE TRIGGER ALL;



ALTER TABLE public.forecast_model_definition ENABLE TRIGGER ALL;

--
-- Data for Name: forecast_point; Type: TABLE DATA; Schema: public; Owner: -
--

ALTER TABLE public.forecast_point DISABLE TRIGGER ALL;



ALTER TABLE public.forecast_point ENABLE TRIGGER ALL;

--
-- Data for Name: generation_media; Type: TABLE DATA; Schema: public; Owner: -
--

ALTER TABLE public.generation_media DISABLE TRIGGER ALL;



ALTER TABLE public.generation_media ENABLE TRIGGER ALL;

--
-- Data for Name: sources; Type: TABLE DATA; Schema: public; Owner: -
--

ALTER TABLE public.sources DISABLE TRIGGER ALL;



ALTER TABLE public.sources ENABLE TRIGGER ALL;

--
-- Data for Name: import_jobs; Type: TABLE DATA; Schema: public; Owner: -
--

ALTER TABLE public.import_jobs DISABLE TRIGGER ALL;



ALTER TABLE public.import_jobs ENABLE TRIGGER ALL;

--
-- Data for Name: inventory_position; Type: TABLE DATA; Schema: public; Owner: -
--

ALTER TABLE public.inventory_position DISABLE TRIGGER ALL;



ALTER TABLE public.inventory_position ENABLE TRIGGER ALL;

--
-- Data for Name: replenishment_plan; Type: TABLE DATA; Schema: public; Owner: -
--

ALTER TABLE public.replenishment_plan DISABLE TRIGGER ALL;



ALTER TABLE public.replenishment_plan ENABLE TRIGGER ALL;

--
-- Data for Name: logistics_voucher; Type: TABLE DATA; Schema: public; Owner: -
--

ALTER TABLE public.logistics_voucher DISABLE TRIGGER ALL;



ALTER TABLE public.logistics_voucher ENABLE TRIGGER ALL;

--
-- Data for Name: outbox_event; Type: TABLE DATA; Schema: public; Owner: -
--

ALTER TABLE public.outbox_event DISABLE TRIGGER ALL;



ALTER TABLE public.outbox_event ENABLE TRIGGER ALL;

--
-- Data for Name: pcc_workflow_template; Type: TABLE DATA; Schema: public; Owner: -
--

ALTER TABLE public.pcc_workflow_template DISABLE TRIGGER ALL;

INSERT INTO public.pcc_workflow_template (id, org_id, code, purpose, platform, status, version, config, created_at, updated_at) VALUES (1, '1', 'PCC-COPY-AMAZON-US-V1', 'COPY', 'AMAZON_US', 'PUBLISHED', 1, '{"executor": "local_copy_draft", "strategies": ["parameter_first", "conversion_first", "scene_first"], "term_dictionary": {"storage": "minio", "read_only": true, "object_key": "pcc/term-dictionaries/amazon-us/en-US/v1.json"}, "publish_to_marketplace": false}', '2026-11-24 18:06:33.354781+08', '2026-11-24 18:13:43.4309+08');
INSERT INTO public.pcc_workflow_template (id, org_id, code, purpose, platform, status, version, config, created_at, updated_at) VALUES (2, '1', 'PCC-IMAGE-AMAZON-US-V1', 'IMAGE', 'AMAZON_US', 'PUBLISHED', 1, '{"executor": "external_media_callback", "allowed_mime": ["image/png", "image/jpeg", "image/webp"], "publish_to_marketplace": false}', '2026-11-24 19:44:54.535438+08', '2026-11-24 19:44:54.535438+08');
INSERT INTO public.pcc_workflow_template (id, org_id, code, purpose, platform, status, version, config, created_at, updated_at) VALUES (3, '1', 'PCC-VIDEO-AMAZON-US-V1', 'VIDEO', 'AMAZON_US', 'PUBLISHED', 1, '{"executor": "external_media_callback", "allowed_mime": ["video/mp4", "video/webm"], "publish_to_marketplace": false}', '2026-11-24 19:44:54.535438+08', '2026-11-24 19:44:54.535438+08');


ALTER TABLE public.pcc_workflow_template ENABLE TRIGGER ALL;

--
-- Data for Name: pcc_generation_job; Type: TABLE DATA; Schema: public; Owner: -
--

ALTER TABLE public.pcc_generation_job DISABLE TRIGGER ALL;



ALTER TABLE public.pcc_generation_job ENABLE TRIGGER ALL;

--
-- Data for Name: pcc_agent_run; Type: TABLE DATA; Schema: public; Owner: -
--

ALTER TABLE public.pcc_agent_run DISABLE TRIGGER ALL;



ALTER TABLE public.pcc_agent_run ENABLE TRIGGER ALL;

--
-- Data for Name: pcc_generation_asset; Type: TABLE DATA; Schema: public; Owner: -
--

ALTER TABLE public.pcc_generation_asset DISABLE TRIGGER ALL;



ALTER TABLE public.pcc_generation_asset ENABLE TRIGGER ALL;

--
-- Data for Name: pcc_generation_media; Type: TABLE DATA; Schema: public; Owner: -
--

ALTER TABLE public.pcc_generation_media DISABLE TRIGGER ALL;



ALTER TABLE public.pcc_generation_media ENABLE TRIGGER ALL;

--
-- Data for Name: pcc_asset_reference; Type: TABLE DATA; Schema: public; Owner: -
--

ALTER TABLE public.pcc_asset_reference DISABLE TRIGGER ALL;



ALTER TABLE public.pcc_asset_reference ENABLE TRIGGER ALL;

--
-- Data for Name: pcc_compliance_check; Type: TABLE DATA; Schema: public; Owner: -
--

ALTER TABLE public.pcc_compliance_check DISABLE TRIGGER ALL;



ALTER TABLE public.pcc_compliance_check ENABLE TRIGGER ALL;

--
-- Data for Name: pcc_content_approval; Type: TABLE DATA; Schema: public; Owner: -
--

ALTER TABLE public.pcc_content_approval DISABLE TRIGGER ALL;



ALTER TABLE public.pcc_content_approval ENABLE TRIGGER ALL;

--
-- Data for Name: product_sourcing; Type: TABLE DATA; Schema: public; Owner: -
--

ALTER TABLE public.product_sourcing DISABLE TRIGGER ALL;



ALTER TABLE public.product_sourcing ENABLE TRIGGER ALL;

--
-- Data for Name: purchases; Type: TABLE DATA; Schema: public; Owner: -
--

ALTER TABLE public.purchases DISABLE TRIGGER ALL;



ALTER TABLE public.purchases ENABLE TRIGGER ALL;

--
-- Data for Name: receipt_batch; Type: TABLE DATA; Schema: public; Owner: -
--

ALTER TABLE public.receipt_batch DISABLE TRIGGER ALL;



ALTER TABLE public.receipt_batch ENABLE TRIGGER ALL;

--
-- Data for Name: replenishment_cost_card; Type: TABLE DATA; Schema: public; Owner: -
--

ALTER TABLE public.replenishment_cost_card DISABLE TRIGGER ALL;



ALTER TABLE public.replenishment_cost_card ENABLE TRIGGER ALL;

--
-- Data for Name: replenishment_event; Type: TABLE DATA; Schema: public; Owner: -
--

ALTER TABLE public.replenishment_event DISABLE TRIGGER ALL;



ALTER TABLE public.replenishment_event ENABLE TRIGGER ALL;

--
-- Data for Name: reviews; Type: TABLE DATA; Schema: public; Owner: -
--

ALTER TABLE public.reviews DISABLE TRIGGER ALL;



ALTER TABLE public.reviews ENABLE TRIGGER ALL;

--
-- Data for Name: sales_order; Type: TABLE DATA; Schema: public; Owner: -
--

ALTER TABLE public.sales_order DISABLE TRIGGER ALL;



ALTER TABLE public.sales_order ENABLE TRIGGER ALL;

--
-- Data for Name: sales_order_item; Type: TABLE DATA; Schema: public; Owner: -
--

ALTER TABLE public.sales_order_item DISABLE TRIGGER ALL;



ALTER TABLE public.sales_order_item ENABLE TRIGGER ALL;

--
-- Data for Name: study_sources; Type: TABLE DATA; Schema: public; Owner: -
--

ALTER TABLE public.study_sources DISABLE TRIGGER ALL;



ALTER TABLE public.study_sources ENABLE TRIGGER ALL;

--
-- Data for Name: sys_permission; Type: TABLE DATA; Schema: public; Owner: -
--

ALTER TABLE public.sys_permission DISABLE TRIGGER ALL;

INSERT INTO public.sys_permission (id, perm_name, perm_key, perm_type, status, created_at, updated_at, created_by, updated_by, deleted, description, module_name, parent_id) VALUES (3, '模拟买家发送消息', 'cs:mock:sendMsg', 'API', 'ENABLED', '2026-11-23 18:07:28.794958', '2026-11-23 18:07:28.794958', NULL, NULL, false, '仅演示环境，发起咨询、投诉消息', '智能客服 Agent', NULL);
INSERT INTO public.sys_permission (id, perm_name, perm_key, perm_type, status, created_at, updated_at, created_by, updated_by, deleted, description, module_name, parent_id) VALUES (4, '查看会话与意图', 'cs:session:view', 'API', 'ENABLED', '2026-11-23 18:07:28.794958', '2026-11-23 18:07:28.794958', NULL, NULL, false, '读取会话、意图分析结果', '智能客服 Agent', NULL);
INSERT INTO public.sys_permission (id, perm_name, perm_key, perm_type, status, created_at, updated_at, created_by, updated_by, deleted, description, module_name, parent_id) VALUES (5, '人工接管会话', 'cs:session:takeover', 'API', 'ENABLED', '2026-11-23 18:07:28.794958', '2026-11-23 18:07:28.794958', NULL, NULL, false, '人工接手买家会话', '智能客服 Agent', NULL);
INSERT INTO public.sys_permission (id, perm_name, perm_key, perm_type, status, created_at, updated_at, created_by, updated_by, deleted, description, module_name, parent_id) VALUES (6, '翻译复核回复', 'cs:session:translateReview', 'API', 'ENABLED', '2026-11-23 18:07:28.794958', '2026-11-23 18:07:28.794958', NULL, NULL, false, '核对中英文回复草稿', '智能客服 Agent', NULL);
INSERT INTO public.sys_permission (id, perm_name, perm_key, perm_type, status, created_at, updated_at, created_by, updated_by, deleted, description, module_name, parent_id) VALUES (7, '创建售后工单', 'cs:ticket:create', 'API', 'ENABLED', '2026-11-23 18:07:28.794958', '2026-11-23 18:07:28.794958', NULL, NULL, false, '新建售后工单、上传附件', '智能客服 Agent', NULL);
INSERT INTO public.sys_permission (id, perm_name, perm_key, perm_type, status, created_at, updated_at, created_by, updated_by, deleted, description, module_name, parent_id) VALUES (8, '查看售后工单', 'cs:ticket:view', 'API', 'ENABLED', '2026-11-23 18:07:28.794958', '2026-11-23 18:07:28.794958', NULL, NULL, false, '查看工单列表与详情', '智能客服 Agent', NULL);
INSERT INTO public.sys_permission (id, perm_name, perm_key, perm_type, status, created_at, updated_at, created_by, updated_by, deleted, description, module_name, parent_id) VALUES (9, '售后工单审批', 'cs:ticket:audit', 'API', 'ENABLED', '2026-11-23 18:07:28.794958', '2026-11-23 18:07:28.794958', NULL, NULL, false, '批准 / 驳回内部售后工单', '智能客服 Agent', NULL);
INSERT INTO public.sys_permission (id, perm_name, perm_key, perm_type, status, created_at, updated_at, created_by, updated_by, deleted, description, module_name, parent_id) VALUES (10, '编排 BI 驾驶舱', 'bi:dashboard:design', 'API', 'ENABLED', '2026-11-23 18:07:28.794958', '2026-11-23 18:07:28.794958', NULL, NULL, false, '画布拖拽、自然语言生成 BI 卡片', '驾驶舱设计 Agent', NULL);
INSERT INTO public.sys_permission (id, perm_name, perm_key, perm_type, status, created_at, updated_at, created_by, updated_by, deleted, description, module_name, parent_id) VALUES (11, '保存驾驶舱草稿', 'bi:dashboard:saveDraft', 'API', 'ENABLED', '2026-11-23 18:07:28.794958', '2026-11-23 18:07:28.794958', NULL, NULL, false, '保存未发布草稿版本', '驾驶舱设计 Agent', NULL);
INSERT INTO public.sys_permission (id, perm_name, perm_key, perm_type, status, created_at, updated_at, created_by, updated_by, deleted, description, module_name, parent_id) VALUES (12, '发布驾驶舱', 'bi:dashboard:publish', 'API', 'ENABLED', '2026-11-23 18:07:28.794958', '2026-11-23 18:07:28.794958', NULL, NULL, false, '草稿快照发布为线上正式版本', '驾驶舱设计 Agent', NULL);
INSERT INTO public.sys_permission (id, perm_name, perm_key, perm_type, status, created_at, updated_at, created_by, updated_by, deleted, description, module_name, parent_id) VALUES (13, '查看已发布驾驶舱', 'bi:dashboard:view', 'API', 'ENABLED', '2026-11-23 18:07:28.794958', '2026-11-23 18:07:28.794958', NULL, NULL, false, '浏览大屏、刷新、全屏查看', '驾驶舱设计 Agent', NULL);
INSERT INTO public.sys_permission (id, perm_name, perm_key, perm_type, status, created_at, updated_at, created_by, updated_by, deleted, description, module_name, parent_id) VALUES (14, '自然语言问数查询', 'bi:query:ask', 'API', 'ENABLED', '2026-11-23 18:07:28.794958', '2026-11-23 18:07:28.794958', NULL, NULL, false, '自然语言查询经营指标，支持连续追问', '智能问数 Agent', NULL);
INSERT INTO public.sys_permission (id, perm_name, perm_key, perm_type, status, created_at, updated_at, created_by, updated_by, deleted, description, module_name, parent_id) VALUES (15, '维护指标口径与知识库', 'bi:metric:edit', 'API', 'ENABLED', '2026-11-23 18:07:28.794958', '2026-11-23 18:07:28.794958', NULL, NULL, false, '维护指标快照、同步任务、READY 知识库', '智能问数 Agent', NULL);
INSERT INTO public.sys_permission (id, perm_name, perm_key, perm_type, status, created_at, updated_at, created_by, updated_by, deleted, description, module_name, parent_id) VALUES (16, '执行 SKU 销量预测', 'forecast:sales:run', 'API', 'ENABLED', '2026-11-23 18:07:28.794958', '2026-11-23 18:07:28.794958', NULL, NULL, false, '执行 SKU 预测、历史回测、导出预测结果', '销量预测 Agent', NULL);
INSERT INTO public.sys_permission (id, perm_name, perm_key, perm_type, status, created_at, updated_at, created_by, updated_by, deleted, description, module_name, parent_id) VALUES (17, '采集 & 人工修正实际销量', 'forecast:sales:editActual', 'API', 'ENABLED', '2026-11-23 18:07:28.794958', '2026-11-23 18:07:28.794958', NULL, NULL, false, '录入 / 修正实际销量，查看 WAPE/MAE 评估误差', '销量预测 Agent', NULL);
INSERT INTO public.sys_permission (id, perm_name, perm_key, perm_type, status, created_at, updated_at, created_by, updated_by, deleted, description, module_name, parent_id) VALUES (18, '模型注册启停管理', 'forecast:model:manage', 'API', 'ENABLED', '2026-11-23 18:07:28.794958', '2026-11-23 18:07:28.794958', NULL, NULL, false, '注册模型版本、启停模型、编辑 SKU 需求画像', '销量预测 Agent', NULL);
INSERT INTO public.sys_permission (id, perm_name, perm_key, perm_type, status, created_at, updated_at, created_by, updated_by, deleted, description, module_name, parent_id) VALUES (19, '登记 & 导入选品数据源', 'product:source:upload', 'API', 'ENABLED', '2026-11-23 18:07:28.794958', '2026-11-23 18:07:28.794958', NULL, NULL, false, '登记采购凭证、上传 CSV/XLSX 选品文件', '选品分析 Agent', NULL);
INSERT INTO public.sys_permission (id, perm_name, perm_key, perm_type, status, created_at, updated_at, created_by, updated_by, deleted, description, module_name, parent_id) VALUES (20, '查看选品研究档案', 'product:research:view', 'API', 'ENABLED', '2026-11-23 18:07:28.794958', '2026-11-23 18:07:28.794958', NULL, NULL, false, '查看 AI 初筛、商品研究档案', '选品分析 Agent', NULL);
INSERT INTO public.sys_permission (id, perm_name, perm_key, perm_type, status, created_at, updated_at, created_by, updated_by, deleted, description, module_name, parent_id) VALUES (21, '选品测款人工决策', 'product:research:audit', 'API', 'ENABLED', '2026-11-23 18:07:28.794958', '2026-11-23 18:07:28.794958', NULL, NULL, false, '测款评审，执行投产 / 补充 / 待下架决策', '选品分析 Agent', NULL);
INSERT INTO public.sys_permission (id, perm_name, perm_key, perm_type, status, created_at, updated_at, created_by, updated_by, deleted, description, module_name, parent_id) VALUES (23, '维护成本卡凭证', 'replenish:cost:edit', 'API', 'ENABLED', '2026-11-23 18:07:28.794958', '2026-11-23 18:07:28.794958', NULL, NULL, false, '录入成本卡，上传报价、合同凭证', '补货预测 Agent', NULL);
INSERT INTO public.sys_permission (id, perm_name, perm_key, perm_type, status, created_at, updated_at, created_by, updated_by, deleted, description, module_name, parent_id) VALUES (1, '下载导入推荐商品', 'cs:goods:import', 'API', 'ENABLED', '2026-11-23 18:07:28.794958', '2026-11-23 18:07:28.794958', NULL, NULL, false, '导入 XLSX 商品样例文件', '智能客服 Agent', NULL);
INSERT INTO public.sys_permission (id, perm_name, perm_key, perm_type, status, created_at, updated_at, created_by, updated_by, deleted, description, module_name, parent_id) VALUES (2, '重建向量商品索引', 'cs:goods:rebuildIndex', 'API', 'ENABLED', '2026-11-23 18:07:28.794958', '2026-11-23 18:07:28.794958', NULL, NULL, false, '重建 Milvus 商品向量索引', '智能客服 Agent', NULL);
INSERT INTO public.sys_permission (id, perm_name, perm_key, perm_type, status, created_at, updated_at, created_by, updated_by, deleted, description, module_name, parent_id) VALUES (22, '补货方案测算 & 提交计划', 'replenish:plan:submit', 'API', 'ENABLED', '2026-11-23 18:07:28.794958', '2026-11-23 18:07:28.794958', NULL, NULL, false, 'SKU 仓位选择、多方案对比，提交待审批计划', '补货预测 Agent', NULL);
INSERT INTO public.sys_permission (id, perm_name, perm_key, perm_type, status, created_at, updated_at, created_by, updated_by, deleted, description, module_name, parent_id) VALUES (24, '补货计划审批', 'replenish:plan:audit', 'API', 'ENABLED', '2026-11-23 18:07:28.794958', '2026-11-23 18:07:28.794958', NULL, NULL, false, '批准 / 驳回补货计划，禁止自审自批', '补货预测 Agent', NULL);
INSERT INTO public.sys_permission (id, perm_name, perm_key, perm_type, status, created_at, updated_at, created_by, updated_by, deleted, description, module_name, parent_id) VALUES (25, '创建内部采购任务', 'replenish:purchase:create', 'API', 'ENABLED', '2026-11-23 18:07:28.794958', '2026-11-23 18:07:28.794958', NULL, NULL, false, '审批通过后登记采购任务与采购单', '补货预测 Agent', NULL);
INSERT INTO public.sys_permission (id, perm_name, perm_key, perm_type, status, created_at, updated_at, created_by, updated_by, deleted, description, module_name, parent_id) VALUES (26, '登记收货质检凭证', 'replenish:receive:save', 'API', 'ENABLED', '2026-11-23 18:07:28.794958', '2026-11-23 18:07:28.794958', NULL, NULL, false, '登记收货、质检合格数量，上传凭证', '补货预测 Agent', NULL);
INSERT INTO public.sys_permission (id, perm_name, perm_key, perm_type, status, created_at, updated_at, created_by, updated_by, deleted, description, module_name, parent_id) VALUES (27, '登记发货运单', 'replenish:deliver:save', 'API', 'ENABLED', '2026-11-23 18:07:28.794958', '2026-11-23 18:07:28.794958', NULL, NULL, false, '登记发货记录与运单信息', '补货预测 Agent', NULL);
INSERT INTO public.sys_permission (id, perm_name, perm_key, perm_type, status, created_at, updated_at, created_by, updated_by, deleted, description, module_name, parent_id) VALUES (28, '复盘审计查看', 'replenish:audit:view', 'API', 'ENABLED', '2026-11-23 18:07:28.794958', '2026-11-23 18:07:28.794958', NULL, NULL, false, '只读查看计划、采购收货发货差异、审计记录', '补货预测 Agent', NULL);
INSERT INTO public.sys_permission (id, perm_name, perm_key, perm_type, status, created_at, updated_at, created_by, updated_by, deleted, description, module_name, parent_id) VALUES (29, '角色租户管理', 'system:tenant:roleManage', 'API', 'ENABLED', '2026-11-23 18:07:28.794958', '2026-11-23 18:07:28.794958', NULL, NULL, false, '租户、用户、角色、权限维护配置', '系统管理', NULL);


ALTER TABLE public.sys_permission ENABLE TRIGGER ALL;

--
-- Data for Name: sys_department_permission; Type: TABLE DATA; Schema: public; Owner: -
--

ALTER TABLE public.sys_department_permission DISABLE TRIGGER ALL;

INSERT INTO public.sys_department_permission (id, org_id, dept_id, perm_id, created_at, updated_at, created_by, updated_by, deleted) VALUES (5, 1, 1, 10, '2026-11-23 21:34:16.884045', '2026-11-23 21:34:16.884045', NULL, NULL, false);
INSERT INTO public.sys_department_permission (id, org_id, dept_id, perm_id, created_at, updated_at, created_by, updated_by, deleted) VALUES (4, 1, 1, 13, '2026-11-23 21:34:16.884045', '2026-11-23 21:34:16.884045', NULL, NULL, false);
INSERT INTO public.sys_department_permission (id, org_id, dept_id, perm_id, created_at, updated_at, created_by, updated_by, deleted) VALUES (1, 1, 1, 18, '2026-11-23 21:34:16.884045', '2026-11-23 21:34:16.884045', NULL, NULL, false);
INSERT INTO public.sys_department_permission (id, org_id, dept_id, perm_id, created_at, updated_at, created_by, updated_by, deleted) VALUES (3, 1, 1, 15, '2026-11-23 21:34:16.884045', '2026-11-23 21:34:16.884045', NULL, NULL, false);
INSERT INTO public.sys_department_permission (id, org_id, dept_id, perm_id, created_at, updated_at, created_by, updated_by, deleted) VALUES (6, 1, 1, 29, '2026-11-23 21:34:16.884045', '2026-11-23 21:34:16.884045', NULL, NULL, false);
INSERT INTO public.sys_department_permission (id, org_id, dept_id, perm_id, created_at, updated_at, created_by, updated_by, deleted) VALUES (2, 1, 1, 11, '2026-11-23 21:34:16.884045', '2026-11-23 21:34:16.884045', NULL, NULL, false);
INSERT INTO public.sys_department_permission (id, org_id, dept_id, perm_id, created_at, updated_at, created_by, updated_by, deleted) VALUES (8, 1, 1, 28, '2026-11-23 21:34:16.884045', '2026-11-23 21:34:16.884045', NULL, NULL, false);
INSERT INTO public.sys_department_permission (id, org_id, dept_id, perm_id, created_at, updated_at, created_by, updated_by, deleted) VALUES (7, 1, 1, 12, '2026-11-23 21:34:16.884045', '2026-11-23 21:34:16.884045', NULL, NULL, false);
INSERT INTO public.sys_department_permission (id, org_id, dept_id, perm_id, created_at, updated_at, created_by, updated_by, deleted) VALUES (17, 1, 2, 2, '2026-11-23 21:34:16.884045', '2026-11-23 21:34:16.884045', NULL, NULL, false);
INSERT INTO public.sys_department_permission (id, org_id, dept_id, perm_id, created_at, updated_at, created_by, updated_by, deleted) VALUES (10, 1, 2, 17, '2026-11-23 21:34:16.884045', '2026-11-23 21:34:16.884045', NULL, NULL, false);
INSERT INTO public.sys_department_permission (id, org_id, dept_id, perm_id, created_at, updated_at, created_by, updated_by, deleted) VALUES (16, 1, 2, 21, '2026-11-23 21:34:16.884045', '2026-11-23 21:34:16.884045', NULL, NULL, false);
INSERT INTO public.sys_department_permission (id, org_id, dept_id, perm_id, created_at, updated_at, created_by, updated_by, deleted) VALUES (13, 1, 2, 14, '2026-11-23 21:34:16.884045', '2026-11-23 21:34:16.884045', NULL, NULL, false);
INSERT INTO public.sys_department_permission (id, org_id, dept_id, perm_id, created_at, updated_at, created_by, updated_by, deleted) VALUES (14, 1, 2, 20, '2026-11-23 21:34:16.884045', '2026-11-23 21:34:16.884045', NULL, NULL, false);
INSERT INTO public.sys_department_permission (id, org_id, dept_id, perm_id, created_at, updated_at, created_by, updated_by, deleted) VALUES (12, 1, 2, 16, '2026-11-23 21:34:16.884045', '2026-11-23 21:34:16.884045', NULL, NULL, false);
INSERT INTO public.sys_department_permission (id, org_id, dept_id, perm_id, created_at, updated_at, created_by, updated_by, deleted) VALUES (11, 1, 2, 22, '2026-11-23 21:34:16.884045', '2026-11-23 21:34:16.884045', NULL, NULL, false);
INSERT INTO public.sys_department_permission (id, org_id, dept_id, perm_id, created_at, updated_at, created_by, updated_by, deleted) VALUES (15, 1, 2, 19, '2026-11-23 21:34:16.884045', '2026-11-23 21:34:16.884045', NULL, NULL, false);
INSERT INTO public.sys_department_permission (id, org_id, dept_id, perm_id, created_at, updated_at, created_by, updated_by, deleted) VALUES (9, 1, 2, 1, '2026-11-23 21:34:16.884045', '2026-11-23 21:34:16.884045', NULL, NULL, false);
INSERT INTO public.sys_department_permission (id, org_id, dept_id, perm_id, created_at, updated_at, created_by, updated_by, deleted) VALUES (24, 1, 3, 2, '2026-11-23 21:34:16.884045', '2026-11-23 21:34:16.884045', NULL, NULL, false);
INSERT INTO public.sys_department_permission (id, org_id, dept_id, perm_id, created_at, updated_at, created_by, updated_by, deleted) VALUES (19, 1, 3, 17, '2026-11-23 21:34:16.884045', '2026-11-23 21:34:16.884045', NULL, NULL, false);
INSERT INTO public.sys_department_permission (id, org_id, dept_id, perm_id, created_at, updated_at, created_by, updated_by, deleted) VALUES (20, 1, 3, 14, '2026-11-23 21:34:16.884045', '2026-11-23 21:34:16.884045', NULL, NULL, false);
INSERT INTO public.sys_department_permission (id, org_id, dept_id, perm_id, created_at, updated_at, created_by, updated_by, deleted) VALUES (22, 1, 3, 20, '2026-11-23 21:34:16.884045', '2026-11-23 21:34:16.884045', NULL, NULL, false);
INSERT INTO public.sys_department_permission (id, org_id, dept_id, perm_id, created_at, updated_at, created_by, updated_by, deleted) VALUES (21, 1, 3, 16, '2026-11-23 21:34:16.884045', '2026-11-23 21:34:16.884045', NULL, NULL, false);
INSERT INTO public.sys_department_permission (id, org_id, dept_id, perm_id, created_at, updated_at, created_by, updated_by, deleted) VALUES (23, 1, 3, 19, '2026-11-23 21:34:16.884045', '2026-11-23 21:34:16.884045', NULL, NULL, false);
INSERT INTO public.sys_department_permission (id, org_id, dept_id, perm_id, created_at, updated_at, created_by, updated_by, deleted) VALUES (18, 1, 3, 1, '2026-11-23 21:34:16.884045', '2026-11-23 21:34:16.884045', NULL, NULL, false);
INSERT INTO public.sys_department_permission (id, org_id, dept_id, perm_id, created_at, updated_at, created_by, updated_by, deleted) VALUES (25, 1, 4, 17, '2026-11-23 21:34:16.884045', '2026-11-23 21:34:16.884045', NULL, NULL, false);
INSERT INTO public.sys_department_permission (id, org_id, dept_id, perm_id, created_at, updated_at, created_by, updated_by, deleted) VALUES (30, 1, 4, 21, '2026-11-23 21:34:16.884045', '2026-11-23 21:34:16.884045', NULL, NULL, false);
INSERT INTO public.sys_department_permission (id, org_id, dept_id, perm_id, created_at, updated_at, created_by, updated_by, deleted) VALUES (28, 1, 4, 14, '2026-11-23 21:34:16.884045', '2026-11-23 21:34:16.884045', NULL, NULL, false);
INSERT INTO public.sys_department_permission (id, org_id, dept_id, perm_id, created_at, updated_at, created_by, updated_by, deleted) VALUES (29, 1, 4, 20, '2026-11-23 21:34:16.884045', '2026-11-23 21:34:16.884045', NULL, NULL, false);
INSERT INTO public.sys_department_permission (id, org_id, dept_id, perm_id, created_at, updated_at, created_by, updated_by, deleted) VALUES (27, 1, 4, 16, '2026-11-23 21:34:16.884045', '2026-11-23 21:34:16.884045', NULL, NULL, false);
INSERT INTO public.sys_department_permission (id, org_id, dept_id, perm_id, created_at, updated_at, created_by, updated_by, deleted) VALUES (26, 1, 4, 22, '2026-11-23 21:34:16.884045', '2026-11-23 21:34:16.884045', NULL, NULL, false);
INSERT INTO public.sys_department_permission (id, org_id, dept_id, perm_id, created_at, updated_at, created_by, updated_by, deleted) VALUES (31, 1, 5, 23, '2026-11-23 21:34:16.884045', '2026-11-23 21:34:16.884045', NULL, NULL, false);
INSERT INTO public.sys_department_permission (id, org_id, dept_id, perm_id, created_at, updated_at, created_by, updated_by, deleted) VALUES (32, 1, 5, 24, '2026-11-23 21:34:16.884045', '2026-11-23 21:34:16.884045', NULL, NULL, false);
INSERT INTO public.sys_department_permission (id, org_id, dept_id, perm_id, created_at, updated_at, created_by, updated_by, deleted) VALUES (33, 1, 6, 25, '2026-11-23 21:34:16.884045', '2026-11-23 21:34:16.884045', NULL, NULL, false);
INSERT INTO public.sys_department_permission (id, org_id, dept_id, perm_id, created_at, updated_at, created_by, updated_by, deleted) VALUES (34, 1, 6, 27, '2026-11-23 21:34:16.884045', '2026-11-23 21:34:16.884045', NULL, NULL, false);
INSERT INTO public.sys_department_permission (id, org_id, dept_id, perm_id, created_at, updated_at, created_by, updated_by, deleted) VALUES (35, 1, 6, 26, '2026-11-23 21:34:16.884045', '2026-11-23 21:34:16.884045', NULL, NULL, false);
INSERT INTO public.sys_department_permission (id, org_id, dept_id, perm_id, created_at, updated_at, created_by, updated_by, deleted) VALUES (37, 1, 7, 3, '2026-11-23 21:34:16.884045', '2026-11-23 21:34:16.884045', NULL, NULL, false);
INSERT INTO public.sys_department_permission (id, org_id, dept_id, perm_id, created_at, updated_at, created_by, updated_by, deleted) VALUES (41, 1, 7, 7, '2026-11-23 21:34:16.884045', '2026-11-23 21:34:16.884045', NULL, NULL, false);
INSERT INTO public.sys_department_permission (id, org_id, dept_id, perm_id, created_at, updated_at, created_by, updated_by, deleted) VALUES (38, 1, 7, 9, '2026-11-23 21:34:16.884045', '2026-11-23 21:34:16.884045', NULL, NULL, false);
INSERT INTO public.sys_department_permission (id, org_id, dept_id, perm_id, created_at, updated_at, created_by, updated_by, deleted) VALUES (40, 1, 7, 4, '2026-11-23 21:34:16.884045', '2026-11-23 21:34:16.884045', NULL, NULL, false);
INSERT INTO public.sys_department_permission (id, org_id, dept_id, perm_id, created_at, updated_at, created_by, updated_by, deleted) VALUES (36, 1, 7, 8, '2026-11-23 21:34:16.884045', '2026-11-23 21:34:16.884045', NULL, NULL, false);
INSERT INTO public.sys_department_permission (id, org_id, dept_id, perm_id, created_at, updated_at, created_by, updated_by, deleted) VALUES (39, 1, 7, 6, '2026-11-23 21:34:16.884045', '2026-11-23 21:34:16.884045', NULL, NULL, false);
INSERT INTO public.sys_department_permission (id, org_id, dept_id, perm_id, created_at, updated_at, created_by, updated_by, deleted) VALUES (42, 1, 7, 5, '2026-11-23 21:34:16.884045', '2026-11-23 21:34:16.884045', NULL, NULL, false);


ALTER TABLE public.sys_department_permission ENABLE TRIGGER ALL;

--
-- Data for Name: sys_role; Type: TABLE DATA; Schema: public; Owner: -
--

ALTER TABLE public.sys_role DISABLE TRIGGER ALL;

INSERT INTO public.sys_role (id, org_id, role_name, role_code, description, data_scope, sort, status, created_at, updated_at, created_by, updated_by, deleted) VALUES (5, 1, '成本核验人', 'COST_VERIFY', '录入普通补货计划成本卡；上传报价、合同凭证；维护成本卡版本与有效期。', 'SELF', 14, 'ENABLED', '2026-11-23 18:07:28.794958', '2026-11-23 18:07:28.794958', NULL, NULL, false);
INSERT INTO public.sys_role (id, org_id, role_name, role_code, description, data_scope, sort, status, created_at, updated_at, created_by, updated_by, deleted) VALUES (10, 1, '商品运营', 'GOODS_OPER', '维护推荐商品目录，导入商品 XLSX，重建 Milvus 向量索引；登记选品数据源、上传导入选品文件，跟踪导入任务；维护数据源配置。', 'SELF', 1, 'ENABLED', '2026-11-23 18:07:28.794958', '2026-11-23 18:07:28.794958', NULL, NULL, false);
INSERT INTO public.sys_role (id, org_id, role_name, role_code, description, data_scope, sort, status, created_at, updated_at, created_by, updated_by, deleted) VALUES (13, 1, '模拟买家（仅演示环境）', 'MOCK_BUYER', '演示测试角色，生产环境删除；模拟发起买家咨询、售后投诉，发送模拟消息，接收 WebSocket 推送；不访问真实电商平台 API。', 'SELF', 2, 'ENABLED', '2026-11-23 18:07:28.794958', '2026-11-23 18:07:28.794958', NULL, NULL, false);
INSERT INTO public.sys_role (id, org_id, role_name, role_code, description, data_scope, sort, status, created_at, updated_at, created_by, updated_by, deleted) VALUES (7, 1, '客服人员', 'CS_STAFF', '查看会话与意图，翻译复核、人工接管买家会话；生成中英文回复草稿；定位投诉、检索候选订单、创建售后工单、上传附件；无工单审批权限。', 'SELF', 3, 'ENABLED', '2026-11-23 18:07:28.794958', '2026-11-23 18:07:28.794958', NULL, NULL, false);
INSERT INTO public.sys_role (id, org_id, role_name, role_code, description, data_scope, sort, status, created_at, updated_at, created_by, updated_by, deleted) VALUES (6, 1, '售后专员', 'CS_SPECIALIST', '核验买家身份、订单关联证据；创建售后工单、上传附件，把工单提交待主管审批；不能审批工单。', 'SELF', 4, 'ENABLED', '2026-11-23 18:07:28.794958', '2026-11-23 18:07:28.794958', NULL, NULL, false);
INSERT INTO public.sys_role (id, org_id, role_name, role_code, description, data_scope, sort, status, created_at, updated_at, created_by, updated_by, deleted) VALUES (8, 1, '售后主管', 'CS_SUPERVISOR', '查看待审批售后工单；基于行锁 + 版本号对售后工单做批准 / 驳回，填写审批理由；仅修改系统内部工单状态，不会触发真实平台退款退货。', 'SELF', 5, 'ENABLED', '2026-11-23 18:07:28.794958', '2026-11-23 18:07:28.794958', NULL, NULL, false);
INSERT INTO public.sys_role (id, org_id, role_name, role_code, description, data_scope, sort, status, created_at, updated_at, created_by, updated_by, deleted) VALUES (3, 1, 'BI 设计者', 'BI_DESIGNER', '自然语言编排 BI 卡片、拖拽画布布局；AI 生成卡片描述、预览；保存草稿版本；执行发布，把草稿复制为线上正式驾驶舱版本。', 'SELF', 6, 'ENABLED', '2026-11-23 18:07:28.794958', '2026-11-23 18:07:28.794958', NULL, NULL, false);
INSERT INTO public.sys_role (id, org_id, role_name, role_code, description, data_scope, sort, status, created_at, updated_at, created_by, updated_by, deleted) VALUES (4, 1, 'BI 浏览者', 'BI_VIEWER', '只读查看已经发布完成的 BI 驾驶舱大屏；手动 / 定时刷新、全屏浏览；不能编辑、保存、发布。', 'SELF', 7, 'ENABLED', '2026-11-23 18:07:28.794958', '2026-11-23 18:07:28.794958', NULL, NULL, false);
INSERT INTO public.sys_role (id, org_id, role_name, role_code, description, data_scope, sort, status, created_at, updated_at, created_by, updated_by, deleted) VALUES (14, 1, '运营分析人员', 'OP_ANALYST', '智能问数做自然语言查询经营指标；执行 SKU 销量预测、历史回测；导出预测结果；采集、人工修正实际销量；查看模型评估误差 WAPE/MAE。', 'SELF', 8, 'ENABLED', '2026-11-23 18:07:28.794958', '2026-11-23 18:07:28.794958', NULL, NULL, false);
INSERT INTO public.sys_role (id, org_id, role_name, role_code, description, data_scope, sort, status, created_at, updated_at, created_by, updated_by, deleted) VALUES (17, 1, '补货审批人', 'REPLENISH_AUDITOR', '查看补货计划快照、风险清单；独立对补货计划做批准 / 驳回；后端强制校验不能审批本人提交的计划。', 'SELF', 15, 'ENABLED', '2026-11-23 18:07:28.794958', '2026-11-23 18:07:28.794958', NULL, NULL, false);
INSERT INTO public.sys_role (id, org_id, role_name, role_code, description, data_scope, sort, status, created_at, updated_at, created_by, updated_by, deleted) VALUES (16, 1, '采购员', 'PURCHASER', '补货计划审批通过之后，创建内部采购任务；登记采购单信息，核对计划采购数量。', 'SELF', 16, 'ENABLED', '2026-11-23 18:07:28.794958', '2026-11-23 18:07:28.794958', NULL, NULL, false);
INSERT INTO public.sys_role (id, org_id, role_name, role_code, description, data_scope, sort, status, created_at, updated_at, created_by, updated_by, deleted) VALUES (20, 1, '仓库质检', 'WH_INSPECT', '逐批登记收货、质检、实收合格数量；上传收货凭证；登记凭证不会自动更新库存，库存走独立同步流程。', 'SELF', 17, 'ENABLED', '2026-11-23 18:07:28.794958', '2026-11-23 18:07:28.794958', NULL, NULL, false);
INSERT INTO public.sys_role (id, org_id, role_name, role_code, description, data_scope, sort, status, created_at, updated_at, created_by, updated_by, deleted) VALUES (11, 1, '物流专员', 'LOGISTICS', '登记发货记录、运单信息；业务约束：发货量不能超过累计合格入库数量。', 'SELF', 18, 'ENABLED', '2026-11-23 18:07:28.794958', '2026-11-23 18:07:28.794958', NULL, NULL, false);
INSERT INTO public.sys_role (id, org_id, role_name, role_code, description, data_scope, sort, status, created_at, updated_at, created_by, updated_by, deleted) VALUES (2, 1, '分析 / 复盘人员', 'AUDIT_ANALYST', '只读权限；查看计划事件、采购‑收货‑发货差异、风险清单、全部审计复盘记录；无任何写操作权限。', 'SELF', 19, 'ENABLED', '2026-11-23 18:07:28.794958', '2026-11-23 18:07:28.794958', NULL, NULL, false);
INSERT INTO public.sys_role (id, org_id, role_name, role_code, description, data_scope, sort, status, created_at, updated_at, created_by, updated_by, deleted) VALUES (19, 1, '超级管理员', 'SUPER_ADMIN', '系统管理角色，不属于业务 Agent；全部菜单、全部数据表 CRUD 权限，包括物理删除权限；租户管理、角色权限维护。', 'ALL', 20, 'ENABLED', '2026-11-23 18:07:28.794958', '2026-11-23 18:07:28.794958', NULL, NULL, false);
INSERT INTO public.sys_role (id, org_id, role_name, role_code, description, data_scope, sort, status, created_at, updated_at, created_by, updated_by, deleted) VALUES (12, 1, '指标 / 知识管理员', 'METRIC_ADMIN', '维护指标快照、指标口径配置；管理指标绑定、同步调度任务；维护知识库 READY 资料；配置 REST/MCP 模拟接入。', 'SELF', 9, 'ENABLED', '2026-11-23 18:07:28.794958', '2026-11-23 18:07:28.794958', NULL, NULL, false);
INSERT INTO public.sys_role (id, org_id, role_name, role_code, description, data_scope, sort, status, created_at, updated_at, created_by, updated_by, deleted) VALUES (1, 1, '算法负责人', 'ALG_ADMIN', '查看模型注册表；注册新版本模型、启停模型状态；编辑 SKU 需求画像；查看模型选型依据，维护预测模型元数据。', 'SELF', 10, 'ENABLED', '2026-11-23 18:07:28.794958', '2026-11-23 18:07:28.794958', NULL, NULL, false);
INSERT INTO public.sys_role (id, org_id, role_name, role_code, description, data_scope, sort, status, created_at, updated_at, created_by, updated_by, deleted) VALUES (9, 1, '数据运营人员', 'DATA_OPER', '登记数据源与采购凭证；上传 CSV/XLSX 选品文件、跟踪导入任务；建立选品研究档案、周事实数据；仅做数据接入，不做测款投产审批。', 'SELF', 11, 'ENABLED', '2026-11-23 18:07:28.794958', '2026-11-23 18:07:28.794958', NULL, NULL, false);
INSERT INTO public.sys_role (id, org_id, role_name, role_code, description, data_scope, sort, status, created_at, updated_at, created_by, updated_by, deleted) VALUES (18, 1, '研究与审批人员', 'SELECT_AUDITOR', '查看选品研究概览、AI 初筛结果；人工评审商品研究档案；录入测款计划；人工执行最终业务决策：投产 PRODUCE / 补充 SUPPLEMENT / 待下架 DELIST，记录负责人与理由。', 'SELF', 12, 'ENABLED', '2026-11-23 18:07:28.794958', '2026-11-23 18:07:28.794958', NULL, NULL, false);
INSERT INTO public.sys_role (id, org_id, role_name, role_code, description, data_scope, sort, status, created_at, updated_at, created_by, updated_by, deleted) VALUES (15, 1, '运营 / 计划员', 'PLANNER', '选择 SKU 与仓位；读取预测、库存、供货依据；普通 / 智能补货测算、多方案对比；提交待审批补货计划；不能审批自己提交的计划。', 'SELF', 13, 'ENABLED', '2026-11-23 18:07:28.794958', '2026-11-23 18:07:28.794958', NULL, NULL, false);


ALTER TABLE public.sys_role ENABLE TRIGGER ALL;

--
-- Data for Name: sys_role_permission; Type: TABLE DATA; Schema: public; Owner: -
--

ALTER TABLE public.sys_role_permission DISABLE TRIGGER ALL;

INSERT INTO public.sys_role_permission (id, role_id, perm_id, created_at, updated_at, created_by, updated_by, deleted) VALUES (338, 1, 18, '2026-11-23 23:56:40.485774', '2026-11-23 23:56:40.485774', 1, NULL, false);
INSERT INTO public.sys_role_permission (id, role_id, perm_id, created_at, updated_at, created_by, updated_by, deleted) VALUES (11, 8, 8, '2026-11-23 18:07:28.794958', '2026-11-23 18:07:28.794958', NULL, NULL, false);
INSERT INTO public.sys_role_permission (id, role_id, perm_id, created_at, updated_at, created_by, updated_by, deleted) VALUES (12, 8, 9, '2026-11-23 18:07:28.794958', '2026-11-23 18:07:28.794958', NULL, NULL, false);
INSERT INTO public.sys_role_permission (id, role_id, perm_id, created_at, updated_at, created_by, updated_by, deleted) VALUES (13, 3, 10, '2026-11-23 18:07:28.794958', '2026-11-23 18:07:28.794958', NULL, NULL, false);
INSERT INTO public.sys_role_permission (id, role_id, perm_id, created_at, updated_at, created_by, updated_by, deleted) VALUES (14, 3, 11, '2026-11-23 18:07:28.794958', '2026-11-23 18:07:28.794958', NULL, NULL, false);
INSERT INTO public.sys_role_permission (id, role_id, perm_id, created_at, updated_at, created_by, updated_by, deleted) VALUES (15, 3, 12, '2026-11-23 18:07:28.794958', '2026-11-23 18:07:28.794958', NULL, NULL, false);
INSERT INTO public.sys_role_permission (id, role_id, perm_id, created_at, updated_at, created_by, updated_by, deleted) VALUES (16, 3, 13, '2026-11-23 18:07:28.794958', '2026-11-23 18:07:28.794958', NULL, NULL, false);
INSERT INTO public.sys_role_permission (id, role_id, perm_id, created_at, updated_at, created_by, updated_by, deleted) VALUES (17, 4, 13, '2026-11-23 18:07:28.794958', '2026-11-23 18:07:28.794958', NULL, NULL, false);
INSERT INTO public.sys_role_permission (id, role_id, perm_id, created_at, updated_at, created_by, updated_by, deleted) VALUES (18, 14, 14, '2026-11-23 18:07:28.794958', '2026-11-23 18:07:28.794958', NULL, NULL, false);
INSERT INTO public.sys_role_permission (id, role_id, perm_id, created_at, updated_at, created_by, updated_by, deleted) VALUES (19, 12, 15, '2026-11-23 18:07:28.794958', '2026-11-23 18:07:28.794958', NULL, NULL, false);
INSERT INTO public.sys_role_permission (id, role_id, perm_id, created_at, updated_at, created_by, updated_by, deleted) VALUES (20, 14, 16, '2026-11-23 18:07:28.794958', '2026-11-23 18:07:28.794958', NULL, NULL, false);
INSERT INTO public.sys_role_permission (id, role_id, perm_id, created_at, updated_at, created_by, updated_by, deleted) VALUES (21, 14, 17, '2026-11-23 18:07:28.794958', '2026-11-23 18:07:28.794958', NULL, NULL, false);
INSERT INTO public.sys_role_permission (id, role_id, perm_id, created_at, updated_at, created_by, updated_by, deleted) VALUES (23, 9, 19, '2026-11-23 18:07:28.794958', '2026-11-23 18:07:28.794958', NULL, NULL, false);
INSERT INTO public.sys_role_permission (id, role_id, perm_id, created_at, updated_at, created_by, updated_by, deleted) VALUES (24, 9, 20, '2026-11-23 18:07:28.794958', '2026-11-23 18:07:28.794958', NULL, NULL, false);
INSERT INTO public.sys_role_permission (id, role_id, perm_id, created_at, updated_at, created_by, updated_by, deleted) VALUES (25, 18, 20, '2026-11-23 18:07:28.794958', '2026-11-23 18:07:28.794958', NULL, NULL, false);
INSERT INTO public.sys_role_permission (id, role_id, perm_id, created_at, updated_at, created_by, updated_by, deleted) VALUES (26, 18, 21, '2026-11-23 18:07:28.794958', '2026-11-23 18:07:28.794958', NULL, NULL, false);
INSERT INTO public.sys_role_permission (id, role_id, perm_id, created_at, updated_at, created_by, updated_by, deleted) VALUES (27, 15, 22, '2026-11-23 18:07:28.794958', '2026-11-23 18:07:28.794958', NULL, NULL, false);
INSERT INTO public.sys_role_permission (id, role_id, perm_id, created_at, updated_at, created_by, updated_by, deleted) VALUES (28, 5, 23, '2026-11-23 18:07:28.794958', '2026-11-23 18:07:28.794958', NULL, NULL, false);
INSERT INTO public.sys_role_permission (id, role_id, perm_id, created_at, updated_at, created_by, updated_by, deleted) VALUES (29, 17, 24, '2026-11-23 18:07:28.794958', '2026-11-23 18:07:28.794958', NULL, NULL, false);
INSERT INTO public.sys_role_permission (id, role_id, perm_id, created_at, updated_at, created_by, updated_by, deleted) VALUES (30, 16, 25, '2026-11-23 18:07:28.794958', '2026-11-23 18:07:28.794958', NULL, NULL, false);
INSERT INTO public.sys_role_permission (id, role_id, perm_id, created_at, updated_at, created_by, updated_by, deleted) VALUES (31, 20, 26, '2026-11-23 18:07:28.794958', '2026-11-23 18:07:28.794958', NULL, NULL, false);
INSERT INTO public.sys_role_permission (id, role_id, perm_id, created_at, updated_at, created_by, updated_by, deleted) VALUES (32, 11, 27, '2026-11-23 18:07:28.794958', '2026-11-23 18:07:28.794958', NULL, NULL, false);
INSERT INTO public.sys_role_permission (id, role_id, perm_id, created_at, updated_at, created_by, updated_by, deleted) VALUES (33, 2, 28, '2026-11-23 18:07:28.794958', '2026-11-23 18:07:28.794958', NULL, NULL, false);
INSERT INTO public.sys_role_permission (id, role_id, perm_id, created_at, updated_at, created_by, updated_by, deleted) VALUES (1, 10, 1, '2026-11-23 18:07:28.794958', '2026-11-23 18:07:28.794958', NULL, NULL, false);
INSERT INTO public.sys_role_permission (id, role_id, perm_id, created_at, updated_at, created_by, updated_by, deleted) VALUES (2, 10, 2, '2026-11-23 18:07:28.794958', '2026-11-23 18:07:28.794958', NULL, NULL, false);
INSERT INTO public.sys_role_permission (id, role_id, perm_id, created_at, updated_at, created_by, updated_by, deleted) VALUES (3, 13, 3, '2026-11-23 18:07:28.794958', '2026-11-23 18:07:28.794958', NULL, NULL, false);
INSERT INTO public.sys_role_permission (id, role_id, perm_id, created_at, updated_at, created_by, updated_by, deleted) VALUES (4, 7, 4, '2026-11-23 18:07:28.794958', '2026-11-23 18:07:28.794958', NULL, NULL, false);
INSERT INTO public.sys_role_permission (id, role_id, perm_id, created_at, updated_at, created_by, updated_by, deleted) VALUES (5, 7, 5, '2026-11-23 18:07:28.794958', '2026-11-23 18:07:28.794958', NULL, NULL, false);
INSERT INTO public.sys_role_permission (id, role_id, perm_id, created_at, updated_at, created_by, updated_by, deleted) VALUES (6, 7, 6, '2026-11-23 18:07:28.794958', '2026-11-23 18:07:28.794958', NULL, NULL, false);
INSERT INTO public.sys_role_permission (id, role_id, perm_id, created_at, updated_at, created_by, updated_by, deleted) VALUES (7, 7, 7, '2026-11-23 18:07:28.794958', '2026-11-23 18:07:28.794958', NULL, NULL, false);
INSERT INTO public.sys_role_permission (id, role_id, perm_id, created_at, updated_at, created_by, updated_by, deleted) VALUES (8, 6, 7, '2026-11-23 18:07:28.794958', '2026-11-23 18:07:28.794958', NULL, NULL, false);
INSERT INTO public.sys_role_permission (id, role_id, perm_id, created_at, updated_at, created_by, updated_by, deleted) VALUES (9, 7, 8, '2026-11-23 18:07:28.794958', '2026-11-23 18:07:28.794958', NULL, NULL, false);
INSERT INTO public.sys_role_permission (id, role_id, perm_id, created_at, updated_at, created_by, updated_by, deleted) VALUES (10, 6, 8, '2026-11-23 18:07:28.794958', '2026-11-23 18:07:28.794958', NULL, NULL, false);
INSERT INTO public.sys_role_permission (id, role_id, perm_id, created_at, updated_at, created_by, updated_by, deleted) VALUES (34, 19, 29, '2026-11-23 18:07:28.794958', '2026-11-23 18:07:28.794958', NULL, NULL, false);


ALTER TABLE public.sys_role_permission ENABLE TRIGGER ALL;

--
-- Data for Name: sys_user_role; Type: TABLE DATA; Schema: public; Owner: -
--

ALTER TABLE public.sys_user_role DISABLE TRIGGER ALL;

INSERT INTO public.sys_user_role (id, org_id, user_id, role_id, created_at, updated_at, created_by, updated_by, deleted) VALUES (3, 1, 3, 10, '2026-11-23 20:32:56.747365', '2026-11-23 20:32:56.747365', NULL, NULL, false);
INSERT INTO public.sys_user_role (id, org_id, user_id, role_id, created_at, updated_at, created_by, updated_by, deleted) VALUES (4, 1, 4, 13, '2026-11-23 20:32:56.747365', '2026-11-23 20:32:56.747365', NULL, NULL, false);
INSERT INTO public.sys_user_role (id, org_id, user_id, role_id, created_at, updated_at, created_by, updated_by, deleted) VALUES (5, 1, 5, 7, '2026-11-23 20:32:56.747365', '2026-11-23 20:32:56.747365', NULL, NULL, false);
INSERT INTO public.sys_user_role (id, org_id, user_id, role_id, created_at, updated_at, created_by, updated_by, deleted) VALUES (6, 1, 6, 6, '2026-11-23 20:32:56.747365', '2026-11-23 20:32:56.747365', NULL, NULL, false);
INSERT INTO public.sys_user_role (id, org_id, user_id, role_id, created_at, updated_at, created_by, updated_by, deleted) VALUES (7, 1, 7, 8, '2026-11-23 20:32:56.747365', '2026-11-23 20:32:56.747365', NULL, NULL, false);
INSERT INTO public.sys_user_role (id, org_id, user_id, role_id, created_at, updated_at, created_by, updated_by, deleted) VALUES (8, 1, 8, 3, '2026-11-23 20:32:56.747365', '2026-11-23 20:32:56.747365', NULL, NULL, false);
INSERT INTO public.sys_user_role (id, org_id, user_id, role_id, created_at, updated_at, created_by, updated_by, deleted) VALUES (9, 1, 9, 4, '2026-11-23 20:32:56.747365', '2026-11-23 20:32:56.747365', NULL, NULL, false);
INSERT INTO public.sys_user_role (id, org_id, user_id, role_id, created_at, updated_at, created_by, updated_by, deleted) VALUES (10, 1, 10, 14, '2026-11-23 20:32:56.747365', '2026-11-23 20:32:56.747365', NULL, NULL, false);
INSERT INTO public.sys_user_role (id, org_id, user_id, role_id, created_at, updated_at, created_by, updated_by, deleted) VALUES (11, 1, 11, 14, '2026-11-23 20:32:56.747365', '2026-11-23 20:32:56.747365', NULL, NULL, false);
INSERT INTO public.sys_user_role (id, org_id, user_id, role_id, created_at, updated_at, created_by, updated_by, deleted) VALUES (12, 1, 12, 12, '2026-11-23 20:32:56.747365', '2026-11-23 20:32:56.747365', NULL, NULL, false);
INSERT INTO public.sys_user_role (id, org_id, user_id, role_id, created_at, updated_at, created_by, updated_by, deleted) VALUES (13, 1, 13, 1, '2026-11-23 20:32:56.747365', '2026-11-23 20:32:56.747365', NULL, NULL, false);
INSERT INTO public.sys_user_role (id, org_id, user_id, role_id, created_at, updated_at, created_by, updated_by, deleted) VALUES (14, 1, 14, 9, '2026-11-23 20:32:56.747365', '2026-11-23 20:32:56.747365', NULL, NULL, false);
INSERT INTO public.sys_user_role (id, org_id, user_id, role_id, created_at, updated_at, created_by, updated_by, deleted) VALUES (15, 1, 15, 18, '2026-11-23 20:32:56.747365', '2026-11-23 20:32:56.747365', NULL, NULL, false);
INSERT INTO public.sys_user_role (id, org_id, user_id, role_id, created_at, updated_at, created_by, updated_by, deleted) VALUES (16, 1, 16, 15, '2026-11-23 20:32:56.747365', '2026-11-23 20:32:56.747365', NULL, NULL, false);
INSERT INTO public.sys_user_role (id, org_id, user_id, role_id, created_at, updated_at, created_by, updated_by, deleted) VALUES (17, 1, 17, 5, '2026-11-23 20:32:56.747365', '2026-11-23 20:32:56.747365', NULL, NULL, false);
INSERT INTO public.sys_user_role (id, org_id, user_id, role_id, created_at, updated_at, created_by, updated_by, deleted) VALUES (18, 1, 18, 17, '2026-11-23 20:32:56.747365', '2026-11-23 20:32:56.747365', NULL, NULL, false);
INSERT INTO public.sys_user_role (id, org_id, user_id, role_id, created_at, updated_at, created_by, updated_by, deleted) VALUES (19, 1, 19, 16, '2026-11-23 20:32:56.747365', '2026-11-23 20:32:56.747365', NULL, NULL, false);
INSERT INTO public.sys_user_role (id, org_id, user_id, role_id, created_at, updated_at, created_by, updated_by, deleted) VALUES (20, 1, 20, 20, '2026-11-23 20:32:56.747365', '2026-11-23 20:32:56.747365', NULL, NULL, false);
INSERT INTO public.sys_user_role (id, org_id, user_id, role_id, created_at, updated_at, created_by, updated_by, deleted) VALUES (21, 1, 21, 11, '2026-11-23 20:32:56.747365', '2026-11-23 20:32:56.747365', NULL, NULL, false);
INSERT INTO public.sys_user_role (id, org_id, user_id, role_id, created_at, updated_at, created_by, updated_by, deleted) VALUES (22, 1, 22, 2, '2026-11-23 20:32:56.747365', '2026-11-23 20:32:56.747365', NULL, NULL, false);
INSERT INTO public.sys_user_role (id, org_id, user_id, role_id, created_at, updated_at, created_by, updated_by, deleted) VALUES (172, 1, 172, 6, '2026-11-23 23:35:08.671362', '2026-11-23 23:35:08.671362', 1, NULL, false);
INSERT INTO public.sys_user_role (id, org_id, user_id, role_id, created_at, updated_at, created_by, updated_by, deleted) VALUES (176, 1, 1, 19, '2026-11-24 10:14:00.547983', '2026-11-24 10:14:00.547983', 1, NULL, false);
INSERT INTO public.sys_user_role (id, org_id, user_id, role_id, created_at, updated_at, created_by, updated_by, deleted) VALUES (177, 1, 173, 7, '2026-11-24 10:30:25.605981', '2026-11-24 10:30:25.605981', 1, NULL, false);
INSERT INTO public.sys_user_role (id, org_id, user_id, role_id, created_at, updated_at, created_by, updated_by, deleted) VALUES (178, 1, 174, 10, '2026-11-24 15:27:09.6288', '2026-11-24 15:27:09.6288', 1, NULL, false);


ALTER TABLE public.sys_user_role ENABLE TRIGGER ALL;

--
-- Data for Name: sys_user_shop; Type: TABLE DATA; Schema: public; Owner: -
--

ALTER TABLE public.sys_user_shop DISABLE TRIGGER ALL;

INSERT INTO public.sys_user_shop (id, org_id, user_id, shop_id, created_at, updated_at, created_by, updated_by, deleted) VALUES (1, 1, 1, 1, '2026-11-23 20:52:05.140717', '2026-11-23 20:52:05.140717', NULL, NULL, false);
INSERT INTO public.sys_user_shop (id, org_id, user_id, shop_id, created_at, updated_at, created_by, updated_by, deleted) VALUES (2, 1, 1, 2, '2026-11-23 20:52:05.140717', '2026-11-23 20:52:05.140717', NULL, NULL, false);
INSERT INTO public.sys_user_shop (id, org_id, user_id, shop_id, created_at, updated_at, created_by, updated_by, deleted) VALUES (3, 1, 1, 3, '2026-11-23 20:52:05.140717', '2026-11-23 20:52:05.140717', NULL, NULL, false);
INSERT INTO public.sys_user_shop (id, org_id, user_id, shop_id, created_at, updated_at, created_by, updated_by, deleted) VALUES (4, 1, 3, 1, '2026-11-23 20:52:05.140717', '2026-11-23 20:52:05.140717', NULL, NULL, false);
INSERT INTO public.sys_user_shop (id, org_id, user_id, shop_id, created_at, updated_at, created_by, updated_by, deleted) VALUES (5, 1, 3, 2, '2026-11-23 20:52:05.140717', '2026-11-23 20:52:05.140717', NULL, NULL, false);
INSERT INTO public.sys_user_shop (id, org_id, user_id, shop_id, created_at, updated_at, created_by, updated_by, deleted) VALUES (6, 1, 3, 3, '2026-11-23 20:52:05.140717', '2026-11-23 20:52:05.140717', NULL, NULL, false);
INSERT INTO public.sys_user_shop (id, org_id, user_id, shop_id, created_at, updated_at, created_by, updated_by, deleted) VALUES (7, 1, 4, 1, '2026-11-23 20:52:05.140717', '2026-11-23 20:52:05.140717', NULL, NULL, false);
INSERT INTO public.sys_user_shop (id, org_id, user_id, shop_id, created_at, updated_at, created_by, updated_by, deleted) VALUES (8, 1, 5, 1, '2026-11-23 20:52:05.140717', '2026-11-23 20:52:05.140717', NULL, NULL, false);
INSERT INTO public.sys_user_shop (id, org_id, user_id, shop_id, created_at, updated_at, created_by, updated_by, deleted) VALUES (9, 1, 5, 2, '2026-11-23 20:52:05.140717', '2026-11-23 20:52:05.140717', NULL, NULL, false);
INSERT INTO public.sys_user_shop (id, org_id, user_id, shop_id, created_at, updated_at, created_by, updated_by, deleted) VALUES (10, 1, 6, 1, '2026-11-23 20:52:05.140717', '2026-11-23 20:52:05.140717', NULL, NULL, false);
INSERT INTO public.sys_user_shop (id, org_id, user_id, shop_id, created_at, updated_at, created_by, updated_by, deleted) VALUES (11, 1, 6, 2, '2026-11-23 20:52:05.140717', '2026-11-23 20:52:05.140717', NULL, NULL, false);
INSERT INTO public.sys_user_shop (id, org_id, user_id, shop_id, created_at, updated_at, created_by, updated_by, deleted) VALUES (12, 1, 7, 1, '2026-11-23 20:52:05.140717', '2026-11-23 20:52:05.140717', NULL, NULL, false);
INSERT INTO public.sys_user_shop (id, org_id, user_id, shop_id, created_at, updated_at, created_by, updated_by, deleted) VALUES (13, 1, 7, 2, '2026-11-23 20:52:05.140717', '2026-11-23 20:52:05.140717', NULL, NULL, false);
INSERT INTO public.sys_user_shop (id, org_id, user_id, shop_id, created_at, updated_at, created_by, updated_by, deleted) VALUES (14, 1, 8, 1, '2026-11-23 20:52:05.140717', '2026-11-23 20:52:05.140717', NULL, NULL, false);
INSERT INTO public.sys_user_shop (id, org_id, user_id, shop_id, created_at, updated_at, created_by, updated_by, deleted) VALUES (15, 1, 8, 2, '2026-11-23 20:52:05.140717', '2026-11-23 20:52:05.140717', NULL, NULL, false);
INSERT INTO public.sys_user_shop (id, org_id, user_id, shop_id, created_at, updated_at, created_by, updated_by, deleted) VALUES (16, 1, 8, 3, '2026-11-23 20:52:05.140717', '2026-11-23 20:52:05.140717', NULL, NULL, false);
INSERT INTO public.sys_user_shop (id, org_id, user_id, shop_id, created_at, updated_at, created_by, updated_by, deleted) VALUES (17, 1, 9, 1, '2026-11-23 20:52:05.140717', '2026-11-23 20:52:05.140717', NULL, NULL, false);
INSERT INTO public.sys_user_shop (id, org_id, user_id, shop_id, created_at, updated_at, created_by, updated_by, deleted) VALUES (18, 1, 9, 2, '2026-11-23 20:52:05.140717', '2026-11-23 20:52:05.140717', NULL, NULL, false);
INSERT INTO public.sys_user_shop (id, org_id, user_id, shop_id, created_at, updated_at, created_by, updated_by, deleted) VALUES (19, 1, 9, 3, '2026-11-23 20:52:05.140717', '2026-11-23 20:52:05.140717', NULL, NULL, false);
INSERT INTO public.sys_user_shop (id, org_id, user_id, shop_id, created_at, updated_at, created_by, updated_by, deleted) VALUES (20, 1, 10, 1, '2026-11-23 20:52:05.140717', '2026-11-23 20:52:05.140717', NULL, NULL, false);
INSERT INTO public.sys_user_shop (id, org_id, user_id, shop_id, created_at, updated_at, created_by, updated_by, deleted) VALUES (21, 1, 10, 2, '2026-11-23 20:52:05.140717', '2026-11-23 20:52:05.140717', NULL, NULL, false);
INSERT INTO public.sys_user_shop (id, org_id, user_id, shop_id, created_at, updated_at, created_by, updated_by, deleted) VALUES (22, 1, 10, 3, '2026-11-23 20:52:05.140717', '2026-11-23 20:52:05.140717', NULL, NULL, false);
INSERT INTO public.sys_user_shop (id, org_id, user_id, shop_id, created_at, updated_at, created_by, updated_by, deleted) VALUES (23, 1, 11, 1, '2026-11-23 20:52:05.140717', '2026-11-23 20:52:05.140717', NULL, NULL, false);
INSERT INTO public.sys_user_shop (id, org_id, user_id, shop_id, created_at, updated_at, created_by, updated_by, deleted) VALUES (24, 1, 11, 2, '2026-11-23 20:52:05.140717', '2026-11-23 20:52:05.140717', NULL, NULL, false);
INSERT INTO public.sys_user_shop (id, org_id, user_id, shop_id, created_at, updated_at, created_by, updated_by, deleted) VALUES (25, 1, 11, 3, '2026-11-23 20:52:05.140717', '2026-11-23 20:52:05.140717', NULL, NULL, false);
INSERT INTO public.sys_user_shop (id, org_id, user_id, shop_id, created_at, updated_at, created_by, updated_by, deleted) VALUES (26, 1, 12, 1, '2026-11-23 20:52:05.140717', '2026-11-23 20:52:05.140717', NULL, NULL, false);
INSERT INTO public.sys_user_shop (id, org_id, user_id, shop_id, created_at, updated_at, created_by, updated_by, deleted) VALUES (27, 1, 12, 2, '2026-11-23 20:52:05.140717', '2026-11-23 20:52:05.140717', NULL, NULL, false);
INSERT INTO public.sys_user_shop (id, org_id, user_id, shop_id, created_at, updated_at, created_by, updated_by, deleted) VALUES (28, 1, 12, 3, '2026-11-23 20:52:05.140717', '2026-11-23 20:52:05.140717', NULL, NULL, false);
INSERT INTO public.sys_user_shop (id, org_id, user_id, shop_id, created_at, updated_at, created_by, updated_by, deleted) VALUES (29, 1, 13, 1, '2026-11-23 20:52:05.140717', '2026-11-23 20:52:05.140717', NULL, NULL, false);
INSERT INTO public.sys_user_shop (id, org_id, user_id, shop_id, created_at, updated_at, created_by, updated_by, deleted) VALUES (30, 1, 13, 2, '2026-11-23 20:52:05.140717', '2026-11-23 20:52:05.140717', NULL, NULL, false);
INSERT INTO public.sys_user_shop (id, org_id, user_id, shop_id, created_at, updated_at, created_by, updated_by, deleted) VALUES (31, 1, 13, 3, '2026-11-23 20:52:05.140717', '2026-11-23 20:52:05.140717', NULL, NULL, false);
INSERT INTO public.sys_user_shop (id, org_id, user_id, shop_id, created_at, updated_at, created_by, updated_by, deleted) VALUES (32, 1, 14, 1, '2026-11-23 20:52:05.140717', '2026-11-23 20:52:05.140717', NULL, NULL, false);
INSERT INTO public.sys_user_shop (id, org_id, user_id, shop_id, created_at, updated_at, created_by, updated_by, deleted) VALUES (33, 1, 14, 2, '2026-11-23 20:52:05.140717', '2026-11-23 20:52:05.140717', NULL, NULL, false);
INSERT INTO public.sys_user_shop (id, org_id, user_id, shop_id, created_at, updated_at, created_by, updated_by, deleted) VALUES (34, 1, 14, 3, '2026-11-23 20:52:05.140717', '2026-11-23 20:52:05.140717', NULL, NULL, false);
INSERT INTO public.sys_user_shop (id, org_id, user_id, shop_id, created_at, updated_at, created_by, updated_by, deleted) VALUES (35, 1, 15, 1, '2026-11-23 20:52:05.140717', '2026-11-23 20:52:05.140717', NULL, NULL, false);
INSERT INTO public.sys_user_shop (id, org_id, user_id, shop_id, created_at, updated_at, created_by, updated_by, deleted) VALUES (36, 1, 15, 2, '2026-11-23 20:52:05.140717', '2026-11-23 20:52:05.140717', NULL, NULL, false);
INSERT INTO public.sys_user_shop (id, org_id, user_id, shop_id, created_at, updated_at, created_by, updated_by, deleted) VALUES (37, 1, 15, 3, '2026-11-23 20:52:05.140717', '2026-11-23 20:52:05.140717', NULL, NULL, false);
INSERT INTO public.sys_user_shop (id, org_id, user_id, shop_id, created_at, updated_at, created_by, updated_by, deleted) VALUES (38, 1, 16, 1, '2026-11-23 20:52:05.140717', '2026-11-23 20:52:05.140717', NULL, NULL, false);
INSERT INTO public.sys_user_shop (id, org_id, user_id, shop_id, created_at, updated_at, created_by, updated_by, deleted) VALUES (39, 1, 16, 2, '2026-11-23 20:52:05.140717', '2026-11-23 20:52:05.140717', NULL, NULL, false);
INSERT INTO public.sys_user_shop (id, org_id, user_id, shop_id, created_at, updated_at, created_by, updated_by, deleted) VALUES (40, 1, 16, 3, '2026-11-23 20:52:05.140717', '2026-11-23 20:52:05.140717', NULL, NULL, false);
INSERT INTO public.sys_user_shop (id, org_id, user_id, shop_id, created_at, updated_at, created_by, updated_by, deleted) VALUES (41, 1, 17, 1, '2026-11-23 20:52:05.140717', '2026-11-23 20:52:05.140717', NULL, NULL, false);
INSERT INTO public.sys_user_shop (id, org_id, user_id, shop_id, created_at, updated_at, created_by, updated_by, deleted) VALUES (42, 1, 17, 2, '2026-11-23 20:52:05.140717', '2026-11-23 20:52:05.140717', NULL, NULL, false);
INSERT INTO public.sys_user_shop (id, org_id, user_id, shop_id, created_at, updated_at, created_by, updated_by, deleted) VALUES (43, 1, 17, 3, '2026-11-23 20:52:05.140717', '2026-11-23 20:52:05.140717', NULL, NULL, false);
INSERT INTO public.sys_user_shop (id, org_id, user_id, shop_id, created_at, updated_at, created_by, updated_by, deleted) VALUES (44, 1, 18, 1, '2026-11-23 20:52:05.140717', '2026-11-23 20:52:05.140717', NULL, NULL, false);
INSERT INTO public.sys_user_shop (id, org_id, user_id, shop_id, created_at, updated_at, created_by, updated_by, deleted) VALUES (45, 1, 18, 2, '2026-11-23 20:52:05.140717', '2026-11-23 20:52:05.140717', NULL, NULL, false);
INSERT INTO public.sys_user_shop (id, org_id, user_id, shop_id, created_at, updated_at, created_by, updated_by, deleted) VALUES (46, 1, 18, 3, '2026-11-23 20:52:05.140717', '2026-11-23 20:52:05.140717', NULL, NULL, false);
INSERT INTO public.sys_user_shop (id, org_id, user_id, shop_id, created_at, updated_at, created_by, updated_by, deleted) VALUES (47, 1, 19, 1, '2026-11-23 20:52:05.140717', '2026-11-23 20:52:05.140717', NULL, NULL, false);
INSERT INTO public.sys_user_shop (id, org_id, user_id, shop_id, created_at, updated_at, created_by, updated_by, deleted) VALUES (48, 1, 19, 2, '2026-11-23 20:52:05.140717', '2026-11-23 20:52:05.140717', NULL, NULL, false);
INSERT INTO public.sys_user_shop (id, org_id, user_id, shop_id, created_at, updated_at, created_by, updated_by, deleted) VALUES (49, 1, 19, 3, '2026-11-23 20:52:05.140717', '2026-11-23 20:52:05.140717', NULL, NULL, false);
INSERT INTO public.sys_user_shop (id, org_id, user_id, shop_id, created_at, updated_at, created_by, updated_by, deleted) VALUES (50, 1, 20, 1, '2026-11-23 20:52:05.140717', '2026-11-23 20:52:05.140717', NULL, NULL, false);
INSERT INTO public.sys_user_shop (id, org_id, user_id, shop_id, created_at, updated_at, created_by, updated_by, deleted) VALUES (51, 1, 20, 2, '2026-11-23 20:52:05.140717', '2026-11-23 20:52:05.140717', NULL, NULL, false);
INSERT INTO public.sys_user_shop (id, org_id, user_id, shop_id, created_at, updated_at, created_by, updated_by, deleted) VALUES (52, 1, 20, 3, '2026-11-23 20:52:05.140717', '2026-11-23 20:52:05.140717', NULL, NULL, false);
INSERT INTO public.sys_user_shop (id, org_id, user_id, shop_id, created_at, updated_at, created_by, updated_by, deleted) VALUES (53, 1, 21, 1, '2026-11-23 20:52:05.140717', '2026-11-23 20:52:05.140717', NULL, NULL, false);
INSERT INTO public.sys_user_shop (id, org_id, user_id, shop_id, created_at, updated_at, created_by, updated_by, deleted) VALUES (54, 1, 21, 2, '2026-11-23 20:52:05.140717', '2026-11-23 20:52:05.140717', NULL, NULL, false);
INSERT INTO public.sys_user_shop (id, org_id, user_id, shop_id, created_at, updated_at, created_by, updated_by, deleted) VALUES (55, 1, 21, 3, '2026-11-23 20:52:05.140717', '2026-11-23 20:52:05.140717', NULL, NULL, false);
INSERT INTO public.sys_user_shop (id, org_id, user_id, shop_id, created_at, updated_at, created_by, updated_by, deleted) VALUES (56, 1, 22, 1, '2026-11-23 20:52:05.140717', '2026-11-23 20:52:05.140717', NULL, NULL, false);
INSERT INTO public.sys_user_shop (id, org_id, user_id, shop_id, created_at, updated_at, created_by, updated_by, deleted) VALUES (57, 1, 22, 2, '2026-11-23 20:52:05.140717', '2026-11-23 20:52:05.140717', NULL, NULL, false);
INSERT INTO public.sys_user_shop (id, org_id, user_id, shop_id, created_at, updated_at, created_by, updated_by, deleted) VALUES (58, 1, 22, 3, '2026-11-23 20:52:05.140717', '2026-11-23 20:52:05.140717', NULL, NULL, false);


ALTER TABLE public.sys_user_shop ENABLE TRIGGER ALL;

--
-- Data for Name: trials; Type: TABLE DATA; Schema: public; Owner: -
--

ALTER TABLE public.trials DISABLE TRIGGER ALL;



ALTER TABLE public.trials ENABLE TRIGGER ALL;

--
-- Data for Name: weekly_facts; Type: TABLE DATA; Schema: public; Owner: -
--

ALTER TABLE public.weekly_facts DISABLE TRIGGER ALL;



ALTER TABLE public.weekly_facts ENABLE TRIGGER ALL;

--
-- Name: audit_log_id_seq; Type: SEQUENCE SET; Schema: public; Owner: -
--

SELECT pg_catalog.setval('public.audit_log_id_seq', 699, true);


--
-- Name: bi_approval_flow_id_seq; Type: SEQUENCE SET; Schema: public; Owner: -
--

SELECT pg_catalog.setval('public.bi_approval_flow_id_seq', 15, true);


--
-- Name: bi_dashboard_access_request_id_seq; Type: SEQUENCE SET; Schema: public; Owner: -
--

SELECT pg_catalog.setval('public.bi_dashboard_access_request_id_seq', 9, true);


--
-- Name: bi_dashboard_designs_id_seq; Type: SEQUENCE SET; Schema: public; Owner: -
--

SELECT pg_catalog.setval('public.bi_dashboard_designs_id_seq', 102, true);


--
-- Name: bi_operation_log_id_seq; Type: SEQUENCE SET; Schema: public; Owner: -
--

SELECT pg_catalog.setval('public.bi_operation_log_id_seq', 333, true);


--
-- Name: bi_publish_approvals_id_seq; Type: SEQUENCE SET; Schema: public; Owner: -
--

SELECT pg_catalog.setval('public.bi_publish_approvals_id_seq', 33, true);


--
-- Name: biz_department_id_seq; Type: SEQUENCE SET; Schema: public; Owner: -
--

SELECT pg_catalog.setval('public.biz_department_id_seq', 10, true);


--
-- Name: biz_department_manager_history_id_seq; Type: SEQUENCE SET; Schema: public; Owner: -
--

SELECT pg_catalog.setval('public.biz_department_manager_history_id_seq', 15, true);


--
-- Name: biz_department_shop_id_seq; Type: SEQUENCE SET; Schema: public; Owner: -
--

SELECT pg_catalog.setval('public.biz_department_shop_id_seq', 8, true);


--
-- Name: biz_platform_config_id_seq; Type: SEQUENCE SET; Schema: public; Owner: -
--

SELECT pg_catalog.setval('public.biz_platform_config_id_seq', 1, false);


--
-- Name: biz_shop_id_seq; Type: SEQUENCE SET; Schema: public; Owner: -
--

SELECT pg_catalog.setval('public.biz_shop_id_seq', 22, true);


--
-- Name: pcc_agent_run_id_seq; Type: SEQUENCE SET; Schema: public; Owner: -
--

SELECT pg_catalog.setval('public.pcc_agent_run_id_seq', 1, false);


--
-- Name: pcc_asset_reference_id_seq; Type: SEQUENCE SET; Schema: public; Owner: -
--

SELECT pg_catalog.setval('public.pcc_asset_reference_id_seq', 1, false);


--
-- Name: pcc_compliance_check_id_seq; Type: SEQUENCE SET; Schema: public; Owner: -
--

SELECT pg_catalog.setval('public.pcc_compliance_check_id_seq', 1, false);


--
-- Name: pcc_content_approval_id_seq; Type: SEQUENCE SET; Schema: public; Owner: -
--

SELECT pg_catalog.setval('public.pcc_content_approval_id_seq', 1, false);


--
-- Name: pcc_generation_asset_id_seq; Type: SEQUENCE SET; Schema: public; Owner: -
--

SELECT pg_catalog.setval('public.pcc_generation_asset_id_seq', 1, false);


--
-- Name: pcc_generation_job_id_seq; Type: SEQUENCE SET; Schema: public; Owner: -
--

SELECT pg_catalog.setval('public.pcc_generation_job_id_seq', 1, false);


--
-- Name: pcc_generation_media_id_seq; Type: SEQUENCE SET; Schema: public; Owner: -
--

SELECT pg_catalog.setval('public.pcc_generation_media_id_seq', 1, false);


--
-- Name: pcc_workflow_template_id_seq; Type: SEQUENCE SET; Schema: public; Owner: -
--

SELECT pg_catalog.setval('public.pcc_workflow_template_id_seq', 3, true);


--
-- Name: sys_department_permission_id_seq; Type: SEQUENCE SET; Schema: public; Owner: -
--

SELECT pg_catalog.setval('public.sys_department_permission_id_seq', 126, true);


--
-- Name: sys_org_id_seq; Type: SEQUENCE SET; Schema: public; Owner: -
--

SELECT pg_catalog.setval('public.sys_org_id_seq', 10, true);


--
-- Name: sys_permission_id_seq; Type: SEQUENCE SET; Schema: public; Owner: -
--

SELECT pg_catalog.setval('public.sys_permission_id_seq', 269, true);


--
-- Name: sys_role_id_seq; Type: SEQUENCE SET; Schema: public; Owner: -
--

SELECT pg_catalog.setval('public.sys_role_id_seq', 181, true);


--
-- Name: sys_role_permission_id_seq; Type: SEQUENCE SET; Schema: public; Owner: -
--

SELECT pg_catalog.setval('public.sys_role_permission_id_seq', 338, true);


--
-- Name: sys_user_id_seq; Type: SEQUENCE SET; Schema: public; Owner: -
--

SELECT pg_catalog.setval('public.sys_user_id_seq', 174, true);


--
-- Name: sys_user_role_id_seq; Type: SEQUENCE SET; Schema: public; Owner: -
--

SELECT pg_catalog.setval('public.sys_user_role_id_seq', 178, true);


--
-- Name: sys_user_shop_id_seq; Type: SEQUENCE SET; Schema: public; Owner: -
--

SELECT pg_catalog.setval('public.sys_user_shop_id_seq', 406, true);


--
-- PostgreSQL database dump complete
--


