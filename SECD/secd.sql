-- evaluate a lambda term t using an SECD machine
DROP FUNCTION IF EXISTS evaluate;
CREATE FUNCTION evaluate(t term) RETURNS val AS
$$
  WITH RECURSIVE machine_states(s,e,c,d,finished) AS (
  
    SELECT array[]::stack, 
           '{}'::env, 
           array[row(t, null)]::control, 
           array[]::dump, 
           false
    
      UNION ALL
      
    SELECT step.*
    FROM machine_states AS ms,
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
      SELECT (array[row(null,lit)]::stack || ms.s)::stack, 
             ms.e, 
             ms.c[2:]::control, 
             ms.d, 
             false
      FROM (SELECT ms.c[1].*) AS c(t,_), 
           LATERAL jsonb_to_record(c.t) AS t(lit int)
      WHERE NOT ms.finished 
        AND get_type(c.t) = 'lit'
      
        UNION ALL
        
      --4. Push variable value onto stack
      SELECT (array[lookup(ms.e, t.var)] || ms.s)::stack, 
             ms.e, 
             ms.c[2:]::control, 
             ms.d, 
             false
      FROM (SELECT ms.c[1].*) AS c(t,_), 
           LATERAL jsonb_to_record(c.t) AS t(var text)
      WHERE NOT ms.finished 
        AND get_type(c.t) = 'var'
      
        UNION ALL
        
      --5. Push lambda abstraction onto stack as closure
      SELECT (array[row(row(t.var, t.body, ms.e),null)]::stack || ms.s)::stack, 
             ms.e, 
             ms.c[2:]::control, 
             ms.d, 
             false
      FROM (SELECT ms.c[1].*) AS c(t,_), 
           LATERAL jsonb_to_record(c.t) AS _(lam jsonb),
           LATERAL jsonb_to_record(lam) AS t(var text, body term)
      WHERE NOT ms.finished  
        AND get_type(c.t) = 'lam'
      
        UNION ALL
      
      --6. Handle function application
      SELECT ms.s, 
             ms.e, 
             (array[row(arg,null), row(fun,null), row(null, 'apply')]::control || ms.c[2:])::control, 
             ms.d, 
             false
      FROM (SELECT ms.c[1].*) AS c(t,_),
           LATERAL jsonb_to_record(c.t) AS _(app jsonb),
           LATERAL jsonb_to_record(app) AS t(fun term, arg term)
      WHERE NOT ms.finished  
        AND get_type(c.t) = 'app'
      
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
    
        UNION ALL
        
      --8. Handle addition
      SELECT ms.s, 
             ms.e, 
             (array[row("left",null), row("right",null), row(null, '+')]::control || ms.c[2:])::control, 
             ms.d, 
             false
      FROM (SELECT ms.c[1].*) AS c(t,_),
           LATERAL jsonb_to_record(c.t) AS _(add jsonb),
           LATERAL jsonb_to_record(add) AS t("left" term, "right" term)
      WHERE NOT ms.finished 
        AND get_type(c.t) = 'add'
      
        UNION ALL
        
      --9. Perform addition  
      SELECT (array[row(null, n + m)]::stack || ms.s[3:])::stack, 
             ms.e, 
             ms.c[2:]::control, 
             ms.d, 
             false
      FROM (SELECT ms.s[1].n) AS _(n), 
           (SELECT ms.s[2].n) AS t(m), 
           (SELECT ms.c[1].*) AS c(_,p)
      WHERE NOT ms.finished  
        AND c.p = '+'
        
    ) AS step(s,e,c,d,finished)  
  )
  SELECT s[1]
  FROM machine_states AS _(s,_,_,_,finished)
  WHERE finished
$$ LANGUAGE SQL IMMUTABLE;

DROP TABLE IF EXISTS terms;
CREATE TABLE terms (t term);

\copy terms FROM '../term_input.json';

SELECT (evaluate(t)).*
FROM terms AS _(t);
