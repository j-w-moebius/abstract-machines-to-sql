DROP TYPE IF EXISTS term,var,primitive,env,closure,val,stack,directive,control,frame,dump,term_type CASCADE;

CREATE DOMAIN term AS jsonb;
CREATE DOMAIN var  AS text;
CREATE TYPE primitive AS ENUM('apply', '+');
CREATE DOMAIN env AS jsonb;
CREATE TYPE closure AS (v var, t term, e env);    -- Closure = (Var, Term, Env)
CREATE TYPE val AS (c closure, n int);            -- Val = Closure | Int
CREATE DOMAIN stack AS val[];
CREATE TYPE directive AS (t term, p primitive);   -- Directive = Term | Primitive
CREATE DOMAIN control AS directive[];
CREATE TYPE frame AS (s stack, e env, c control); -- Frame = (Stack, Env, Control)
CREATE DOMAIN dump AS frame[]; 

CREATE TYPE term_type AS ENUM('lit', 'var', 'app', 'lam', 'add');

-- look up identifier ide in environment env
-- return corresponding value or empty row set if ide not defined in env
CREATE FUNCTION lookup(e env, ide var) RETURNS val AS
$$
  SELECT row(res.*)
  FROM jsonb_each(e) AS _(name, def),
       LATERAL jsonb_to_record(def) AS res(c closure, n int)
  WHERE name = ide
$$
LANGUAGE SQL IMMUTABLE;

-- extend an environment env's bindings by (ide -> v)
CREATE FUNCTION extend(e env, ide var, v val) RETURNS env AS
$$
  WITH bindings(name, def) AS (
    SELECT t.*
    FROM jsonb_each(e) AS t(name, def)
    WHERE name <> ide
  
      UNION ALL
    
    SELECT ide, row_to_json(v)::jsonb
  )
  SELECT jsonb_object_agg(b.name, b.def)
  FROM bindings AS b(name, def);
$$
LANGUAGE SQL IMMUTABLE;

-- return the type of a term t
CREATE FUNCTION get_type(t term) RETURNS term_type AS
$$
  SELECT type::term_type
  FROM jsonb_each(t) AS _(type,_)
$$ 
LANGUAGE SQL IMMUTABLE;
