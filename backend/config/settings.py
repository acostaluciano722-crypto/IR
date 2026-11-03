import os
import re
from pathlib import Path
from urllib.parse import parse_qs, unquote, urlparse

from django.core.exceptions import ImproperlyConfigured
from dotenv import load_dotenv

BASE_DIR = Path(__file__).resolve().parent.parent
load_dotenv(BASE_DIR.parent / '.env', override=False)
SECRET_KEY = os.environ.get('DJANGO_SECRET_KEY', 'dev-only-change-me')
DEBUG = os.environ.get('DJANGO_DEBUG', 'true').strip().lower() in {'1', 'true', 'yes'}
ALLOWED_HOSTS = [
    host.strip()
    for host in os.environ.get(
        'ALLOWED_HOSTS', '127.0.0.1,localhost,0.0.0.0,10.0.2.2'
    ).split(',')
    if host.strip()
]

INSTALLED_APPS = [
    'django.contrib.admin',
    'django.contrib.auth',
    'django.contrib.contenttypes',
    'django.contrib.sessions',
    'django.contrib.messages',
    'django.contrib.staticfiles',
    'rest_framework',
    'corsheaders',
    'coredata',
]

MIDDLEWARE = [
    'django.middleware.security.SecurityMiddleware',
    'corsheaders.middleware.CorsMiddleware',
    'django.contrib.sessions.middleware.SessionMiddleware',
    'django.middleware.common.CommonMiddleware',
    'django.middleware.csrf.CsrfViewMiddleware',
    'django.contrib.auth.middleware.AuthenticationMiddleware',
    'django.contrib.messages.middleware.MessageMiddleware',
    'django.middleware.clickjacking.XFrameOptionsMiddleware',
]

ROOT_URLCONF = 'config.urls'
TEMPLATES = [{
    'BACKEND': 'django.template.backends.django.DjangoTemplates',
    'DIRS': [],
    'APP_DIRS': True,
    'OPTIONS': {'context_processors': [
        'django.template.context_processors.request',
        'django.contrib.auth.context_processors.auth',
        'django.contrib.messages.context_processors.messages',
    ]},
}]
WSGI_APPLICATION = 'config.wsgi.application'

DB_ENGINE = os.environ.get('DB_ENGINE', 'postgresql')
DATABASE_URL = os.environ.get('DATABASE_URL', '')
DB_SCHEMA = os.environ.get('DB_SCHEMA', 'public')
if not re.fullmatch(r'[a-z_][a-z0-9_]*', DB_SCHEMA):
    raise ImproperlyConfigured('DB_SCHEMA no es un identificador valido.')

if DB_ENGINE == 'postgresql':
    DATABASES = {
        'default': {
            'ENGINE': 'django.db.backends.postgresql',
            'NAME': os.environ.get('DB_NAME', 'ir_promaster_db'),
            'USER': os.environ.get('DB_USER', 'casaco'),
            'PASSWORD': os.environ.get('DB_PASSWORD', ''),
            'HOST': os.environ.get('DB_HOST', '127.0.0.1'),
            'PORT': os.environ.get('DB_PORT', '5433'),
            'CONN_MAX_AGE': 60,
            'CONN_HEALTH_CHECKS': True,
            'TEST': {'NAME': os.environ.get('DB_TEST_NAME')},
        }
    }

    if DATABASE_URL:
        database_url = urlparse(DATABASE_URL)
        if database_url.scheme not in {'postgres', 'postgresql'} or not database_url.hostname:
            raise ImproperlyConfigured('DATABASE_URL debe ser una conexion PostgreSQL.')
        query = parse_qs(database_url.query)
        if database_url.port == 6543 and DB_SCHEMA != 'public':
            raise ImproperlyConfigured('Usa el pooler de sesiones de Supabase en el puerto 5432 para el esquema privado.')
        DATABASES['default'].update({
            'NAME': unquote(database_url.path.lstrip('/')),
            'USER': unquote(database_url.username or ''),
            'PASSWORD': unquote(database_url.password or ''),
            'HOST': database_url.hostname,
            'PORT': str(database_url.port or 5432),
            'DISABLE_SERVER_SIDE_CURSORS': True,
            'OPTIONS': {
                'sslmode': query.get('sslmode', ['require'])[0],
                'prepare_threshold': None,
            },
        })
    if DB_SCHEMA != 'public':
        DATABASES['default'].setdefault('OPTIONS', {})['options'] = f'-c search_path={DB_SCHEMA},extensions,public'
else:
    DATABASES = {
        'default': {
            'ENGINE': 'django.db.backends.sqlite3',
            'NAME': BASE_DIR / 'db.sqlite3',
        }
    }

AUTH_PASSWORD_VALIDATORS = []
LANGUAGE_CODE = 'es-co'
TIME_ZONE = 'America/Bogota'
USE_I18N = True
USE_TZ = True
STATIC_URL = 'static/'
STATIC_ROOT = BASE_DIR / 'staticfiles'
MEDIA_URL = '/media/'
MEDIA_ROOT = BASE_DIR / 'media'
DEFAULT_AUTO_FIELD = 'django.db.models.BigAutoField'

REST_FRAMEWORK = {
    'DEFAULT_AUTHENTICATION_CLASSES': [
        'coredata.authentication.SignedTokenAuthentication',
    ],
    'DEFAULT_PERMISSION_CLASSES': [
        'rest_framework.permissions.IsAuthenticated',
    ],
}


CORS_ALLOWED_ORIGINS = [
    origin.strip()
    for origin in os.environ.get(
        'CORS_ALLOWED_ORIGINS',
        'http://localhost:5353,http://127.0.0.1:5353,http://localhost:5354,http://127.0.0.1:5354,http://localhost:5355,http://127.0.0.1:5355',
    ).split(',')
    if origin.strip()
]
CORS_ALLOW_ALL_ORIGINS = DEBUG and os.environ.get(
    'CORS_ALLOW_ALL_ORIGINS', 'true'
).strip().lower() in {'1', 'true', 'yes'}

GOOGLE_MAPS_API_KEY = os.environ.get('GOOGLE_MAPS_API_KEY', '')

# Redis is optional for run_dev.ps1; Docker always supplies these URLs.
REDIS_CACHE_URL = os.environ.get('REDIS_CACHE_URL', '')
if REDIS_CACHE_URL:
    CACHES = {
        'default': {
            'BACKEND': 'django.core.cache.backends.redis.RedisCache',
            'LOCATION': REDIS_CACHE_URL,
            'KEY_PREFIX': 'ir',
            'TIMEOUT': 300,
            'OPTIONS': {'socket_connect_timeout': 2, 'socket_timeout': 2},
        },
    }

CELERY_BROKER_URL = os.environ.get('CELERY_BROKER_URL', 'redis://127.0.0.1:6379/0')
CELERY_RESULT_BACKEND = os.environ.get('CELERY_RESULT_BACKEND', 'redis://127.0.0.1:6379/2')
CELERY_ACCEPT_CONTENT = ['json']
CELERY_TASK_SERIALIZER = 'json'
CELERY_RESULT_SERIALIZER = 'json'
CELERY_TIMEZONE = TIME_ZONE
CELERY_BROKER_CONNECTION_RETRY_ON_STARTUP = True
CELERY_BROKER_CONNECTION_TIMEOUT = 3
CELERY_TASK_TIME_LIMIT = 300
CELERY_TASK_SOFT_TIME_LIMIT = 240
CELERY_WORKER_PREFETCH_MULTIPLIER = 1
CELERY_RESULT_EXPIRES = 3600

# Gunicorn serves Django without runserver's static-file handler.
if os.environ.get('DJANGO_SERVE_STATIC', '').strip().lower() in {'1', 'true', 'yes'}:
    MIDDLEWARE.insert(1, 'whitenoise.middleware.WhiteNoiseMiddleware')

SUPABASE_URL = os.environ.get('SUPABASE_URL', '').rstrip('/')
SUPABASE_PUBLISHABLE_KEY = os.environ.get('SUPABASE_PUBLISHABLE_KEY', '')
SUPABASE_SECRET_KEY = os.environ.get('SUPABASE_SECRET_KEY', '')
if bool(SUPABASE_URL) != bool(SUPABASE_PUBLISHABLE_KEY):
    raise ImproperlyConfigured('Configura SUPABASE_URL y SUPABASE_PUBLISHABLE_KEY juntos.')
SUPABASE_JWT_ISSUER = os.environ.get('SUPABASE_JWT_ISSUER') or f'{SUPABASE_URL}/auth/v1'
SUPABASE_AUTH_REDIRECT_URL = os.environ.get('SUPABASE_AUTH_REDIRECT_URL', 'http://localhost:5353')
SUPABASE_STORAGE_BUCKET = os.environ.get('SUPABASE_STORAGE_BUCKET', 'ir-profile-photos')
SUPABASE_AUTH_ENABLED = bool(SUPABASE_URL and SUPABASE_PUBLISHABLE_KEY)
ALLOW_LEGACY_AUTH = os.environ.get(
    'ALLOW_LEGACY_AUTH', 'false' if SUPABASE_AUTH_ENABLED else 'true',
).lower() in {'1', 'true', 'yes'}

REST_FRAMEWORK['DEFAULT_AUTHENTICATION_CLASSES'].insert(
    0, 'coredata.authentication.SupabaseJWTAuthentication',
)
if os.environ.get('SUPABASE_STORAGE_ENABLED', 'false').lower() in {'1', 'true', 'yes'}:
    if not SUPABASE_URL or not SUPABASE_SECRET_KEY:
        raise ImproperlyConfigured('Supabase Storage necesita URL y clave secreta del servidor.')
    STORAGES = {
        'default': {'BACKEND': 'coredata.storage.SupabaseStorage'},
        'staticfiles': {'BACKEND': 'django.contrib.staticfiles.storage.StaticFilesStorage'},
    }
