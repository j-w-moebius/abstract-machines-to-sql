\i definitions.sql

DROP TYPE IF EXISTS machine_state CASCADE;
CREATE TYPE machine_state AS (t term, s stack, e env, finished boolean);

-- evaluate a lambda term t using a Krivine machine
CREATE FUNCTION evaluate(t term) RETURNS SETOF machine_state AS
$$
  WITH RECURSIVE machine_states(t,s,e,finished) AS (
  
    SELECT t, 
           array[]::stack, 
           empty_env(),
           false
    
      UNION ALL
      
    SELECT step.*
    FROM machine_states AS ms JOIN terms AS t
            ON ms.t = t.id,
    LATERAL (
    
      --1. Terminate computation
      SELECT ms.t,
             ms.s,
             ms.e,
             true
      WHERE NOT ms.finished 
        AND t.lam IS NOT NULL
        AND cardinality(ms.s) = 0
      
        UNION ALL
        
      --2. Handle function application (Rule App)
      SELECT fun,
             (array[row(arg, ms.e)]:: stack || ms.s)::stack,
             ms.e,
             false
      FROM (SELECT (t.app).*) AS _(fun, arg)
      WHERE NOT ms.finished 
        AND t.app IS NOT NULL

        UNION ALL
        
      --3. Handle lammbda abstraction (Rule Abs)
      SELECT t.lam,
             ms.s[2:]::stack,
             push(ms.e, closure),
             false
      FROM (SELECT ms.s[1]) AS _(closure)
      WHERE NOT ms.finished 
        AND t.lam IS NOT NULL
        AND cardinality(ms.s) > 0
      
        UNION ALL
        
      --4. Handle De Bruijn index (Rule Zero / Succ combined)
      SELECT e.t,
             ms.s,
             e.e,
             false
      FROM (SELECT pop(ms.e, t.i)) AS _(new_env),
      LATERAL (SELECT (e.c).*
               FROM environments AS e
               WHERE e.id = new_env) AS e(t, e)
      WHERE NOT ms.finished 
        AND t.i IS NOT NULL

    ) AS step(t,s,e,finished)  
  )
  SELECT ms.*
  FROM machine_states AS ms(s,_,_,finished)
  --WHERE finished
$$ LANGUAGE SQL VOLATILE;


-- load input term from json file:

DROP TABLE IF EXISTS input_terms;
CREATE TABLE input_terms (t jsonb);

\copy input_terms FROM '../term_input.json';

SELECT r.*
FROM input_terms AS _(t), evaluate(load_term(t)) AS r;


-----------------------------------------------------------------

-- Only for testing purposes: Create table test to simulate recursive
-- CTE machine_state

DROP TABLE IF EXISTS test;
CREATE TABLE test OF machine_state;
INSERT INTO test VALUES 
          (1, 
           array[row(2,2)]::stack, 
           2,
           false);

SELECT e.t,
       ms.s,
       e.e,
       false
FROM test AS ms JOIN terms AS t
       ON ms.t = t.id,
LATERAL (SELECT pop(ms.e, t.i)) AS _(new_env),
LATERAL (SELECT (e.c).*
         FROM environments AS e
         WHERE e.id = new_env) AS e(t, e)
WHERE NOT ms.finished 
      AND t.i IS NOT NULL