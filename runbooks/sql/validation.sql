-- Validation queries for the wave 1 cutover (runbooks/wave-1-cutover.md, section "Validation queries").
-- Run each block with psql against SRV-07 and against RDS, save the output and compare it with diff.
-- The output is sorted and free of timestamps of the run itself, so identical data gives identical files.

-- V-01: application sessions still connected (expect 0 rows during the write freeze)
SELECT pid, usename, application_name, client_addr, state
FROM pg_stat_activity
WHERE datname = 'harbor'
  AND usename NOT IN ('dms_user', 'harbor_admin', 'rdsadmin')
  AND pid <> pg_backend_pid()
ORDER BY pid;

-- V-02: exact row count of every migrated table (audit.request_log is excluded from DMS)
CREATE TEMP TABLE v02_counts (table_name text, row_count bigint);
DO $$
DECLARE t record;
BEGIN
  FOR t IN
    SELECT table_schema, table_name
    FROM information_schema.tables
    WHERE table_type = 'BASE TABLE'
      AND table_schema IN ('catalog', 'shipping', 'orders', 'inventory', 'audit')
      AND NOT (table_schema = 'audit' AND table_name = 'request_log')
  LOOP
    EXECUTE format('INSERT INTO v02_counts SELECT %L, count(*) FROM %I.%I',
                   t.table_schema || '.' || t.table_name, t.table_schema, t.table_name);
  END LOOP;
END $$;
SELECT table_name, row_count FROM v02_counts ORDER BY table_name;

-- V-03: checksum of the last seven days of fulfillment orders and order lines
SELECT 'orders.orders' AS table_name,
       count(*) AS row_count,
       md5(string_agg(o::text, '|' ORDER BY o.order_id)) AS checksum
FROM orders.orders AS o
WHERE o.created_at >= now() - interval '7 days'
UNION ALL
SELECT 'orders.order_lines',
       count(*),
       md5(string_agg(l::text, '|' ORDER BY l.order_id, l.line_no))
FROM orders.order_lines AS l
JOIN orders.orders AS o USING (order_id)
WHERE o.created_at >= now() - interval '7 days'
ORDER BY 1;

-- V-04: highest order ID and newest order timestamp
SELECT max(order_id) AS max_order_id, max(created_at) AS newest_order
FROM orders.orders;

-- V-05: sequences whose next value would collide with an existing ID (expect 0 rows after M-02).
-- The last column is the setval statement that fixes the sequence.
SELECT s.schemaname || '.' || s.sequencename AS sequence_name,
       s.last_value,
       d.refobjid::regclass AS table_name,
       a.attname AS column_name,
       format('SELECT setval(%L, (SELECT max(%I) FROM %s));',
              s.schemaname || '.' || s.sequencename, a.attname, d.refobjid::regclass) AS fix
FROM pg_sequences AS s
JOIN pg_class AS c ON c.relname = s.sequencename
JOIN pg_namespace AS n ON n.oid = c.relnamespace AND n.nspname = s.schemaname
JOIN pg_depend AS d ON d.objid = c.oid AND d.deptype = 'a'
JOIN pg_attribute AS a ON a.attrelid = d.refobjid AND a.attnum = d.refobjsubid
WHERE s.schemaname IN ('catalog', 'shipping', 'orders', 'inventory', 'audit')
  AND coalesce(s.last_value, 0) < (
    SELECT coalesce((xpath('/row/m/text()',
           query_to_xml(format('SELECT max(%I) AS m FROM %s', a.attname, d.refobjid::regclass), false, true, '')))[1]::text::bigint, 0)
  )
ORDER BY 1;

-- V-06: newest order on this side after the DNS switch (compare SRV-07 with RDS; same order ID within 60 s)
SELECT order_id, created_at
FROM orders.orders
ORDER BY order_id DESC
LIMIT 1;

-- V-07: rows in the DMS apply exceptions table (expect 0; run on the target of the task being checked)
SELECT count(*) AS apply_exceptions
FROM dms_control.awsdms_apply_exceptions;
