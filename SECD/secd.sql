\i definitions.sql

-- evaluate a lambda term t using an SECD machine
CREATE OR REPLACE FUNCTION evaluate(t term) RETURNS val AS
$$
  WITH RECURSIVE r(finished, ms, e) AS (
  
    SELECT 
      false,
      row(array[]::stack, 
          nextval('env_keys')::env, 
          array[row(t, null)]::control, 
          array[]::dump)::machine_state,
      null::env_entry
    
      UNION ALL

    (WITH 
      r AS (TABLE r),              -- non-linear recursion hack
      machine(s,e,c,d) AS (
        SELECT (r.ms).*
        FROM r
        WHERE r.ms IS NOT NULL
      ),

      environment(id,name,val) AS (
        SELECT (r.e).*
        FROM r
        WHERE r.e IS NOT NULL
      ),

      term(lit,var,lam,app) AS (
        SELECT t.lit, t.var, t.lam, t.app
        FROM machine AS ms, terms AS t
        WHERE ms.c[1].t = t.id
      ),

      step(r,s,e,c,d,id,name,val) AS (
        --1. Terminate computation
        SELECT '1'::rule,
               ms.s, 
               ms.e, 
               ms.c, 
               ms.d, 
               null::env,null::var,null::val
        FROM machine AS ms
        WHERE cardinality(ms.s) = 1 
          AND cardinality(ms.c) = 0 
          AND cardinality(ms.d) = 0
        
          UNION ALL
          
        --2. Return from function call
        SELECT '2'::rule,
              (ms.s || d.s)::stack, 
              d.e, 
              d.c, 
              ms.d[2:]::dump, 
              ms.e,null::var,null
        FROM machine AS ms,
        LATERAL (SELECT ms.d[1].*) AS d(s,e,c)
        WHERE cardinality(ms.s) = 1 
          AND cardinality(ms.c) = 0
        
          UNION ALL
          
        --3. Push literal onto stack
        SELECT '3'::rule,
              (array[row(null,t.lit)]::stack || ms.s)::stack, 
              ms.e, 
              ms.c[2:]::control, 
              ms.d, 
              null,null::var,null
        FROM machine AS ms,
             term AS t
        WHERE t.lit IS NOT NULL

           UNION ALL
          
        --4. Push variable value onto stack
        SELECT '4'::rule,
               (array[(SELECT e.val
                       FROM environment AS e
                       WHERE e.id = ms.e AND e.name = t.var
                       )] || ms.s)::stack, 
                ms.e, 
                ms.c[2:]::control, 
                ms.d, 
                null,null::var,null
        FROM machine AS ms,
             term AS t
        WHERE t.var IS NOT NULL
          
          UNION ALL
          
        --5. Push lambda abstraction onto stack as closure
        SELECT '5'::rule,
              (array[row(row(lam.var, lam.body, ms.e),null)]::stack || ms.s)::stack, 
              ms.e, 
              ms.c[2:]::control, 
              ms.d, 
              null, null::var,null
        FROM machine AS ms,
             term AS t,
        LATERAL (SELECT (t.lam).*) AS lam(var, body)
        WHERE t.lam IS NOT NULL
        
          UNION ALL
        
        --6. Handle function application
        SELECT '6'::rule,
              ms.s, 
              ms.e, 
              (array[row(app.arg,null), row(app.fun,null), row(null, 'apply')]::control || ms.c[2:])::control, 
              ms.d, 
              null,null::var,null
        FROM machine AS ms,
             term AS t,
        LATERAL (SELECT (t.app).*) AS app(fun, arg)
        WHERE t.app IS NOT NULL
        
          UNION ALL
          
        --7. Apply function
        SELECT '7'::rule,
              array[]::stack, 
              nextval('env_keys')::env, 
              array[row(closure.t,null)]::control, 
              (array[row(ms.s[3:],ms.e,ms.c[2:])]::dump || ms.d)::dump, 
              closure.e, closure.v, arg
        FROM machine AS ms,
        LATERAL (SELECT ms.s[1].c.*) AS closure(v,t,e), 
        LATERAL (SELECT ms.s[2]) AS _(arg), 
        LATERAL (SELECT ms.c[1].*) AS c(_,p)
        WHERE c.p = 'apply'
      ),
      new_envs(id,name,val) AS (
        -- use old env
        SELECT e.*
        FROM step AS s, environment AS e
        WHERE s.r >= '2' -- rules 2,3,4,5,6,7
        
          UNION ALL

         -- copy old env and extend it
        SELECT s.e, s.name, s.val
        FROM step AS s
        WHERE s.r = '7'

          UNION ALL
        
        SELECT s.e, e.name, e.val
        FROM step AS s, environment AS e
        WHERE s.r = '7'
          AND e.id = s.id
          AND e.name <> s.name
      )

      SELECT CASE s.r WHEN '1' THEN true ELSE false END CASE, 
             row(s.s, s.e, s.c, s.d)::machine_state, 
             null::env_entry
      FROM r, step AS s
      WHERE NOT r.finished

        UNION ALL

      SELECT null::boolean,
             null::machine_state, 
             e::env_entry
      FROM new_envs AS e
    )
  )
  SELECT (r.ms).s[1]
  FROM r
  WHERE r.finished
$$ LANGUAGE SQL VOLATILE;

DROP TABLE IF EXISTS input_terms;
CREATE TABLE input_terms (t jsonb);

\copy input_terms FROM '../term_input.json';

SELECT r.*
FROM input_terms AS _(t), load_term(t) AS __(id), evaluate(id) AS r;

----------------------------------------------------------------------------------
--test

DROP TABLE IF EXISTS test;
CREATE TABLE test (ms machine_state, e env_entry);
INSERT INTO test VALUES (row(array[]::stack, 
           nextval('env_keys')::env, 
           array[row(1, null)]::control, 
           array[]::dump)::machine_state,
           null::env_entry);