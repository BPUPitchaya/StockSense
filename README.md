# StockSense

A swing trading application with technical analysis, stock predictions, and portfolio management.

## Features

- **Backend (Python/FastAPI)**:
  - Technical indicators: RSI, MACD, Bollinger Bands, Volume, ADX
  - Multiple timeframe analysis (daily, weekly, monthly)
  - Stock predictions with confidence scores
  - Portfolio management with SQLite database
  - RESTful API endpoints

- **Frontend (Flutter)**:
  - Signals screen with buy/sell recommendations
  - Portfolio management screen
  - Stock detail view with charts
  - Predictions screen with timeframe confirmations
  - Search functionality

## Setup

### Backend

```bash
cd /Users/bpu/Documents/Projects/Stockz
./start.sh
```

This creates a virtual environment, installs dependencies, and starts the FastAPI server on port 8000.

### Frontend

```bash
cd /Users/bpu/Documents/Projects/Stockz/flutter_app
flutter pub get
flutter run -d chrome
```

## API Endpoints

- `GET /signals` - Trading signals for watchlist
- `GET /portfolio` - Get portfolio positions
- `POST /portfolio` - Add position
- `DELETE /portfolio/{id}` - Delete position
- `GET /watchlist` - Get watchlist
- `GET /search/{ticker}` - Search individual stock
- `GET /history/{ticker}` - Historical price data
- `GET /info/{ticker}` - Detailed stock information
- `GET /predictions` - Stock predictions with multiple timeframe analysis

## Technical Indicators

- RSI (Relative Strength Index)
- MACD (Moving Average Convergence Divergence)
- Bollinger Bands
- Volume analysis
- ADX (Average Directional Index)
- Moving Averages (50-day, 200-day)

## Prediction System

The prediction system uses:
- Weighted scoring based on multiple technical indicators
- Multiple timeframe confirmation (daily, weekly, monthly)
- Trend strength filtering (ADX > 20)
- Confidence scores for each prediction

## Watchlist

Includes major S&P 500 stocks across technology, financial, healthcare, consumer, energy, and industrial sectors.
