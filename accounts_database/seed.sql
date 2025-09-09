-- Seed data for multi-tenant accounts management platform
-- This creates a default tenant (tenant_id = 1), organization, baseline roles, permissions, and an admin user

-- Defaults
SET NAMES utf8mb4;
SET FOREIGN_KEY_CHECKS = 0;

-- Create default organization (tenant)
INSERT INTO organizations (tenant_id, name, slug, email_domain, is_active)
VALUES
  (1, 'Acme Corporation', 'acme', 'acme.example.com', 1)
ON DUPLICATE KEY UPDATE
  name = VALUES(name),
  email_domain = VALUES(email_domain),
  is_active = VALUES(is_active);

-- Create default roles for tenant 1
INSERT INTO roles (tenant_id, name, description, is_system)
VALUES
  (1, 'Admin', 'Full administrative access', 1),
  (1, 'Manager', 'Manage teams and operations', 1),
  (1, 'Sales Rep', 'Access to sales-related features', 1),
  (1, 'Viewer', 'Read-only access', 1)
ON DUPLICATE KEY UPDATE
  description = VALUES(description),
  is_system = VALUES(is_system);

-- Create baseline permissions (examples aligned with backend expectations)
INSERT INTO permissions (tenant_id, name, code, description)
VALUES
  (1, 'Manage Organizations', 'org.manage', 'Create and manage organizations'),
  (1, 'Manage Users', 'users.manage', 'Create, update, and deactivate users'),
  (1, 'View Users', 'users.view', 'Read user data'),
  (1, 'Manage Roles', 'roles.manage', 'Create and assign roles'),
  (1, 'View Roles', 'roles.view', 'Read role definitions'),
  (1, 'View Dashboard', 'dashboard.view', 'Access dashboard data')
ON DUPLICATE KEY UPDATE
  name = VALUES(name),
  description = VALUES(description);

-- Map permissions to roles for tenant 1
-- Admin gets all permissions
INSERT INTO role_permissions (tenant_id, role_id, permission_id)
SELECT 1 AS tenant_id, r.id, p.id
FROM roles r
JOIN permissions p ON p.tenant_id = r.tenant_id
WHERE r.tenant_id = 1 AND r.name = 'Admin'
ON DUPLICATE KEY UPDATE tenant_id = VALUES(tenant_id);

-- Manager gets common management + view
INSERT INTO role_permissions (tenant_id, role_id, permission_id)
SELECT 1, r.id, p.id
FROM roles r
JOIN permissions p ON p.tenant_id = r.tenant_id
WHERE r.tenant_id = 1
  AND r.name = 'Manager'
  AND p.code IN ('users.manage','users.view','roles.view','dashboard.view')
ON DUPLICATE KEY UPDATE tenant_id = VALUES(tenant_id);

-- Sales Rep gets dashboard view
INSERT INTO role_permissions (tenant_id, role_id, permission_id)
SELECT 1, r.id, p.id
FROM roles r
JOIN permissions p ON p.tenant_id = r.tenant_id
WHERE r.tenant_id = 1
  AND r.name = 'Sales Rep'
  AND p.code IN ('dashboard.view')
ON DUPLICATE KEY UPDATE tenant_id = VALUES(tenant_id);

-- Viewer gets view permissions
INSERT INTO role_permissions (tenant_id, role_id, permission_id)
SELECT 1, r.id, p.id
FROM roles r
JOIN permissions p ON p.tenant_id = r.tenant_id
WHERE r.tenant_id = 1
  AND r.name = 'Viewer'
  AND p.code IN ('users.view','roles.view','dashboard.view')
ON DUPLICATE KEY UPDATE tenant_id = VALUES(tenant_id);

-- Create default admin user (password hash placeholder)
-- Replace '{BCRYPT_HASH}' with actual bcrypt hash in production pipelines.
-- Example hash below corresponds to password 'ChangeMe123!' (bcrypt cost 10) - do NOT use in production.
SET @admin_password_hash = '$2b$10$gqg1xI4m3M3x6c4oN0oSuu9wHf1k2mNq3cVt2x2oSgR8b7zqS0b2W';

-- Ensure we have the organization id for tenant 1
SET @org_id := (SELECT id FROM organizations WHERE tenant_id = 1 LIMIT 1);

INSERT INTO users (tenant_id, organization_id, email, password_hash, first_name, last_name, is_email_verified, is_active)
VALUES (1, @org_id, 'admin@acme.example.com', @admin_password_hash, 'System', 'Admin', 1, 1)
ON DUPLICATE KEY UPDATE
  password_hash = VALUES(password_hash),
  is_email_verified = VALUES(is_email_verified),
  is_active = VALUES(is_active);

-- Assign Admin role to admin user
SET @admin_user_id := (SELECT id FROM users WHERE tenant_id = 1 AND email = 'admin@acme.example.com' LIMIT 1);
SET @admin_role_id := (SELECT id FROM roles WHERE tenant_id = 1 AND name = 'Admin' LIMIT 1);

INSERT INTO user_roles (tenant_id, user_id, role_id)
VALUES (1, @admin_user_id, @admin_role_id)
ON DUPLICATE KEY UPDATE tenant_id = VALUES(tenant_id);

-- Audit seed entries
INSERT INTO audit_logs (tenant_id, organization_id, user_id, action, resource_type, resource_id, ip_address, user_agent, metadata)
VALUES
(1, @org_id, @admin_user_id, 'system.seed', 'seed', 'initial', '127.0.0.1', 'seed-script/1.0', JSON_OBJECT('note','Initial seed completed'));

SET FOREIGN_KEY_CHECKS = 1;
