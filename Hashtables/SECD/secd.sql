\i Hashtables/SECD/definitions.sql

-- evaluate a lambda term t using an SECD machine
CREATE OR REPLACE FUNCTION evaluate(t term) RETURNS val AS
$$
  WITH RECURSIVE machine_states(s,e,c,d,finished) AS (
  
    SELECT array[]::stack, 
           empty_env(), 
           array[row(t, null)]::control, 
           array[]::dump, 
           false
    
      UNION ALL
      
    SELECT step.*
    FROM machine_states AS ms LEFT OUTER JOIN terms AS t
            ON ms.c[1].t = t.id,
    LATERAL (
    
      --1. Terminate computation
      SELECT ms.s, 
             ms.e, 
             ms.c, 
             ms.d, 
             true
      WHERE NOT ms.finished 
        AND cardinality(ms.s) = 1 
        AND cardinality(ms.c) = 0 
        AND cardinality(ms.d) = 0
      
        UNION ALL
        
      --2. Return from function call
      SELECT (ms.s || d.s)::stack, 
             d.e, 
             d.c, 
             ms.d[2:]::dump, 
             false
      FROM (SELECT ms.d[1].*) AS d(s,e,c)
      WHERE NOT ms.finished 
        AND cardinality(ms.s) = 1 
        AND cardinality(ms.c) = 0
      
        UNION ALL
        
      --3. Push literal onto stack
      SELECT (array[row(null,t.lit)]::stack || ms.s)::stack, 
             ms.e, 
             ms.c[2:]::control, 
             ms.d, 
             false
      WHERE NOT ms.finished 
        AND t.lit IS NOT NULL
      
        UNION ALL
        
      --4. Push variable value onto stack
      SELECT (array[lookup(ms.e,t.var)] || ms.s)::stack, 
             ms.e, 
             ms.c[2:]::control, 
             ms.d, 
             false
      WHERE NOT ms.finished 
        AND t.var IS NOT NULL
      
        UNION ALL
        
      --5. Push lambda abstraction onto stack as closure
      SELECT (array[row(row(lam.var, lam.body, copy_env(ms.e)),null)]::stack || ms.s)::stack, 
             ms.e, 
             ms.c[2:]::control, 
             ms.d, 
             false
      FROM (SELECT (t.lam).*) AS lam(var, body)
      WHERE NOT ms.finished  
        AND t.lam IS NOT NULL
      
        UNION ALL
      
      --6. Handle function application
      SELECT ms.s, 
             ms.e, 
             (array[row(app.arg,null), row(app.fun,null), row(null, 'apply')]::control || ms.c[2:])::control, 
             ms.d, 
             false
      FROM (SELECT (t.app).*) AS app(fun, arg)
      WHERE NOT ms.finished  
        AND t.app IS NOT NULL
      
        UNION ALL
        
      --7. Apply function
      SELECT array[]::stack, 
             extend(closure.e, closure.v, arg), 
             array[row(closure.t,null)]::control, 
             (array[row(ms.s[3:],ms.e,ms.c[2:])]::dump || ms.d)::dump, 
             false
      FROM (SELECT ms.s[1].c.*) AS closure(v,t,e), 
           (SELECT ms.s[2]) AS _(arg), 
           (SELECT ms.c[1].*) AS c(_,p)
      WHERE NOT ms.finished 
        AND c.p = 'apply'
        
    ) AS step(s,e,c,d,finished)  
  )
  SELECT s[1]
  FROM machine_states AS ms(s,_,_,_,finished)
  WHERE finished
$$ LANGUAGE SQL VOLATILE;

DROP TABLE IF EXISTS input_terms;
CREATE TABLE input_terms (t jsonb);

\copy input_terms FROM '../term_input.json';

INSERT INTO root_terms(id) (
  SELECT id
  FROM input_terms AS _(t), load_term(t) AS __(id)
);