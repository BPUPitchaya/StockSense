import os
from typing import List, Dict, Optional
from sqlalchemy import create_engine, Column, Integer, String, Float, DateTime, ForeignKey
from sqlalchemy.ext.declarative import declarative_base
from sqlalchemy.orm import sessionmaker, relationship
from datetime import datetime
import hashlib

# Get database URL from environment variable, default to SQLite for local development
DATABASE_URL = os.getenv('DATABASE_URL', 'sqlite:///stock_portfolio.db')

# Create engine
engine = create_engine(DATABASE_URL)
SessionLocal = sessionmaker(autocommit=False, autoflush=False, bind=engine)
Base = declarative_base()

# Define models
class User(Base):
    __tablename__ = 'users'
    id = Column(Integer, primary_key=True, autoincrement=True)
    email = Column(String, nullable=False, unique=True)
    password_hash = Column(String, nullable=False)
    created_at = Column(DateTime, default=datetime.utcnow)

class PortfolioPosition(Base):
    __tablename__ = 'portfolio'
    id = Column(Integer, primary_key=True, autoincrement=True)
    user_id = Column(Integer, ForeignKey('users.id'), nullable=True)
    ticker = Column(String, nullable=False)
    buy_price = Column(Float, nullable=False)
    quantity = Column(Float, nullable=False)
    date = Column(String, nullable=False)
    user = relationship("User", backref="portfolio_positions")

class Budget(Base):
    __tablename__ = 'budget'
    id = Column(Integer, primary_key=True, autoincrement=True)
    amount = Column(Float, nullable=False)
    created_at = Column(DateTime, default=datetime.utcnow)

class PersonalWatchlist(Base):
    __tablename__ = 'personal_watchlist'
    id = Column(Integer, primary_key=True, autoincrement=True)
    user_id = Column(Integer, ForeignKey('users.id'), nullable=True)
    ticker = Column(String, nullable=False)
    added_at = Column(DateTime, default=datetime.utcnow)
    user = relationship("User", backref="watchlist_items")

def init_db():
    """Initialize the database tables"""
    Base.metadata.create_all(bind=engine)
    print("Database initialized successfully")

def hash_password(password: str) -> str:
    """Hash a password using SHA256"""
    return hashlib.sha256(password.encode()).hexdigest()

def create_user(email: str, password: str) -> Optional[int]:
    """Create a new user and return the user ID"""
    session = SessionLocal()
    try:
        # Check if user already exists
        existing = session.query(User).filter(User.email == email).first()
        if existing:
            return None
        
        password_hash = hash_password(password)
        new_user = User(email=email, password_hash=password_hash)
        session.add(new_user)
        session.commit()
        return new_user.id
    finally:
        session.close()

def verify_user(email: str, password: str) -> Optional[Dict]:
    """Verify user credentials and return user data if valid"""
    session = SessionLocal()
    try:
        user = session.query(User).filter(User.email == email).first()
        if user and user.password_hash == hash_password(password):
            return {
                'id': user.id,
                'email': user.email,
                'created_at': user.created_at.isoformat() if user.created_at else None
            }
        return None
    finally:
        session.close()

def add_position(position: Dict, user_id: int = None) -> None:
    """Add a position to the portfolio"""
    session = SessionLocal()
    try:
        new_position = PortfolioPosition(
            user_id=user_id,
            ticker=position['ticker'],
            buy_price=position['buy_price'],
            quantity=position['quantity'],
            date=position['date']
        )
        session.add(new_position)
        session.commit()
    finally:
        session.close()

def get_all_positions(user_id: int = None) -> List[Dict]:
    """Get all positions from the portfolio"""
    session = SessionLocal()
    try:
        query = session.query(PortfolioPosition)
        if user_id:
            query = query.filter(PortfolioPosition.user_id == user_id)
        positions = query.all()
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

def add_to_personal_watchlist(ticker: str, user_id: int = None) -> None:
    """Add a stock to the personal watchlist"""
    session = SessionLocal()
    try:
        # Check if already exists for this user
        query = session.query(PersonalWatchlist).filter(
            PersonalWatchlist.ticker == ticker.upper()
        )
        if user_id:
            query = query.filter(PersonalWatchlist.user_id == user_id)
        existing = query.first()
        if not existing:
            new_watchlist_item = PersonalWatchlist(
                user_id=user_id,
                ticker=ticker.upper()
            )
            session.add(new_watchlist_item)
            session.commit()
    finally:
        session.close()

def remove_from_personal_watchlist(ticker: str, user_id: int = None) -> None:
    """Remove a stock from the personal watchlist"""
    session = SessionLocal()
    try:
        query = session.query(PersonalWatchlist).filter(
            PersonalWatchlist.ticker == ticker.upper()
        )
        if user_id:
            query = query.filter(PersonalWatchlist.user_id == user_id)
        watchlist_item = query.first()
        if watchlist_item:
            session.delete(watchlist_item)
            session.commit()
    finally:
        session.close()

def get_personal_watchlist(user_id: int = None) -> List[str]:
    """Get all stocks in the personal watchlist"""
    session = SessionLocal()
    try:
        query = session.query(PersonalWatchlist)
        if user_id:
            query = query.filter(PersonalWatchlist.user_id == user_id)
        watchlist_items = query.all()
        return [item.ticker for item in watchlist_items]
    finally:
        session.close()