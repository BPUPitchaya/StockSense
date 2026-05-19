#!/usr/bin/env python3
"""
Training script for LSTM and Random Forest models
Trains models on historical stock data for the watchlist
"""

import sys
import os
from ml_models import EnsemblePredictor, StockDataPreprocessor
import signals

def train_single_stock(ticker: str):
    """Train models for a single stock"""
    print(f"\n{'='*60}")
    print(f"Training models for {ticker}")
    print(f"{'='*60}")
    
    try:
        predictor = EnsemblePredictor()
        predictor.train_models(ticker)
        predictor.save_models(ticker)
        print(f"✓ Successfully trained and saved models for {ticker}")
        return True
    except Exception as e:
        print(f"✗ Error training {ticker}: {e}")
        return False

def train_all_watchlist():
    """Train models for all stocks in watchlist"""
    print(f"\nTraining models for {len(signals.WATCHLIST)} stocks...")
    
    success_count = 0
    failure_count = 0
    
    for ticker in signals.WATCHLIST:
        if train_single_stock(ticker):
            success_count += 1
        else:
            failure_count += 1
    
    print(f"\n{'='*60}")
    print(f"Training Summary:")
    print(f"  Successful: {success_count}/{len(signals.WATCHLIST)}")
    print(f"  Failed: {failure_count}/{len(signals.WATCHLIST)}")
    print(f"{'='*60}")

def train_selected_stocks(tickers: list):
    """Train models for selected stocks"""
    print(f"\nTraining models for {len(tickers)} selected stocks...")
    
    success_count = 0
    for ticker in tickers:
        if train_single_stock(ticker.upper()):
            success_count += 1
    
    print(f"\nSuccessfully trained {success_count}/{len(tickers)} stocks")

if __name__ == "__main__":
    if len(sys.argv) > 1:
        # Train specific stocks provided as arguments
        tickers = sys.argv[1:]
        train_selected_stocks(tickers)
    else:
        # Train all stocks in watchlist
        print("No specific stocks provided. Training all watchlist stocks...")
        print("Usage: python train_models.py [TICKER1 TICKER2 ...]")
        print("Example: python train_models.py AAPL MSFT NVDA")
        
        response = input("\nTrain all watchlist stocks? (y/n): ")
        if response.lower() == 'y':
            train_all_watchlist()
        else:
            print("Training cancelled.")
