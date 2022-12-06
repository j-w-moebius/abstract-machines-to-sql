DROP TYPE IF EXISTS term,var,primitive,env,closure,val,stack,directive,control,frame,dump,term_type CASCADE;

CREATE DOMAIN term AS jsonb;
CREATE DOMAIN var  AS text;
CREATE TYPE primitive AS ENUM('apply', '+');
CREATE DOMAIN env AS int;
CREATE TYPE closure AS (v var, t term, e env);    -- Closure = (Var, Term, Env)
CREATE TYPE val AS (c closure, n int);            -- Val = Closure | Int
CREATE DOMAIN stack AS val[];
CREATE TYPE directive AS (t term, p primitive);   -- Directive = Term | Primitive
CREATE DOMAIN control AS directive[];
CREATE TYPE frame AS (s stack, e env, c control); -- Frame = (Stack, Env, Control)
CREATE DOMAIN dump AS frame[]; 

CREATE TYPE term_type AS ENUM('lit', 'var', 'app', 'lam', 'add');

DROP SEQUENCE IF EXISTS keys;
CREATE SEQUENCE keys START 1;

DROP TABLE IF EXISTS environments;
CREATE TABLE environments(id env, name var, def val);
ALTER TABLE environments
  ADD PRIMARY KEY (id, name);

-- look up identifier ide in environment env
-- return corresponding value or null if ide not defined in env
CREATE FUNCTION lookup(e env, ide var) RETURNS val AS
$$
  SELECT t.def
  FROM environments AS t
  WHERE t.id = e
    AND t.name = ide
$$
LANGUAGE SQL VOLATILE;

-- extend an environment env's bindings by (ide -> v)
CREATE FUNCTION extend(e env, ide var, v val) RETURNS env AS
$$
  INSERT INTO environments VALUES (e, ide, v)
    ON CONFLICT (id, name) DO UPDATE
      SET def = v
  RETURNING e
$$
LANGUAGE SQL VOLATILE;

-- return new empty env
CREATE FUNCTION empty_env() RETURNS env AS 
$$
  SELECT nextval('keys')
$$
LANGUAGE SQL VOLATILE;

-- delete env old and return new
CREATE FUNCTION replace_env(old env, new env) RETURNS env AS 
$$
  DELETE FROM environments AS t
    WHERE t.id = old;
  SELECT new
$$
LANGUAGE SQL VOLATILE;

-- create copy of env e
CREATE FUNCTION copy_env(e env) RETURNS env AS
$$
  WITH fresh_env AS 
    (SELECT empty_env()),
  _ AS                   -- RETURNING doesn't work with empty environments
    (INSERT INTO environments
      (SELECT f.id, t.name, t.def
       FROM environments AS t, fresh_env AS f(id)
       WHERE t.id = e))
  SELECT f.id
  FROM fresh_env AS f(id)
$$
LANGUAGE SQL VOLATILE;

-- return the type of a term t
CREATE FUNCTION get_type(t term) RETURNS term_type AS
$$
  SELECT type::term_type
  FROM jsonb_each(t) AS _(type,_)
$$ 
LANGUAGE SQL IMMUTABLE;