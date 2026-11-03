-- Read-only verification of the shared IR project. Does not return personal data.
SELECT jsonb_build_object(
    'database', current_database(),
    'business_schema', 'ir',
    'postgis_version', (SELECT extversion FROM pg_extension WHERE extname = 'postgis'),
    'business_tables', (SELECT count(*) FROM pg_tables WHERE schemaname = 'ir'),
    'tables_without_rls', (SELECT count(*) FROM pg_tables WHERE schemaname = 'ir' AND NOT rowsecurity),
    'anon_schema_access', has_schema_privilege('anon', 'ir', 'USAGE'),
    'authenticated_schema_access', has_schema_privilege('authenticated', 'ir', 'USAGE'),
    'backend_role', (
        SELECT jsonb_build_object(
            'name', rolname, 'superuser', rolsuper,
            'create_database', rolcreatedb, 'create_role', rolcreaterole,
            'bypass_rls', rolbypassrls
        ) FROM pg_roles WHERE rolname = 'ir_backend'
    ),
    'rows', jsonb_build_object(
        'users', (SELECT count(*) FROM ir.usuario),
        'passenger_profiles', (SELECT count(*) FROM ir.perfil_pasajero),
        'driver_profiles', (SELECT count(*) FROM ir.perfil_conductor),
        'vehicles', (SELECT count(*) FROM ir.vehiculo),
        'rides', (SELECT count(*) FROM ir.viaje),
        'offers', (SELECT count(*) FROM ir.ofertas),
        'transactions', (SELECT count(*) FROM ir.transacciones),
        'point_history', (SELECT count(*) FROM ir.historial_puntos)
    ),
    'auth_identities', (SELECT count(*) FROM ir.ir_auth_identity),
    'profile_bucket', (
        SELECT jsonb_build_object('id', id, 'private', NOT public, 'max_bytes', file_size_limit)
        FROM storage.buckets WHERE id = 'ir-profile-photos'
    ),
    'migrations', (
        SELECT jsonb_agg(jsonb_build_object('version', version, 'name', name) ORDER BY version)
        FROM supabase_migrations.schema_migrations
    )
) AS shared_project;
