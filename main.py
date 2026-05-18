from fastapi import FastAPI, HTTPException
from pydantic import BaseModel
from typing import List, Optional
import database
import signals

app = FastAPI()

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

class Position(BaseModel):
    ticker: str
    buy_price: float
    quantity: int
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

@app.on_event("startup")
def startup_event():
    database.init_db()

@app.get("/")
def read_root():
    return {"message": "StockSense API"}

@app.get("/signals", response_model=List[Signal])
def get_signals():
    """Get trading signals for watchlist stocks"""
    try:
        signals_data = signals.get_all_signals()
        return signals_data
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))

@app.get("/portfolio", response_model=List[Position])
def get_portfolio():
    """Get all portfolio positions"""
    try:
        positions = database.get_all_positions()
        return positions
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))

@app.post("/portfolio")
def add_position(position: Position):
    """Add a new position to portfolio"""
    try:
        database.add_position(position.dict())
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
        info = signals.get_stock_info(ticker)
        if info is None:
            raise HTTPException(status_code=404, detail=f"Stock {ticker} not found or insufficient data")
        return info
    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Error fetching stock info: {str(e)}")

@app.get("/predictions")
def get_predictions():
    """Get predictions for all watchlist stocks"""
    try:
        predictions = signals.get_all_predictions()
        return predictions
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Error fetching predictions: {str(e)}")

if __name__ == "__main__":
    import uvicorn
    uvicorn.run(app, host="0.0.0.0", port=8000)