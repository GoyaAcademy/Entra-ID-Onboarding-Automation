-- 1. Define ENUM type for environments
CREATE TYPE environment_enum AS ENUM ('dev', 'qa', 'prod');

-- 2. Create applications table
CREATE TABLE applications (
    app_id SERIAL PRIMARY KEY,
    app_name TEXT NOT NULL,
    app_technology JSONB NOT NULL, -- expected keys: os, db, architecture
    environment environment_enum NOT NULL,
    custodian TEXT,
    architect TEXT,
    created_at TIMESTAMP DEFAULT now(),
    updated_at TIMESTAMP DEFAULT now()
);

-- 3. Seed data with 5 realistic enterprise applications

-- Application 1: HR Management System
INSERT INTO applications (app_name, app_technology, environment, custodian, architect)
VALUES (
    'HR Management System',
    '{"os": "Windows Server 2019", "db": "SQL Server 2019", "architecture": "3-tier"}',
    'prod',
    'Corporate IT',
    'Jane Smith'
);

-- Application 2: Customer Portal
INSERT INTO applications (app_name, app_technology, environment, custodian, architect)
VALUES (
    'Customer Portal',
    '{"os": "Linux (Ubuntu 22.04)", "db": "PostgreSQL 14", "architecture": "microservices"}',
    'qa',
    'Digital Services',
    'Michael Johnson'
);

-- Application 3: Financial Reporting System
INSERT INTO applications (app_name, app_technology, environment, custodian, architect)
VALUES (
    'Financial Reporting System',
    '{"os": "Windows Server 2016", "db": "Oracle 19c", "architecture": "2-tier"}',
    'prod',
    'Finance IT',
    'Anita Patel'
);

-- Application 4: Inventory Management
INSERT INTO applications (app_name, app_technology, environment, custodian, architect)
VALUES (
    'Inventory Management',
    '{"os": "Linux (RHEL 8)", "db": "PostgreSQL 15", "architecture": "3-tier"}',
    'dev',
    'Supply Chain IT',
    'Carlos Martinez'
);

-- Application 5: CRM Platform
INSERT INTO applications (app_name, app_technology, environment, custodian, architect)
VALUES (
    'CRM Platform',
    '{"os": "Linux (CentOS 7)", "db": "SQL Server 2022", "architecture": "microservices"}',
    'prod',
    'Sales Operations',
    'Emily Davis'
);
