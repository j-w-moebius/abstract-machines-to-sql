.read DuckDB/SECD/definitions.sql

-- evaluate a lambda term t using an SECD machine
CREATE OR REPLACE FUNCTION evaluate(t_init) AS (

-- The recursive CTE r has the following columns:
-- finished: indicates whether the computation is finished
-- ms: a single (!) machine state: Only one row per iteration has ms != null
-- e: environment entries (an arbitrary number of rows)
  WITH RECURSIVE r(finished, ms, e) AS (
  
    SELECT false, 
           {'s':[], 
            'e':nextval('env_keys'), 
            'c':[t_init], 
            'd': []} ::
            STRUCT(s UNION(c STRUCT(v text, t integer, e integer), n int)[], 
                e integer, 
                c UNION(t integer, p primitive)[], 
                d STRUCT(s UNION(c STRUCT(v text, t integer, e integer), n int)[], 
                         e integer, 
                         c UNION(t integer, p primitive)[])[]),
            null :: 
            STRUCT(id int, 
                name text, 
                val UNION(c STRUCT(v text, t integer, e integer), n int))
  
      UNION ALL

    (WITH 
      machine(s,e,c,d) AS (
        SELECT r.ms.s, r.ms.e, r.ms.c, r.ms.d
        FROM r
        WHERE r.ms NOT NULL
	        AND NOT r.finished
      ),

      environment(id,name,val) AS (
        SELECT r.e.id, r.e.name, r.e.val
        FROM r
        WHERE r.e NOT NULL
	        AND NOT r.finished
      ),

      term(t) AS (
        SELECT t.t
        FROM machine AS ms, terms AS t
        WHERE ms.c[1] = t.id
      ),

      -- compute next machine state
      step(finished,s,e,c,d,new_env_entry) AS (
        WITH one(finished,s,e,c,d,new_env_entry) AS (
        --1. Terminate computation
        SELECT true,
               ms.s, 
               ms.e, 
               ms.c, 
               ms.d, 
               null
        FROM machine AS ms
        WHERE len(ms.s) = 1 
          AND len(ms.c) = 0 
          AND len(ms.d) = 0
        ),

        two(finished,s,e,c,d,new_env_entry) AS (
        --2. Return from function call
        SELECT false,
              ms.s || ms.d[1].s, 
              ms.d[1].e, 
              ms.d[1].c, 
              ms.d[2:], 
              null
        FROM machine AS ms
        WHERE len(ms.s) = 1 
          AND len(ms.c) = 0
          AND len(ms.d) > 0
        ), 

        three(finished,s,e,c,d,new_env_entry) AS (
        --3. Push literal onto stack
        SELECT false,
              array_push_front(ms.s, t.lit),
              ms.e, 
              ms.c[2:], 
              ms.d, 
              null
        FROM machine AS ms,
             term AS _(t)
        WHERE union_tag(t) = 'lit'
        ),

        four(finished,s,e,c,d,new_env_entry) AS (
        --4. Push variable value onto stack
        SELECT false,
               array_push_front(ms.s, (SELECT e.val
                 FROM environment AS e
                 WHERE e.id = ms.e AND e.name = t.var
                )),
                ms.e, 
                ms.c[2:], 
                ms.d, 
                null
        FROM machine AS ms,
             term AS _(t)
        WHERE union_tag(t) = 'var'
        ),

        five(finished,s,e,c,d,new_env_entry) AS (
        --5. Push lambda abstraction onto stack as closure
        SELECT false,
              array_push_front(ms.s, {'v': t.lam.ide, 
                                 't': t.lam.body, 
                                 'e': ms.e}),
              ms.e, 
              ms.c[2:], 
              ms.d, 
              null
        FROM machine AS ms,
             term AS _(t)
        WHERE union_tag(t) = 'lam'
        ),
        
        six(finished,s,e,c,d,new_env_entry) AS (
        --6. Handle function application
        SELECT false,
              ms.s, 
              ms.e, 
              array_push_front(array_push_front(array_push_front(ms.c[2:], 'apply'::primitive), t.app.fun), t.app.arg), 
              ms.d, 
              null
        FROM machine AS ms,
             term AS _(t)
        WHERE union_tag(t) = 'app'
        ), 

        seven(finished,s,e,c,d,new_env_entry) AS (
        --7. Apply function
        SELECT false,
              [], 
              nextval('env_keys'), 
              [ms.s[1].c.t :: UNION(t integer, p primitive)], 
              array_push_front(ms.d, {'s': ms.s[3:],
                'e': ms.e,
                'c': ms.c[2:]}), 
              -- indicate that environment has to be created by extending id with (name -> val)
              {'id': ms.s[1].c.e,
               'name': ms.s[1].c.v, 
               'val': ms.s[2]}
        FROM machine AS ms
        WHERE union_tag(ms.c[1]) = 'p'
          AND ms.c[1].p = 'apply'
        )

        -- the following cluster performs the union of the CTEs one, two, three, four, five, six, seven
        -- its necessity arises from DuckDB forbidding the use of UNIONs (and full outer joins) in recursive CTEs
        SELECT COALESCE(one.finished, COALESCE(two.finished, COALESCE(three.finished, COALESCE(four.finished, COALESCE(five.finished, COALESCE(six.finished, seven.finished)))))),
               COALESCE(one.s, COALESCE(two.s, COALESCE(three.s, COALESCE(four.s, COALESCE(five.s, COALESCE(six.s, seven.s)))))),
               COALESCE(one.e, COALESCE(two.e, COALESCE(three.e, COALESCE(four.e, COALESCE(five.e, COALESCE(six.e, seven.e)))))),
               COALESCE(one.c, COALESCE(two.c, COALESCE(three.c, COALESCE(four.c, COALESCE(five.c, COALESCE(six.c, seven.c)))))),
               COALESCE(one.d, COALESCE(two.d, COALESCE(three.d, COALESCE(four.d, COALESCE(five.d, COALESCE(six.d, seven.d)))))),
               COALESCE(one.new_env_entry, COALESCE(two.new_env_entry, COALESCE(three.new_env_entry, COALESCE(four.new_env_entry, COALESCE(five.new_env_entry, COALESCE(six.new_env_entry, seven.new_env_entry))))))

        FROM (SELECT (SELECT finished FROM one), (SELECT s FROM one), (SELECT e FROM one), (SELECT c FROM one), 
             (SELECT d FROM one), (SELECT new_env_entry FROM one)) 
               AS one(finished,s,e,c,d,new_env_entry),
             (SELECT (SELECT finished FROM two), (SELECT s FROM two), (SELECT e FROM two), (SELECT c FROM two), 
             (SELECT d FROM two), (SELECT new_env_entry FROM two)) 
               AS two(finished,s,e,c,d,new_env_entry),
             (SELECT (SELECT finished FROM three), (SELECT s FROM three), (SELECT e FROM three), (SELECT c FROM three), 
             (SELECT d FROM three), (SELECT new_env_entry FROM three)) 
               AS three(finished,s,e,c,d,new_env_entry),
             (SELECT (SELECT finished FROM four), (SELECT s FROM four), (SELECT e FROM four), (SELECT c FROM four), 
             (SELECT d FROM four), (SELECT new_env_entry FROM four)) 
               AS four(finished,s,e,c,d,new_env_entry),
             (SELECT (SELECT finished FROM five), (SELECT s FROM five), (SELECT e FROM five), (SELECT c FROM five), 
             (SELECT d FROM five), (SELECT new_env_entry FROM five)) 
               AS five(finished,s,e,c,d,new_env_entry),
             (SELECT (SELECT finished FROM six), (SELECT s FROM six), (SELECT e FROM six), (SELECT c FROM six), 
             (SELECT d FROM six), (SELECT new_env_entry FROM six)) 
               AS six(finished,s,e,c,d,new_env_entry),
             (SELECT (SELECT finished FROM seven), (SELECT s FROM seven), (SELECT e FROM seven), (SELECT c FROM seven), 
             (SELECT d FROM seven), (SELECT new_env_entry FROM seven)) 
               AS seven(finished,s,e,c,d,new_env_entry)
      ),

      --update the environments according to the rule applied by 'step'
      --each possible union_id corresponds to a UNION block in the PSQL query
      -- (1: copy old envs, 2: extend env, 3: create new env)
      new_envs(id,name,val) AS (
        SELECT DISTINCT CASE union_id WHEN 1 THEN e.id
                                      WHEN 2 THEN currval('env_keys')   -- using s.e lead to strange behavior
                                      ELSE currval('env_keys') END,
                        CASE union_id WHEN 1 THEN e.name
                                      WHEN 2 THEN s.new_env_entry.name
                                      ELSE e.name END,
                        CASE union_id WHEN 1 THEN e.val
                                      WHEN 2 THEN s.new_env_entry.val
                                      ELSE e.val END
        FROM step AS s LEFT OUTER JOIN environment AS e ON true, (VALUES (1), (2), (3)) AS _(union_id)
        WHERE (union_id = 1 AND e.id NOT NULL) 
           OR (union_id = 2 AND s.new_env_entry NOT NULL)
           OR (union_id = 3 AND s.new_env_entry NOT NULL AND e.id = s.new_env_entry.id AND e.name <> s.new_env_entry.name)
      )

      SELECT DISTINCT s.finished,
                      CASE WHEN union_id = 1 THEN {'s': s.s, 'e': s.e, 'c': s.c, 'd': s.d}
                                             ELSE null END,
                      CASE WHEN union_id = 1 THEN null
                                             ELSE {'id': e.id, 'name': e.name, 'val': e.val} END
      FROM step AS s LEFT OUTER JOIN new_envs AS e ON true,
           (VALUES (1), (2)) AS _(union_id)
      WHERE (union_id = 1 AND s.finished NOT NULL)
         OR (union_id = 2 AND e.id IS NOT NULL)
    )
  )
  SELECT r.ms.s[1]
  FROM r
  WHERE r.finished
    AND r.ms IS NOT NULL
);