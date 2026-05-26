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
    """Initialize database and warm up cache"""
    database.init_db()
    
    # Warm up cache on startup (background)
    def warm_cache():
        try:
            print("Warming up signals cache...")
            data = signals.get_all_signals()
            if data:
                cache_key = get_cache_key("signals_5stocks", category="all")
                set_cache(cache_key, clean_for_json(data))
                print(f"Cache warmed with {len(data)} signals")
        except Exception as e:
            print(f"Cache warm-up failed: {e}")
    
    threading.Thread(target=warm_cache, daemon=True).start()

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
    
    # No cache - must fetch (this is the slow path on cold start)
    try:
        all_signals_data = signals.get_all_signals()
        print(f"Generated {len(all_signals_data)} signals (cold start)")
        clean_data = clean_for_json(all_signals_data)
        set_cache(cache_key, clean_data)
        return clean_data
    except Exception as e:
        print(f"Error in get_signals: {e}")
        raise HTTPException(status_code=500, detail=str(e))

@app.get("/predictions")
def get_predictions(category: Optional[str] = None, authorization: str = Header(...)):
    """Get predictions using same fast signals as main page for consistency"""
    try:
        payload = verify_jwt_token(authorization)
        user_id = payload.get("user_id")
        
        # Use same fast signals as main page for consistency
        watchlist = database.get_personal_watchlist(user_id=user_id)
        if not watchlist:
            watchlist = signals.WATCHLIST
        
        # Use unified cache key with stale-while-revalidate
        watchlist_key = ",".join(sorted(watchlist))
        cache_key = get_cache_key("predictions_unified", category=category or "all", watchlist=watchlist_key[:50])
        cached_data, is_fresh = get_from_cache(cache_key, allow_stale=True)
        
        if cached_data:
            if is_fresh:
                return cached_data
            else:
                # Stale - refresh in background
                def refresh_predictions():
                    try:
                        all_signals = signals.get_all_signals()
                        sorted_signals = sorted(all_signals, key=lambda x: x.get('percent_change', 0), reverse=True)
                        predictions = {
                            'gainers': sorted_signals[:3],
                            'losers': sorted_signals[-3:] if len(sorted_signals) >= 3 else sorted_signals,
                            'all_signals': sorted_signals,
                            'count': len(sorted_signals)
                        }
                        set_cache(cache_key, clean_for_json(predictions))
                    except Exception as e:
                        print(f"Background refresh predictions failed: {e}")
                _refresh_executor.submit(refresh_predictions)
                return cached_data
        
        # Cold start - fetch fresh
        all_signals = signals.get_all_signals()
        
        # Sort by percent_change for gainers/losers
        sorted_signals = sorted(all_signals, key=lambda x: x.get('percent_change', 0), reverse=True)
        
        # Format as predictions response
        predictions = {
            'gainers': sorted_signals[:3],  # Top 3
            'losers': sorted_signals[-3:] if len(sorted_signals) >= 3 else sorted_signals,  # Bottom 3
            'all_signals': sorted_signals,
            'count': len(sorted_signals)
        }
        
        clean_predictions = clean_for_json(predictions)
        set_cache(cache_key, clean_predictions)
        return clean_predictions
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))

@app.get("/info/{ticker}")
def get_stock_info_endpoint(ticker: str):
    """Get stock info with market cap, P/E ratio, etc."""
    try:
        stock_info = signals.get_stock_info_finnhub(ticker)
        if stock_info is not None:
            return stock_info
        else:
            raise HTTPException(status_code=404, detail="Stock not found")
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
            return stock_info
        else:
            raise HTTPException(status_code=404, detail="Stock not found or not supported (US market only)")
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
        
        # Use percent change as score for allocation
        total_score = sum(s.get('percent_change', 1) for s in top_picks) or 1
        
        stock_recommendations = []
        total_allocated = 0.0
        
        for signal in top_picks:
            score = signal.get('percent_change', 1)
            allocation_pct = score / total_score if total_score > 0 else 1 / len(top_picks)
            amount = budget * allocation_pct * 0.8  # Use 80% of budget, keep 20% cash
            
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

if __name__ == "__main__":
    import uvicorn
    uvicorn.run(app, host="0.0.0.0", port=8000)