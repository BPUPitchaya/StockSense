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

# Models
class User(Base):
    __tablename__ = 'users'
    id = Column(Integer, primary_key=True)
    email = Column(String, unique=True, nullable=False)
    password_hash = Column(String, nullable=False)
    created_at = Column(DateTime, default=datetime.utcnow)

class PortfolioPosition(Base):
    __tablename__ = 'portfolio'
    id = Column(Integer, primary_key=True)
    user_id = Column(Integer, ForeignKey('users.id'), nullable=True)
    ticker = Column(String, nullable=False)
    buy_price = Column(Float, nullable=False)
    quantity = Column(Float, nullable=False)
    date = Column(DateTime, default=datetime.utcnow)

class PersonalWatchlist(Base):
    __tablename__ = 'personal_watchlist'
    id = Column(Integer, primary_key=True)
    user_id = Column(Integer, ForeignKey('users.id'), nullable=True)
    ticker = Column(String, nullable=False)
    added_at = Column(DateTime, default=datetime.utcnow)

def init_db():
    """Initialize the database"""
    try:
        Base.metadata.create_all(bind=engine)
        print("Database initialized successfully")
        
        # Add user_id column to portfolio if it doesn't exist
        from sqlalchemy import inspect
        inspector = inspect(engine)
        columns = [col['name'] for col in inspector.get_columns('portfolio')]
        if 'user_id' not in columns:
            with engine.connect() as conn:
                conn.execute("ALTER TABLE portfolio ADD COLUMN user_id INTEGER")
                conn.commit()
            print("user_id column added to portfolio")
        
        # Add user_id column to personal_watchlist if it doesn't exist
        columns = [col['name'] for col in inspector.get_columns('personal_watchlist')]
        if 'user_id' not in columns:
            with engine.connect() as conn:
                conn.execute("ALTER TABLE personal_watchlist ADD COLUMN user_id INTEGER")
                conn.commit()
            print("user_id column added to personal_watchlist")
        
        # Ensure default stocks are in personal watchlist
        session = SessionLocal()
        try:
            # Check if personal watchlist is empty
            count = session.query(PersonalWatchlist).count()
            if count == 0:
                # Add default stocks
                default_stocks = ['AAPL', 'MSFT', 'GOOGL', 'AMZN', 'TSLA']
                for ticker in default_stocks:
                    stock = PersonalWatchlist(ticker=ticker)
                    session.add(stock)
                session.commit()
                print("Ensured 5 default stocks are in personal watchlist")
        finally:
            session.close()
            
    except Exception as e:
        print(f"Error initializing database: {e}")

def hash_password(password: str) -> str:
    """Hash a password using SHA256"""
    return hashlib.sha256(password.encode()).hexdigest()

def create_user(email: str, password: str) -> bool:
    """Create a new user"""
    session = SessionLocal()
    try:
        # Check if user already exists
        existing_user = session.query(User).filter(User.email == email).first()
        if existing_user:
            return False
        
        # Create new user
        password_hash = hash_password(password)
        new_user = User(email=email, password_hash=password_hash)
        session.add(new_user)
        session.commit()
        return True
    finally:
        session.close()

def verify_user(email: str, password: str) -> Optional[Dict]:
    """Verify user credentials and return user data if valid"""
    session = SessionLocal()
    try:
        password_hash = hash_password(password)
        user = session.query(User).filter(
            User.email == email,
            User.password_hash == password_hash
        ).first()
        
        if user:
            return {
                'id': user.id,
                'email': user.email,
                'created_at': user.created_at.isoformat() if user.created_at else None
            }
        return None
    finally:
        session.close()

def verify_admin(email: str, password: str) -> bool:
    """Verify admin credentials (hardcoded for now)"""
    ADMIN_EMAIL = "admin@admin.com"
    ADMIN_PASSWORD = "1234"
    return email == ADMIN_EMAIL and password == ADMIN_PASSWORD

def get_all_users() -> Dict:
    """Get all users (admin only)"""
    session = SessionLocal()
    try:
        users = session.query(User).all()
        return {
            'users': [
                {
                    'id': user.id,
                    'email': user.email,
                    'created_at': user.created_at.isoformat() if user.created_at else None
                }
                for user in users
            ]
        }
    finally:
        session.close()

def delete_user(user_id: int) -> bool:
    """Delete a user (admin only)"""
    session = SessionLocal()
    try:
        user = session.query(User).filter(User.id == user_id).first()
        if user:
            session.delete(user)
            session.commit()
            return True
        return False
    finally:
        session.close()

def get_user_statistics() -> Dict:
    """Get user statistics for admin dashboard"""
    session = SessionLocal()
    try:
        from datetime import datetime, timedelta
        
        total_users = session.query(User).count()
        
        # Users created in the last 7 days
        week_ago = datetime.now() - timedelta(days=7)
        new_users_week = session.query(User).filter(User.created_at >= week_ago).count()
        
        # Users created today
        today = datetime.now().date()
        new_users_today = session.query(User).filter(
            User.created_at >= datetime.combine(today, datetime.min.time())
        ).count()
        
        return {
            'total_users': total_users,
            'new_users_week': new_users_week,
            'new_users_today': new_users_today,
        }
    finally:
        session.close()

def get_popular_stocks() -> List[Dict]:
    """Get most popular stocks in watchlists"""
    session = SessionLocal()
    try:
        from sqlalchemy import func
        
        # Count stocks in personal watchlists
        stock_counts = session.query(
            PersonalWatchlist.ticker,
            func.count(PersonalWatchlist.ticker).label('count')
        ).group_by(PersonalWatchlist.ticker).order_by(
            func.count(PersonalWatchlist.ticker).desc()
        ).limit(10).all()
        
        return [
            {'ticker': ticker, 'count': count}
            for ticker, count in stock_counts
        ]
    finally:
        session.close()

def get_total_portfolio_value() -> Dict:
    """Get total portfolio value across all users"""
    session = SessionLocal()
    try:
        positions = session.query(PortfolioPosition).all()
        total_value = 0
        total_positions = len(positions)
        
        for pos in positions:
            total_value += pos.buy_price * pos.quantity
        
        return {
            'total_value': total_value,
            'total_positions': total_positions,
        }
    finally:
        session.close()

def get_recent_signups(limit: int = 5) -> List[Dict]:
    """Get recent user signups"""
    session = SessionLocal()
    try:
        recent_users = session.query(User).order_by(
            User.created_at.desc()
        ).limit(limit).all()
        
        return [
            {
                'id': user.id,
                'email': user.email,
                'created_at': user.created_at.isoformat() if user.created_at else None
            }
            for user in recent_users
        ]
    finally:
        session.close()

def get_system_info() -> Dict:
    """Get system information"""
    import os
    session = SessionLocal()
    try:
        # Count total records in each table
        user_count = session.query(User).count()
        portfolio_count = session.query(PortfolioPosition).count()
        watchlist_count = session.query(PersonalWatchlist).count()
        
        return {
            'user_count': user_count,
            'portfolio_count': portfolio_count,
            'watchlist_count': watchlist_count,
            'database_url': os.getenv('DATABASE_URL', 'SQLite'),
        }
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
                'id': pos.id,
                'ticker': pos.ticker,
                'buy_price': pos.buy_price,
                'quantity': pos.quantity,
                'date': pos.date.isoformat() if pos.date else None
            }
            for pos in positions
        ]
    finally:
        session.close()

def delete_position(position_id: int) -> bool:
    """Delete a position from the portfolio"""
    session = SessionLocal()
    try:
        position = session.query(PortfolioPosition).filter(PortfolioPosition.id == position_id).first()
        if position:
            session.delete(position)
            session.commit()
            return True
        return False
    finally:
        session.close()

def add_to_watchlist(ticker: str, user_id: int = None) -> bool:
    """Add a stock to the personal watchlist"""
    session = SessionLocal()
    try:
        # Check if already in watchlist
        existing = session.query(PersonalWatchlist).filter(
            PersonalWatchlist.ticker == ticker,
            (PersonalWatchlist.user_id == user_id) | (PersonalWatchlist.user_id.is_(None))
        ).first()
        if existing:
            return False
        
        new_watchlist_item = PersonalWatchlist(ticker=ticker, user_id=user_id)
        session.add(new_watchlist_item)
        session.commit()
        return True
    finally:
        session.close()

def get_personal_watchlist(user_id: int = None) -> List[str]:
    """Get personal watchlist for a user"""
    session = SessionLocal()
    try:
        query = session.query(PersonalWatchlist.ticker).distinct()
        if user_id:
            query = query.filter(
                (PersonalWatchlist.user_id == user_id) | (PersonalWatchlist.user_id.is_(None))
            )
        result = query.all()
        return [ticker for (ticker,) in result]
    finally:
        session.close()

def remove_from_watchlist(ticker: str, user_id: int = None) -> bool:
    """Remove a stock from the personal watchlist"""
    session = SessionLocal()
    try:
        # Find and delete the stock
        item = session.query(PersonalWatchlist).filter(
            PersonalWatchlist.ticker == ticker,
            (PersonalWatchlist.user_id == user_id) | (PersonalWatchlist.user_id.is_(None))
        ).first()
        if item:
            session.delete(item)
            session.commit()
            return True
        return False
    finally:
        session.close()

def set_budget(amount: float, user_id: int = None) -> bool:
    """Set the budget for a user"""
    session = SessionLocal()
    try:
        # For simplicity, we'll store budget in a separate table or use user model
        # For now, this is a placeholder
        return True
    finally:
        session.close()

def get_budget(user_id: int = None) -> float:
    """Get the budget for a user"""
    session = SessionLocal()
    try:
        # Placeholder - return default budget
        return 10000.0
    finally:
        session.close()
