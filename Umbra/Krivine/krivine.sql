\o out.txt
\i Umbra/Krivine/definitions.sql

CREATE FUNCTION evaluate(t integer) RETURNS integer[] AS 
$$
  let term_res: integer;
  let env_res: integer;
  let n_res: integer;
  SELECT res.ms_t AS term, res.ms_e AS env, res.n AS n
  FROM (
    WITH RECURSIVE r(finished, ms_t, ms_s, ms_e, e_id, e_c_t, e_c_e, e_n, env_key) AS (

      SELECT 
        false,
        t, 
        array[0], -- empty array won't be cast to integer[]
        1,
        null::integer, null::integer, null::integer, null::integer,
        2
        
      
        UNION ALL
        
      (WITH
        r AS (TABLE r),
        machine(t,s,e) AS (
          SELECT r.ms_t, r.ms_s, r.ms_e
          FROM r
          WHERE r.ms_t IS NOT NULL
            AND NOT r.finished
        ),

        environment(id,c_t,c_e,n) AS (
          SELECT r.e_id, r.e_c_t, r.e_c_e, r.e_n
          FROM r
          WHERE r.e_id IS NOT NULL
            AND NOT r.finished
        ),

        env_key(n) AS (
          SELECT r.env_key 
          FROM r
          WHERE r.env_key IS NOT NULL
        ),

        term(i,lam,app_fun,app_arg) AS (
          SELECT t.i, t.lam, t.app_fun, t.app_arg
          FROM machine AS ms JOIN terms AS t
              ON ms.t = t.id
        ),

        step(finished,t,s,e,id,c_t,c_e) AS (

        --1. Terminate computation
        SELECT true,
              ms.t,
              ms.s,
              ms.e,
              null::integer, null::integer, null::integer
        FROM machine AS ms,
            term AS t
        WHERE t.lam IS NOT NULL
          AND cardinality(ms.s) = 1
        
          UNION ALL
          
        --2. Handle function application (Rule App)
        SELECT false,
              t.app_fun,
              array[t.app_arg, ms.e] || ms.s,
              ms.e,
              null, null, null
        FROM machine AS ms,
            term AS t
        WHERE t.app_fun IS NOT NULL

          UNION ALL
          
        --3. Handle lambda abstraction (Rule Abs)
        SELECT false,
              t.lam,
              ms.s[3:],
              k,
              ms.e, closure_t, closure_e
        FROM machine AS ms,
            term AS t,
            env_key AS _(k),
        LATERAL (SELECT ms.s[1], ms.s[2]) AS __(closure_t, closure_e)
        WHERE t.lam IS NOT NULL
          AND cardinality(ms.s) > 1
        
          UNION ALL
          
        --4. Handle De Bruijn index (Rule Zero / Succ combined)
        SELECT false,
              e.t,
              ms.s,
              e.e,
              null,null,null
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
        LATERAL (SELECT e.c_t, e.c_e
                FROM environment AS e
                WHERE e.id = new_env) AS e(t, e)
        WHERE t.i IS NOT NULL
        ),

        --update the environments according to the rule applied by 'step'
        new_envs(id,c_t,c_e,n) AS (
          -- use old env
          SELECT e.*
          FROM step AS s, environment AS e
          
            UNION ALL

          -- add new binding to new env
          SELECT s.e, s.c_t, s.c_e, s.id
          FROM step AS s
          WHERE s.c_t IS NOT NULL
        )

        SELECT s.finished,
              s.t, s.s, s.e,
              null,null,null,null,
              CASE WHEN (s.c_t IS NULL) THEN k ELSE k+1 END
        FROM env_key AS _(k), step AS s

          UNION ALL

        SELECT s.finished,
              null,null,null,
              ne.*,
              null
        FROM step AS s, new_envs AS ne
      )
    )
    SELECT r.ms_t, r.ms_e,
          (SELECT count(*) - 2
            FROM r 
            WHERE r.ms_t IS NOT NULL) AS n
    FROM r
    WHERE finished
    AND ms_t IS NOT NULL
  ) AS res {
      term_res = term;
      env_res = env;
      n_res = n;
    }
  RETURN array[term_res, env_res, n_res];
$$ LANGUAGE 'umbrascript';

SELECT id, evaluate(t)
FROM root_terms AS _(id,t);