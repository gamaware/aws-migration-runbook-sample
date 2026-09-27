-- Minimal Harbor Goods schema with a few rows, used by `make sql-check` to prove that
-- runbooks/sql/validation.sql runs on PostgreSQL 14 (source) and 16 (target).
CREATE SCHEMA catalog;
CREATE SCHEMA shipping;
CREATE SCHEMA orders;
CREATE SCHEMA inventory;
CREATE SCHEMA audit;
CREATE SCHEMA dms_control;

CREATE TABLE catalog.products (product_id bigserial PRIMARY KEY, sku text NOT NULL UNIQUE, price numeric(10, 2) NOT NULL);
CREATE TABLE shipping.addresses (address_id bigserial PRIMARY KEY, postal_code text NOT NULL);
CREATE TABLE orders.orders (
  order_id bigserial PRIMARY KEY,
  address_id bigint NOT NULL REFERENCES shipping.addresses,
  created_at timestamptz NOT NULL DEFAULT now(),
  status text NOT NULL DEFAULT 'received'
);
CREATE TABLE orders.order_lines (
  order_id bigint NOT NULL REFERENCES orders.orders,
  line_no int NOT NULL,
  product_id bigint NOT NULL REFERENCES catalog.products,
  quantity int NOT NULL,
  PRIMARY KEY (order_id, line_no)
);
CREATE TABLE inventory.stock (product_id bigint PRIMARY KEY REFERENCES catalog.products, on_hand int NOT NULL);
CREATE TABLE audit.change_events (event_id bigserial PRIMARY KEY, detail text);
CREATE TABLE audit.request_log (logged_at timestamptz, path text);
CREATE TABLE dms_control.awsdms_apply_exceptions (task_name text, table_owner text, table_name text, error_time timestamptz, statement text, error text);

INSERT INTO catalog.products (sku, price) VALUES ('HG-10001', 19.90), ('HG-10002', 5.00);
INSERT INTO shipping.addresses (postal_code) VALUES ('00000');
INSERT INTO orders.orders (address_id) VALUES (1), (1);
INSERT INTO orders.order_lines VALUES (1, 1, 1, 2), (2, 1, 2, 1);
INSERT INTO inventory.stock VALUES (1, 40), (2, 12);

-- Simulate what DMS leaves behind: rows copied with explicit IDs, sequence never advanced.
INSERT INTO audit.change_events (event_id, detail) VALUES (1, 'a'), (2, 'b');
