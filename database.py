import os
from typing import List, Dict, Optional
from sqlalchemy import create_engine, Column, Integer, String, Float, DateTime, ForeignKey, text, Boolean
from sqlalchemy.ext.declarative import declarative_base
from sqlalchemy.orm import sessionmaker, relationship
from datetime import datetime, timedelta
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
    preferred_currency = Column(String, default='USD')  # User's preferred currency
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

class PredictionHistory(Base):
    __tablename__ = 'prediction_history'
    id = Column(Integer, primary_key=True)
    ticker = Column(String, nullable=False, index=True)
    signal = Column(String, nullable=False)  # BUY, SELL, HOLD
    current_price = Column(Float, nullable=False)  # Price when prediction made
    predicted_direction = Column(String, nullable=False)  # up, down, flat
    prediction_date = Column(DateTime, default=datetime.utcnow)
    target_date = Column(DateTime, nullable=False)  # 30 days forward
    actual_price = Column(Float, nullable=True)  # Filled in later
    accuracy_percent = Column(Float, nullable=True)  # Calculated when target_date reached
    is_correct = Column(Boolean, nullable=True)  # True if direction matched

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
        
        # Create verification_tokens table if it doesn't exist
        if 'verification_tokens' not in inspector.get_table_names():
            VerificationToken.__table__.create(bind=engine)
            print("verification_tokens table created")
        
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
                'is_verified': user.is_verified,
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
            query = query.filter(
                (PersonalWatchlist.user_id == user_id) | (PersonalWatchlist.user_id.is_(None))
            )
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

def save_prediction(ticker: str, signal: str, current_price: float, predicted_direction: str, days_forward: int = 30) -> int:
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
            predicted_change = 0.002 * 30 if prediction.predicted_direction == 'up' else -0.002 * 30 if prediction.predicted_direction == 'down' else 0
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

def send_verification_email(email: str, token: str, token_type: str = 'email_verification') -> bool:
    """Send verification or password reset email using SendGrid"""
    import os
    from dotenv import load_dotenv
    from sendgrid import SendGridAPIClient
    from sendgrid.helpers.mail import Mail
    
    load_dotenv()
    
    # SendGrid API key
    sendgrid_api_key = os.getenv('SENDGRID_API_KEY')
    sender_email = os.getenv('SMTP_USERNAME', 'noreply@stocksense.app')
    
    if not sendgrid_api_key:
        print("SendGrid API key not configured")
        return False
    
    try:
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
        
        # Create SendGrid message
        message = Mail(
            from_email=sender_email,
            to_emails=email,
            subject=subject,
            html_content=html_content
        )
        
        # Send email
        print(f"Attempting to send email to {email} via SendGrid")
        sg = SendGridAPIClient(sendgrid_api_key)
        response = sg.send(message)
        
        if response.status_code in [200, 202]:
            print(f"Email sent to {email} successfully")
            return True
        else:
            print(f"SendGrid returned status code: {response.status_code}")
            print(f"Response body: {response.body}")
            return False
    except Exception as e:
        print(f"Error sending email via SendGrid: {e}")
        return False
