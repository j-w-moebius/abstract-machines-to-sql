\i Hashtables/SECD/definitions.sql

DROP TYPE IF EXISTS result, machine_state;
CREATE TYPE result AS (v val, n bigint);

CREATE TYPE machine_state AS (s stack, e env, c control, d dump);

-- evaluate a lambda term t using an SECD machine, but stop after cutoff steps
CREATE OR REPLACE FUNCTION evaluate_interrupt(t term, cutoff bigint) RETURNS result AS
$$
  WITH RECURSIVE r(s,e,c,d,finished,n) AS (
  
    SELECT array[]::stack, 
           nextval('env_keys')::env, 
           array[row(t, null)]::control, 
           array[]::dump, 
           false,
           0
    
      UNION ALL
      
    (WITH
      r AS (TABLE r),                -- non-linear recursion hack
      machine(s,e,c,d) AS (
        SELECT r.s, r.e, r.c, r.d
        FROM r
        WHERE NOT r.finished
      ),

      term(lit,var,lam,app) AS (
        SELECT t.lit, t.var, t.lam, t.app
        FROM machine AS ms, terms AS t
        WHERE ms.c[1].t = t.id
      ),

      step(s,e,c,d,finished) AS (
        --1. Terminate computation
        SELECT ms.s, 
              ms.e, 
              ms.c, 
              ms.d, 
              true
        FROM machine AS ms
        WHERE cardinality(ms.s) = 1 
          AND cardinality(ms.c) = 0 
          AND cardinality(ms.d) = 0
        
          UNION ALL
          
        --2. Return from function call
        SELECT (ms.s || d.s)::stack, 
              d.e, 
              d.c, 
              ms.d[2:]::dump, 
              false
        FROM machine AS ms,
        LATERAL (SELECT ms.d[1].*) AS d(s,e,c)
        WHERE cardinality(ms.s) = 1 
          AND cardinality(ms.c) = 0
        
          UNION ALL
          
        --3. Push literal onto stack
        SELECT (array[row(null,t.lit)]::stack || ms.s)::stack, 
              ms.e, 
              ms.c[2:]::control, 
              ms.d, 
              false
        FROM machine AS ms,
            term AS t
        WHERE t.lit IS NOT NULL
        
          UNION ALL
          
        --4. Push variable value onto stack
        SELECT (array[variable_value] || ms.s)::stack, 
              ms.e, 
              ms.c[2:]::control, 
              ms.d, 
              false
        FROM machine AS ms,
            term AS t,
        LATERAL (
          WITH RECURSIVE s(e,name,val) AS (
            SELECT e.next, e.name, e.v
            FROM lookupHT(1, false, ms.e) AS e(_ env, name var, v val, next env)
              
              UNION ALL
            
            SELECT e.next, e.name, e.v
            FROM s, 
            LATERAL lookupHT(1, false, s.e) AS e(_ env, name var, v val, next env)
            WHERE s.name <> t.var
          )
          SELECT s.val
          FROM s
          WHERE s.name = t.var
        ) AS _(variable_value)
        WHERE t.var IS NOT NULL
        
          UNION ALL
          
        --5. Push lambda abstraction onto stack as closure
        SELECT (array[row(row(lam.var, lam.body, ms.e),null)]::stack || ms.s)::stack, 
              ms.e, 
              ms.c[2:]::control, 
              ms.d, 
              false
        FROM machine AS ms,
            term AS t,
        LATERAL (SELECT (t.lam).*) AS lam(var, body)
        WHERE t.lam IS NOT NULL
        
          UNION ALL
        
        --6. Handle function application
        SELECT ms.s, 
              ms.e, 
              (array[row(app.arg,null), row(app.fun,null), row(null, 'apply')]::control || ms.c[2:])::control, 
              ms.d, 
              false
        FROM machine AS ms,
            term AS t,
        LATERAL (SELECT (t.app).*) AS app(fun, arg)
        WHERE t.app IS NOT NULL
        
          UNION ALL
          
        --7. Apply function
        SELECT array[]::stack, 
              (SELECT new_env
                FROM (SELECT nextval('env_keys')::env) AS _(new_env),
                LATERAL insertToHT(1, true, new_env, closure.v, arg, closure.e)),
              array[row(closure.t,null)]::control, 
              (array[row(ms.s[3:],ms.e,ms.c[2:])]::dump || ms.d)::dump, 
              false
        FROM machine AS ms, 
             LATERAL (SELECT ms.s[1].c.*) AS closure(v,t,e), 
             LATERAL (SELECT ms.s[2]) AS _(arg), 
             LATERAL (SELECT ms.c[1].*) AS c(_,p)
        WHERE c.p = 'apply'     
      )
      SELECT s.*,r.n + 1
      FROM r,step AS s
      WHERE r.n < cutoff
    )
  )
  SELECT r.s[1], 
         r.n
  FROM r AS r(s,e,c,d,finished,n)
  WHERE finished
$$ LANGUAGE SQL VOLATILE;