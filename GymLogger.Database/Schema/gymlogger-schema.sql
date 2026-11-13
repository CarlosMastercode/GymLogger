--
-- PostgreSQL database dump
--

\restrict WwFzZuiyzX27Vb5etBBR2cwAyqV5gZvdfbXBJv2vAGz2l8zxlPrWqGOQkwlEDDn

-- Dumped from database version 17.11 (Debian 17.11-1.pgdg13+2)
-- Dumped by pg_dump version 17.11 (Debian 17.11-1.pgdg13+2)

SET statement_timeout = 0;
SET lock_timeout = 0;
SET idle_in_transaction_session_timeout = 0;
SET transaction_timeout = 0;
SET client_encoding = 'UTF8';
SET standard_conforming_strings = on;
SELECT pg_catalog.set_config('search_path', '', false);
SET check_function_bodies = false;
SET xmloption = content;
SET client_min_messages = warning;
SET row_security = off;

--
-- Name: enforce_one_trial_per_user(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.enforce_one_trial_per_user() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
    IF NEW.status = 'trialing'
       AND EXISTS (
           SELECT 1
           FROM public.user_subscriptions
           WHERE user_id = NEW.user_id
       )
    THEN
        RAISE EXCEPTION
            'User % already has a subscription record and is not eligible for another trial.',
            NEW.user_id
            USING ERRCODE = '23505';
    END IF;

    RETURN NEW;
END;
$$;


SET default_tablespace = '';

SET default_table_access_method = heap;

--
-- Name: auth_challenges; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.auth_challenges (
    id bigint NOT NULL,
    user_email_id bigint,
    user_phone_id bigint,
    code_hash text NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    expires_at timestamp with time zone DEFAULT (now() + '00:05:00'::interval) NOT NULL,
    failed_attempts integer DEFAULT 0 NOT NULL,
    consumed_at timestamp with time zone,
    CONSTRAINT auth_challenges_check CHECK ((((user_email_id IS NOT NULL) AND (user_phone_id IS NULL)) OR ((user_email_id IS NULL) AND (user_phone_id IS NOT NULL)))),
    CONSTRAINT auth_challenges_check1 CHECK ((expires_at > created_at)),
    CONSTRAINT auth_challenges_check2 CHECK (((consumed_at IS NULL) OR (consumed_at >= created_at))),
    CONSTRAINT auth_challenges_failed_attempts_check CHECK (((failed_attempts >= 0) AND (failed_attempts <= 5)))
);


--
-- Name: TABLE auth_challenges; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE public.auth_challenges IS 'Stores passwordless authentication challenges delivered to verified email addresses or phone numbers. Challenges expire after five minutes and may be consumed only once.';


--
-- Name: COLUMN auth_challenges.id; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.auth_challenges.id IS 'Unique identifier for the authentication challenge.';


--
-- Name: COLUMN auth_challenges.user_email_id; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.auth_challenges.user_email_id IS 'Email contact receiving the challenge. NULL when the challenge is sent by SMS.';


--
-- Name: COLUMN auth_challenges.user_phone_id; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.auth_challenges.user_phone_id IS 'Phone contact receiving the challenge. NULL when the challenge is sent by email.';


--
-- Name: COLUMN auth_challenges.code_hash; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.auth_challenges.code_hash IS 'Cryptographic hash of the one-time code. The plaintext code must never be stored here.';


--
-- Name: COLUMN auth_challenges.created_at; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.auth_challenges.created_at IS 'Timestamp when the challenge was created.';


--
-- Name: COLUMN auth_challenges.expires_at; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.auth_challenges.expires_at IS 'Timestamp after which the challenge can no longer be used. Defaults to five minutes after creation.';


--
-- Name: COLUMN auth_challenges.failed_attempts; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.auth_challenges.failed_attempts IS 'Number of failed verification attempts. The API must reject further attempts after five failures.';


--
-- Name: COLUMN auth_challenges.consumed_at; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.auth_challenges.consumed_at IS 'Timestamp when the challenge was successfully consumed. NULL indicates that it has not been consumed.';


--
-- Name: auth_challenges_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

ALTER TABLE public.auth_challenges ALTER COLUMN id ADD GENERATED ALWAYS AS IDENTITY (
    SEQUENCE NAME public.auth_challenges_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: auth_sessions; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.auth_sessions (
    id bigint NOT NULL,
    user_id bigint NOT NULL,
    token_hash text NOT NULL,
    stay_logged_in boolean DEFAULT false NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    expires_at timestamp with time zone NOT NULL,
    last_used_at timestamp with time zone,
    revoked_at timestamp with time zone,
    CONSTRAINT auth_sessions_check CHECK ((expires_at > created_at)),
    CONSTRAINT auth_sessions_check1 CHECK (((last_used_at IS NULL) OR (last_used_at >= created_at))),
    CONSTRAINT auth_sessions_check2 CHECK (((revoked_at IS NULL) OR (revoked_at >= created_at)))
);


--
-- Name: TABLE auth_sessions; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE public.auth_sessions IS 'Stores authenticated login sessions separately from workout sessions. Supports session expiration, revocation, and optional stay-logged-in behavior.';


--
-- Name: COLUMN auth_sessions.id; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.auth_sessions.id IS 'Unique identifier for the authenticated session.';


--
-- Name: COLUMN auth_sessions.user_id; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.auth_sessions.user_id IS 'Identifies the user associated with this authenticated session.';


--
-- Name: COLUMN auth_sessions.token_hash; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.auth_sessions.token_hash IS 'Hash of the bearer session token used to authenticate requests. The raw token must never be stored in the database.';


--
-- Name: COLUMN auth_sessions.stay_logged_in; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.auth_sessions.stay_logged_in IS 'Records whether the user opted to remain logged in for an extended period.';


--
-- Name: COLUMN auth_sessions.created_at; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.auth_sessions.created_at IS 'Timestamp when the authenticated session was created.';


--
-- Name: COLUMN auth_sessions.expires_at; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.auth_sessions.expires_at IS 'Timestamp when the session expires and can no longer be used to renew authentication.';


--
-- Name: COLUMN auth_sessions.last_used_at; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.auth_sessions.last_used_at IS 'Timestamp when the session was last used. NULL indicates that no subsequent use has been recorded.';


--
-- Name: COLUMN auth_sessions.revoked_at; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.auth_sessions.revoked_at IS 'Timestamp when the session was revoked. NULL indicates that it has not been revoked.';


--
-- Name: auth_sessions_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

ALTER TABLE public.auth_sessions ALTER COLUMN id ADD GENERATED ALWAYS AS IDENTITY (
    SEQUENCE NAME public.auth_sessions_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: billing_events; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.billing_events (
    id bigint NOT NULL,
    user_subscription_id bigint,
    provider character varying(30) NOT NULL,
    provider_event_id character varying(255) NOT NULL,
    event_type character varying(100) NOT NULL,
    processing_status character varying(20) DEFAULT 'pending'::character varying NOT NULL,
    occurred_at timestamp with time zone,
    received_at timestamp with time zone DEFAULT now() NOT NULL,
    processed_at timestamp with time zone,
    error_message character varying(1000),
    CONSTRAINT billing_events_processing_status_valid CHECK (((processing_status)::text = ANY ((ARRAY['pending'::character varying, 'processed'::character varying, 'failed'::character varying])::text[])))
);


--
-- Name: billing_events_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

ALTER TABLE public.billing_events ALTER COLUMN id ADD GENERATED ALWAYS AS IDENTITY (
    SEQUENCE NAME public.billing_events_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: contribution_models; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.contribution_models (
    id bigint NOT NULL,
    name character varying(100) NOT NULL,
    version character varying(50) NOT NULL,
    description text,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    last_used_at timestamp with time zone
);


--
-- Name: TABLE contribution_models; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE public.contribution_models IS 'Stores named, versioned models used to estimate the contribution of exercises to muscle groups.';


--
-- Name: COLUMN contribution_models.id; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.contribution_models.id IS 'Unique identifier for the contribution model.';


--
-- Name: COLUMN contribution_models.name; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.contribution_models.name IS 'Name of the contribution model.';


--
-- Name: COLUMN contribution_models.version; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.contribution_models.version IS 'Version identifier for the model. A new version can preserve historical reproducibility when the methodology or estimates change.';


--
-- Name: COLUMN contribution_models.description; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.contribution_models.description IS 'Optional description of the model and its methodology.';


--
-- Name: COLUMN contribution_models.created_at; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.contribution_models.created_at IS 'Timestamp when the model version was created.';


--
-- Name: COLUMN contribution_models.updated_at; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.contribution_models.updated_at IS 'Timestamp when the model version was last updated.';


--
-- Name: COLUMN contribution_models.last_used_at; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.contribution_models.last_used_at IS 'Timestamp when the model was last used. NULL indicates that it has not been used.';


--
-- Name: contribution_models_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

ALTER TABLE public.contribution_models ALTER COLUMN id ADD GENERATED ALWAYS AS IDENTITY (
    SEQUENCE NAME public.contribution_models_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: exercise_muscles; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.exercise_muscles (
    exercise_id bigint NOT NULL,
    muscle_group_id bigint NOT NULL
);


--
-- Name: TABLE exercise_muscles; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE public.exercise_muscles IS 'Associates exercises with the muscle groups they target. Supports many-to-many relationships.';


--
-- Name: COLUMN exercise_muscles.exercise_id; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.exercise_muscles.exercise_id IS 'Identifies the exercise in this association.';


--
-- Name: COLUMN exercise_muscles.muscle_group_id; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.exercise_muscles.muscle_group_id IS 'Identifies a muscle group targeted by the exercise.';


--
-- Name: exercises; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.exercises (
    id bigint NOT NULL,
    name character varying(100) NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL
);


--
-- Name: TABLE exercises; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE public.exercises IS 'Catalog of exercises available for users to record in workout sessions.';


--
-- Name: COLUMN exercises.id; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.exercises.id IS 'Unique identifier for the exercise.';


--
-- Name: COLUMN exercises.name; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.exercises.name IS 'Unique exercise name.';


--
-- Name: COLUMN exercises.created_at; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.exercises.created_at IS 'Timestamp when the exercise was added to the catalog.';


--
-- Name: exercises_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

ALTER TABLE public.exercises ALTER COLUMN id ADD GENERATED ALWAYS AS IDENTITY (
    SEQUENCE NAME public.exercises_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: muscle_contribution_estimates; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.muscle_contribution_estimates (
    id bigint NOT NULL,
    model_id bigint NOT NULL,
    exercise_id bigint NOT NULL,
    muscle_group_id bigint NOT NULL,
    contribution numeric(5,4) NOT NULL,
    source text NOT NULL,
    assessed_at timestamp with time zone,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    notes text,
    CONSTRAINT chk_contribution_range CHECK (((contribution >= (0)::numeric) AND (contribution <= (1)::numeric)))
);


--
-- Name: TABLE muscle_contribution_estimates; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE public.muscle_contribution_estimates IS 'Stores muscle-contribution estimates for exercises under specific model versions, including source provenance and assessment details.';


--
-- Name: COLUMN muscle_contribution_estimates.id; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.muscle_contribution_estimates.id IS 'Unique identifier for the muscle-contribution estimate.';


--
-- Name: COLUMN muscle_contribution_estimates.model_id; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.muscle_contribution_estimates.model_id IS 'Identifies the contribution model version associated with this estimate.';


--
-- Name: COLUMN muscle_contribution_estimates.exercise_id; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.muscle_contribution_estimates.exercise_id IS 'Identifies the exercise being evaluated.';


--
-- Name: COLUMN muscle_contribution_estimates.muscle_group_id; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.muscle_contribution_estimates.muscle_group_id IS 'Identifies the muscle group for which the contribution is estimated.';


--
-- Name: COLUMN muscle_contribution_estimates.contribution; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.muscle_contribution_estimates.contribution IS 'Estimated contribution proportion from 0 to 1, where 1 represents 100 percent.';


--
-- Name: COLUMN muscle_contribution_estimates.source; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.muscle_contribution_estimates.source IS 'Identifies the source or methodology used to produce the estimate.';


--
-- Name: COLUMN muscle_contribution_estimates.assessed_at; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.muscle_contribution_estimates.assessed_at IS 'Timestamp when the estimate was assessed. NULL when no assessment timestamp is recorded.';


--
-- Name: COLUMN muscle_contribution_estimates.created_at; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.muscle_contribution_estimates.created_at IS 'Timestamp when the estimate record was created.';


--
-- Name: COLUMN muscle_contribution_estimates.notes; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.muscle_contribution_estimates.notes IS 'Optional notes explaining the estimate, evidence, or assessment.';


--
-- Name: muscle_contribution_estimates_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

ALTER TABLE public.muscle_contribution_estimates ALTER COLUMN id ADD GENERATED ALWAYS AS IDENTITY (
    SEQUENCE NAME public.muscle_contribution_estimates_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: muscle_groups; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.muscle_groups (
    id bigint NOT NULL,
    name character varying(50) NOT NULL
);


--
-- Name: TABLE muscle_groups; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE public.muscle_groups IS 'Catalog of muscle groups that exercises can target.';


--
-- Name: COLUMN muscle_groups.id; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.muscle_groups.id IS 'Unique identifier for the muscle group.';


--
-- Name: COLUMN muscle_groups.name; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.muscle_groups.name IS 'Unique display name of the muscle group.';


--
-- Name: muscle_groups_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

ALTER TABLE public.muscle_groups ALTER COLUMN id ADD GENERATED ALWAYS AS IDENTITY (
    SEQUENCE NAME public.muscle_groups_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: subscription_plans; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.subscription_plans (
    id bigint NOT NULL,
    name character varying(50) NOT NULL,
    price_amount integer NOT NULL,
    currency character(3) DEFAULT 'USD'::bpchar NOT NULL,
    billing_interval character varying(20) NOT NULL,
    trial_duration_months integer DEFAULT 0 NOT NULL,
    is_active boolean DEFAULT true NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT subscription_plans_interval_valid CHECK (((billing_interval)::text = 'month'::text)),
    CONSTRAINT subscription_plans_price_nonnegative CHECK ((price_amount >= 0)),
    CONSTRAINT subscription_plans_trial_nonnegative CHECK ((trial_duration_months >= 0))
);


--
-- Name: subscription_plans_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

ALTER TABLE public.subscription_plans ALTER COLUMN id ADD GENERATED ALWAYS AS IDENTITY (
    SEQUENCE NAME public.subscription_plans_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: user_emails; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.user_emails (
    id bigint NOT NULL,
    user_id bigint NOT NULL,
    email character varying(254) NOT NULL,
    is_verified boolean DEFAULT false NOT NULL,
    verified_at timestamp with time zone,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT user_emails_check CHECK ((((is_verified = false) AND (verified_at IS NULL)) OR ((is_verified = true) AND (verified_at IS NOT NULL))))
);


--
-- Name: TABLE user_emails; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE public.user_emails IS 'Stores email addresses associated with user accounts, including verification status.';


--
-- Name: COLUMN user_emails.id; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.user_emails.id IS 'Unique identifier for this email record.';


--
-- Name: COLUMN user_emails.user_id; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.user_emails.user_id IS 'Identifies the user who owns this email address.';


--
-- Name: COLUMN user_emails.email; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.user_emails.email IS 'Email address used for account verification and passwordless sign-in. Must be unique across all users.';


--
-- Name: COLUMN user_emails.is_verified; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.user_emails.is_verified IS 'Indicates whether ownership of this email address has been verified.';


--
-- Name: COLUMN user_emails.verified_at; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.user_emails.verified_at IS 'Timestamp when this email address was verified. NULL when the address is unverified.';


--
-- Name: COLUMN user_emails.created_at; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.user_emails.created_at IS 'Timestamp when this email record was created.';


--
-- Name: user_emails_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

ALTER TABLE public.user_emails ALTER COLUMN id ADD GENERATED ALWAYS AS IDENTITY (
    SEQUENCE NAME public.user_emails_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: user_phones; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.user_phones (
    id bigint NOT NULL,
    user_id bigint NOT NULL,
    phone_number character varying(20) NOT NULL,
    is_verified boolean DEFAULT false NOT NULL,
    verified_at timestamp with time zone,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT user_phones_check CHECK ((((is_verified = false) AND (verified_at IS NULL)) OR ((is_verified = true) AND (verified_at IS NOT NULL))))
);


--
-- Name: TABLE user_phones; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE public.user_phones IS 'Stores phone numbers associated with user accounts, including verification status.';


--
-- Name: COLUMN user_phones.id; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.user_phones.id IS 'Unique identifier for this phone record.';


--
-- Name: COLUMN user_phones.user_id; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.user_phones.user_id IS 'Identifies the user who owns this phone number.';


--
-- Name: COLUMN user_phones.phone_number; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.user_phones.phone_number IS 'Phone number used for account verification and passwordless sign-in. Must be unique across all users.';


--
-- Name: COLUMN user_phones.is_verified; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.user_phones.is_verified IS 'Indicates whether ownership of this phone number has been verified.';


--
-- Name: COLUMN user_phones.verified_at; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.user_phones.verified_at IS 'Timestamp when this phone number was verified. NULL when the number is unverified.';


--
-- Name: COLUMN user_phones.created_at; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.user_phones.created_at IS 'Timestamp when this phone record was created.';


--
-- Name: user_phones_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

ALTER TABLE public.user_phones ALTER COLUMN id ADD GENERATED ALWAYS AS IDENTITY (
    SEQUENCE NAME public.user_phones_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: user_subscriptions; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.user_subscriptions (
    id bigint NOT NULL,
    user_id bigint NOT NULL,
    subscription_plan_id bigint NOT NULL,
    status character varying(20) NOT NULL,
    trial_started_at timestamp with time zone,
    trial_ends_at timestamp with time zone,
    current_period_started_at timestamp with time zone,
    current_period_ends_at timestamp with time zone,
    cancel_at_period_end boolean DEFAULT false NOT NULL,
    canceled_at timestamp with time zone,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT user_subscriptions_period_dates_valid CHECK (((current_period_ends_at IS NULL) OR (current_period_started_at IS NULL) OR (current_period_ends_at > current_period_started_at))),
    CONSTRAINT user_subscriptions_status_valid CHECK (((status)::text = ANY ((ARRAY['trialing'::character varying, 'active'::character varying, 'canceled'::character varying, 'expired'::character varying])::text[]))),
    CONSTRAINT user_subscriptions_trial_dates_valid CHECK (((trial_ends_at IS NULL) OR (trial_started_at IS NULL) OR (trial_ends_at > trial_started_at)))
);


--
-- Name: user_subscriptions_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

ALTER TABLE public.user_subscriptions ALTER COLUMN id ADD GENERATED ALWAYS AS IDENTITY (
    SEQUENCE NAME public.user_subscriptions_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: users; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.users (
    id bigint NOT NULL,
    first_name character varying(100) NOT NULL,
    last_name character varying(100) NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL
);


--
-- Name: TABLE users; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE public.users IS 'Stores user accounts and their stable internal identities.';


--
-- Name: COLUMN users.id; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.users.id IS 'Unique internal identifier for the user. Referenced by workout sessions and contact records.';


--
-- Name: COLUMN users.first_name; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.users.first_name IS 'User first name.';


--
-- Name: COLUMN users.last_name; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.users.last_name IS 'User last name.';


--
-- Name: COLUMN users.created_at; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.users.created_at IS 'Timestamp when the user account was created.';


--
-- Name: users_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

ALTER TABLE public.users ALTER COLUMN id ADD GENERATED ALWAYS AS IDENTITY (
    SEQUENCE NAME public.users_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: workout_sessions; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.workout_sessions (
    id bigint NOT NULL,
    user_id bigint NOT NULL,
    started_at timestamp with time zone DEFAULT now() NOT NULL,
    ended_at timestamp with time zone,
    status character varying(20) DEFAULT 'in_progress'::character varying NOT NULL,
    CONSTRAINT workout_sessions_check CHECK (((((status)::text = 'in_progress'::text) AND (ended_at IS NULL)) OR (((status)::text = 'completed'::text) AND (ended_at IS NOT NULL)))),
    CONSTRAINT workout_sessions_check1 CHECK (((ended_at IS NULL) OR (ended_at >= started_at))),
    CONSTRAINT workout_sessions_status_check CHECK (((status)::text = ANY ((ARRAY['in_progress'::character varying, 'completed'::character varying])::text[])))
);


--
-- Name: TABLE workout_sessions; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE public.workout_sessions IS 'Records user workout sessions. In-progress sessions allow the application to offer recovery options when a user returns.';


--
-- Name: COLUMN workout_sessions.user_id; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.workout_sessions.user_id IS 'Identifies the user who owns this workout session.';


--
-- Name: COLUMN workout_sessions.started_at; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.workout_sessions.started_at IS 'Timestamp when the workout session began. Defaults to the database current time.';


--
-- Name: COLUMN workout_sessions.ended_at; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.workout_sessions.ended_at IS 'Timestamp when the session was completed. NULL indicates that the session is still in progress.';


--
-- Name: COLUMN workout_sessions.status; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.workout_sessions.status IS 'Session lifecycle status: in_progress or completed. Must agree with ended_at.';


--
-- Name: workout_sessions_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

ALTER TABLE public.workout_sessions ALTER COLUMN id ADD GENERATED ALWAYS AS IDENTITY (
    SEQUENCE NAME public.workout_sessions_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: workout_sets; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.workout_sets (
    id bigint NOT NULL,
    session_id bigint NOT NULL,
    exercise_id bigint NOT NULL,
    set_number integer NOT NULL,
    weight numeric(7,2) NOT NULL,
    reps integer NOT NULL,
    logged_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT workout_sets_reps_check CHECK ((reps > 0)),
    CONSTRAINT workout_sets_set_number_check CHECK ((set_number > 0)),
    CONSTRAINT workout_sets_weight_check CHECK ((weight >= (0)::numeric))
);


--
-- Name: TABLE workout_sets; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE public.workout_sets IS 'Records individual exercise sets performed during a workout session.';


--
-- Name: COLUMN workout_sets.session_id; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.workout_sets.session_id IS 'Identifies the workout session containing this set.';


--
-- Name: COLUMN workout_sets.exercise_id; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.workout_sets.exercise_id IS 'Identifies the exercise performed, referencing the exercise catalog.';


--
-- Name: COLUMN workout_sets.set_number; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.workout_sets.set_number IS 'Set sequence number for this exercise within the session.';


--
-- Name: COLUMN workout_sets.weight; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.workout_sets.weight IS 'Weight used for the set, stored to two decimal places. The unit system will be defined by the application.';


--
-- Name: COLUMN workout_sets.reps; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.workout_sets.reps IS 'Number of repetitions completed in the set.';


--
-- Name: COLUMN workout_sets.logged_at; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.workout_sets.logged_at IS 'Timestamp when the set was recorded.';


--
-- Name: workout_sets_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

ALTER TABLE public.workout_sets ALTER COLUMN id ADD GENERATED ALWAYS AS IDENTITY (
    SEQUENCE NAME public.workout_sets_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: auth_challenges auth_challenges_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.auth_challenges
    ADD CONSTRAINT auth_challenges_pkey PRIMARY KEY (id);


--
-- Name: auth_sessions auth_sessions_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.auth_sessions
    ADD CONSTRAINT auth_sessions_pkey PRIMARY KEY (id);


--
-- Name: auth_sessions auth_sessions_token_hash_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.auth_sessions
    ADD CONSTRAINT auth_sessions_token_hash_key UNIQUE (token_hash);


--
-- Name: billing_events billing_events_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.billing_events
    ADD CONSTRAINT billing_events_pkey PRIMARY KEY (id);


--
-- Name: billing_events billing_events_provider_event_unique; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.billing_events
    ADD CONSTRAINT billing_events_provider_event_unique UNIQUE (provider, provider_event_id);


--
-- Name: contribution_models contribution_models_name_version_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.contribution_models
    ADD CONSTRAINT contribution_models_name_version_key UNIQUE (name, version);


--
-- Name: contribution_models contribution_models_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.contribution_models
    ADD CONSTRAINT contribution_models_pkey PRIMARY KEY (id);


--
-- Name: exercise_muscles exercise_muscles_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.exercise_muscles
    ADD CONSTRAINT exercise_muscles_pkey PRIMARY KEY (exercise_id, muscle_group_id);


--
-- Name: exercises exercises_name_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.exercises
    ADD CONSTRAINT exercises_name_key UNIQUE (name);


--
-- Name: exercises exercises_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.exercises
    ADD CONSTRAINT exercises_pkey PRIMARY KEY (id);


--
-- Name: muscle_contribution_estimates muscle_contribution_estimates_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.muscle_contribution_estimates
    ADD CONSTRAINT muscle_contribution_estimates_pkey PRIMARY KEY (id);


--
-- Name: muscle_groups muscle_groups_name_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.muscle_groups
    ADD CONSTRAINT muscle_groups_name_key UNIQUE (name);


--
-- Name: muscle_groups muscle_groups_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.muscle_groups
    ADD CONSTRAINT muscle_groups_pkey PRIMARY KEY (id);


--
-- Name: subscription_plans subscription_plans_name_unique; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.subscription_plans
    ADD CONSTRAINT subscription_plans_name_unique UNIQUE (name);


--
-- Name: subscription_plans subscription_plans_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.subscription_plans
    ADD CONSTRAINT subscription_plans_pkey PRIMARY KEY (id);


--
-- Name: muscle_contribution_estimates uq_estimate_model_exercise_muscle_source; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.muscle_contribution_estimates
    ADD CONSTRAINT uq_estimate_model_exercise_muscle_source UNIQUE (model_id, exercise_id, muscle_group_id, source);


--
-- Name: user_emails user_emails_email_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.user_emails
    ADD CONSTRAINT user_emails_email_key UNIQUE (email);


--
-- Name: user_emails user_emails_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.user_emails
    ADD CONSTRAINT user_emails_pkey PRIMARY KEY (id);


--
-- Name: user_phones user_phones_phone_number_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.user_phones
    ADD CONSTRAINT user_phones_phone_number_key UNIQUE (phone_number);


--
-- Name: user_phones user_phones_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.user_phones
    ADD CONSTRAINT user_phones_pkey PRIMARY KEY (id);


--
-- Name: user_subscriptions user_subscriptions_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.user_subscriptions
    ADD CONSTRAINT user_subscriptions_pkey PRIMARY KEY (id);


--
-- Name: users users_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.users
    ADD CONSTRAINT users_pkey PRIMARY KEY (id);


--
-- Name: workout_sessions workout_sessions_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.workout_sessions
    ADD CONSTRAINT workout_sessions_pkey PRIMARY KEY (id);


--
-- Name: workout_sets workout_sets_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.workout_sets
    ADD CONSTRAINT workout_sets_pkey PRIMARY KEY (id);


--
-- Name: workout_sets workout_sets_session_id_exercise_id_set_number_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.workout_sets
    ADD CONSTRAINT workout_sets_session_id_exercise_id_set_number_key UNIQUE (session_id, exercise_id, set_number);


--
-- Name: billing_events_processing_status_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX billing_events_processing_status_idx ON public.billing_events USING btree (processing_status);


--
-- Name: billing_events_subscription_id_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX billing_events_subscription_id_idx ON public.billing_events USING btree (user_subscription_id);


--
-- Name: idx_auth_challenges_user_email; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_auth_challenges_user_email ON public.auth_challenges USING btree (user_email_id, created_at DESC) WHERE (user_email_id IS NOT NULL);


--
-- Name: idx_auth_challenges_user_phone; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_auth_challenges_user_phone ON public.auth_challenges USING btree (user_phone_id, created_at DESC) WHERE (user_phone_id IS NOT NULL);


--
-- Name: idx_auth_sessions_active_user; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_auth_sessions_active_user ON public.auth_sessions USING btree (user_id) WHERE (revoked_at IS NULL);


--
-- Name: idx_auth_sessions_last_used; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_auth_sessions_last_used ON public.auth_sessions USING btree (last_used_at) WHERE (revoked_at IS NULL);


--
-- Name: idx_auth_sessions_user; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_auth_sessions_user ON public.auth_sessions USING btree (user_id, expires_at DESC);


--
-- Name: idx_workout_sessions_user_started_at; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_workout_sessions_user_started_at ON public.workout_sessions USING btree (user_id, started_at DESC);


--
-- Name: idx_workout_sets_session_logged_at; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_workout_sets_session_logged_at ON public.workout_sets USING btree (session_id, logged_at);


--
-- Name: uq_workout_sessions_one_in_progress_per_user; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX uq_workout_sessions_one_in_progress_per_user ON public.workout_sessions USING btree (user_id) WHERE ((status)::text = 'in_progress'::text);


--
-- Name: user_subscriptions_one_current_per_user_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX user_subscriptions_one_current_per_user_idx ON public.user_subscriptions USING btree (user_id) WHERE ((status)::text = ANY ((ARRAY['trialing'::character varying, 'active'::character varying])::text[]));


--
-- Name: user_subscriptions_status_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX user_subscriptions_status_idx ON public.user_subscriptions USING btree (status);


--
-- Name: user_subscriptions_user_id_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX user_subscriptions_user_id_idx ON public.user_subscriptions USING btree (user_id);


--
-- Name: user_subscriptions user_subscriptions_trial_eligibility; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER user_subscriptions_trial_eligibility BEFORE INSERT ON public.user_subscriptions FOR EACH ROW EXECUTE FUNCTION public.enforce_one_trial_per_user();


--
-- Name: auth_challenges auth_challenges_user_email_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.auth_challenges
    ADD CONSTRAINT auth_challenges_user_email_id_fkey FOREIGN KEY (user_email_id) REFERENCES public.user_emails(id) ON DELETE CASCADE;


--
-- Name: auth_challenges auth_challenges_user_phone_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.auth_challenges
    ADD CONSTRAINT auth_challenges_user_phone_id_fkey FOREIGN KEY (user_phone_id) REFERENCES public.user_phones(id) ON DELETE CASCADE;


--
-- Name: auth_sessions auth_sessions_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.auth_sessions
    ADD CONSTRAINT auth_sessions_user_id_fkey FOREIGN KEY (user_id) REFERENCES public.users(id) ON DELETE CASCADE;


--
-- Name: billing_events billing_events_subscription_fk; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.billing_events
    ADD CONSTRAINT billing_events_subscription_fk FOREIGN KEY (user_subscription_id) REFERENCES public.user_subscriptions(id) ON DELETE SET NULL;


--
-- Name: exercise_muscles exercise_muscles_exercise_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.exercise_muscles
    ADD CONSTRAINT exercise_muscles_exercise_id_fkey FOREIGN KEY (exercise_id) REFERENCES public.exercises(id);


--
-- Name: exercise_muscles exercise_muscles_muscle_group_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.exercise_muscles
    ADD CONSTRAINT exercise_muscles_muscle_group_id_fkey FOREIGN KEY (muscle_group_id) REFERENCES public.muscle_groups(id);


--
-- Name: muscle_contribution_estimates muscle_contribution_estimates_exercise_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.muscle_contribution_estimates
    ADD CONSTRAINT muscle_contribution_estimates_exercise_id_fkey FOREIGN KEY (exercise_id) REFERENCES public.exercises(id);


--
-- Name: muscle_contribution_estimates muscle_contribution_estimates_model_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.muscle_contribution_estimates
    ADD CONSTRAINT muscle_contribution_estimates_model_id_fkey FOREIGN KEY (model_id) REFERENCES public.contribution_models(id);


--
-- Name: muscle_contribution_estimates muscle_contribution_estimates_muscle_group_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.muscle_contribution_estimates
    ADD CONSTRAINT muscle_contribution_estimates_muscle_group_id_fkey FOREIGN KEY (muscle_group_id) REFERENCES public.muscle_groups(id);


--
-- Name: user_emails user_emails_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.user_emails
    ADD CONSTRAINT user_emails_user_id_fkey FOREIGN KEY (user_id) REFERENCES public.users(id) ON DELETE CASCADE;


--
-- Name: user_phones user_phones_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.user_phones
    ADD CONSTRAINT user_phones_user_id_fkey FOREIGN KEY (user_id) REFERENCES public.users(id) ON DELETE CASCADE;


--
-- Name: user_subscriptions user_subscriptions_plan_fk; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.user_subscriptions
    ADD CONSTRAINT user_subscriptions_plan_fk FOREIGN KEY (subscription_plan_id) REFERENCES public.subscription_plans(id) ON DELETE RESTRICT;


--
-- Name: user_subscriptions user_subscriptions_user_fk; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.user_subscriptions
    ADD CONSTRAINT user_subscriptions_user_fk FOREIGN KEY (user_id) REFERENCES public.users(id) ON DELETE CASCADE;


--
-- Name: workout_sessions workout_sessions_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.workout_sessions
    ADD CONSTRAINT workout_sessions_user_id_fkey FOREIGN KEY (user_id) REFERENCES public.users(id) ON DELETE CASCADE;


--
-- Name: workout_sets workout_sets_exercise_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.workout_sets
    ADD CONSTRAINT workout_sets_exercise_id_fkey FOREIGN KEY (exercise_id) REFERENCES public.exercises(id);


--
-- Name: workout_sets workout_sets_session_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.workout_sets
    ADD CONSTRAINT workout_sets_session_id_fkey FOREIGN KEY (session_id) REFERENCES public.workout_sessions(id) ON DELETE CASCADE;


--
-- PostgreSQL database dump complete
--

\unrestrict WwFzZuiyzX27Vb5etBBR2cwAyqV5gZvdfbXBJv2vAGz2l8zxlPrWqGOQkwlEDDn
