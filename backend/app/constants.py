
"""Global constants used across the application."""

# Snapshot & Balance Constants
# ---------------------------

# Interval for Lazy Snapshot Creation.
# If the latest snapshot is older than this, a new one is created for Yesterday.
LAZY_SNAPSHOT_INTERVAL_DAYS = 90  # 3 months

# Large Cache Rebuild Protection
# Warning verification is required if editing a transaction older than X days
# AND it affects more than Y transactions.
LARGE_CACHE_REBUILD_DAYS = 180  # 6 months
LARGE_CACHE_REBUILD_TRANSACTIONS = 10000

# Application Version
APP_VERSION = "0.1.0"

