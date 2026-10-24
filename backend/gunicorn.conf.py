"""Small hosted runtime; one API process keeps Supabase pool use bounded."""
import os

bind = f"0.0.0.0:{int(os.environ.get('PORT', '8000'))}"
workers = 1
worker_class = 'gthread'
threads = 4
timeout = 90
graceful_timeout = 30
keepalive = 5
max_requests = 1000
max_requests_jitter = 100
# Do not write patient identifiers, request paths, query strings or headers
# to hosting access logs. Application errors remain on stderr.
accesslog = None
errorlog = '-'
capture_output = False
