\i Vanilla-PSQL/SECD/definitions.sql

-- evaluate a lambda term t using an SECD machine
CREATE OR REPLACE FUNCTION evaluate(t term) RETURNS TABLE (v val, steps bigint, env_size bigint) AS
$$
-- finished: indicates whether the computation is finished
-- ms: a single (!) machine state: Only one row per iteration has ms != null
-- e: environment entries (an arbitrary number of rows)
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
	        AND NOT r.finished
      ),

      environments(id,name,val,next) AS (
        SELECT (r.e).*
        FROM r
        WHERE r.e IS NOT NULL
	        AND NOT r.finished
      ),

      term(lit,var,lam,app) AS (
        SELECT t.lit, t.var, t.lam, t.app
        FROM machine AS ms JOIN terms AS t
          ON ms.c[1].t = t.id
      ),

      -- compute next machine state
      -- new_env_entry (optional): contains the binding an environment is to be extended by
      step(finished,s,e,c,d,new_env_entry) AS (
        --1. Terminate computation
        SELECT true,
               ms.s, 
               ms.e, 
               ms.c, 
               ms.d, 
               null::env_entry
        FROM machine AS ms
        WHERE cardinality(ms.s) = 1 
          AND cardinality(ms.c) = 0 
          AND cardinality(ms.d) = 0
        
          UNION ALL
          
        --2. Return from function call
        SELECT false,
              (ms.s || d.s)::stack, 
              d.e, 
              d.c, 
              ms.d[2:]::dump, 
              null
        FROM machine AS ms,
        LATERAL (SELECT ms.d[1].*) AS d(s,e,c)
        WHERE cardinality(ms.s) = 1 
          AND cardinality(ms.c) = 0
          AND cardinality(ms.d) > 0
        
          UNION ALL
          
        --3. Push literal onto stack
        SELECT false,
              (array[row(null,t.lit)]::stack || ms.s)::stack, 
              ms.e, 
              ms.c[2:]::control, 
              ms.d, 
              null
        FROM machine AS ms,
             term AS t
        WHERE t.lit IS NOT NULL

           UNION ALL
          
        --4. Push variable value onto stack
        SELECT false,
               (array[variable_value] || ms.s)::stack, 
                ms.e, 
                ms.c[2:]::control, 
                ms.d, 
                null
        FROM machine AS ms,
             term AS t,
             LATERAL (
              -- traverse environment stack until needed variable is found for the first time
              WITH RECURSIVE s(e,name,val) AS (
                SELECT e.next, e.name, e.val
                FROM environments AS e
                WHERE ms.e = e.id
                  
                  UNION ALL

                SELECT e.next, e.name, e.val
                FROM s JOIN environments AS e
                     ON s.e = e.id
                WHERE s.name <> t.var
              )
              SELECT s.val
              FROM s
              WHERE s.name = t.var
             ) AS _(variable_value)
        WHERE t.var IS NOT NULL
          
          UNION ALL
          
        --5. Push lambda abstraction onto stack as closure
        SELECT false,
              (array[row(row(lam.var, lam.body, ms.e),null)]::stack || ms.s)::stack, 
              ms.e, 
              ms.c[2:]::control, 
              ms.d, 
              null
        FROM machine AS ms,
             term AS t,
        LATERAL (SELECT (t.lam).*) AS lam(var, body)
        WHERE t.lam IS NOT NULL
        
          UNION ALL
        
        --6. Handle function application
        SELECT false,
              ms.s, 
              ms.e, 
              (array[row(app.arg,null), row(app.fun,null), row(null, 'apply')]::control || ms.c[2:])::control, 
              ms.d, 
              null
        FROM machine AS ms,
             term AS t,
        LATERAL (SELECT (t.app).*) AS app(fun, arg)
        WHERE t.app IS NOT NULL
        
          UNION ALL
          
        --7. Apply function
        SELECT false,
              array[]::stack, 
              new_env_id, 
              array[row(closure.t,null)]::control, 
              (array[row(ms.s[3:],ms.e,ms.c[2:])]::dump || ms.d)::dump, 
              row(new_env_id, closure.v, arg, closure.e)::env_entry
        FROM machine AS ms,
        LATERAL (SELECT ms.s[1].c.*) AS closure(v,t,e), 
        LATERAL (SELECT ms.s[2]) AS _(arg), 
        LATERAL (SELECT ms.c[1].*) AS c(_,p),
        (SELECT nextval('env_keys')::env) AS __(new_env_id)
        WHERE c.p = 'apply'
      ),

      --update the environments
      new_envs(id,name,val,next) AS (
        -- copy old env
        SELECT e.*
        FROM step AS s, environments AS e
        
          UNION ALL

         -- add new binding to new env
        SELECT (s.new_env_entry).*
        FROM step AS s
        WHERE s.new_env_entry IS NOT NULL
      )

      SELECT s.finished, 
             row(s.s, s.e, s.c, s.d)::machine_state, 
             null::env_entry
      FROM step AS s

        UNION ALL

      SELECT s.finished,
             null::machine_state, 
             ne::env_entry
      FROM step AS s, new_envs AS ne
    )
  )
  SELECT (r.ms).s[1], 
         (SELECT count(*) - 2
           FROM r
		       WHERE r.ms IS NOT NULL),
         (SELECT count(*)
          FROM r
          WHERE r.e IS NOT NULL AND r.finished)
  FROM r
  WHERE r.finished 
    AND r.ms IS NOT NULL
$$ LANGUAGE SQL VOLATILE;

-- import terms from JSON representatin in to table 'terms'
INSERT INTO root_terms (
  SELECT term_id,term
  FROM input_terms_secd AS _(set_id,term_id,t), load_term(t) AS __(term)
  WHERE set_id = :term_set
);
