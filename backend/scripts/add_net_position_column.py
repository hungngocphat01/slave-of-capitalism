from sqlalchemy import create_engine, text
import os

# Database path
DB_PATH = "expense.db" # Default path, might be different in dev but let's try default first or use the one from args if possible.
# Actually, let's look at where the app is running. User used /tmp/test.db recently.
# But often they use expense.db. I should probably handle both or ask? 
# The user's command was: poetry run python -m app.main --port 8000 --database /tmp/test.db
# So I should migrate /tmp/test.db? OR the production one?
# "The user has 1 active workspaces... /Volumes/Documents/Source/expense-manager"
# Usually dev uses /tmp/test.db. I should validly migrate the one being used.
# I will check ENV or just default to common paths.

def migrate(db_path):
    print(f"Migrating {db_path}...")
    if not os.path.exists(db_path):
        print(f"Database {db_path} not found.")
        return

    engine = create_engine(f"sqlite:///{db_path}")
    with engine.connect() as conn:
        try:
            conn.execute(text("ALTER TABLE balance_audits ADD COLUMN net_position DECIMAL(20,2) DEFAULT 0"))
            print(f"Successfully added net_position to {db_path}")
        except Exception as e:
            if "duplicate column" in str(e).lower():
                print("Column already exists.")
            else:
                print(f"Error: {e}")

if __name__ == "__main__":
    # Migrate both potential dev databases to be safe
    migrate("/tmp/test.db")
    migrate("expense.db")
