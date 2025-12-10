# Expense Manager Backend

Python backend for the Expense Manager application using FastAPI and SQLAlchemy.

## Setup

### Prerequisites
- Python 3.11+
- Poetry

### Installation

```bash
# Install dependencies
poetry install

# Activate virtual environment
poetry shell
```

## Running the Server

```bash
# Development mode with auto-reload
poetry run uvicorn app.main:app --reload --port 8000

# Production mode
poetry run uvicorn app.main:app --host 0.0.0.0 --port 8000
```

The API will be available at `http://localhost:8000`

## API Documentation

Once the server is running, visit:
- Swagger UI: `http://localhost:8000/docs`
- ReDoc: `http://localhost:8000/redoc`

## Database

The application uses SQLite with the database file stored at `backend/expense.db`.

### Initialization

The database is automatically initialized on first run with:
- All required tables
- 7 pre-seeded categories (Food, Shopping, Miscellaneous, Subscriptions, Rent, Trips, Unexpected expenses)
- Sample wallets (Cash, Bank Account, PayPay)

## Testing

```bash
# Run all tests
poetry run pytest

# Run with coverage
poetry run pytest --cov=app tests/

# Run specific test file
poetry run pytest tests/test_wallets.py -v
```

## Project Structure

```
backend/
├── app/
│   ├── main.py              # FastAPI application
│   ├── database.py          # Database configuration
│   ├── models/              # SQLAlchemy models
│   ├── schemas/             # Pydantic schemas
│   ├── services/            # Business logic
│   ├── routers/             # API endpoints
│   └── utils/               # Utilities (seed data, etc.)
├── tests/                   # Test suite
├── pyproject.toml           # Poetry configuration
└── expense.db               # SQLite database (gitignored)
```

## Development

### Adding a New Feature

1. Create model in `app/models/`
2. Create Pydantic schemas in `app/schemas/`
3. Implement business logic in `app/services/`
4. Create API routes in `app/routers/`
5. Write tests in `tests/`

### Database Migrations

Currently using direct SQLAlchemy table creation. Alembic migrations can be added later if needed.
