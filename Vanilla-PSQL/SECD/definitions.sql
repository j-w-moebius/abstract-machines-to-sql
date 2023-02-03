DROP TYPE IF EXISTS term,var,primitive,env,closure,val,stack,directive,control,frame,dump,lam,app,rule,machine_state,env_entry CASCADE;
DROP TABLE IF EXISTS terms, root_terms;

CREATE DOMAIN term AS integer;
CREATE DOMAIN var  AS text;
CREATE TYPE primitive AS ENUM('apply');
CREATE DOMAIN env AS int;
CREATE TYPE closure AS (v var, t term, e env);    -- Closure = (Var, Term, Env)
CREATE TYPE val AS (c closure, n int);            -- Val = Closure | Int
CREATE DOMAIN stack AS val[];
CREATE TYPE directive AS (t term, p primitive);   -- Directive = Term | Primitive
CREATE DOMAIN control AS directive[];
CREATE TYPE frame AS (s stack, e env, c control); -- Frame = (Stack, Env, Control)
CREATE DOMAIN dump AS frame[]; 

CREATE TYPE lam AS (ide var, body term);
CREATE TYPE app AS (fun term, arg term);

-- An enum type for the rules which can be applied by the SECD machine.
-- Roughly corresponding to those presented by Danvy.
CREATE TYPE rule AS ENUM('1', '2', '3', '4', '5', '6', '7');

CREATE TYPE machine_state AS (s stack, e env, c control, d dump);

-- A single environment entry consists of:
-- id: The environment's identifier
-- name: The name of a variable
-- val: The value to which this variable is bound in environment id
CREATE TYPE env_entry AS (id env, name var, val val, next env);

-- The self-referencing table terms holds all globally existing terms.
-- invariant: After filling it with load_term, it doesn't change.

-- The object language consits of terms, which are defined in the following way
-- (corresponding to lambda calculus extended with integer literals):
-- Term = Lit Int         (Integer literal)
--      | Var Text        (Variable)
--      | Lam Text Term   (Lambda abstraction with variable and body)
--      | App Term Term   (Application with fun and arg)
CREATE TABLE terms (id integer PRIMARY KEY GENERATED ALWAYS AS IDENTITY, lit int, var var, lam lam, app app);

CREATE TABLE root_terms(id integer PRIMARY KEY GENERATED ALWAYS AS IDENTITY, term integer REFERENCES terms);

DROP SEQUENCE IF EXISTS env_keys;
CREATE SEQUENCE env_keys START 1;

-- load a term from JSON into tabular representation in table terms
CREATE FUNCTION load_term(t jsonb) RETURNS term AS
$$
  INSERT INTO terms(lit, var, lam, app) (
    SELECT new.*
      FROM jsonb_each(t) AS _(type, content),
          LATERAL (

            SELECT lit, null, null::lam, null::app
            FROM jsonb_to_record(t) AS _(lit int)
            WHERE type = 'lit'
              
              UNION ALL

            SELECT null::int, var, null::lam, null::app
            FROM jsonb_to_record(t) AS _(var var)
            WHERE type = 'var'

              UNION ALL

            SELECT null::int, null, row(var, load_term(body))::lam, null::app
            FROM jsonb_to_record(content) AS _(var var, body jsonb)
            WHERE type = 'lam'

              UNION ALL

            SELECT null::int, null, null::lam, row(load_term(fun),load_term(arg))::app
            FROM jsonb_to_record(content) AS _(fun jsonb, arg jsonb)
            WHERE type = 'app'

          ) AS new(lit, var, lam, app)
  )
  RETURNING id
$$
LANGUAGE SQL VOLATILE;