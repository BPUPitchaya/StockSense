from fastapi import FastAPI, HTTPException, Depends, Header, Request
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import JSONResponse
from fastapi.middleware.httpsredirect import HTTPSRedirectMiddleware
from fastapi.middleware.trustedhost import TrustedHostMiddleware
from pydantic import BaseModel, Field
from typing import Dict, Any, List, Optional
import database
import signals
from datetime import datetime, timedelta
import time
import jwt
import os
import json
import numpy as np
import threading
from concurrent.futures import ThreadPoolExecutor
from slowapi import Limiter, _rate_limit_exceeded_handler
from slowapi.util import get_remote_address
from slowapi.errors import RateLimitExceeded

class NumpySafeEncoder(json.JSONEncoder):
    def default(self, obj):
        if isinstance(obj, np.integer):
            return int(obj)
        if isinstance(obj, np.floating):
            return float(obj)
        if isinstance(obj, np.bool_):
            return bool(obj)
        if isinstance(obj, np.ndarray):
            return obj.tolist()
        return super().default(obj)

def clean_for_json(data):
    """Strip numpy types by round-tripping through JSON"""
    return json.loads(json.dumps(data, cls=NumpySafeEncoder))

def signal_to_prediction(signal_data):
    """Convert signal data to prediction format Flutter expects"""
    signal = signal_data.get('signal', 'HOLD')
    percent_change = signal_data.get('percent_change', 0) or 0
    
    # Map signal to prediction text (calculate_signal_score returns Title Case)
    prediction_map = {
        'Strong Buy': 'STRONG BUY',
        'Buy': 'BUY',
        'Hold': 'HOLD',
        'Sell': 'SELL',
        'Strong Sell': 'STRONG SELL'
    }
    prediction = prediction_map.get(signal, 'HOLD')
    
    # Calculate confidence based on percent change magnitude
    abs_change = abs(percent_change)
    if abs_change >= 3:
        confidence = 85
    elif abs_change >= 2:
        confidence = 70
    elif abs_change >= 1:
        confidence = 55
    else:
        confidence = 50
    
    # Determine trend strength
    if abs_change >= 2.5:
        trend_strength = 'strong'
    elif abs_change >= 1:
        trend_strength = 'moderate'
    else:
        trend_strength = 'weak'
    
    # Build factors list
    factors = []
    if percent_change > 0:
        factors.append(f'Up {percent_change:.1f}% today')
        factors.append('Positive momentum')
    elif percent_change < 0:
        factors.append(f'Down {abs(percent_change):.1f}% today')
        factors.append('Negative momentum')
    else:
        factors.append('Neutral price action')
    
    factors.append(f'Signal: {signal}')
    
    return {
        'ticker': signal_data.get('ticker'),
        'name': signal_data.get('name'),
        'current_price': signal_data.get('current_price', 0),
        'prediction': prediction,
        'confidence': confidence,
        'score': percent_change,  # Use percent_change as score
        'potential_change': percent_change,
        'trend_strength': trend_strength,
        'factors': factors,
        'signal': signal,
        'percent_change': percent_change,
        'date': signal_data.get('date', datetime.now().isoformat())
    }

def convert_signals_to_predictions(signals_list):
    """Convert list of signals to predictions format"""
    return [signal_to_prediction(s) for s in signals_list]

app = FastAPI()

# Initialize rate limiter
limiter = Limiter(key_func=get_remote_address)
app.state.limiter = limiter
app.add_exception_handler(RateLimitExceeded, _rate_limit_exceeded_handler)

# Security middleware
# HTTPS redirect (only in production)
if os.getenv("ENVIRONMENT") == "production":
    app.add_middleware(HTTPSRedirectMiddleware)

# Trusted host middleware (prevent host header attacks)
app.add_middleware(
    TrustedHostMiddleware,
    allowed_hosts=["stocksense-h0n6.onrender.com", "localhost", "127.0.0.1"]
)

# Configure CORS
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# Security headers middleware
@app.middleware("http")
async def add_security_headers(request, call_next):
    response = await call_next(request)
    response.headers["X-Content-Type-Options"] = "nosniff"
    response.headers["X-Frame-Options"] = "DENY"
    response.headers["X-XSS-Protection"] = "1; mode=block"
    response.headers["Referrer-Policy"] = "strict-origin-when-cross-origin"
    response.headers["Permissions-Policy"] = "geolocation=(), microphone=(), camera=()"
    return response

# JWT Secret
JWT_SECRET = os.getenv("JWT_SECRET", "your-secret-key-change-this")
JWT_ALGORITHM = "HS256"

def create_jwt_token(data: dict) -> str:
    """Create a JWT token"""
    to_encode = data.copy()
    expire = datetime.utcnow() + timedelta(days=7)
    to_encode.update({"exp": expire})
    encoded_jwt = jwt.encode(to_encode, JWT_SECRET, algorithm=JWT_ALGORITHM)
    return encoded_jwt

def verify_jwt_token(authorization: str = Header(...)) -> dict:
    """Verify JWT token and return payload"""
    try:
        token = authorization.replace("Bearer ", "")
        payload = jwt.decode(token, JWT_SECRET, algorithms=[JWT_ALGORITHM])
        return payload
    except jwt.ExpiredSignatureError:
        raise HTTPException(status_code=401, detail="Token expired")
    except jwt.InvalidTokenError:
        raise HTTPException(status_code=401, detail="Invalid token")

# Pydantic models
class SignupRequest(BaseModel):
    email: str
    password: str
    first_name: str = None
    last_name: str = None

class LoginRequest(BaseModel):
    email: str
    password: str

class ProfileUpdateRequest(BaseModel):
    first_name: Optional[str] = None
    last_name: Optional[str] = None

class Position(BaseModel):
    ticker: str
    buy_price: float
    quantity: float
    date: Optional[str] = None

class WatchlistRequest(BaseModel):
    ticker: str

class Signal(BaseModel):
    ticker: str
    current_price: float
    ma50: Optional[float] = Field(default=None)
    ma200: Optional[float] = Field(default=None)
    rsi: Optional[float] = Field(default=None)
    signal: str
    date: str
    name: Optional[str] = Field(default=None)  # Company full name

# Simple in-memory cache with stale-while-revalidate
_cache: Dict[str, tuple] = {}
CACHE_DURATION = 600  # 10 minutes - data considered fresh
STALE_DURATION = 1800  # 30 minutes - stale but usable data
_refresh_executor = ThreadPoolExecutor(max_workers=2)

def get_cache_key(prefix: str, **kwargs) -> str:
    """Generate a cache key"""
    key_parts = [prefix]
    for k, v in sorted(kwargs.items()):
        key_parts.append(f"{k}={v}")
    return ":".join(key_parts)

def get_from_cache(key: str, allow_stale: bool = False, custom_duration: Optional[int] = None) -> tuple[Optional[Any], bool]:
    """
    Get data from cache.
    Returns: (data, is_fresh) - is_fresh is False if stale but usable
    """
    if key in _cache:
        data, timestamp = _cache[key]
        age = time.time() - timestamp
        duration = custom_duration if custom_duration is not None else CACHE_DURATION
        
        if age < duration:
            return data, True  # Fresh
        elif allow_stale and age < STALE_DURATION:
            return data, False  # Stale but usable
        else:
            del _cache[key]
    return None, False

def set_cache(key: str, data: Any) -> None:
    """Set data in cache"""
    _cache[key] = (data, time.time())

def refresh_cache_async(key: str, refresh_func, *args, **kwargs):
    """Refresh cache in background"""
    def _refresh():
        try:
            new_data = refresh_func(*args, **kwargs)
            if new_data:
                set_cache(key, clean_for_json(new_data))
                print(f"Background refresh completed for {key}")
        except Exception as e:
            print(f"Background refresh failed for {key}: {e}")
    
    _refresh_executor.submit(_refresh)

@app.on_event("startup")
def startup_event():
    """Initialize database and clear cache - cache warms on first request"""
    _cache.clear()  # Clear cache on startup to ensure fresh data
    database.init_db()
    print("Database initialized, ready for requests")
    
    # Check and update prediction accuracy for due predictions
    try:
        due_predictions = database.get_predictions_due_for_check()
        if due_predictions:
            print(f"Checking accuracy for {len(due_predictions)} due predictions...")
            for pred in due_predictions:
                try:
                    ticker = pred['ticker']
                    stock_info = signals.get_stock_info_finnhub(ticker)
                    if stock_info and stock_info.get('current_price'):
                        database.update_prediction_accuracy(pred['id'], stock_info['current_price'])
                        print(f"  Updated accuracy for {ticker}: ${stock_info['current_price']}")
                except Exception as e:
                    print(f"  Error checking {pred.get('ticker')}: {e}")
    except Exception as e:
        print(f"Error checking prediction accuracy: {e}")

@app.get("/")
def read_root():
    return {"message": "StockSense API is running"}

@app.get("/health")
def health_check():
    """Health check endpoint for monitoring"""
    try:
        # Check database connection
        session = SessionLocal()
        session.execute("SELECT 1")
        session.close()
        
        return {
            "status": "healthy",
            "database": "connected",
            "timestamp": datetime.utcnow().isoformat()
        }
    except Exception as e:
        return {
            "status": "unhealthy",
            "database": "disconnected",
            "error": str(e),
            "timestamp": datetime.utcnow().isoformat()
        }

@app.post("/signup")
@limiter.limit("5/minute")
def signup(request: Request, signup_request: SignupRequest):
    """User signup endpoint - email verification temporarily disabled"""
    try:
        # Password validation
        password = signup_request.password
        if len(password) < 8:
            raise HTTPException(status_code=400, detail="Password must be at least 8 characters long")
        if not any(c.isupper() for c in password):
            raise HTTPException(status_code=400, detail="Password must contain at least one uppercase letter")
        if not any(c.islower() for c in password):
            raise HTTPException(status_code=400, detail="Password must contain at least one lowercase letter")
        if not any(c.isdigit() for c in password):
            raise HTTPException(status_code=400, detail="Password must contain at least one digit")
        
        success = database.create_user(
            request.email, 
            request.password,
            request.first_name,
            request.last_name
        )
        if success:
            return {"message": "User created successfully. You can now log in."}
        else:
            raise HTTPException(status_code=400, detail="An account with this email already exists. Please try logging in or use a different email.")
    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))

@app.post("/login")
@limiter.limit("10/minute")
def login(request: Request, login_request: LoginRequest):
    """User login endpoint - email verification check temporarily disabled"""
    try:
        user = database.verify_user(login_request.email, login_request.password)
        if user:
            # Email verification check temporarily disabled
            token = create_jwt_token({"sub": user['email'], "user_id": user['id']})
            return {
                "access_token": token,
                "token_type": "bearer",
                "user": user
            }
        else:
            raise HTTPException(status_code=401, detail="Invalid email or password. Please check your credentials and try again.")
    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))

@app.post("/admin/login")
@limiter.limit("10/minute")
def admin_login(request: Request, login_request: LoginRequest):
    """Admin login endpoint"""
    try:
        if database.verify_admin(login_request.email, login_request.password):
            return {"message": "Admin login successful", "email": login_request.email}
        else:
            raise HTTPException(status_code=401, detail="Invalid admin credentials. Please check your email and password.")
    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))

@app.get("/verify-email")
def verify_email(token: str):
    """Verify email with token"""
    try:
        email = database.verify_token(token, 'email_verification')
        if email:
            success = database.mark_user_verified(email)
            if success:
                return {"message": "Email verified successfully. You can now log in."}
            else:
                raise HTTPException(status_code=500, detail="Failed to mark user as verified")
        else:
            raise HTTPException(status_code=400, detail="Invalid or expired token")
    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))

@app.post("/forgot-password")
def forgot_password(request: dict):
    """Send password reset email"""
    try:
        email = request.get('email')
        if not email:
            raise HTTPException(status_code=400, detail="Email is required")
        
        # Check if user exists
        user = database.get_user_by_email(email)
        if not user:
            # Don't reveal if user exists for security
            return {"message": "If an account exists with this email, a password reset link has been sent."}
        
        # Create reset token (1 hour expiry)
        token = database.create_verification_token(email, 'password_reset', 1)
        if token:
            # Send reset email
            email_sent = database.send_verification_email(email, token, 'password_reset')
            if email_sent:
                return {"message": "Password reset email sent successfully."}
            else:
                return {"message": "Password reset email failed (SMTP not configured)."}
        else:
            raise HTTPException(status_code=500, detail="Failed to generate reset token")
    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))

@app.post("/reset-password")
def reset_password(request: dict):
    """Reset password with token"""
    try:
        token = request.get('token')
        new_password = request.get('new_password')
        
        if not token or not new_password:
            raise HTTPException(status_code=400, detail="Token and new password are required")
        
        # Verify token
        email = database.verify_token(token, 'password_reset')
        if not email:
            raise HTTPException(status_code=400, detail="Invalid or expired token")
        
        # Hash new password
        password_hash = hashlib.sha256(new_password.encode()).hexdigest()
        
        # Update password
        success = database.update_user_password(email, password_hash)
        if success:
            return {"message": "Password reset successfully. You can now log in with your new password."}
        else:
            raise HTTPException(status_code=500, detail="Failed to update password")
    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))

@app.get("/admin/users")
def get_all_users():
    """Get all users (admin only)"""
    try:
        return database.get_all_users()
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))

@app.get("/admin/users/{user_id}")
@limiter.limit("30/minute")
def get_user_profile(request: Request, user_id: int):
    """Get detailed user profile (admin only)"""
    try:
        profile = database.get_user_profile(user_id)
        if profile:
            return profile
        else:
            raise HTTPException(status_code=404, detail="User not found")
    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))

@app.post("/admin/users/{user_id}/reset-password")
@limiter.limit("10/minute")
def reset_user_password(request: Request, user_id: int, password_request: dict):
    """Reset user password (admin only)"""
    try:
        new_password = password_request.get("new_password")
        if not new_password:
            raise HTTPException(status_code=400, detail="new_password is required")
        
        # Password validation
        if len(new_password) < 8:
            raise HTTPException(status_code=400, detail="Password must be at least 8 characters long")
        if not any(c.isupper() for c in new_password):
            raise HTTPException(status_code=400, detail="Password must contain at least one uppercase letter")
        if not any(c.islower() for c in new_password):
            raise HTTPException(status_code=400, detail="Password must contain at least one lowercase letter")
        if not any(c.isdigit() for c in new_password):
            raise HTTPException(status_code=400, detail="Password must contain at least one digit")
        
        success = database.reset_user_password(user_id, new_password)
        if success:
            return {"message": "Password reset successfully"}
        else:
            raise HTTPException(status_code=404, detail="User not found")
    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))

@app.delete("/admin/users/{user_id}")
@limiter.limit("10/minute")
def delete_user(request: Request, user_id: int):
    """Delete a user (admin only)"""
    try:
        success = database.delete_user(user_id)
        if success:
            return {"message": "User deleted successfully"}
        else:
            raise HTTPException(status_code=404, detail="User not found")
    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))

@app.delete("/admin/cache/predictions/{user_id}")
def clear_prediction_cache(user_id: int):
    """Clear prediction cache for a specific user"""
    keys_removed = [k for k in list(_cache.keys()) if f"predictions_{user_id}" in k]
    for k in keys_removed:
        del _cache[k]
    return {"message": f"Cleared {len(keys_removed)} cache entries for user {user_id}"}

@app.delete("/admin/users/{email}/watchlist")
def clear_user_watchlist(email: str):
    """Clear all watchlist entries for a user by email (admin only)"""
    try:
        result = database.clear_watchlist_by_email(email)
        return {"message": f"Cleared watchlist for {email}", "removed": result}
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))

@app.get("/admin/statistics")
def get_admin_statistics():
    """Get admin dashboard statistics"""
    try:
        user_stats = database.get_user_statistics()
        popular_stocks = database.get_popular_stocks()
        portfolio_stats = database.get_total_portfolio_value()
        recent_signups = database.get_recent_signups()
        system_info = database.get_system_info()
        
        return {
            "user_statistics": user_stats,
            "popular_stocks": popular_stocks,
            "portfolio_statistics": portfolio_stats,
            "recent_signups": recent_signups,
            "system_info": system_info,
        }
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))

@app.get("/categories")
def get_categories():
    """Get available stock categories"""
    return {"categories": list(signals.CATEGORIES.keys())}

@app.get("/signals")
@limiter.limit("30/minute")
def get_signals(request: Request, category: Optional[str] = None, refresh: bool = False):
    """Get trading signals - instant with stale-while-revalidate"""
    cache_key = get_cache_key("signals_5stocks", category=category or "all")
    
    # Force refresh bypasses cache
    if refresh:
        print("Force refresh requested - bypassing cache")
        max_retries = 3
        for attempt in range(max_retries):
            try:
                all_signals_data = signals.get_all_signals()
                if all_signals_data:
                    print(f"Generated {len(all_signals_data)} signals (force refresh)")
                    clean_data = clean_for_json(all_signals_data)
                    set_cache(cache_key, clean_data)
                    return clean_data
            except Exception as e:
                print(f"Attempt {attempt + 1}/{max_retries} failed: {e}")
                if attempt < max_retries - 1:
                    time.sleep(1)
        raise HTTPException(status_code=503, detail="Stock data temporarily unavailable. Please try again.")
    
    # Use shorter cache during premarket hours (1 minute vs 10 minutes)
    is_premarket = signals.is_premarket_hours()
    current_cache_duration = 60 if is_premarket else CACHE_DURATION
    
    # Try to get from cache (allow stale for instant response)
    cached_data, is_fresh = get_from_cache(cache_key, allow_stale=True, custom_duration=current_cache_duration)
    
    if cached_data:
        if is_fresh:
            print(f"Returning {len(cached_data)} FRESH cached signals (premarket: {is_premarket})")
            return cached_data
        else:
            # Stale data - return immediately, refresh in background
            print(f"Returning {len(cached_data)} STALE signals (refreshing in background)")
            refresh_cache_async(cache_key, signals.get_all_signals)
            return cached_data
    
    # Cold start - fetch fresh with retry
    max_retries = 3
    for attempt in range(max_retries):
        try:
            all_signals_data = signals.get_all_signals()
            if all_signals_data:
                print(f"Generated {len(all_signals_data)} signals (cold start, premarket: {is_premarket})")
                clean_data = clean_for_json(all_signals_data)
                set_cache(cache_key, clean_data)
                return clean_data
        except Exception as e:
            print(f"Attempt {attempt + 1}/{max_retries} failed: {e}")
            if attempt < max_retries - 1:
                time.sleep(1)
    
    # All retries failed
    print(f"All retries failed for signals fetch")
    raise HTTPException(status_code=503, detail="Unable to fetch stock data at this time. The service may be temporarily unavailable. Please try again in a few minutes.")

@app.get("/predictions")
@limiter.limit("30/minute")
def get_predictions(request: Request, category: Optional[str] = None, authorization: str = Header(...)):
    """Get predictions using same fast signals as main page for consistency"""
    try:
        payload = verify_jwt_token(authorization)
        user_id = payload.get("user_id")
        
        # Get user's personal watchlist
        user_watchlist = database.get_personal_watchlist(user_id=user_id)
        if not user_watchlist:
            return {
                'gainers': [],
                'losers': [],
                'all_predictions': [],
                'count': 0,
                'message': 'Your watchlist is empty. Add stocks to see predictions.'
            }
        
        # Use user-specific cache key so each user gets their own predictions
        watchlist_key = ",".join(sorted(user_watchlist))
        cache_key = get_cache_key(f"predictions_{user_id}", watchlist=watchlist_key)
        cached_signals, is_fresh = get_from_cache(cache_key, allow_stale=True)
        
        if cached_signals:
            sorted_signals = sorted(cached_signals, key=lambda x: x.get('percent_change', 0), reverse=True)
            all_predictions = convert_signals_to_predictions(sorted_signals)
            
            # Separate gainers (positive change) and losers (negative change)
            gainers = [p for p in all_predictions if p.get('percent_change', 0) > 0][:3]
            losers = [p for p in all_predictions if p.get('percent_change', 0) < 0][-3:]
            
            predictions = {
                'gainers': gainers,
                'losers': losers,
                'all_predictions': all_predictions,
                'count': len(all_predictions)
            }
            
            if is_fresh:
                print(f"Returning {len(all_predictions)} FRESH predictions for user {user_id}")
                return predictions
            else:
                print(f"Returning {len(all_predictions)} STALE predictions for user {user_id} (refreshing)")
                refresh_cache_async(cache_key, lambda: signals.get_all_signals(watchlist=user_watchlist))
                return predictions
        
        # Cold start - fetch signals for this user's watchlist
        max_retries = 3
        for attempt in range(max_retries):
            try:
                all_signals = signals.get_all_signals(watchlist=user_watchlist)
                if all_signals:
                    clean_signals = clean_for_json(all_signals)
                    set_cache(cache_key, clean_signals)
                    sorted_signals = sorted(clean_signals, key=lambda x: x.get('percent_change', 0), reverse=True)
                    all_predictions = convert_signals_to_predictions(sorted_signals)
                    
                    # Save predictions for accuracy tracking
                    for pred in all_predictions:
                        signal_upper = pred.get('signal', '').upper()
                        direction = 'up' if 'BUY' in signal_upper else 'down' if 'SELL' in signal_upper else 'flat'
                        database.save_prediction(
                            ticker=pred['ticker'],
                            signal=pred['signal'],
                            current_price=pred['current_price'],
                            predicted_direction=direction
                        )
                    
                    predictions = {
                        'gainers': [p for p in all_predictions if p.get('percent_change', 0) > 0][:3],
                        'losers': [p for p in all_predictions if p.get('percent_change', 0) < 0][-3:],
                        'all_predictions': all_predictions,
                        'count': len(all_predictions)
                    }
                    return predictions
            except Exception as e:
                print(f"Predictions attempt {attempt + 1}/{max_retries} failed: {e}")
                if attempt < max_retries - 1:
                    time.sleep(1)
        
        # All retries failed
        raise HTTPException(status_code=503, detail="Unable to generate predictions at this time. The prediction service may be temporarily unavailable. Please try again in a few minutes.")
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))

@app.get("/predictions/history/{ticker}")
@limiter.limit("30/minute")
def get_prediction_history_endpoint(request: Request, ticker: str):
    """Get historical predictions for a ticker to show accuracy"""
    try:
        history = database.get_prediction_history(ticker)
        return {"ticker": ticker, "predictions": history}
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))

@app.post("/predictions/save")
def save_prediction_endpoint(request: dict):
    """Save a prediction for accuracy tracking"""
    try:
        ticker = request.get('ticker')
        signal = request.get('signal')
        current_price = request.get('current_price')
        predicted_direction = request.get('predicted_direction', 'flat')
        
        if not all([ticker, signal, current_price]):
            raise HTTPException(status_code=400, detail="Missing required fields")
        
        prediction_id = database.save_prediction(ticker, signal, current_price, predicted_direction)
        return {"success": True, "prediction_id": prediction_id}
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))

@app.get("/market/status")
def get_market_status_endpoint():
    """Get current US market status and hours"""
    try:
        market_status = signals.get_market_hours()
        return market_status
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))

@app.get("/info/{ticker}")
def get_stock_info_endpoint(ticker: str):
    """Get stock info including technical indicators (MA50, MA200, volume)."""
    try:
        stock_info = signals.get_stock_info_finnhub(ticker)
        if stock_info is None:
            raise HTTPException(status_code=404, detail="Stock not found")
        technicals = signals.get_technical_indicators(ticker)
        stock_info['ma50'] = technicals.get('ma50')
        stock_info['ma200'] = technicals.get('ma200')
        stock_info['volume_ratio'] = technicals.get('volume_ratio')
        return stock_info
    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))

@app.get("/search/{ticker}")
def search_stock(ticker: str):
    """Search/validate a stock ticker"""
    # Route non-US tickers (NZ, AU, futures) through yfinance
    is_regional = ticker.endswith('=F') or ticker.endswith('.NZ') or ticker.endswith('.AX')
    if is_regional:
        try:
            stock_info = signals.get_stock_info(ticker)
            if stock_info:
                # Attach technicals
                technicals = signals.get_technical_indicators(ticker)
                stock_info['ma50'] = technicals.get('ma50')
                stock_info['ma200'] = technicals.get('ma200')
                stock_info['volume_ratio'] = technicals.get('volume_ratio')
                # Label the market
                if ticker.endswith('.NZ'):
                    stock_info.setdefault('description', 'NZX Listed')
                    stock_info['market'] = 'NZX'
                elif ticker.endswith('.AX'):
                    stock_info.setdefault('description', 'ASX Listed')
                    stock_info['market'] = 'ASX'
                return stock_info
        except Exception as e:
            print(f"yfinance failed for {ticker}: {e}")
        raise HTTPException(status_code=404, detail="Ticker not found")
    
    # For US stocks, use Finnhub
    try:
        stock_info = signals.get_stock_info_finnhub(ticker)
        if stock_info:
            technicals = signals.get_technical_indicators(ticker)
            stock_info['ma50'] = technicals.get('ma50')
            stock_info['ma200'] = technicals.get('ma200')
            stock_info['volume_ratio'] = technicals.get('volume_ratio')
            return stock_info
        else:
            raise HTTPException(status_code=404, detail="Stock not found. For NZ stocks use ticker.NZ (e.g. AIR.NZ), for AU use ticker.AX (e.g. CBA.AX)")
    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))

@app.get("/validate-stock/{ticker}")
def validate_stock(ticker: str):
    """Validate a stock ticker"""
    try:
        # NZ / AU / futures go through yfinance
        if ticker.endswith('=F') or ticker.endswith('.NZ') or ticker.endswith('.AX'):
            stock_info = signals.get_stock_info(ticker)
            if stock_info and stock_info.get('current_price'):
                return {"valid": True, "ticker": ticker, "name": stock_info.get('name', ticker), "is_etf": False}
            return {"valid": False, "ticker": ticker}
        stock_info = signals.get_stock_info_finnhub(ticker)
        if stock_info:
            return {"valid": True, "ticker": ticker, "name": stock_info.get('description', ''), "is_etf": False}
        else:
            return {"valid": False, "ticker": ticker}
    except Exception as e:
        return {"valid": False, "ticker": ticker, "error": str(e)}

@app.get("/history/{ticker}")
def get_stock_history(ticker: str, period: str = "3mo"):
    """Get stock history"""
    try:
        history = signals.get_stock_history(ticker, period)
        if history:
            return history
        else:
            raise HTTPException(status_code=404, detail="History not found")
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))

@app.get("/projection/{ticker}")
def get_projection(ticker: str, period: str = "1y"):
    """Get price projection based on technical indicators"""
    try:
        # Get stock analysis with indicators
        analysis = signals.analyze_stock(ticker)
        if not analysis:
            raise HTTPException(status_code=404, detail="Could not analyze stock")
        
        # Get historical data for projection
        history = signals.get_stock_history(ticker, period)
        if not history or len(history) < 5:
            raise HTTPException(status_code=400, detail="Insufficient historical data")
        
        # Extract indicator values
        rsi = analysis.get('rsi', 50)
        macd = analysis.get('macd', {})
        macd_line = macd.get('macd_line', 0)
        macd_signal = macd.get('signal_line', 0)
        macd_above = macd.get('macd_above_signal', False)
        
        adx = analysis.get('adx', {})
        adx_value = adx.get('adx', 20)
        trend_strength = adx.get('trend_strength', 'Weak')
        
        ma50 = analysis.get('ma50', 0)
        ma200 = analysis.get('ma200', 0)
        current_price = analysis.get('current_price', 0)
        
        # Calculate projection strength based on indicators
        score = 0
        
        # RSI factor (oversold < 30 = bullish, overbought > 70 = bearish)
        if rsi < 30:
            score += 2  # Strong buy signal
        elif rsi < 40:
            score += 1  # Buy signal
        elif rsi > 70:
            score -= 3  # Strong sell signal (increased weight)
        elif rsi > 60:
            score -= 2  # Sell signal (increased weight)
        
        # MACD factor
        if macd_above:
            score += 1
        else:
            score -= 2  # Increased weight for bearish MACD
        
        # Trend strength factor
        if trend_strength == 'Strong':
            score *= 1.5
        elif trend_strength == 'Moderate':
            score *= 1.2
        
        # Moving average factor
        if current_price > ma50 > ma200:
            score += 1  # Bullish alignment
        elif current_price < ma50 < ma200:
            score -= 2  # Bearish alignment (increased weight)
        
        # Add slight downward bias (market gravity)
        score -= 0.5
        
        # Calculate daily change percentage based on score
        # Score range typically -7 to +5, map to -0.7% to +0.5% daily
        daily_change = (score / 10) * 0.01  # Max 0.7% daily change down, 0.5% up
        
        # Calculate projection for next 30 days
        projection = []
        last_price = current_price
        
        # Volatility based on recent price range
        prices = [h['close'] for h in history]
        price_range = max(prices) - min(prices)
        volatility = price_range / len(prices) * 0.15
        
        import math
        
        for day in range(1, 31):
            # Add sine wave oscillation for realistic curves
            wave = math.sin(day * 0.5) * volatility * 0.5
            # Add smaller high-frequency noise
            noise = math.sin(day * 2) * volatility * 0.2
            
            # Apply daily change with wave patterns
            projected_price = last_price * (1 + daily_change) + wave + noise
            projection.append({
                'day': day,
                'price': projected_price
            })
            last_price = projected_price
        
        return {
            'ticker': ticker,
            'current_price': current_price,
            'score': score,
            'daily_change_pct': daily_change * 100,
            'projection': projection,
            'indicators': {
                'rsi': rsi,
                'macd_above_signal': macd_above,
                'trend_strength': trend_strength,
                'adx': adx_value
            }
        }
    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))

@app.post("/portfolio")
@limiter.limit("20/minute")
def add_position(request: Request, position: Position, authorization: str = Header(...)):
    """Add a position to portfolio"""
    try:
        payload = verify_jwt_token(authorization)
        user_id = payload.get("user_id")
        
        position_data = position.dict()
        if position.date:
            position_data['date'] = datetime.fromisoformat(position.date)
        else:
            position_data['date'] = datetime.utcnow()
        
        database.add_position(position_data, user_id=user_id)
        return {"message": "Position added successfully"}
    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))

@app.get("/portfolio")
@limiter.limit("30/minute")
def get_portfolio(request: Request, authorization: str = Header(...)):
    """Get portfolio positions"""
    try:
        payload = verify_jwt_token(authorization)
        user_id = payload.get("user_id")
        print(f"Fetching portfolio for user_id: {user_id}")
        positions = database.get_all_positions(user_id=user_id)
        print(f"Found {len(positions)} positions")
        return {"positions": positions}
    except HTTPException:
        raise
    except Exception as e:
        print(f"Portfolio error: {e}")
        raise HTTPException(status_code=500, detail=str(e))

@app.delete("/portfolio/{position_id}")
@limiter.limit("20/minute")
def delete_position(request: Request, position_id: int, authorization: str = Header(...)):
    """Delete a position from portfolio"""
    try:
        payload = verify_jwt_token(authorization)
        user_id = payload.get("user_id")
        
        success = database.delete_position(position_id)
        if success:
            return {"message": "Position deleted successfully"}
        else:
            raise HTTPException(status_code=404, detail="Position not found. It may have been already deleted.")
    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))

@app.post("/watchlist")
@limiter.limit("20/minute")
def add_to_watchlist(request: Request, watchlist_request: WatchlistRequest, authorization: str = Header(...)):
    """Add a stock to personal watchlist (also adds to prediction watchlist for tracking)"""
    try:
        payload = verify_jwt_token(authorization)
        user_id = payload.get("user_id")
        
        current = database.get_personal_watchlist(user_id=user_id)
        if len(current) >= 5:
            raise HTTPException(status_code=400, detail="Watchlist limit reached. You can only track up to 5 stocks at a time. Please remove some stocks from your watchlist first.")
        
        # Get current price for tracking
        try:
            stock_info = signals.get_stock_info_finnhub(watchlist_request.ticker)
            current_price = stock_info.get('current_price') if stock_info else None
            if not current_price:
                raise HTTPException(status_code=400, detail="Could not get current price")
        except:
            raise HTTPException(status_code=400, detail="Could not get current price")
        
        # Add to regular watchlist
        success = database.add_to_watchlist(watchlist_request.ticker, user_id=user_id)
        if not success:
            raise HTTPException(status_code=400, detail="This stock is already in your watchlist.")
        
        # Also add to prediction watchlist for tracking
        database.add_to_prediction_watchlist(watchlist_request.ticker, current_price, user_id=user_id)
        
        return {"message": "Stock added to watchlist"}
    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))

@app.get("/watchlist")
def get_watchlist(authorization: str = Header(...)):
    """Get personal watchlist"""
    try:
        payload = verify_jwt_token(authorization)
        user_id = payload.get("user_id")
        
        watchlist = database.get_personal_watchlist(user_id=user_id)
        return {"watchlist": watchlist}
    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))

@app.delete("/watchlist/{ticker}")
@limiter.limit("20/minute")
def remove_from_watchlist(request: Request, ticker: str, authorization: str = Header(...)):
    """Remove a stock from personal watchlist (also removes from prediction watchlist)"""
    try:
        payload = verify_jwt_token(authorization)
        user_id = payload.get("user_id")
        
        success = database.remove_from_watchlist(ticker, user_id=user_id)
        if success:
            # Also remove from prediction watchlist
            database.remove_from_prediction_watchlist(ticker, user_id=user_id)
            return {"message": "Stock removed from watchlist"}
        else:
            raise HTTPException(status_code=404, detail="Stock not found in your watchlist. It may have been already removed.")
    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))

class PredictionWatchlistRequest(BaseModel):
    ticker: str
    added_price: float

@app.post("/prediction-watchlist")
@limiter.limit("20/minute")
def add_to_prediction_watchlist(request: Request, prediction_request: PredictionWatchlistRequest, authorization: str = Header(...)):
    """Add a stock to prediction watchlist"""
    try:
        payload = verify_jwt_token(authorization)
        user_id = payload.get("user_id")
        
        success = database.add_to_prediction_watchlist(prediction_request.ticker, prediction_request.added_price, user_id=user_id)
        if success:
            return {"message": "Stock added to prediction watchlist"}
        else:
            raise HTTPException(status_code=400, detail="This stock is already in your prediction watchlist.")
    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))

@app.get("/prediction-watchlist")
@limiter.limit("30/minute")
def get_prediction_watchlist(request: Request, authorization: str = Header(...)):
    """Get prediction watchlist with performance tracking"""
    try:
        payload = verify_jwt_token(authorization)
        user_id = payload.get("user_id")
        
        # Get regular watchlist
        regular_watchlist = database.get_personal_watchlist(user_id=user_id)
        
        # Get prediction watchlist
        prediction_watchlist = database.get_prediction_watchlist(user_id=user_id)
        prediction_tickers = {item['ticker'] for item in prediction_watchlist}
        
        # Migrate any stocks in regular watchlist that aren't in prediction watchlist
        for ticker in regular_watchlist:
            if ticker not in prediction_tickers:
                try:
                    stock_info = signals.get_stock_info_finnhub(ticker)
                    current_price = stock_info.get('current_price') if stock_info else None
                    if current_price:
                        database.add_to_prediction_watchlist(ticker, current_price, user_id=user_id)
                except:
                    pass
        
        # Re-fetch prediction watchlist after migration
        watchlist = database.get_prediction_watchlist(user_id=user_id)
        
        # Get current prices and calculate performance
        result = []
        for item in watchlist:
            ticker = item['ticker']
            added_price = item['added_price']
            added_date = item['added_date']
            
            # Get current price
            try:
                stock_info = signals.get_stock_info_finnhub(ticker)
                current_price = stock_info.get('current_price') if stock_info else None
                
                if current_price:
                    percent_change = ((current_price - added_price) / added_price) * 100
                else:
                    percent_change = 0
            except:
                current_price = None
                percent_change = 0
            
            result.append({
                'ticker': ticker,
                'added_date': added_date,
                'added_price': added_price,
                'current_price': current_price,
                'percent_change': percent_change
            })
        
        return {"watchlist": result}
    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))

@app.delete("/prediction-watchlist/{ticker}")
@limiter.limit("20/minute")
def remove_from_prediction_watchlist(request: Request, ticker: str, authorization: str = Header(...)):
    """Remove a stock from prediction watchlist"""
    try:
        payload = verify_jwt_token(authorization)
        user_id = payload.get("user_id")
        
        success = database.remove_from_prediction_watchlist(ticker, user_id=user_id)
        if success:
            return {"message": "Stock removed from prediction watchlist"}
        else:
            raise HTTPException(status_code=404, detail="Stock not found in your prediction watchlist. It may have been already removed.")
    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))

@app.get("/budget")
def get_budget(authorization: str = Header(...)):
    """Get budget"""
    try:
        payload = verify_jwt_token(authorization)
        user_id = payload.get("user_id")
        
        budget = database.get_budget(user_id=user_id)
        return {"budget": budget}
    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))

# Curated stock list for budget recommendations
CURATED_STOCKS = [
    # Major ETFs
    'SPY', 'QQQ', 'VTI', 'VOO', 'IWM', 'GLD', 'TLT',
    # Popular blue-chip stocks
    'AAPL', 'MSFT', 'GOOGL', 'AMZN', 'NVDA', 'META', 'TSLA',
    'BRK.B', 'JPM', 'V', 'JNJ', 'WMT', 'PG', 'MA',
    # Sector ETFs
    'XLK', 'XLF', 'XLV', 'XLE', 'XLI', 'XLU', 'XLRE',
]

def get_ai_allocation(budget: float, goal: str, time_horizon: str, stock_pool: List[str]) -> Dict[str, Any]:
    """Get AI-powered stock allocation based on goal and time horizon"""
    try:
        # Get signals for the stock pool
        all_signals = signals.get_all_signals(watchlist=stock_pool)
        pool_signals = all_signals
        
        if not pool_signals:
            return {
                "total_budget": budget,
                "total_allocated": 0.0,
                "remaining_budget": budget,
                "recommendations": [],
                "message": "No valid stocks found in the selected pool"
            }
        
        # Determine risk profile based on time horizon
        horizon_years = int(time_horizon)
        if horizon_years <= 1:
            # Short-term: Conservative - focus on stability
            pool_signals = [s for s in pool_signals if s.get('signal') in ['Buy', 'Hold']]
            risk_multiplier = 0.5
        elif horizon_years <= 3:
            # Medium-term: Balanced
            pool_signals = [s for s in pool_signals if s.get('signal') in ['Buy', 'Strong Buy', 'Hold']]
            risk_multiplier = 1.0
        else:
            # Long-term: Aggressive - focus on growth
            pool_signals = [s for s in pool_signals if s.get('signal') in ['Buy', 'Strong Buy']]
            risk_multiplier = 1.5
        
        # Sort by score (combination of signal strength and momentum)
        def score_signal(s):
            signal_score = {'Strong Buy': 3, 'Buy': 2, 'Hold': 1}.get(s.get('signal', 'Hold'), 0)
            momentum = abs(s.get('percent_change', 0))
            return (signal_score * risk_multiplier) + (momentum * 0.1)
        
        pool_signals.sort(key=score_signal, reverse=True)
        
        # Select top stocks (5-7 depending on pool size)
        num_stocks = min(len(pool_signals), 7)
        top_picks = pool_signals[:num_stocks]
        
        if not top_picks:
            return {
                "total_budget": budget,
                "total_allocated": 0.0,
                "remaining_budget": budget,
                "recommendations": [],
                "message": "No suitable stocks found for your criteria"
            }
        
        # Calculate allocation percentages
        scores = [score_signal(s) for s in top_picks]
        total_score = sum(scores) or 1
        
        stock_recommendations = []
        total_allocated = 0.0
        
        for i, signal in enumerate(top_picks):
            score = scores[i]
            allocation_pct = score / total_score
            amount = budget * allocation_pct
            
            current_price = signal.get('current_price', 0)
            shares = amount / current_price if current_price > 0 else 0
            
            # Generate factors based on goal and time horizon
            factors = []
            goal_lower = goal.lower()
            if 'retirement' in goal_lower:
                factors.append("Long-term growth focus")
            elif 'house' in goal_lower or 'home' in goal_lower:
                factors.append("Balanced growth/stability")
            elif 'emergency' in goal_lower:
                factors.append("Conservative allocation")
            elif 'vacation' in goal_lower:
                factors.append("Short-term focus")
            elif 'car' in goal_lower:
                factors.append("Medium-term focus")
            elif 'education' in goal_lower:
                factors.append("Long-term growth focus")
            elif 'wealth' in goal_lower:
                factors.append("Aggressive growth focus")
            else:
                factors.append(f"Goal: {goal}")
            
            factors.append(f"Time horizon: {time_horizon} years")
            factors.append(f"Signal: {signal.get('signal')}")
            factors.append(f"Momentum: {signal.get('percent_change', 0):.2f}%")
            
            stock_recommendations.append({
                'ticker': signal.get('ticker'),
                'prediction': signal.get('signal'),
                'current_price': current_price,
                'shares': shares,
                'actual_amount': amount,
                'allocation_percentage': allocation_pct * 100,
                'confidence': min(score_signal(signal) * 15 + 50, 95),
                'score': score,
                'potential_change': signal.get('percent_change', 0),
                'factors': factors
            })
            total_allocated += amount
        
        return {
            "total_budget": budget,
            "total_allocated": total_allocated,
            "remaining_budget": budget - total_allocated,
            "recommendations": stock_recommendations,
            "message": f"Based on your goal '{goal}' and {time_horizon}-year horizon, here are {len(stock_recommendations)} recommendations"
        }
    except Exception as e:
        print(f"Error in get_ai_allocation: {e}")
        return {
            "total_budget": budget,
            "total_allocated": 0.0,
            "remaining_budget": budget,
            "recommendations": [],
            "message": f"Error generating recommendations: {str(e)}"
        }

@app.get("/budget-recommendations")
def get_budget_recommendations(
    stock_source: str = 'watchlist',
    goal: str = '',
    time_horizon: str = '5',
    custom_stocks: str = '',
    authorization: str = Header(...)
):
    """Get budget recommendations with AI-powered stock allocations"""
    try:
        payload = verify_jwt_token(authorization)
        user_id = payload.get("user_id")
        budget = database.get_budget(user_id=user_id)
        
        if budget <= 0:
            return {
                "total_budget": 0.0,
                "total_allocated": 0.0,
                "remaining_budget": 0.0,
                "recommendations": [],
                "message": "Please set a budget to get recommendations"
            }
        
        # Determine stock pool based on source
        stock_pool = []
        if stock_source == 'watchlist':
            watchlist = database.get_personal_watchlist(user_id=user_id)
            print(f"DEBUG: User {user_id} watchlist: {watchlist}")
            if not watchlist:
                return {
                    "total_budget": budget,
                    "total_allocated": 0.0,
                    "remaining_budget": budget,
                    "recommendations": [],
                    "message": "Your watchlist is empty. Please add stocks to your watchlist or use the Curated List option."
                }
            stock_pool = watchlist
        elif stock_source == 'curated':
            stock_pool = CURATED_STOCKS
        elif stock_source == 'custom':
            stock_pool = [s.strip().upper() for s in custom_stocks.split(',') if s.strip()]
        
        if not stock_pool:
            return {
                "total_budget": budget,
                "total_allocated": 0.0,
                "remaining_budget": budget,
                "recommendations": [],
                "message": "No stocks available for recommendations"
            }
        
        # Get AI-powered allocation
        allocation = get_ai_allocation(
            budget=budget,
            goal=goal,
            time_horizon=time_horizon,
            stock_pool=stock_pool
        )
        
        return allocation
    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))

class BudgetRequest(BaseModel):
    amount: float

@app.post("/budget")
def set_budget(budget: BudgetRequest, authorization: str = Header(...)):
    """Set budget"""
    try:
        payload = verify_jwt_token(authorization)
        user_id = payload.get("user_id")
        
        success = database.set_budget(budget.amount, user_id=user_id)
        if success:
            return {"message": "Budget set successfully"}
        else:
            raise HTTPException(status_code=400, detail="Failed to set budget")
    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))

# Currency conversion with caching
import requests

CURRENCY_SYMBOLS = {
    'USD': '$', 'EUR': '€', 'GBP': '£', 'JPY': '¥', 'CNY': '¥',
    'THB': '฿', 'KRW': '₩', 'INR': '₹', 'AUD': 'A$', 'CAD': 'C$',
    'CHF': 'Fr', 'SEK': 'kr', 'NOK': 'kr', 'DKK': 'kr', 'NZD': 'NZ$',
    'SGD': 'S$', 'HKD': 'HK$', 'MXN': '$', 'BRL': 'R$', 'ZAR': 'R'
}

def get_exchange_rates(base: str = 'USD') -> Dict[str, float]:
    """Get exchange rates with Redis caching (24h TTL)"""
    cache_key = f"exchange_rates:{base}"
    
    # Try Redis cache first
    if signals.redis_client:
        try:
            cached = signals.redis_client.get(cache_key)
            if cached:
                return json.loads(cached)
        except Exception as e:
            print(f"Redis cache read failed: {e}")
    
    # Fetch from API
    try:
        response = requests.get(f"https://api.exchangerate-api.com/v4/latest/{base}", timeout=5)
        rates = response.json()['rates']
        
        # Cache in Redis (24 hours = 86400 seconds)
        if signals.redis_client:
            try:
                signals.redis_client.setex(cache_key, 86400, json.dumps(rates))
            except Exception as e:
                print(f"Redis cache write failed: {e}")
        
        return rates
    except Exception as e:
        print(f"Failed to fetch exchange rates: {e}")
        return {}

def convert_price(price_usd: float, target_currency: str) -> tuple:
    """Convert USD price to target currency, returns (converted_price, symbol)"""
    if target_currency == 'USD' or not target_currency:
        return price_usd, CURRENCY_SYMBOLS.get('USD', '$')
    
    rates = get_exchange_rates('USD')
    if target_currency in rates:
        converted = price_usd * rates[target_currency]
        symbol = CURRENCY_SYMBOLS.get(target_currency, target_currency)
        return converted, symbol
    return price_usd, CURRENCY_SYMBOLS.get('USD', '$')

class CurrencyRequest(BaseModel):
    currency: str

@app.get("/exchange-rates")
def get_exchange_rates_endpoint():
    """Get current exchange rates from USD"""
    rates = get_exchange_rates('USD')
    return {"base": "USD", "rates": rates, "symbols": CURRENCY_SYMBOLS}

@app.get("/currencies")
def get_supported_currencies():
    """Get list of supported currencies"""
    return {
        "currencies": [
            {"code": "USD", "name": "US Dollar", "symbol": "$"},
            {"code": "EUR", "name": "Euro", "symbol": "€"},
            {"code": "GBP", "name": "British Pound", "symbol": "£"},
            {"code": "JPY", "name": "Japanese Yen", "symbol": "¥"},
            {"code": "CNY", "name": "Chinese Yuan", "symbol": "¥"},
            {"code": "THB", "name": "Thai Baht", "symbol": "฿"},
            {"code": "KRW", "name": "Korean Won", "symbol": "₩"},
            {"code": "INR", "name": "Indian Rupee", "symbol": "₹"},
            {"code": "AUD", "name": "Australian Dollar", "symbol": "A$"},
            {"code": "NZD", "name": "New Zealand Dollar", "symbol": "NZ$"},
            {"code": "CAD", "name": "Canadian Dollar", "symbol": "C$"},
            {"code": "SGD", "name": "Singapore Dollar", "symbol": "S$"},
        ]
    }

@app.get("/user/currency")
@limiter.limit("30/minute")
def get_user_currency(request: Request, authorization: str = Header(...)):
    """Get user's preferred currency"""
    try:
        payload = verify_jwt_token(authorization)
        user_id = payload.get("user_id")
        currency = database.get_user_currency(user_id)
        return {"currency": currency, "symbol": CURRENCY_SYMBOLS.get(currency, '$')}
    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))

@app.put("/user/profile")
@limiter.limit("20/minute")
def update_user_profile(request: Request, profile_request: ProfileUpdateRequest, authorization: str = Header(...)):
    """Update user profile information"""
    try:
        payload = verify_jwt_token(authorization)
        user_id = payload.get("user_id")
        
        success = database.update_user_profile(user_id, profile_request.first_name, profile_request.last_name)
        if success:
            return {"message": "Profile updated successfully"}
        else:
            raise HTTPException(status_code=404, detail="User not found")
    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))

@app.get("/user/profile")
@limiter.limit("30/minute")
def get_user_profile_endpoint(request: Request, authorization: str = Header(...)):
    """Get current user profile"""
    try:
        payload = verify_jwt_token(authorization)
        user_id = payload.get("user_id")
        
        profile = database.get_user_profile(user_id)
        if profile:
            return profile
        else:
            raise HTTPException(status_code=404, detail="User not found")
    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))

class PasswordChangeRequest(BaseModel):
    current_password: str
    new_password: str

@app.post("/user/change-password")
@limiter.limit("5/minute")
def change_user_password(request: Request, password_request: PasswordChangeRequest, authorization: str = Header(...)):
    """Change user password"""
    try:
        payload = verify_jwt_token(authorization)
        user_id = payload.get("user_id")
        
        # Get user email
        user = database.get_user_by_id(user_id)
        if not user:
            raise HTTPException(status_code=404, detail="User not found")
        
        # Verify current password
        if not database.verify_user(user['email'], password_request.current_password):
            raise HTTPException(status_code=401, detail="Current password is incorrect")
        
        # Validate new password
        new_password = password_request.new_password
        if len(new_password) < 8:
            raise HTTPException(status_code=400, detail="Password must be at least 8 characters long")
        if not any(c.isupper() for c in new_password):
            raise HTTPException(status_code=400, detail="Password must contain at least one uppercase letter")
        if not any(c.islower() for c in new_password):
            raise HTTPException(status_code=400, detail="Password must contain at least one lowercase letter")
        if not any(c.isdigit() for c in new_password):
            raise HTTPException(status_code=400, detail="Password must contain at least one digit")
        
        # Update password
        import hashlib
        password_hash = hashlib.sha256(new_password.encode()).hexdigest()
        success = database.update_user_password(user['email'], password_hash)
        
        if success:
            return {"message": "Password changed successfully"}
        else:
            raise HTTPException(status_code=500, detail="Failed to update password")
    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))

@app.post("/user/currency")
def set_user_currency(request: CurrencyRequest, authorization: str = Header(...)):
    """Set user's preferred currency"""
    try:
        payload = verify_jwt_token(authorization)
        user_id = payload.get("user_id")
        
        success = database.set_user_currency(user_id, request.currency.upper())
        if success:
            return {"message": "Currency updated", "currency": request.currency.upper()}
        else:
            raise HTTPException(status_code=400, detail="Failed to update currency")
    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))

@app.get("/convert-price")
def convert_price_endpoint(price: float, from_currency: str = 'USD', to_currency: str = 'USD'):
    """Convert price between currencies"""
    try:
        rates = get_exchange_rates(from_currency)
        if to_currency in rates:
            converted = price * rates[to_currency]
            return {
                "original_price": price,
                "original_currency": from_currency,
                "converted_price": converted,
                "target_currency": to_currency,
                "symbol": CURRENCY_SYMBOLS.get(to_currency, to_currency)
            }
        else:
            raise HTTPException(status_code=400, detail=f"Currency {to_currency} not supported")
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))

if __name__ == "__main__":
    import uvicorn
    uvicorn.run(app, host="0.0.0.0", port=8000)