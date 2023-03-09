\i Vanilla-PSQL/Krivine/definitions.sql


-- evaluate a lambda term t using a Krivine machine
CREATE FUNCTION evaluate(t term) RETURNS TABLE (c closure, steps bigint, env_size bigint) AS
$$
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
	        AND NOT r.finished
      ),

      environments(id,c,n) AS (
        SELECT (r.e).*
        FROM r
        WHERE r.e IS NOT NULL
	        AND NOT r.finished
      ),

      term(i,lam,app) AS (
        SELECT t.i, t.lam, t.app
        FROM machine AS ms JOIN terms AS t
             ON ms.t = t.id
      ),

      -- compute next machine state
      -- new_env_entry (optional): contains the binding an environment is to be extended by
      step(finished,t,s,e,new_env_entry) AS (

      --1. Terminate computation
      SELECT true,
             ms.t,
             ms.s,
             ms.e,
             null::env_entry
      FROM machine AS ms,
           term AS t
      WHERE t.lam IS NOT NULL
        AND cardinality(ms.s) = 0
      
        UNION ALL
        
      --2. Handle function application (Rule App)
      SELECT false,
             fun,
             (array[row(arg, ms.e)]:: stack || ms.s)::stack,
             ms.e,
             null
      FROM machine AS ms,
           term AS t,
      LATERAL (SELECT (t.app).*) AS _(fun, arg)
      WHERE t.app IS NOT NULL

        UNION ALL
        
      --3. Handle lambda abstraction (Rule Abs)
      SELECT false,
             t.lam,
             ms.s[2:]::stack,
             new_env_id,
             row(new_env_id, closure, ms.e)::env_entry
      FROM machine AS ms,
           term AS t,
      LATERAL (SELECT ms.s[1]) AS _(closure),
      (SELECT nextval('env_keys')::env) AS __(new_env_id)
      WHERE t.lam IS NOT NULL
        AND cardinality(ms.s) > 0
      
        UNION ALL
        
      --4. Handle De Bruijn index (Rule Zero / Succ combined)
      SELECT false,
             e.t,
             ms.s,
             e.e,
             null
      FROM machine AS ms,
           term AS t,
           LATERAL (
            WITH RECURSIVE s(e, n) AS (
              SELECT ms.e, t.i

                UNION ALL
    
              SELECT e.n, s.n - 1
              FROM s JOIN environments AS e
                   ON s.e = e.id
              WHERE s.n > 0
            )
            SELECT s.e
            FROM s
            WHERE s.n = 0
           ) AS _(new_env),
      LATERAL (SELECT (e.c).*
               FROM environments AS e
               WHERE e.id = new_env) AS e(t, e)
      WHERE t.i IS NOT NULL
      ),

      --update the environments according to the rule applied by 'step'
      new_envs(id,c,n) AS (
        -- use old env
        SELECT e.*
        FROM step AS s, environments AS e
        
          UNION ALL

         -- add new binding to new env
        SELECT (s.new_env_entry).*
        FROM step AS s
        WHERE s.new_env_entry IS NOT NULL
      )

      SELECT s.finished,
             row(s.t, s.s, s.e)::machine_state,
             null::env_entry
      FROM step AS s

        UNION ALL

      SELECT s.finished,
             null::machine_state,
             ne::env_entry
      FROM step AS s, new_envs AS ne
    )
  )
  SELECT row((ms).t, (ms).e)::closure,
         (SELECT count(*) - 2 
          FROM r 
          WHERE r.ms IS NOT NULL),
         (SELECT count(*)
          FROM r
          WHERE r.e IS NOT NULL AND r.finished)
  FROM r AS _(finished, ms, _)
  WHERE finished
    AND ms IS NOT NULL
$$ LANGUAGE SQL VOLATILE;


-- import terms from JSON representatin in to table 'terms'
INSERT INTO root_terms (
  SELECT term_id, term
  FROM input_terms_krivine AS _(set_id, term_id, t), load_term(t) AS __(term)
  WHERE set_id = :term_set
);
