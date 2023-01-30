\i definitions.sql

DROP TYPE IF EXISTS machine_state CASCADE;
CREATE TYPE machine_state AS (t term, s stack, e env, finished boolean);

-- evaluate a lambda term t using a Krivine machine
CREATE OR REPLACE FUNCTION evaluate(t term) RETURNS closure AS
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
      LATERAL (
        SELECT (c).*
        FROM lookupHT(1,false,new_env) AS _(_ env, c closure, __ env)
      ) AS e(t,e)
      WHERE NOT ms.finished 
        AND t.i IS NOT NULL

    ) AS step(t,s,e,finished)  
  )
  SELECT row(t,e)::closure
  FROM machine_states AS ms(t,_,e)
  WHERE finished
$$ LANGUAGE SQL VOLATILE;


-- load input term from json file:

DROP TABLE IF EXISTS input_terms;
CREATE TABLE input_terms (t jsonb);

\copy input_terms FROM '../term_input.json';

INSERT INTO root_terms(id) (
  SELECT id
  FROM input_terms AS _(t), load_term(t) AS __(id)
);
