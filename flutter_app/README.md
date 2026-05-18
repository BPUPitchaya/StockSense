# Stockz Flutter App

Flutter frontend for the Stockz swing trading backend.

## Prerequisites

- Flutter SDK installed
- Python backend running at http://localhost:8000

## Setup

1. Navigate to the flutter_app directory:
```bash
cd flutter_app
```

2. Install dependencies:
```bash
flutter pub get
```

## Running the App

Make sure the Python backend is running first:
```bash
cd ..
./start.sh
```

Then in a new terminal, run the Flutter app:
```bash
cd flutter_app
flutter run
```

## Features

- **Signals Tab**: View buy/sell recommendations for watchlist stocks
  - Current price
  - 50-day and 200-day moving averages
  - RSI indicator
  - Trading signal (BUY/SELL/HOLD)
  - Search functionality

- **Predictions Tab**: View stock predictions
  - Potential gainers and losers
  - Confidence scores
  - Multiple timeframe confirmations
  - Technical indicator factors

- **Portfolio Tab**: Manage your portfolio
  - View all positions
  - Add new positions
  - Delete positions

- **Stock Details**: Tap any stock to see
  - Historical price charts
  - Detailed stock information (market cap, P/E, dividends, etc.)

## API Endpoints Used

- `GET http://localhost:8000/signals` - Get trading signals
- `GET http://localhost:8000/portfolio` - Get portfolio positions
- `POST http://localhost:8000/portfolio` - Add position
- `DELETE http://localhost:8000/portfolio/{id}` - Delete position
- `GET http://localhost:8000/watchlist` - Get watchlist
- `GET http://localhost:8000/search/{ticker}` - Search individual stock
- `GET http://localhost:8000/history/{ticker}` - Historical price data
- `GET http://localhost:8000/info/{ticker}` - Detailed stock information
- `GET http://localhost:8000/predictions` - Stock predictions