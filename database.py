import os
from typing import List, Dict, Optional
from sqlalchemy import create_engine, Column, Integer, String, Float, DateTime
from sqlalchemy.ext.declarative import declarative_base
from sqlalchemy.orm import sessionmaker
from datetime import datetime

# Get database URL from environment variable, default to SQLite for local development
DATABASE_URL = os.getenv('DATABASE_URL', 'sqlite:///stock_portfolio.db')

# Create engine
engine = create_engine(DATABASE_URL)
SessionLocal = sessionmaker(autocommit=False, autoflush=False, bind=engine)
Base = declarative_base()

# Define models
class PortfolioPosition(Base):
    __tablename__ = 'portfolio'
    id = Column(Integer, primary_key=True, autoincrement=True)
    ticker = Column(String, nullable=False)
    buy_price = Column(Float, nullable=False)
    quantity = Column(Float, nullable=False)
    date = Column(String, nullable=False)

class Budget(Base):
    __tablename__ = 'budget'
    id = Column(Integer, primary_key=True, autoincrement=True)
    amount = Column(Float, nullable=False)
    created_at = Column(DateTime, default=datetime.utcnow)

class PersonalWatchlist(Base):
    __tablename__ = 'personal_watchlist'
    id = Column(Integer, primary_key=True, autoincrement=True)
    ticker = Column(String, nullable=False, unique=True)
    added_at = Column(DateTime, default=datetime.utcnow)

def init_db():
    """Initialize the database tables"""
    Base.metadata.create_all(bind=engine)
    print("Database initialized successfully")

def add_position(position: Dict) -> None:
    """Add a position to the portfolio"""
    session = SessionLocal()
    try:
        new_position = PortfolioPosition(
            ticker=position['ticker'],
            buy_price=position['buy_price'],
            quantity=position['quantity'],
            date=position['date']
        )
        session.add(new_position)
        session.commit()
    finally:
        session.close()

def get_all_positions() -> List[Dict]:
    """Get all positions from the portfolio"""
    session = SessionLocal()
    try:
        positions = session.query(PortfolioPosition).all()
        return [
            {
                'id': p.id,
                'ticker': p.ticker,
                'buy_price': p.buy_price,
                'quantity': p.quantity,
                'date': p.date
            }
            for p in positions
        ]
    finally:
        session.close()

def delete_position(position_id: int) -> None:
    """Delete a position from the portfolio"""
    session = SessionLocal()
    try:
        position = session.query(PortfolioPosition).filter(PortfolioPosition.id == position_id).first()
        if position:
            session.delete(position)
            session.commit()
    finally:
        session.close()

def update_position(position_id: int, position: Dict) -> None:
    """Update a position in the portfolio"""
    session = SessionLocal()
    try:
        db_position = session.query(PortfolioPosition).filter(PortfolioPosition.id == position_id).first()
        if db_position:
            db_position.ticker = position['ticker']
            db_position.buy_price = position['buy_price']
            db_position.quantity = position['quantity']
            db_position.date = position['date']
            session.commit()
    finally:
        session.close()

def set_budget(amount: float) -> None:
    """Set the budget amount"""
    session = SessionLocal()
    try:
        # Delete existing budget
        session.query(Budget).delete()
        # Add new budget
        new_budget = Budget(amount=amount)
        session.add(new_budget)
        session.commit()
    finally:
        session.close()

def get_budget() -> Optional[Dict]:
    """Get the current budget"""
    session = SessionLocal()
    try:
        budget = session.query(Budget).order_by(Budget.id.desc()).first()
        if budget:
            return {
                'id': budget.id,
                'amount': budget.amount,
                'created_at': budget.created_at.isoformat() if budget.created_at else None
            }
        return None
    finally:
        session.close()

def add_to_personal_watchlist(ticker: str) -> None:
    """Add a stock to the personal watchlist"""
    session = SessionLocal()
    try:
        # Check if already exists
        existing = session.query(PersonalWatchlist).filter(PersonalWatchlist.ticker == ticker.upper()).first()
        if not existing:
            new_watchlist_item = PersonalWatchlist(ticker=ticker.upper())
            session.add(new_watchlist_item)
            session.commit()
    finally:
        session.close()

def remove_from_personal_watchlist(ticker: str) -> None:
    """Remove a stock from the personal watchlist"""
    session = SessionLocal()
    try:
        watchlist_item = session.query(PersonalWatchlist).filter(PersonalWatchlist.ticker == ticker.upper()).first()
        if watchlist_item:
            session.delete(watchlist_item)
            session.commit()
    finally:
        session.close()

def get_personal_watchlist() -> List[str]:
    """Get all stocks in the personal watchlist"""
    session = SessionLocal()
    try:
        watchlist_items = session.query(PersonalWatchlist).all()
        return [item.ticker for item in watchlist_items]
    finally:
        session.close()