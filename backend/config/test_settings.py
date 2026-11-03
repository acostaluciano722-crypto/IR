"""Tests always use a disposable local PostGIS database, never the cloud DSN."""

import os

from .settings import *  # noqa: F403

DB_SCHEMA = 'public'
DATABASE_URL = ''
DATABASES = {'default': {
    'ENGINE': 'django.db.backends.postgresql',
    'NAME': os.environ.get('DB_NAME', 'ir_promaster_db'),
    'USER': os.environ.get('DB_USER', 'casaco'),
    'PASSWORD': os.environ.get('DB_PASSWORD', ''),
    'HOST': os.environ.get('DB_HOST', '127.0.0.1'),
    'PORT': os.environ.get('DB_PORT', '5433'),
    'TEST': {'NAME': os.environ.get('DB_TEST_NAME')},
}}
SUPABASE_AUTH_ENABLED = False
ALLOW_LEGACY_AUTH = True
STORAGES = {
    'default': {'BACKEND': 'django.core.files.storage.FileSystemStorage'},
    'staticfiles': {'BACKEND': 'django.contrib.staticfiles.storage.StaticFilesStorage'},
}
CACHES = {'default': {'BACKEND': 'django.core.cache.backends.locmem.LocMemCache'}}
