import os
from typing import List, Dict, Optional
from sqlalchemy import create_engine, Column, Integer, String, Float, DateTime, ForeignKey, text, Boolean
from sqlalchemy.ext.declarative import declarative_base
from sqlalchemy.orm import sessionmaker, relationship
from datetime import datetime, timedelta
import hashlib

# Get database URL from environment variable, default to SQLite for local development
DATABASE_URL = os.getenv('DATABASE_URL') or 'sqlite:///stock_portfolio.db'

# Create engine
engine = create_engine(DATABASE_URL)
SessionLocal = sessionmaker(autocommit=False, autoflush=False, bind=engine)
Base = declarative_base()

# Models
class User(Base):
    __tablename__ = 'users'
    id = Column(Integer, primary_key=True)
    first_name = Column(String, nullable=True)
    last_name = Column(String, nullable=True)
    email = Column(String, unique=True, nullable=False)
    password_hash = Column(String, nullable=False)
    preferred_currency = Column(String, default='USD')  # User's preferred currency
    use_native_currency = Column(Boolean, default=False)  # Show stock in native currency
    is_verified = Column(Boolean, default=False)  # Email verification status
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

class Budget(Base):
    __tablename__ = 'budgets'
    id = Column(Integer, primary_key=True)
    user_id = Column(Integer, ForeignKey('users.id'), nullable=True)
    amount = Column(Float, default=0.0)
    updated_at = Column(DateTime, default=datetime.utcnow)

class VerificationToken(Base):
    __tablename__ = 'verification_tokens'
    id = Column(Integer, primary_key=True)
    email = Column(String, nullable=False)
    token = Column(String, unique=True, nullable=False)
    token_type = Column(String, nullable=False)  # 'email_verification' or 'password_reset'
    expires_at = Column(DateTime, nullable=False)
    used = Column(Boolean, default=False)
    created_at = Column(DateTime, default=datetime.utcnow)

class Notification(Base):
    __tablename__ = 'notifications'
    id = Column(Integer, primary_key=True)
    user_id = Column(Integer, ForeignKey('users.id'), nullable=False)
    type = Column(String, nullable=False)  # 'stock_alert', 'watchlist_update', 'budget_alert', 'admin_announcement'
    title = Column(String, nullable=False)
    message = Column(String, nullable=False)
    is_read = Column(Boolean, default=False)
    created_at = Column(DateTime, default=datetime.utcnow)
    # Optional fields for specific notification types
    ticker = Column(String, nullable=True)
    target_price = Column(Float, nullable=True)
    current_price = Column(Float, nullable=True)

class NotificationPreference(Base):
    __tablename__ = 'notification_preferences'
    id = Column(Integer, primary_key=True)
    user_id = Column(Integer, ForeignKey('users.id'), nullable=False, unique=True)
    stock_alerts_enabled = Column(Boolean, default=True)
    watchlist_updates_enabled = Column(Boolean, default=True)
    budget_alerts_enabled = Column(Boolean, default=True)
    admin_announcements_enabled = Column(Boolean, default=True)
    email_notifications_enabled = Column(Boolean, default=False)  # Disabled until custom domain

class StockPriceAlert(Base):
    __tablename__ = 'stock_price_alerts'
    id = Column(Integer, primary_key=True)
    user_id = Column(Integer, ForeignKey('users.id'), nullable=False)
    ticker = Column(String, nullable=False)
    target_price = Column(Float, nullable=False)
    condition = Column(String, nullable=False)  # 'above' or 'below'
    is_active = Column(Boolean, default=True)
    is_triggered = Column(Boolean, default=False)
    created_at = Column(DateTime, default=datetime.utcnow)
    triggered_at = Column(DateTime, nullable=True)

class PredictionHistory(Base):
    __tablename__ = 'prediction_history'
    id = Column(Integer, primary_key=True)
    ticker = Column(String, nullable=False, index=True)
    signal = Column(String, nullable=False)  # BUY, SELL, HOLD
    current_price = Column(Float, nullable=False)  # Price when prediction made
    predicted_direction = Column(String, nullable=False)  # up, down, flat
    prediction_date = Column(DateTime, default=datetime.utcnow)
    target_date = Column(DateTime, nullable=False)  # 10 days forward
    actual_price = Column(Float, nullable=True)  # Filled in later
    accuracy_percent = Column(Float, nullable=True)  # Calculated when target_date reached
    is_correct = Column(Boolean, nullable=True)  # True if direction matched

class PredictionWatchlist(Base):
    __tablename__ = 'prediction_watchlist'
    id = Column(Integer, primary_key=True)
    user_id = Column(Integer, ForeignKey('users.id'), nullable=True)
    ticker = Column(String, nullable=False)
    added_date = Column(DateTime, default=datetime.utcnow)
    added_price = Column(Float, nullable=False)

class Feedback(Base):
    __tablename__ = 'feedback'
    id = Column(Integer, primary_key=True)
    user_id = Column(Integer, ForeignKey('users.id'), nullable=False)
    feedback = Column(String, nullable=False)
    category = Column(String, nullable=False)  # 'bug', 'feature', 'general', 'other'
    rating = Column(Integer, nullable=True)  # 1-5 rating
    created_at = Column(DateTime, default=datetime.utcnow)

class AIAnalysisCache(Base):
    __tablename__ = 'ai_analysis_cache'
    id = Column(Integer, primary_key=True)
    ticker = Column(String, nullable=False, index=True)
    owns_stock = Column(Boolean, nullable=False)
    rsi = Column(Float, nullable=True)
    ma50 = Column(Float, nullable=True)
    ma200 = Column(Float, nullable=True)
    signal = Column(String, nullable=True)
    analysis = Column(String, nullable=False)
    created_at = Column(DateTime, default=datetime.utcnow)
    expires_at = Column(DateTime, nullable=False)

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
                conn.execute(text("ALTER TABLE portfolio ADD COLUMN user_id INTEGER"))
                conn.commit()
            print("user_id column added to portfolio")
        
        # Add user_id column to personal_watchlist if it doesn't exist
        columns = [col['name'] for col in inspector.get_columns('personal_watchlist')]
        if 'user_id' not in columns:
            with engine.connect() as conn:
                conn.execute(text("ALTER TABLE personal_watchlist ADD COLUMN user_id INTEGER"))
                conn.commit()
            print("user_id column added to personal_watchlist")
        
        # Add preferred_currency column to users if it doesn't exist
        columns = [col['name'] for col in inspector.get_columns('users')]
        if 'preferred_currency' not in columns:
            with engine.connect() as conn:
                conn.execute(text("ALTER TABLE users ADD COLUMN preferred_currency VARCHAR DEFAULT 'USD'"))
                conn.commit()
            print("preferred_currency column added to users")
        
        # Add is_verified column to users if it doesn't exist
        columns = [col['name'] for col in inspector.get_columns('users')]
        if 'is_verified' not in columns:
            with engine.connect() as conn:
                conn.execute(text("ALTER TABLE users ADD COLUMN is_verified BOOLEAN DEFAULT FALSE"))
                conn.commit()
            print("is_verified column added to users")
        
        # Add first_name column to users if it doesn't exist
        columns = [col['name'] for col in inspector.get_columns('users')]
        if 'first_name' not in columns:
            with engine.connect() as conn:
                conn.execute(text("ALTER TABLE users ADD COLUMN first_name VARCHAR"))
                conn.commit()
            print("first_name column added to users")
        
        # Add last_name column to users if it doesn't exist
        columns = [col['name'] for col in inspector.get_columns('users')]
        if 'last_name' not in columns:
            with engine.connect() as conn:
                conn.execute(text("ALTER TABLE users ADD COLUMN last_name VARCHAR"))
                conn.commit()
            print("last_name column added to users")
        
        # Add use_native_currency column to users if it doesn't exist
        columns = [col['name'] for col in inspector.get_columns('users')]
        if 'use_native_currency' not in columns:
            with engine.connect() as conn:
                conn.execute(text("ALTER TABLE users ADD COLUMN use_native_currency BOOLEAN DEFAULT FALSE"))
                conn.commit()
            print("use_native_currency column added to users")
        
        # Create verification_tokens table if it doesn't exist
        if 'verification_tokens' not in inspector.get_table_names():
            VerificationToken.__table__.create(bind=engine)
            print("verification_tokens table created")
        
        # Create prediction_watchlist table if it doesn't exist
        if 'prediction_watchlist' not in inspector.get_table_names():
            PredictionWatchlist.__table__.create(bind=engine)
            print("prediction_watchlist table created")
            
    except Exception as e:
        print(f"Error initializing database: {e}")

def hash_password(password: str) -> str:
    """Hash a password using SHA256"""
    return hashlib.sha256(password.encode()).hexdigest()

def create_user(email: str, password: str, first_name: str = None, last_name: str = None) -> bool:
    """Create a new user"""
    session = SessionLocal()
    try:
        # Check if user already exists
        existing_user = session.query(User).filter(User.email == email).first()
        if existing_user:
            return False
        
        # Create new user (verified by default - email verification disabled until domain is available)
        password_hash = hash_password(password)
        new_user = User(
            email=email, 
            password_hash=password_hash,
            first_name=first_name,
            last_name=last_name,
            is_verified=True
        )
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
                'is_verified': user.is_verified,
                'created_at': user.created_at.isoformat() if user.created_at else None
            }
        return None
    finally:
        session.close()

def verify_admin(email: str, password: str) -> bool:
    """Verify admin credentials from environment variables"""
    ADMIN_EMAIL = os.getenv("ADMIN_EMAIL")
    ADMIN_PASSWORD = os.getenv("ADMIN_PASSWORD")
    if not ADMIN_EMAIL or not ADMIN_PASSWORD:
        raise ValueError("ADMIN_EMAIL and ADMIN_PASSWORD environment variables must be set")
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
                    'first_name': user.first_name,
                    'last_name': user.last_name,
                    'created_at': user.created_at.isoformat() if user.created_at else None
                }
                for user in users
            ]
        }
    finally:
        session.close()

def get_user_profile(user_id: int) -> Dict:
    """Get detailed user profile (admin only)"""
    session = SessionLocal()
    try:
        user = session.query(User).filter(User.id == user_id).first()
        if not user:
            return None
        return {
            'id': user.id,
            'first_name': user.first_name,
            'last_name': user.last_name,
            'email': user.email,
            'password_hash': user.password_hash,
            'preferred_currency': user.preferred_currency,
            'use_native_currency': user.use_native_currency,
            'is_verified': user.is_verified,
            'created_at': user.created_at.isoformat() if user.created_at else None
        }
    finally:
        session.close()

def reset_user_password(user_id: int, new_password: str) -> bool:
    """Reset user password (admin only)"""
    session = SessionLocal()
    try:
        user = session.query(User).filter(User.id == user_id).first()
        if not user:
            return False
        password_hash = hashlib.sha256(new_password.encode()).hexdigest()
        user.password_hash = password_hash
        session.commit()
        return True
    except Exception as e:
        session.rollback()
        raise e
    finally:
        session.close()

def delete_user(user_id: int) -> bool:
    """Delete a user (admin only) - cascades to related data"""
    session = SessionLocal()
    try:
        user = session.query(User).filter(User.id == user_id).first()
        if not user:
            return False
        
        # Delete related data first (cascade delete)
        # Delete portfolio positions
        session.query(PortfolioPosition).filter(PortfolioPosition.user_id == user_id).delete()
        
        # Delete personal watchlist entries
        session.query(PersonalWatchlist).filter(PersonalWatchlist.user_id == user_id).delete()
        
        # Delete prediction watchlist entries
        session.query(PredictionWatchlist).filter(PredictionWatchlist.user_id == user_id).delete()
        
        # Delete budgets
        session.query(Budget).filter(Budget.user_id == user_id).delete()
        
        # Note: verification_tokens table structure differs in production, skip cascade delete
        
        # Delete the user
        session.delete(user)
        session.commit()
        return True
    except Exception as e:
        session.rollback()
        raise e
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
                'first_name': user.first_name,
                'last_name': user.last_name,
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

def get_user_id_from_token(authorization: str) -> Optional[int]:
    """Extract user_id from JWT token"""
    import jwt
    JWT_SECRET = os.getenv("JWT_SECRET")
    if not JWT_SECRET:
        return None
    
    try:
        token = authorization.replace("Bearer ", "")
        payload = jwt.decode(token, JWT_SECRET, algorithms=["HS256"])
        return payload.get("user_id")
    except Exception:
        return None

def create_feedback(user_id: int, feedback: str, category: str, rating: Optional[int] = None) -> bool:
    """Create a new feedback entry"""
    session = SessionLocal()
    try:
        new_feedback = Feedback(
            user_id=user_id,
            feedback=feedback,
            category=category,
            rating=rating
        )
        session.add(new_feedback)
        session.commit()
        return True
    except Exception:
        session.rollback()
        return False
    finally:
        session.close()

def get_all_feedback() -> List[Dict]:
    """Get all feedback for admin view"""
    session = SessionLocal()
    try:
        feedback_list = session.query(Feedback, User).join(User, Feedback.user_id == User.id).order_by(Feedback.created_at.desc()).all()
        return [
            {
                'id': feedback.id,
                'user_id': feedback.user_id,
                'user_email': user.email,
                'feedback': feedback.feedback,
                'category': feedback.category,
                'rating': feedback.rating,
                'created_at': feedback.created_at.isoformat() if feedback.created_at else None,
            }
            for feedback, user in feedback_list
        ]
    finally:
        session.close()

def get_cached_analysis(ticker: str, owns_stock: bool, rsi: float = None, ma50: float = None, ma200: float = None, signal: str = None) -> Optional[str]:
    """Get cached AI analysis if available and not expired"""
    session = SessionLocal()
    try:
        from datetime import datetime
        
        # Delete expired entries
        session.query(AIAnalysisCache).filter(AIAnalysisCache.expires_at < datetime.utcnow()).delete()
        session.commit()
        
        # Try to find matching cache entry
        cache = session.query(AIAnalysisCache).filter(
            AIAnalysisCache.ticker == ticker,
            AIAnalysisCache.owns_stock == owns_stock,
            AIAnalysisCache.expires_at >= datetime.utcnow()
        ).order_by(AIAnalysisCache.created_at.desc()).first()
        
        if cache:
            return cache.analysis
        return None
    finally:
        session.close()

def save_analysis_cache(ticker: str, owns_stock: bool, analysis: str, rsi: float = None, ma50: float = None, ma200: float = None, signal: str = None, cache_hours: int = 24) -> bool:
    """Save AI analysis to cache"""
    session = SessionLocal()
    try:
        from datetime import datetime, timedelta
        
        expires_at = datetime.utcnow() + timedelta(hours=cache_hours)
        
        cache_entry = AIAnalysisCache(
            ticker=ticker,
            owns_stock=owns_stock,
            rsi=rsi,
            ma50=ma50,
            ma200=ma200,
            signal=signal,
            analysis=analysis,
            expires_at=expires_at
        )
        session.add(cache_entry)
        session.commit()
        return True
    except Exception as e:
        session.rollback()
        print(f"Error saving analysis cache: {e}")
        return False
    finally:
        session.close()

def get_rule_based_analysis(ticker: str, owns_stock: bool, rsi: float = None, ma50: float = None, ma200: float = None, signal: str = None, current_price: float = None) -> str:
    """Generate rule-based analysis as fallback when AI is unavailable"""
    recommendation = "HOLD"
    strengths = []
    risks = []
    
    # RSI analysis
    if rsi:
        if rsi < 30:
            strengths.append(f"RSI ({rsi:.1f}) indicates oversold conditions")
            if not owns_stock:
                recommendation = "BUY"
        elif rsi > 70:
            risks.append(f"RSI ({rsi:.1f}) indicates overbought conditions")
            if owns_stock:
                recommendation = "SELL"
        else:
            strengths.append(f"RSI ({rsi:.1f}) is in neutral zone")
    
    # Moving average analysis
    if ma50 and ma200:
        if current_price:
            if current_price > ma50 > ma200:
                strengths.append("Price above both 50-day and 200-day MA (strong uptrend)")
                if not owns_stock:
                    recommendation = "BUY"
            elif current_price < ma50 < ma200:
                risks.append("Price below both 50-day and 200-day MA (downtrend)")
                if owns_stock:
                    recommendation = "SELL"
            elif current_price > ma50 < ma200:
                strengths.append("Price above 50-day MA (short-term bullish)")
            elif current_price < ma50 > ma200:
                risks.append("Price below 50-day MA (short-term bearish)")
    
    # Signal analysis
    if signal:
        if signal in ["Buy", "Strong Buy"]:
            strengths.append(f"Technical signal: {signal}")
            if not owns_stock and recommendation == "HOLD":
                recommendation = "BUY"
        elif signal in ["Sell", "Strong Sell"]:
            risks.append(f"Technical signal: {signal}")
            if owns_stock and recommendation == "HOLD":
                recommendation = "SELL"
    
    # Adjust recommendation based on ownership
    if owns_stock and recommendation == "BUY":
        recommendation = "HOLD"
    elif not owns_stock and recommendation == "SELL":
        recommendation = "HOLD"
    
    # Build analysis text
    analysis = f"""## Recommendation
{recommendation}

## Strengths
"""
    if strengths:
        for strength in strengths:
            analysis += f"- {strength}\n"
    else:
        analysis += "- Limited technical strength indicators\n"
    
    analysis += "\n## Risks\n"
    if risks:
        for risk in risks:
            analysis += f"- {risk}\n"
    else:
        analysis += "- Limited technical risk indicators\n"
    
    analysis += "\n## Outlook\n"
    if recommendation == "BUY":
        analysis += "Technical indicators suggest potential upside. Consider position sizing appropriately."
    elif recommendation == "SELL":
        analysis += "Technical indicators suggest potential downside. Consider risk management."
    else:
        analysis += "Mixed technical signals. Wait for clearer direction before taking action."
    
    return analysis

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
                'date': pos.date.isoformat() if pos.date and hasattr(pos.date, 'isoformat') else pos.date if pos.date else None
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
            query = query.filter(PersonalWatchlist.user_id == user_id)
        result = query.all()
        return [ticker for (ticker,) in result]
    finally:
        session.close()

def clear_watchlist_by_email(email: str) -> int:
    """Clear all watchlist entries for a user by email"""
    session = SessionLocal()
    try:
        user = session.query(User).filter(User.email == email).first()
        if not user:
            raise ValueError(f"User {email} not found")
        deleted = session.query(PersonalWatchlist).filter(PersonalWatchlist.user_id == user.id).delete()
        session.commit()
        return deleted
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
        existing = session.query(Budget).filter(Budget.user_id == user_id).first()
        if existing:
            existing.amount = amount
            existing.updated_at = datetime.utcnow()
        else:
            budget = Budget(user_id=user_id, amount=amount)
            session.add(budget)
        session.commit()
        return True
    except Exception as e:
        session.rollback()
        print(f"Error setting budget: {e}")
        return False
    finally:
        session.close()

def get_budget(user_id: int = None) -> float:
    """Get the budget for a user"""
    session = SessionLocal()
    try:
        budget = session.query(Budget).filter(Budget.user_id == user_id).first()
        return budget.amount if budget else 0.0
    except Exception as e:
        print(f"Error getting budget: {e}")
        return 0.0
    finally:
        session.close()

def get_user_currency(user_id: int) -> str:
    """Get user's preferred currency"""
    session = SessionLocal()
    try:
        user = session.query(User).filter(User.id == user_id).first()
        return user.preferred_currency if user else 'USD'
    except Exception as e:
        print(f"Error getting user currency: {e}")
        return 'USD'
    finally:
        session.close()

def get_user_native_currency_preference(user_id: int) -> bool:
    """Get user's preference for using native currency"""
    session = SessionLocal()
    try:
        user = session.query(User).filter(User.id == user_id).first()
        return user.use_native_currency if user else False
    except Exception as e:
        print(f"Error getting native currency preference: {e}")
        return False
    finally:
        session.close()

def set_user_currency(user_id: int, currency: str) -> bool:
    """Set user's preferred currency"""
    session = SessionLocal()
    try:
        user = session.query(User).filter(User.id == user_id).first()
        if user:
            user.preferred_currency = currency
            session.commit()
            return True
        return False
    except Exception as e:
        print(f"Error setting user currency: {e}")
        session.rollback()
        return False
    finally:
        session.close()

def save_prediction(ticker: str, signal: str, current_price: float, predicted_direction: str, days_forward: int = 10) -> int:
    """Save a prediction to track accuracy later"""
    session = SessionLocal()
    try:
        prediction = PredictionHistory(
            ticker=ticker,
            signal=signal,
            current_price=current_price,
            predicted_direction=predicted_direction,
            prediction_date=datetime.utcnow(),
            target_date=datetime.utcnow() + timedelta(days=days_forward)
        )
        session.add(prediction)
        session.commit()
        return prediction.id
    except Exception as e:
        print(f"Error saving prediction: {e}")
        session.rollback()
        return None
    finally:
        session.close()

def get_prediction_history(ticker: str, limit: int = 50) -> List[Dict]:
    """Get prediction history for a ticker"""
    session = SessionLocal()
    try:
        predictions = session.query(PredictionHistory).filter(
            PredictionHistory.ticker == ticker
        ).order_by(PredictionHistory.prediction_date.desc()).limit(limit).all()
        
        return [{
            'id': p.id,
            'ticker': p.ticker,
            'signal': p.signal,
            'current_price': p.current_price,
            'predicted_direction': p.predicted_direction,
            'prediction_date': p.prediction_date.isoformat() if p.prediction_date else None,
            'target_date': p.target_date.isoformat() if p.target_date else None,
            'actual_price': p.actual_price,
            'accuracy_percent': p.accuracy_percent,
            'is_correct': p.is_correct
        } for p in predictions]
    except Exception as e:
        print(f"Error getting prediction history: {e}")
        return []
    finally:
        session.close()

def update_prediction_accuracy(prediction_id: int, actual_price: float) -> bool:
    """Update a prediction with actual price and calculate accuracy"""
    session = SessionLocal()
    try:
        prediction = session.query(PredictionHistory).filter(PredictionHistory.id == prediction_id).first()
        if not prediction:
            return False
        
        prediction.actual_price = actual_price
        
        # Calculate if direction was correct
        price_change = actual_price - prediction.current_price
        actual_direction = 'up' if price_change > 0.01 else 'down' if price_change < -0.01 else 'flat'
        prediction.is_correct = (actual_direction == prediction.predicted_direction)
        
        # Calculate accuracy percentage (0-100% based on how close the magnitude was)
        if prediction.current_price > 0:
            predicted_change = 0.002 * 10 if prediction.predicted_direction == 'up' else -0.002 * 10 if prediction.predicted_direction == 'down' else 0
            predicted_price = prediction.current_price * (1 + predicted_change)
            if predicted_price > 0:
                error_ratio = abs(actual_price - predicted_price) / predicted_price
                prediction.accuracy_percent = max(0, 100 - (error_ratio * 100))
        
        session.commit()
        return True
    except Exception as e:
        print(f"Error updating prediction accuracy: {e}")
        session.rollback()
        return False
    finally:
        session.close()

def get_predictions_due_for_check() -> List[Dict]:
    """Get predictions that have reached their target date but don't have actual prices"""
    session = SessionLocal()
    try:
        predictions = session.query(PredictionHistory).filter(
            PredictionHistory.target_date <= datetime.utcnow(),
            PredictionHistory.actual_price.is_(None)
        ).all()
        
        return [{
            'id': p.id,
            'ticker': p.ticker,
            'target_date': p.target_date.isoformat() if p.target_date else None
        } for p in predictions]
    except Exception as e:
        print(f"Error getting due predictions: {e}")
        return []

def get_prediction_accuracy_statistics() -> Dict:
    """Get overall prediction accuracy statistics"""
    session = SessionLocal()
    try:
        from sqlalchemy import func
        
        # Get all predictions that have been checked (have actual price)
        checked_predictions = session.query(PredictionHistory).filter(
            PredictionHistory.actual_price.isnot(None)
        ).all()
        
        total_checked = len(checked_predictions)
        
        if total_checked == 0:
            return {
                'total_predictions': 0,
                'checked_predictions': 0,
                'correct_direction_count': 0,
                'direction_accuracy': 0.0,
                'average_accuracy_percent': 0.0,
                'by_ticker': []
            }
        
        # Count correct direction predictions
        correct_direction = sum(1 for p in checked_predictions if p.is_correct)
        direction_accuracy = (correct_direction / total_checked) * 100
        
        # Calculate average accuracy percent
        accuracy_percents = [p.accuracy_percent for p in checked_predictions if p.accuracy_percent is not None]
        avg_accuracy = sum(accuracy_percents) / len(accuracy_percents) if accuracy_percents else 0.0
        
        # Get statistics by ticker
        ticker_stats = session.query(
            PredictionHistory.ticker,
            func.count(PredictionHistory.id).label('total'),
            func.sum(func.cast(PredictionHistory.is_correct, Integer)).label('correct')
        ).filter(
            PredictionHistory.actual_price.isnot(None)
        ).group_by(PredictionHistory.ticker).all()
        
        by_ticker = []
        for ticker, total, correct in ticker_stats:
            ticker_accuracy = (correct / total * 100) if total > 0 else 0.0
            by_ticker.append({
                'ticker': ticker,
                'total_predictions': total,
                'correct_predictions': correct,
                'accuracy_percent': ticker_accuracy
            })
        
        # Sort by accuracy descending
        by_ticker.sort(key=lambda x: x['accuracy_percent'], reverse=True)
        
        return {
            'total_predictions': session.query(PredictionHistory).count(),
            'checked_predictions': total_checked,
            'correct_direction_count': correct_direction,
            'direction_accuracy': round(direction_accuracy, 2),
            'average_accuracy_percent': round(avg_accuracy, 2),
            'by_ticker': by_ticker
        }
    except Exception as e:
        print(f"Error getting prediction accuracy statistics: {e}")
        return {
            'total_predictions': 0,
            'checked_predictions': 0,
            'correct_direction_count': 0,
            'direction_accuracy': 0.0,
            'average_accuracy_percent': 0.0,
            'by_ticker': []
        }
    finally:
        session.close()

def create_verification_token(email: str, token_type: str = 'email_verification', hours_valid: int = 24) -> str:
    """Create a verification token for email verification or password reset"""
    import secrets
    session = SessionLocal()
    try:
        # Generate secure random token
        token = secrets.token_urlsafe(32)
        
        # Set expiration
        expires_at = datetime.utcnow() + timedelta(hours=hours_valid)
        
        # Create token record
        verification_token = VerificationToken(
            email=email,
            token=token,
            token_type=token_type,
            expires_at=expires_at
        )
        
        session.add(verification_token)
        session.commit()
        
        return token
    except Exception as e:
        print(f"Error creating verification token: {e}")
        session.rollback()
        return None
    finally:
        session.close()

def verify_token(token: str, token_type: str) -> Optional[str]:
    """Verify a token and return the email if valid"""
    session = SessionLocal()
    try:
        verification_token = session.query(VerificationToken).filter(
            VerificationToken.token == token,
            VerificationToken.token_type == token_type,
            VerificationToken.used == False,
            VerificationToken.expires_at > datetime.utcnow()
        ).first()
        
        if verification_token:
            # Mark as used
            verification_token.used = True
            session.commit()
            return verification_token.email
        else:
            return None
    except Exception as e:
        print(f"Error verifying token: {e}")
        return None
    finally:
        session.close()

def mark_user_verified(email: str) -> bool:
    """Mark a user's email as verified"""
    session = SessionLocal()
    try:
        user = session.query(User).filter(User.email == email).first()
        if user:
            user.is_verified = True
            session.commit()
            return True
        return False
    except Exception as e:
        print(f"Error marking user as verified: {e}")
        session.rollback()
        return False
    finally:
        session.close()

def update_user_password(email: str, new_password_hash: str) -> bool:
    """Update a user's password"""
    session = SessionLocal()
    try:
        user = session.query(User).filter(User.email == email).first()
        if user:
            user.password_hash = new_password_hash
            session.commit()
            return True
        return False
    except Exception as e:
        print(f"Error updating user password: {e}")
        session.rollback()
        return False
    finally:
        session.close()

def update_user_profile(user_id: int, first_name: Optional[str] = None, last_name: Optional[str] = None, use_native_currency: Optional[bool] = None) -> bool:
    """Update user profile information"""
    session = SessionLocal()
    try:
        user = session.query(User).filter(User.id == user_id).first()
        if not user:
            return False
        
        if first_name is not None:
            user.first_name = first_name
        if last_name is not None:
            user.last_name = last_name
        if use_native_currency is not None:
            user.use_native_currency = use_native_currency
        
        session.commit()
        return True
    except Exception as e:
        print(f"Error updating user profile: {e}")
        session.rollback()
        return False
    finally:
        session.close()

def get_user_by_email(email: str) -> Optional[Dict]:
    """Get user by email"""
    session = SessionLocal()
    try:
        user = session.query(User).filter(User.email == email).first()
        if user:
            return {
                'id': user.id,
                'email': user.email,
                'is_verified': user.is_verified
            }
        return None
    except Exception as e:
        print(f"Error getting user by email: {e}")
        return None
    finally:
        session.close()

def get_user_by_id(user_id: int) -> Optional[Dict]:
    """Get user by ID"""
    session = SessionLocal()
    try:
        user = session.query(User).filter(User.id == user_id).first()
        if user:
            return {
                'id': user.id,
                'email': user.email,
                'first_name': user.first_name,
                'last_name': user.last_name,
                'is_verified': user.is_verified
            }
        return None
    except Exception as e:
        print(f"Error getting user by ID: {e}")
        return None
    finally:
        session.close()

def send_verification_email(email: str, token: str, token_type: str = 'email_verification') -> bool:
    """Send verification or password reset email using Resend"""
    import os
    from dotenv import load_dotenv
    import resend
    
    load_dotenv()
    
    # Resend API key
    resend_api_key = os.getenv('RESEND_API_KEY', 're_4nVA31fD_DjQbyGaQV9JAFGeVEfEgigk5')
    sender_email = os.getenv('SMTP_USERNAME', 'onboarding@resend.dev')
    
    if not resend_api_key:
        print("Resend API key not configured")
        return False
    
    try:
        resend.api_key = resend_api_key
        
        # Create email content
        if token_type == 'email_verification':
            subject = "Verify your StockSense account"
            verification_url = f"https://stocksense-h0n6.onrender.com/verify-email?token={token}"
            html_content = f"""
            <html>
            <body>
                <h2>Welcome to StockSense!</h2>
                <p>Please verify your email address by clicking the link below:</p>
                <p><a href="{verification_url}">Verify Email</a></p>
                <p>This link will expire in 24 hours.</p>
                <p>If you didn't create an account, you can safely ignore this email.</p>
            </body>
            </html>
            """
        else:  # password_reset
            subject = "Reset your StockSense password"
            reset_url = f"https://stocksense-h0n6.onrender.com/reset-password?token={token}"
            html_content = f"""
            <html>
            <body>
                <h2>Reset your password</h2>
                <p>Click the link below to reset your password:</p>
                <p><a href="{reset_url}">Reset Password</a></p>
                <p>This link will expire in 1 hour.</p>
                <p>If you didn't request a password reset, you can safely ignore this email.</p>
            </body>
            </html>
            """
        
        # Send email via Resend
        print(f"Attempting to send email to {email} via Resend")
        params = {
            "from": sender_email,
            "to": [email],
            "subject": subject,
            "html": html_content,
        }
        
        response = resend.Emails.send(params)
        
        if response.get('id'):
            print(f"Email sent to {email} successfully")
            return True
        else:
            print(f"Resend returned error: {response}")
            return False
    except Exception as e:
        print(f"Error sending email via Resend: {e}")
        return False

def add_to_prediction_watchlist(ticker: str, added_price: float, user_id: int = None) -> bool:
    """Add a stock to the prediction watchlist"""
    session = SessionLocal()
    try:
        # Check if already in prediction watchlist
        existing = session.query(PredictionWatchlist).filter(
            PredictionWatchlist.ticker == ticker,
            PredictionWatchlist.user_id == user_id
        ).first()
        if existing:
            return False
        
        new_item = PredictionWatchlist(
            ticker=ticker,
            added_price=added_price,
            user_id=user_id
        )
        session.add(new_item)
        session.commit()
        return True
    finally:
        session.close()

def get_prediction_watchlist(user_id: int = None) -> List[Dict]:
    """Get prediction watchlist for a user"""
    session = SessionLocal()
    try:
        query = session.query(PredictionWatchlist)
        if user_id:
            query = query.filter(PredictionWatchlist.user_id == user_id)
        items = query.all()
        return [
            {
                'id': item.id,
                'ticker': item.ticker,
                'added_date': item.added_date.isoformat() if item.added_date else None,
                'added_price': item.added_price
            }
            for item in items
        ]
    finally:
        session.close()

def remove_from_prediction_watchlist(ticker: str, user_id: int = None) -> bool:
    """Remove a stock from the prediction watchlist"""
    session = SessionLocal()
    try:
        item = session.query(PredictionWatchlist).filter(
            PredictionWatchlist.ticker == ticker,
            PredictionWatchlist.user_id == user_id
        ).first()
        if item:
            session.delete(item)
            session.commit()
            return True
        return False
    finally:
        session.close()

# Notification functions
def create_notification(user_id: int, notification_type: str, title: str, message: str, 
                        ticker: str = None, target_price: float = None, current_price: float = None) -> bool:
    """Create a notification for a user"""
    session = SessionLocal()
    try:
        notification = Notification(
            user_id=user_id,
            type=notification_type,
            title=title,
            message=message,
            ticker=ticker,
            target_price=target_price,
            current_price=current_price
        )
        session.add(notification)
        session.commit()
        return True
    except Exception as e:
        print(f"Error creating notification: {e}")
        session.rollback()
        return False
    finally:
        session.close()

def get_user_notifications(user_id: int, unread_only: bool = False) -> list:
    """Get notifications for a user"""
    session = SessionLocal()
    try:
        query = session.query(Notification).filter(Notification.user_id == user_id)
        if unread_only:
            query = query.filter(Notification.is_read == False)
        query = query.order_by(Notification.created_at.desc())
        notifications = query.limit(100).all()
        return [
            {
                'id': n.id,
                'type': n.type,
                'title': n.title,
                'message': n.message,
                'is_read': n.is_read,
                'created_at': n.created_at.isoformat() if n.created_at else None,
                'ticker': n.ticker,
                'target_price': n.target_price,
                'current_price': n.current_price
            }
            for n in notifications
        ]
    except Exception as e:
        print(f"Error getting notifications: {e}")
        return []
    finally:
        session.close()

def delete_notification(notification_id: int, user_id: int) -> bool:
    """Delete a notification for a user"""
    session = SessionLocal()
    try:
        notification = session.query(Notification).filter(
            Notification.id == notification_id,
            Notification.user_id == user_id
        ).first()
        if notification:
            session.delete(notification)
            session.commit()
            return True
        return False
    except Exception as e:
        print(f"Error deleting notification: {e}")
        session.rollback()
        return False
    finally:
        session.close()

def mark_notification_read(notification_id: int, user_id: int) -> bool:
    """Mark a notification as read"""
    session = SessionLocal()
    try:
        notification = session.query(Notification).filter(
            Notification.id == notification_id,
            Notification.user_id == user_id
        ).first()
        if notification:
            notification.is_read = True
            session.commit()
            return True
        return False
    except Exception as e:
        print(f"Error marking notification as read: {e}")
        session.rollback()
        return False
    finally:
        session.close()

def mark_all_notifications_read(user_id: int) -> bool:
    """Mark all notifications as read for a user"""
    session = SessionLocal()
    try:
        session.query(Notification).filter(
            Notification.user_id == user_id,
            Notification.is_read == False
        ).update({'is_read': True})
        session.commit()
        return True
    except Exception as e:
        print(f"Error marking all notifications as read: {e}")
        session.rollback()
        return False
    finally:
        session.close()

def get_unread_notification_count(user_id: int) -> int:
    """Get count of unread notifications for a user"""
    session = SessionLocal()
    try:
        count = session.query(Notification).filter(
            Notification.user_id == user_id,
            Notification.is_read == False
        ).count()
        return count
    except Exception as e:
        print(f"Error getting unread notification count: {e}")
        return 0
    finally:
        session.close()

# Notification preference functions
def get_notification_preferences(user_id: int) -> dict:
    """Get notification preferences for a user"""
    session = SessionLocal()
    try:
        pref = session.query(NotificationPreference).filter(NotificationPreference.user_id == user_id).first()
        if pref:
            return {
                'stock_alerts_enabled': pref.stock_alerts_enabled,
                'watchlist_updates_enabled': pref.watchlist_updates_enabled,
                'budget_alerts_enabled': pref.budget_alerts_enabled,
                'admin_announcements_enabled': pref.admin_announcements_enabled,
                'email_notifications_enabled': pref.email_notifications_enabled
            }
        # Create default preferences if not exist
        default_pref = NotificationPreference(user_id=user_id)
        session.add(default_pref)
        session.commit()
        return {
            'stock_alerts_enabled': True,
            'watchlist_updates_enabled': True,
            'budget_alerts_enabled': True,
            'admin_announcements_enabled': True,
            'email_notifications_enabled': False
        }
    except Exception as e:
        print(f"Error getting notification preferences: {e}")
        return None
    finally:
        session.close()

def update_notification_preferences(user_id: int, preferences: dict) -> bool:
    """Update notification preferences for a user"""
    session = SessionLocal()
    try:
        pref = session.query(NotificationPreference).filter(NotificationPreference.user_id == user_id).first()
        if not pref:
            pref = NotificationPreference(user_id=user_id)
            session.add(pref)
        
        if 'stock_alerts_enabled' in preferences:
            pref.stock_alerts_enabled = preferences['stock_alerts_enabled']
        if 'watchlist_updates_enabled' in preferences:
            pref.watchlist_updates_enabled = preferences['watchlist_updates_enabled']
        if 'budget_alerts_enabled' in preferences:
            pref.budget_alerts_enabled = preferences['budget_alerts_enabled']
        if 'admin_announcements_enabled' in preferences:
            pref.admin_announcements_enabled = preferences['admin_announcements_enabled']
        if 'email_notifications_enabled' in preferences:
            pref.email_notifications_enabled = preferences['email_notifications_enabled']
        
        session.commit()
        return True
    except Exception as e:
        print(f"Error updating notification preferences: {e}")
        session.rollback()
        return False
    finally:
        session.close()

# Stock price alert functions
def create_stock_price_alert(user_id: int, ticker: str, target_price: float, condition: str) -> bool:
    """Create a stock price alert for a user"""
    session = SessionLocal()
    try:
        alert = StockPriceAlert(
            user_id=user_id,
            ticker=ticker.upper(),
            target_price=target_price,
            condition=condition.lower()  # 'above' or 'below'
        )
        session.add(alert)
        session.commit()
        
        # Create notification to confirm alert was set
        condition_text = condition.lower()
        create_notification(
            user_id=user_id,
            notification_type='stock_alert',
            title=f'Price Alert Set: {ticker.upper()}',
            message=f'Alert set for {ticker.upper()} when price goes {condition_text} ${target_price:.2f}',
            ticker=ticker.upper(),
            target_price=target_price
        )
        
        return True
    except Exception as e:
        print(f"Error creating stock price alert: {e}")
        session.rollback()
        return False
    finally:
        session.close()

def get_user_stock_alerts(user_id: int) -> list:
    """Get all stock price alerts for a user"""
    session = SessionLocal()
    try:
        alerts = session.query(StockPriceAlert).filter(
            StockPriceAlert.user_id == user_id
        ).order_by(StockPriceAlert.created_at.desc()).all()
        return [
            {
                'id': a.id,
                'ticker': a.ticker,
                'target_price': a.target_price,
                'condition': a.condition,
                'is_active': a.is_active,
                'is_triggered': a.is_triggered,
                'created_at': a.created_at.isoformat() if a.created_at else None,
                'triggered_at': a.triggered_at.isoformat() if a.triggered_at else None
            }
            for a in alerts
        ]
    except Exception as e:
        print(f"Error getting stock alerts: {e}")
        return []
    finally:
        session.close()

def delete_stock_alert(alert_id: int, user_id: int) -> bool:
    """Delete a stock price alert"""
    session = SessionLocal()
    try:
        alert = session.query(StockPriceAlert).filter(
            StockPriceAlert.id == alert_id,
            StockPriceAlert.user_id == user_id
        ).first()
        if alert:
            session.delete(alert)
            session.commit()
            return True
        return False
    except Exception as e:
        print(f"Error deleting stock alert: {e}")
        session.rollback()
        return False
    finally:
        session.close()

def check_and_trigger_price_alerts() -> int:
    """Check all active price alerts and trigger if condition is met"""
    import signals
    session = SessionLocal()
    triggered_count = 0
    
    try:
        # Get all active, untriggered alerts
        alerts = session.query(StockPriceAlert).filter(
            StockPriceAlert.is_active == True,
            StockPriceAlert.is_triggered == False
        ).all()
        
        for alert in alerts:
            try:
                # Get current stock price
                stock_info = signals.get_stock_info_finnhub(alert.ticker)
                if not stock_info or 'current_price' not in stock_info:
                    continue
                
                current_price = stock_info['current_price']
                triggered = False
                
                # Check condition
                if alert.condition == 'above' and current_price >= alert.target_price:
                    triggered = True
                elif alert.condition == 'below' and current_price <= alert.target_price:
                    triggered = True
                
                if triggered:
                    # Mark alert as triggered
                    alert.is_triggered = True
                    alert.triggered_at = datetime.utcnow()
                    
                    # Create notification for user
                    create_notification(
                        user_id=alert.user_id,
                        notification_type='stock_alert',
                        title=f'Price Alert: {alert.ticker}',
                        message=f'{alert.ticker} is now ${current_price:.2f} (target: ${alert.target_price:.2f})',
                        ticker=alert.ticker,
                        target_price=alert.target_price,
                        current_price=current_price
                    )
                    
                    triggered_count += 1
            except Exception as e:
                print(f"Error checking alert {alert.id}: {e}")
                continue
        
        session.commit()
        return triggered_count
    except Exception as e:
        print(f"Error checking price alerts: {e}")
        session.rollback()
        return 0
    finally:
        session.close()
