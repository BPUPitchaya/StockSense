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

# Simple in-memory cache with 30-minute expiration
cache_store = {}
CACHE_DURATION = 1800  # 30 minutes in seconds

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
    
    # Try to fetch fresh data
    try:
        if category and category in signals.CATEGORIES:
            stocks = signals.CATEGORIES[category]
        else:
            stocks = signals.WATCHLIST
        
        all_signals = []
        for ticker in stocks:
            result = signals.analyze_stock(ticker)
            if result:
                all_signals.append(result)
        
        if all_signals:
            set_cache(cache_key, all_signals)
            return all_signals
    except Exception as e:
        print(f"Error fetching fresh signals: {e}")
    
    # Return cached data even if expired if fresh fetch fails
    if cached_data:
        return cached_data
    
    return []

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

@app.get("/personal-watchlist")
def get_personal_watchlist():
    """Get the user's personal watchlist"""
    try:
        watchlist = database.get_personal_watchlist()
        return {"personal_watchlist": watchlist}
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))

@app.post("/personal-watchlist/{ticker}")
def add_to_personal_watchlist(ticker: str):
    """Add a stock to the user's personal watchlist"""
    try:
        ticker = ticker.upper()
        database.add_to_personal_watchlist(ticker)
        return {"message": f"Added {ticker} to personal watchlist"}
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))

@app.delete("/personal-watchlist/{ticker}")
def remove_from_personal_watchlist(ticker: str):
    """Remove a stock from the user's personal watchlist"""
    try:
        ticker = ticker.upper()
        database.remove_from_personal_watchlist(ticker)
        return {"message": f"Removed {ticker} from personal watchlist"}
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))

@app.get("/validate-stock/{ticker}")
def validate_stock(ticker: str):
    """Validate if a ticker is a valid stock (not ETF) before adding to watchlist"""
    try:
        ticker = ticker.upper()
        # Try to fetch stock info to validate
        stock_info = signals.analyze_stock(ticker)
        
        if stock_info is None:
            return {
                "valid": False,
                "reason": "Stock not found or insufficient data",
                "is_etf": False
            }
        
        # Check if it's an ETF (ETFs often have different characteristics)
        # ETFs typically have very high volume and lower volatility
        current_price = stock_info.get('current_price', 0)
        avg_volume = stock_info.get('avg_volume', 0)
        
        # Simple heuristic: ETFs often have extremely high volume
        is_likely_etf = avg_volume > 100000000 if avg_volume else False
        
        return {
            "valid": True,
            "reason": "Valid stock",
            "is_etf": is_likely_etf,
            "ticker": ticker,
            "name": stock_info.get('ticker', ticker)
        }
    except Exception as e:
        return {
            "valid": False,
            "reason": f"Validation failed: {str(e)}",
            "is_etf": False
        }

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
    """Get stock information using Finnhub API first, then fallback to cached signals and yfinance"""
    try:
        ticker = ticker.upper()
        cache_key = get_cache_key("info", ticker=ticker)
        cached_data = get_from_cache(cache_key)
        if cached_data:
            return cached_data
        
        # First try Finnhub API (most reliable for current price and company info)
        finnhub_info = signals.get_stock_info_finnhub(ticker)
        if finnhub_info:
            set_cache(cache_key, finnhub_info)
            return finnhub_info
        
        # Fallback to cached signals
        signals_cache_key = get_cache_key("signals", category="all")
        cached_signals = get_from_cache(signals_cache_key)
        if cached_signals:
            for signal in cached_signals:
                if signal.get("ticker") == ticker:
                    # Convert numpy types to Python native types for JSON serialization
                    data = {
                        "ticker": signal.get("ticker"),
                        "current_price": float(signal.get("current_price")) if signal.get("current_price") is not None else None,
                        "signal": signal.get("signal"),
                        "date": signal.get("date"),
                        "ma50": float(signal.get("ma50")) if signal.get("ma50") is not None else None,
                        "ma200": float(signal.get("ma200")) if signal.get("ma200") is not None else None,
                        "rsi": float(signal.get("rsi")) if signal.get("rsi") is not None else None,
                        "source": "cached_signals"
                    }
                    # Add nested indicators if they exist
                    if signal.get("macd"):
                        data["macd"] = {k: float(v) if v is not None else None for k, v in signal["macd"].items()}
                    if signal.get("bollinger"):
                        data["bollinger"] = {k: float(v) if v is not None else None for k, v in signal["bollinger"].items()}
                    if signal.get("volume"):
                        data["volume"] = {k: float(v) if v is not None else None for k, v in signal["volume"].items()}
                    if signal.get("adx"):
                        data["adx"] = {k: float(v) if v is not None else None for k, v in signal["adx"].items()}
                    
                    set_cache(cache_key, data)
                    return data
        
        # Fallback to yfinance analyze_stock if not in cached signals
        try:
            result = signals.analyze_stock(ticker)
            if result:
                # Convert numpy types to Python native types for JSON serialization
                data = {
                    "ticker": result.get("ticker", ticker),
                    "current_price": float(result.get("current_price")) if result.get("current_price") is not None else None,
                    "signal": result.get("signal"),
                    "date": result.get("date"),
                    "ma50": float(result.get("ma50")) if result.get("ma50") is not None else None,
                    "ma200": float(result.get("ma200")) if result.get("ma200") is not None else None,
                    "rsi": float(result.get("rsi")) if result.get("rsi") is not None else None,
                    "source": "yfinance"
                }
                # Add nested indicators if they exist
                if result.get("macd"):
                    data["macd"] = {k: float(v) if v is not None else None for k, v in result["macd"].items()}
                if result.get("bollinger"):
                    data["bollinger"] = {k: float(v) if v is not None else None for k, v in result["bollinger"].items()}
                if result.get("volume"):
                    data["volume"] = {k: float(v) if v is not None else None for k, v in result["volume"].items()}
                if result.get("adx"):
                    data["adx"] = {k: float(v) if v is not None else None for k, v in result["adx"].items()}
                
                set_cache(cache_key, data)
                return data
        except Exception as e:
            print(f"Error analyzing stock {ticker}: {e}")
        
        # Final fallback: return minimal data with just ticker
        data = {
            "ticker": ticker,
            "current_price": None,
            "signal": "NO_DATA",
            "date": None,
            "error": "Stock data currently unavailable",
            "source": "fallback"
        }
        set_cache(cache_key, data)
        return data
        
    except Exception as e:
        print(f"Error in /info endpoint for {ticker}: {e}")
        # Always return data, never 404
        data = {
            "ticker": ticker,
            "current_price": None,
            "signal": "ERROR",
            "date": None,
            "error": str(e),
            "source": "error"
        }
        return data

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