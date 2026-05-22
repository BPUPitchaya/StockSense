from fastapi import FastAPI, HTTPException, Depends, Header, CORSMiddleware, BaseModel, List, Optional
from fastapi.middleware.cors import CORSMiddleware
from typing import Dict, Any
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
    prediction: str
    confidence: float
    score: float
    potential_change: float
    category: Optional[str] = None

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
        set_cache(cache_key, predictions)
        return predictions
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

@app.post("/budget")
def set_budget(amount: float, authorization: str = Header(...)):
    """Set budget"""
    try:
        payload = verify_jwt_token(authorization)
        user_id = payload.get("user_id")
        
        success = database.set_budget(amount, user_id=user_id)
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
