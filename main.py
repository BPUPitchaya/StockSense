from fastapi import FastAPI, HTTPException, Depends, Header
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import JSONResponse
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

# Configure CORS
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

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

class LoginRequest(BaseModel):
    email: str
    password: str

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

def get_from_cache(key: str, allow_stale: bool = False) -> tuple[Optional[Any], bool]:
    """
    Get data from cache.
    Returns: (data, is_fresh) - is_fresh is False if stale but usable
    """
    if key in _cache:
        data, timestamp = _cache[key]
        age = time.time() - timestamp
        
        if age < CACHE_DURATION:
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
    """Initialize database only - cache warms on first request"""
    database.init_db()
    print("Database initialized, ready for requests")

@app.get("/")
def read_root():
    return {"message": "StockSense API is running"}

@app.post("/signup")
def signup(request: SignupRequest):
    """User signup endpoint"""
    try:
        success = database.create_user(request.email, request.password)
        if success:
            return {"message": "User created successfully"}
        else:
            raise HTTPException(status_code=400, detail="User already exists")
    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))

@app.post("/login")
def login(request: LoginRequest):
    """User login endpoint"""
    try:
        user = database.verify_user(request.email, request.password)
        if user:
            token = create_jwt_token({"sub": user['email'], "user_id": user['id']})
            return {
                "access_token": token,
                "token_type": "bearer",
                "user": user
            }
        else:
            raise HTTPException(status_code=401, detail="Invalid credentials")
    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))

@app.post("/admin/login")
def admin_login(request: LoginRequest):
    """Admin login endpoint"""
    try:
        if database.verify_admin(request.email, request.password):
            return {"message": "Admin login successful", "email": request.email}
        else:
            raise HTTPException(status_code=401, detail="Invalid admin credentials")
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

@app.delete("/admin/users/{user_id}")
def delete_user(user_id: int):
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
def get_signals(category: Optional[str] = None):
    """Get trading signals - instant with stale-while-revalidate"""
    cache_key = get_cache_key("signals_5stocks", category=category or "all")
    
    # Try to get from cache (allow stale for instant response)
    cached_data, is_fresh = get_from_cache(cache_key, allow_stale=True)
    
    if cached_data:
        if is_fresh:
            print(f"Returning {len(cached_data)} FRESH cached signals")
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
                print(f"Generated {len(all_signals_data)} signals (cold start)")
                clean_data = clean_for_json(all_signals_data)
                set_cache(cache_key, clean_data)
                return clean_data
        except Exception as e:
            print(f"Attempt {attempt + 1}/{max_retries} failed: {e}")
            if attempt < max_retries - 1:
                time.sleep(1)
    
    # All retries failed
    print(f"All retries failed for signals fetch")
    raise HTTPException(status_code=503, detail="Stock data temporarily unavailable. Please try again.")

@app.get("/predictions")
def get_predictions(category: Optional[str] = None, authorization: str = Header(...)):
    """Get predictions using same fast signals as main page for consistency"""
    try:
        payload = verify_jwt_token(authorization)
        user_id = payload.get("user_id")
        
        # Get user's personal watchlist
        user_watchlist = database.get_personal_watchlist(user_id=user_id)
        if not user_watchlist:
            user_watchlist = signals.WATCHLIST
        
        # Use user-specific cache key so each user gets their own predictions
        watchlist_key = ",".join(sorted(user_watchlist))
        cache_key = get_cache_key(f"predictions_{user_id}", watchlist=watchlist_key)
        cached_signals, is_fresh = get_from_cache(cache_key, allow_stale=True)
        
        if cached_signals:
            sorted_signals = sorted(cached_signals, key=lambda x: x.get('percent_change', 0), reverse=True)
            all_predictions = convert_signals_to_predictions(sorted_signals)
            predictions = {
                'gainers': all_predictions[:3],
                'losers': all_predictions[-3:] if len(all_predictions) >= 3 else all_predictions,
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
                    
                    predictions = {
                        'gainers': all_predictions[:3],
                        'losers': all_predictions[-3:] if len(all_predictions) >= 3 else all_predictions,
                        'all_predictions': all_predictions,
                        'count': len(all_predictions)
                    }
                    return predictions
            except Exception as e:
                print(f"Predictions attempt {attempt + 1}/{max_retries} failed: {e}")
                if attempt < max_retries - 1:
                    time.sleep(1)
        
        # All retries failed
        raise HTTPException(status_code=503, detail="Prediction service temporarily unavailable. Please try again.")
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
    # For futures tickers (ending in =F), use yfinance directly
    if ticker.endswith('=F'):
        try:
            stock_info = signals.get_stock_info(ticker)
            if stock_info:
                return stock_info
        except Exception as e:
            print(f"yfinance failed for {ticker}: {e}")
        raise HTTPException(status_code=404, detail="Commodity not found")
    
    # For regular stocks, use Finnhub
    try:
        stock_info = signals.get_stock_info_finnhub(ticker)
        if stock_info:
            technicals = signals.get_technical_indicators(ticker)
            stock_info['ma50'] = technicals.get('ma50')
            stock_info['ma200'] = technicals.get('ma200')
            stock_info['volume_ratio'] = technicals.get('volume_ratio')
            return stock_info
        else:
            raise HTTPException(status_code=404, detail="Stock not found or not supported (US market only)")
    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))

@app.get("/validate-stock/{ticker}")
def validate_stock(ticker: str):
    """Validate a stock ticker"""
    try:
        stock_info = signals.get_stock_info_finnhub(ticker)
        if stock_info:
            return {"valid": True, "ticker": ticker, "name": stock_info.get('description', '')}
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

@app.post("/portfolio")
def add_position(position: Position, authorization: str = Header(...)):
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
def get_portfolio(authorization: str = Header(...)):
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
def delete_position(position_id: int, authorization: str = Header(...)):
    """Delete a position from portfolio"""
    try:
        payload = verify_jwt_token(authorization)
        user_id = payload.get("user_id")
        
        success = database.delete_position(position_id)
        if success:
            return {"message": "Position deleted successfully"}
        else:
            raise HTTPException(status_code=404, detail="Position not found")
    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))

@app.post("/watchlist")
def add_to_watchlist(request: WatchlistRequest, authorization: str = Header(...)):
    """Add a stock to personal watchlist"""
    try:
        payload = verify_jwt_token(authorization)
        user_id = payload.get("user_id")
        
        current = database.get_personal_watchlist(user_id=user_id)
        if len(current) >= 5:
            raise HTTPException(status_code=400, detail="Watchlist limit reached (max 5 stocks)")
        success = database.add_to_watchlist(request.ticker, user_id=user_id)
        if success:
            return {"message": "Stock added to watchlist"}
        else:
            raise HTTPException(status_code=400, detail="Stock already in watchlist")
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
def remove_from_watchlist(ticker: str, authorization: str = Header(...)):
    """Remove a stock from personal watchlist"""
    try:
        payload = verify_jwt_token(authorization)
        user_id = payload.get("user_id")
        
        success = database.remove_from_watchlist(ticker, user_id=user_id)
        if success:
            return {"message": "Stock removed from watchlist"}
        else:
            raise HTTPException(status_code=404, detail="Stock not in watchlist")
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

@app.get("/budget-recommendations")
def get_budget_recommendations(authorization: str = Header(...)):
    """Get budget recommendations with stock allocations - fast version using daily signals"""
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
        
        # Use fast signals for all 30+ stocks (no rate limiting)
        all_signals = signals.get_all_signals()
        
        # Filter for Buy/Strong Buy signals only
        buy_signals = [s for s in all_signals if s.get('signal') in ['Buy', 'Strong Buy']]
        
        # Sort by percent change (highest momentum first)
        buy_signals.sort(key=lambda x: x.get('percent_change', 0), reverse=True)
        
        # Calculate allocations
        top_picks = buy_signals[:5]  # Top 5 picks
        if not top_picks:
            return {
                "total_budget": budget,
                "total_allocated": 0.0,
                "remaining_budget": budget,
                "recommendations": [],
                "message": "No Buy/Strong Buy stocks found. Check back later when market conditions improve."
            }
        
        # Use absolute percent change as score so allocations always sum to 100%
        scores = [max(abs(s.get('percent_change', 1)), 0.01) for s in top_picks]
        total_score = sum(scores) or 1
        
        stock_recommendations = []
        total_allocated = 0.0
        
        for i, signal in enumerate(top_picks):
            score = scores[i]
            allocation_pct = score / total_score
            amount = budget * allocation_pct
            
            current_price = signal.get('current_price', 0)
            shares = amount / current_price if current_price > 0 else 0
            
            stock_recommendations.append({
                'ticker': signal.get('ticker'),
                'prediction': signal.get('signal'),  # Buy or Strong Buy
                'current_price': current_price,
                'shares': shares,
                'actual_amount': amount,
                'allocation_percentage': allocation_pct * 100,
                'confidence': min(abs(signal.get('percent_change', 0)) * 10 + 50, 95),  # Higher confidence for bigger moves
                'score': score,
                'potential_change': signal.get('percent_change', 0),
                'factors': [f"Daily momentum: {signal.get('percent_change', 0):.2f}%", 
                           f"Price: ${current_price:.2f}"]
            })
            total_allocated += amount
        
        return {
            "total_budget": budget,
            "total_allocated": total_allocated,
            "remaining_budget": budget - total_allocated,
            "recommendations": stock_recommendations,
            "message": f"Based on your ${budget:.2f} budget, here are {len(stock_recommendations)} top momentum picks"
        }
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
            {"code": "CAD", "name": "Canadian Dollar", "symbol": "C$"},
        ]
    }

@app.get("/user/currency")
def get_user_currency(authorization: str = Header(...)):
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