from datetime import datetime
from sqlalchemy import Column, Integer, String, DateTime
from app.database import Base

class SystemMetadata(Base):
    """
    System metadata table to track database versioning and creation.
    """
    __tablename__ = "system_metadata"

    id = Column(Integer, primary_key=True, index=True)
    app_version = Column(String, nullable=False)
    schema_version = Column(Integer, nullable=False, default=1)
    created_at = Column(DateTime, default=datetime.utcnow, nullable=False)

    def __repr__(self):
        return f"<SystemMetadata(version={self.app_version}, schema={self.schema_version})>"
