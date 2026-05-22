from fastapi import FastAPI, HTTPException, Depends, Header
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel
from typing import Dict, Any, List, Optional
import database
import signals
from datetime import datetime, timedelta
import time
import jwt
import os

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

class Signal(BaseModel):
    ticker: str
    current_price: float
    ma50: Optional[float] = None
    ma200: Optional[float] = None
    rsi: Optional[float] = None
    signal: str
    date: str

# Simple in-memory cache
cache: Dict[str, tuple] = {}
CACHE_DURATION = 300  # 5 minutes

def get_cache_key(prefix: str, **kwargs) -> str:
    """Generate a cache key"""
    key_parts = [prefix]
    for k, v in sorted(kwargs.items()):
        key_parts.append(f"{k}={v}")
    return ":".join(key_parts)

def get_from_cache(key: str) -> Optional[Any]:
    """Get data from cache if still valid"""
    if key in cache:
        data, timestamp = cache[key]
        if time.time() - timestamp < CACHE_DURATION:
            return data
        else:
            del cache[key]
    return None

def set_cache(key: str, data: Any) -> None:
    """Set data in cache"""
    cache[key] = (data, time.time())

@app.on_event("startup")
def startup_event():
    """Initialize database on startup"""
    database.init_db()

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

@app.get("/signals", response_model=List[Signal])
def get_signals(category: Optional[str] = None):
    """Get trading signals for watchlist stocks"""
    cache_key = get_cache_key("signals", category=category or "all")
    cached_data = get_from_cache(cache_key)
    if cached_data:
        return cached_data
    
    try:
        predictions = signals.get_all_predictions(category=category)
        # Extract all signals from gainers and losers and map to Signal model
        all_signals = []
        for stock_data in predictions.get('gainers', []) + predictions.get('losers', []):
            signal = Signal(
                ticker=stock_data.get('ticker', ''),
                current_price=stock_data.get('current_price', 0.0),
                ma50=stock_data.get('ma50'),
                ma200=stock_data.get('ma200'),
                rsi=stock_data.get('rsi'),
                signal=stock_data.get('prediction', 'HOLD'),
                date=datetime.utcnow().strftime('%Y-%m-%d')
            )
            all_signals.append(signal)
        set_cache(cache_key, all_signals)
        return all_signals
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))

@app.get("/predictions")
def get_predictions(category: Optional[str] = None, authorization: str = Header(...)):
    """Get all predictions with gainers and losers for the user's watchlist"""
    try:
        payload = verify_jwt_token(authorization)
        user_id = payload.get("user_id")
        
        # Get user's watchlist
        watchlist = database.get_watchlist(user_id=user_id)
        if not watchlist:
            watchlist = signals.get_default_watchlist()
        
        # Use watchlist in cache key to make it user-specific
        watchlist_key = ",".join(sorted(watchlist))
        cache_key = get_cache_key("predictions", category=category or "all", watchlist=watchlist_key[:50])
        cached_data = get_from_cache(cache_key)
        if cached_data:
            return cached_data
        
        predictions = signals.get_all_predictions(category=category, watchlist=watchlist)
        set_cache(cache_key, predictions)
        return predictions
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))

@app.get("/info/{ticker}")
def get_stock_info_endpoint(ticker: str):
    """Get stock info with market cap, P/E ratio, etc."""
    try:
        stock_info = signals.get_stock_info(ticker)
        if stock_info is not None:
            return stock_info
        else:
            raise HTTPException(status_code=404, detail="Stock not found")
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))

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
        positions = database.get_all_positions(user_id=user_id)
        return {"positions": positions}
    except HTTPException:
        raise
    except Exception as e:
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
def add_to_watchlist(ticker: str, authorization: str = Header(...)):
    """Add a stock to personal watchlist"""
    try:
        payload = verify_jwt_token(authorization)
        user_id = payload.get("user_id")
        
        success = database.add_to_watchlist(ticker, user_id=user_id)
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
    """Get budget recommendations with stock allocations"""
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
        
        # Get watchlist
        watchlist = database.get_watchlist(user_id=user_id)
        if not watchlist:
            watchlist = signals.get_default_watchlist()
        
        # Get predictions for watchlist stocks
        all_signals = []
        for ticker in watchlist[:5]:  # Limit to top 5
            try:
                pred = signals.get_prediction(ticker)
                if pred and pred.get('prediction') in ['Buy', 'Strong Buy']:
                    all_signals.append(pred)
            except:
                continue
        
        # Sort by score
        all_signals.sort(key=lambda x: x.get('score', 0), reverse=True)
        
        # Calculate allocations
        top_picks = all_signals[:3]  # Top 3 picks
        total_score = sum(s.get('score', 1) for s in top_picks) or 1
        
        stock_recommendations = []
        total_allocated = 0.0
        
        for signal in top_picks:
            score = signal.get('score', 1)
            allocation_pct = score / total_score
            amount = budget * allocation_pct * 0.8  # Use 80% of budget, keep 20% cash
            
            current_price = signal.get('current_price', 0)
            shares = amount / current_price if current_price > 0 else 0
            
            stock_recommendations.append({
                'ticker': signal.get('ticker'),
                'prediction': signal.get('prediction'),
                'current_price': current_price,
                'shares': shares,
                'actual_amount': amount,
                'allocation_percentage': allocation_pct * 100,
                'confidence': signal.get('confidence', 50),
                'score': score,
                'potential_change': signal.get('potential_change', 0),
                'factors': signal.get('factors', [])
            })
            total_allocated += amount
        
        return {
            "total_budget": budget,
            "total_allocated": total_allocated,
            "remaining_budget": budget - total_allocated,
            "recommendations": stock_recommendations,
            "message": f"Based on your ${budget:.2f} budget, here are top {len(stock_recommendations)} stock picks"
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