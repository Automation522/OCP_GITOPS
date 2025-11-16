CREATE TABLE IF NOT EXISTS customer (
    id SERIAL PRIMARY KEY,
    first_name TEXT NOT NULL,
    last_name TEXT NOT NULL,
    email TEXT UNIQUE,
    last_purchase_at TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP
);

INSERT INTO customer (first_name, last_name, email, last_purchase_at) VALUES
    ('Alice', 'Martin', 'alice.martin@example.com', CURRENT_TIMESTAMP - INTERVAL '1 day'),
    ('Bruno', 'Delacroix', 'bruno.delacroix@example.com', CURRENT_TIMESTAMP - INTERVAL '3 hours'),
    ('Camille', 'Durand', 'camille.durand@example.com', CURRENT_TIMESTAMP - INTERVAL '6 hours'),
    ('David', 'Lambert', 'david.lambert@example.com', CURRENT_TIMESTAMP - INTERVAL '2 days'),
    ('Emma', 'Bernard', 'emma.bernard@example.com', CURRENT_TIMESTAMP - INTERVAL '30 minutes')
ON CONFLICT (email) DO UPDATE SET last_purchase_at = EXCLUDED.last_purchase_at;
