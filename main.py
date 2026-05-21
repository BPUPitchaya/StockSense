from fastapi import FastAPI, HTTPException
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel
from typing import List, Optional
import database
import signals
from datetime import datetime, timedelta
import time

app = FastAPI()

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# Simple in-memory cache
cache_store = {}
CACHE_DURATION = 300  # 5 minutes in seconds

def get_cache_key(endpoint: str, **kwargs) -> str:
    """Generate cache key from endpoint and parameters"""
    key_parts = [endpoint]
    for k, v in sorted(kwargs.items()):
        key_parts.append(f"{k}={v}")
    return "|".join(key_parts)

def get_from_cache(key: str) -> Optional[dict]:
    """Get data from cache if not expired"""
    if key in cache_store:
        data, timestamp = cache_store[key]
        if time.time() - timestamp < CACHE_DURATION:
            return data
        else:
            del cache_store[key]
    return None

def set_cache(key: str, data: dict):
    """Store data in cache"""
    cache_store[key] = (data, time.time())

class Position(BaseModel):
    ticker: str
    buy_price: float
    quantity: float
    date: str

class Signal(BaseModel):
    ticker: str
    current_price: float
    ma50: Optional[float]
    ma200: Optional[float]
    rsi: Optional[float]
    signal: str
    date: str

class HistoricalData(BaseModel):
    date: str
    open: float
    high: float
    low: float
    close: float
    volume: int

class Budget(BaseModel):
    amount: float

@app.on_event("startup")
def startup_event():
    database.init_db()

@app.get("/")
def read_root():
    return {"message": "StockSense API"}

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
        signals_data = signals.get_all_signals(category=category)
        set_cache(cache_key, signals_data)
        return signals_data
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))

@app.get("/portfolio")
def get_portfolio():
    """Get all portfolio positions"""
    try:
        positions = database.get_all_positions()
        return positions
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))

@app.get("/portfolio/value")
def get_portfolio_value():
    """Get total portfolio value"""
    try:
        positions = database.get_all_positions()
        total_value = 0.0
        for position in positions:
            try:
                stock_info = signals.analyze_stock(position['ticker'])
                if stock_info and 'current_price' in stock_info:
                    total_value += stock_info['current_price'] * position['quantity']
            except:
                pass
        return {"total_value": total_value, "position_count": len(positions)}
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))

@app.post("/portfolio")
def add_position(position: Position):
    """Add a new position to portfolio"""
    try:
        database.add_position(position.model_dump())
        return {"message": "Position added successfully"}
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))

@app.delete("/portfolio/{position_id}")
def delete_position(position_id: int):
    """Delete a position from portfolio"""
    try:
        database.delete_position(position_id)
        return {"message": "Position deleted successfully"}
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))

@app.put("/portfolio/{position_id}")
def update_position(position_id: int, position: Position):
    """Update a position in portfolio"""
    try:
        database.update_position(position_id, position.model_dump())
        return {"message": "Position updated successfully"}
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))

@app.get("/watchlist")
def get_watchlist():
    """Get the current watchlist"""
    try:
        return {"watchlist": signals.WATCHLIST}
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))

@app.get("/search/{ticker}", response_model=Signal)
def search_stock(ticker: str):
    """Search for a specific stock by ticker"""
    try:
        ticker = ticker.upper()
        result = signals.analyze_stock(ticker)
        if result is None:
            raise HTTPException(status_code=404, detail=f"Stock {ticker} not found or insufficient data")
        return result
    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Error searching stock: {str(e)}")

@app.get("/history/{ticker}")
def get_stock_history(ticker: str, period: str = "3mo"):
    """Get historical price data for a specific stock"""
    try:
        ticker = ticker.upper()
        history = signals.get_stock_history(ticker, period)
        if history is None or len(history) == 0:
            raise HTTPException(status_code=404, detail=f"Stock {ticker} not found or insufficient data")
        return history
    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Error fetching stock history: {str(e)}")

@app.get("/info/{ticker}")
def get_stock_info(ticker: str):
    """Get detailed stock information including market cap, P/E ratio, dividends, etc."""
    try:
        ticker = ticker.upper()
        cache_key = get_cache_key("info", ticker=ticker)
        cached_data = get_from_cache(cache_key)
        if cached_data:
            return cached_data
        
        info = signals.get_stock_info(ticker)
        if info is None:
            raise HTTPException(status_code=404, detail=f"Stock {ticker} not found or insufficient data")
        
        set_cache(cache_key, info)
        return info
    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Error fetching stock info: {str(e)}")

@app.get("/predictions")
def get_predictions(category: Optional[str] = None, limit: Optional[int] = 5):
    """Get predictions for watchlist stocks (top N gainers and losers)"""
    cache_key = get_cache_key("predictions", category=category or "all", limit=limit)
    cached_data = get_from_cache(cache_key)
    
    if cached_data:
        return cached_data
    
    try:
        predictions = signals.get_all_predictions(category=category, limit=limit)
        set_cache(cache_key, predictions)
        return predictions
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Error fetching predictions: {str(e)}")

@app.post("/budget")
def set_budget(budget: Budget):
    """Set the budget amount"""
    try:
        database.set_budget(budget.amount)
        return {"message": "Budget set successfully", "amount": budget.amount}
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))

@app.get("/budget")
def get_budget():
    """Get the current budget"""
    try:
        budget = database.get_budget()
        if budget is None:
            raise HTTPException(status_code=404, detail="No budget set")
        return budget
    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))

@app.get("/budget-recommendations")
def get_budget_recommendations():
    """Get budget recommendations based on portfolio and predictions"""
    try:
        budget = database.get_budget()
        if budget is None:
            raise HTTPException(status_code=404, detail="No budget set")
        
        # Get top predictions
        predictions = signals.get_all_predictions(limit=5)
        top_gainers = predictions.get('gainers', [])
        
        budget_amount = budget['amount']
        recommendations = []
        total_allocated = 0
        
        # Allocate budget evenly among top gainers
        if top_gainers:
            allocation_per_stock = budget_amount / len(top_gainers)
            
            for prediction in top_gainers:
                price = prediction.get('current_price', 0)
                if price > 0:
                    shares = allocation_per_stock / price
                    actual_amount = shares * price
                    total_allocated += actual_amount
                    
                    recommendations.append({
                        'ticker': prediction['ticker'],
                        'prediction': prediction.get('prediction', 'Buy'),
                        'current_price': price,
                        'shares': shares,
                        'actual_amount': actual_amount,
                        'allocation_percentage': (actual_amount / budget_amount) * 100,
                        'confidence': prediction.get('confidence', 0),
                        'score': prediction.get('score', 0),
                        'potential_change': prediction.get('potential_change'),
                        'factors': prediction.get('factors', [])
                    })
        
        return {
            'total_budget': budget_amount,
            'total_allocated': total_allocated,
            'remaining_budget': budget_amount - total_allocated,
            'message': f'Market is {"bullish" if len(top_gainers) >= 3 else "neutral" if len(top_gainers) >= 1 else "bearish"}',
            'market_condition': 'bullish' if len(top_gainers) >= 3 else 'neutral' if len(top_gainers) >= 1 else 'bearish',
            'recommendations': recommendations
        }
    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))

if __name__ == "__main__":
    import uvicorn
    import os
    
    # Configure host from environment variable or default to localhost
    host = os.getenv("HOST", "127.0.0.1")
    port = int(os.getenv("PORT", "8000"))
    
    uvicorn.run(app, host=host, port=port)