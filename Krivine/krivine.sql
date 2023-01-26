\i Krivine/definitions.sql

-- evaluate a lambda term t using a Krivine machine
CREATE FUNCTION evaluate(t term) RETURNS TABLE(c closure, n bigint) AS
$$
-- The recursive CTE r has the following columns:
-- finished: indicates whether the computation is finished
-- ms: a single (!) machine state: Only one row per iteration has ms != null
-- e: environment entries (an arbitrary number of rows)
  WITH RECURSIVE r(finished, ms, e) AS (
  
    SELECT 
      false,
      row(t, 
          array[]::stack, 
          nextval('env_keys')::env)::machine_state,
      null::env_entry
    
      UNION ALL
      
    (WITH
      r AS (TABLE r),                     -- non-linear recursion hack
      machine(t,s,e) AS (
        SELECT (r.ms).*
        FROM r
        WHERE r.ms IS NOT NULL
      ),

      environment(id,c,n) AS (
        SELECT (r.e).*
        FROM r
        WHERE r.e IS NOT NULL
      ),

      term(i,lam,app) AS (
        SELECT t.i, t.lam, t.app
        FROM machine AS ms JOIN terms AS t
             ON ms.t = t.id
      ),

      -- compute next machine state
      -- r: the applied rule, according to which the environment 
      --    will be modified
      -- id, c (optional): indicate (for rule 3) that a new 
      --   environment has to be created by extending id with closure c
      step(r,t,s,e,id,c) AS (

      --1. Terminate computation
      SELECT '1'::rule,
             ms.t,
             ms.s,
             ms.e,
             null::env, null::closure
      FROM machine AS ms,
           term AS t
      WHERE t.lam IS NOT NULL
        AND cardinality(ms.s) = 0
      
        UNION ALL
        
      --2. Handle function application (Rule App)
      SELECT '2'::rule,
             fun,
             (array[row(arg, ms.e)]:: stack || ms.s)::stack,
             ms.e,
             null, null
      FROM machine AS ms,
           term AS t,
      LATERAL (SELECT (t.app).*) AS _(fun, arg)
      WHERE t.app IS NOT NULL

        UNION ALL
        
      --3. Handle lambda abstraction (Rule Abs)
      SELECT '3'::rule,
             t.lam,
             ms.s[2:]::stack,
             nextval('env_keys'),
             ms.e, closure
      FROM machine AS ms,
           term AS t,
      LATERAL (SELECT ms.s[1]) AS _(closure)
      WHERE t.lam IS NOT NULL
        AND cardinality(ms.s) > 0
      
        UNION ALL
        
      --4. Handle De Bruijn index (Rule Zero / Succ combined)
      SELECT '4'::rule,
             e.t,
             ms.s,
             e.e,
             null,null
      FROM machine AS ms,
           term AS t,
           LATERAL (
            WITH RECURSIVE s(e, n) AS (
              SELECT ms.e, t.i

                UNION ALL
    
              SELECT e.n, s.n - 1
              FROM s JOIN environment AS e
                   ON s.e = e.id
              WHERE s.n > 0
            )
            SELECT s.e
            FROM s
            WHERE s.n = 0
           ) AS _(new_env),
      LATERAL (SELECT (e.c).*
               FROM environment AS e
               WHERE e.id = new_env) AS e(t, e)
      WHERE t.i IS NOT NULL
      ),

      --update the environments according to the rule applied by 'step'
      new_envs(id,c,n) AS (
        -- use old env
        SELECT e.*
        FROM step AS s, environment AS e
        WHERE s.r >= '2' -- rules 2,3,4
        
          UNION ALL

         -- add new binding to new env
        SELECT s.e, s.c, s.id
        FROM step AS s
        WHERE s.r = '3'
      )

      SELECT s.r = '1',
             row(s.t, s.s, s.e)::machine_state,
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
  SELECT row((ms).t, (ms).e)::closure,
         (SELECT count(*) 
          FROM r 
          WHERE r.ms IS NOT NULL)
  FROM r AS _(finished, ms, _)
  WHERE finished
$$ LANGUAGE SQL VOLATILE;


-- load input term from json file:

DROP TABLE IF EXISTS input_terms;
CREATE TABLE input_terms (t jsonb);

\copy input_terms FROM 'krivine_terms.json';

INSERT INTO root_terms(id) (
  SELECT id
  FROM input_terms AS _(t), load_term(t) AS __(id)
);