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

## Deployment

### Environment Variables

The application requires the following environment variables. See `.env.example` for a template.

- `DATABASE_URL` - PostgreSQL connection string (required for production)
- `FINNHUB_API_KEY` - Finnhub API key for stock data
- `REDIS_URL` - Redis connection string for caching
- `JWT_SECRET` - Secret key for JWT token signing
- `ADMIN_EMAIL` - Admin email for admin panel access
- `ADMIN_PASSWORD` - Admin password for admin panel access
- `ENVIRONMENT` - Set to `production` for production deployment

### Render Deployment

1. **Create a PostgreSQL database** on Render
2. **Create a Redis instance** on Render
3. **Set environment variables** in Render dashboard
4. **Deploy the backend**:
   - Connect your GitHub repository
   - Set build command: `pip install -r requirements.txt`
   - Set start command: `python main.py`
5. **Deploy the frontend**:
   - Build Flutter web app: `flutter build web --dart-define=GEMINI_API_KEY=your_key`
   - Deploy the `flutter_app/build/web` directory to Render Static Sites

### Local Development

For local development, you can use SQLite (default) by not setting `DATABASE_URL`. Copy `.env.example` to `.env` and fill in the required values.

```bash
cp .env.example .env
# Edit .env with your values
./start.sh
```

## Health Check

The application provides a health check endpoint at `/health` that returns:
- Database connection status
- Redis connection status
- Finnhub API status
- Overall system health

Use this for monitoring and uptime checks.
