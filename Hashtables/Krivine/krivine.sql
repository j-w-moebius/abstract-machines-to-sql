\i Hashtables/Krivine/definitions.sql

-- evaluate a lambda term t using a Krivine machine
CREATE OR REPLACE FUNCTION evaluate(t term) RETURNS TABLE (c closure, n bigint) AS
$$
  WITH RECURSIVE r(finished,t,s,e) AS (
  
    SELECT false,
           t, 
           array[]::stack, 
           nextval('env_keys')::env
    
      UNION ALL
      
    (WITH
      machine(t,s,e) AS (
        SELECT r.t, r.s, r.e
        FROM r
        WHERE NOT r.finished
      ),

      term(i,lam,app) AS (
        SELECT t.i, t.lam, t.app
        FROM machine AS ms JOIN terms AS t
             ON ms.t = t.id
      ),

      step(finished,t,s,e) AS (

        --1. Terminate computation
        SELECT true,
               ms.t,
               ms.s,
               ms.e
        FROM machine AS ms,
             term AS t
        WHERE t.lam IS NOT NULL
          AND cardinality(ms.s) = 0
      
          UNION ALL
        
        --2. Handle function application (Rule App)
        SELECT false,
               fun,
               (array[row(arg, ms.e)]:: stack || ms.s)::stack,
               ms.e
        FROM machine AS ms,
             term AS t,
        LATERAL (SELECT (t.app).*) AS _(fun, arg)
        WHERE t.app IS NOT NULL

          UNION ALL
        
        --3. Handle lambda abstraction (Rule Abs)
        SELECT false,
               t.lam,
               ms.s[2:]::stack,
               (SELECT new_env
                FROM (SELECT nextval('env_keys')::env) AS _(new_env), 
                LATERAL insertToHT(1, true, new_env, closure, ms.e))
        FROM machine AS ms,
             term AS t,
        LATERAL (SELECT ms.s[1]) AS _(closure)
        WHERE t.lam IS NOT NULL
          AND cardinality(ms.s) > 0
        
          UNION ALL
        
        --4. Handle De Bruijn index (Rule Zero / Succ combined)
        SELECT false,
               e.t,
               ms.s,
               e.e
        FROM machine AS ms,
             term AS t,
        LATERAL (
          WITH RECURSIVE s(e, n) AS (
            SELECT ms.e, t.i

              UNION ALL
    
            SELECT next_env, s.n - 1
            FROM s,
            LATERAL lookupHT(1, false, s.e) AS _(_ env, __ closure, next_env env)
            WHERE s.n > 0
          )
          SELECT s.e
          FROM s
          WHERE s.n = 0) AS _(new_env),
        LATERAL (
          SELECT (c).*
          FROM lookupHT(1,false,new_env) AS _(_ env, c closure, __ env)
        ) AS e(t,e)
        WHERE t.i IS NOT NULL
      )
    SELECT s.*
    FROM step AS s
    )
  )
  SELECT row(r.t,r.e)::closure,
         (SELECT count(*) - 2 
          FROM r)
  FROM r
  WHERE finished
$$ LANGUAGE SQL VOLATILE;

-- import terms from JSON representatin in to table 'terms'
INSERT INTO root_terms (
  SELECT term_id, term
  FROM input_terms_krivine AS _(set_id, term_id, t), load_term(t) AS __(term)
  WHERE set_id = :term_set
);
