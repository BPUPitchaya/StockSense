import yfinance as yf
import pandas as pd
import numpy as np
from typing import List, Dict, Optional
from datetime import datetime, timedelta
import asyncio
from concurrent.futures import ThreadPoolExecutor
import time
import os
import json
from io import StringIO
import finnhub
import redis
import requests
import pytz

# Core 5 stocks for fast loading
CATEGORIES = {
    "Top Stocks": ["AAPL", "MSFT", "NVDA", "GOOGL", "TSLA"],
}

WATCHLIST = ["AAPL", "MSFT", "NVDA", "GOOGL", "TSLA"]

# ETF name mappings (Finnhub doesn't return names for ETFs)
ETF_NAMES = {
    'VOO': 'Vanguard S&P 500 ETF',
    'SPY': 'SPDR S&P 500 ETF Trust',
    'QQQ': 'Invesco QQQ Trust (Nasdaq-100)',
    'GLD': 'SPDR Gold Shares',
    'SLV': 'iShares Silver Trust',
    'VTI': 'Vanguard Total Stock Market ETF',
    'BND': 'Vanguard Total Bond Market ETF',
    'VEA': 'Vanguard FTSE Developed Markets ETF',
    'VWO': 'Vanguard FTSE Emerging Markets ETF',
    'IJH': 'iShares Core S&P Mid-Cap ETF',
    'IJR': 'iShares Core S&P Small-Cap ETF',
    'VUG': 'Vanguard Growth ETF',
    'VTV': 'Vanguard Value ETF',
    'VXUS': 'Vanguard Total International Stock ETF',
    'SCHD': 'Schwab US Dividend Equity ETF',
    'ARKK': 'ARK Innovation ETF',
    'XLF': 'Financial Select Sector SPDR Fund',
    'XLK': 'Technology Select Sector SPDR Fund',
    'XLE': 'Energy Select Sector SPDR Fund',
    'XLI': 'Industrial Select Sector SPDR Fund',
    'XLP': 'Consumer Staples Select Sector SPDR Fund',
    'XLU': 'Utilities Select Sector SPDR Fund',
    'XLV': 'Health Care Select Sector SPDR Fund',
    'XLY': 'Consumer Discretionary Select Sector SPDR Fund',
    'XLB': 'Materials Select Sector SPDR Fund',
    'XRT': 'SPDR S&P Retail ETF',
    'KRE': 'SPDR S&P Regional Banking ETF',
    'IBIT': 'iShares Bitcoin Trust ETF',
}

# Initialize Finnhub client
FINNHUB_API_KEY = os.getenv('FINNHUB_API_KEY', 'd879fr9r01ql0hskrd3gd879fr9r01ql0hskrd40')
finnhub_client = finnhub.Client(api_key=FINNHUB_API_KEY)

# Redis cache connection with authentication
REDIS_URL = os.getenv('REDIS_URL', 'redis://red-d89tjhq8qa3s73eb4320:JZGjlPWddeVHixHr7rcMBWuHt9Z7mhPD@red-d89tjhq8qa3s73eb4320:6379')
try:
    redis_client = redis.from_url(REDIS_URL, decode_responses=True)
    redis_client.ping()  # Test connection
    print("Connected to Redis successfully")
except Exception as e:
    print(f"Redis connection failed, using local cache: {e}")
    redis_client = None

# Fallback local caches if Redis unavailable
_stock_info_cache: Dict[str, Dict] = {}
_stock_history_cache: Dict[str, pd.DataFrame] = {}

# Global rate limiting - track last yfinance request time
_last_yfinance_request: float = 0
_yfinance_min_delay: float = 5.0  # Minimum 5 seconds between yfinance requests (for occasional searches)

def _yfinance_delay():
    """Enforce minimum delay between yfinance requests"""
    global _last_yfinance_request
    elapsed = time.time() - _last_yfinance_request
    if elapsed < _yfinance_min_delay:
        sleep_time = _yfinance_min_delay - elapsed
        print(f"Rate limiting: sleeping {sleep_time:.1f}s before yfinance request")
        time.sleep(sleep_time)
    _last_yfinance_request = time.time()


# Shared session with browser-like headers to avoid Yahoo Finance rate limiting on cloud IPs
_yf_session = requests.Session()
_yf_session.headers.update({
    'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36',
    'Accept': 'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8',
    'Accept-Language': 'en-US,en;q=0.5',
    'Accept-Encoding': 'gzip, deflate, br',
    'Connection': 'keep-alive',
})


def calculate_rsi(df: pd.DataFrame, period: int = 14) -> pd.Series:
    """Calculate RSI manually"""
    delta = df['Close'].diff()
    gain = (delta.where(delta > 0, 0)).rolling(window=period).mean()
    loss = (-delta.where(delta < 0, 0)).rolling(window=period).mean()
    rs = gain / loss
    rsi = 100 - (100 / (1 + rs))
    return rsi


def calculate_macd(df: pd.DataFrame, fast: int = 12, slow: int = 26, signal: int = 9) -> Dict:
    """Calculate MACD indicator"""
    exp_fast = df['Close'].ewm(span=fast, adjust=False).mean()
    exp_slow = df['Close'].ewm(span=slow, adjust=False).mean()
    macd_line = exp_fast - exp_slow
    signal_line = macd_line.ewm(span=signal, adjust=False).mean()
    histogram = macd_line - signal_line
    
    return {
        'macd_line': macd_line.iloc[-1] if len(macd_line) > 0 else None,
        'signal_line': signal_line.iloc[-1] if len(signal_line) > 0 else None,
        'histogram': histogram.iloc[-1] if len(histogram) > 0 else None,
        'macd_above_signal': macd_line.iloc[-1] > signal_line.iloc[-1] if len(macd_line) > 0 and len(signal_line) > 0 else False,
    }


def calculate_bollinger_bands(df: pd.DataFrame, period: int = 20, std_dev: int = 2) -> Dict:
    """Calculate Bollinger Bands"""
    sma = df['Close'].rolling(window=period).mean()
    std = df['Close'].rolling(window=period).std()
    upper_band = sma + (std * std_dev)
    lower_band = sma - (std * std_dev)
    
    current_price = df['Close'].iloc[-1]
    upper = upper_band.iloc[-1] if len(upper_band) > 0 else None
    lower = lower_band.iloc[-1] if len(lower_band) > 0 else None
    
    # Determine position relative to bands
    if upper and lower:
        band_width = upper - lower
        position = (current_price - lower) / band_width if band_width > 0 else 0.5
    else:
        position = 0.5
    
    return {
        'upper_band': upper,
        'middle_band': sma.iloc[-1] if len(sma) > 0 else None,
        'lower_band': lower,
        'position': position,  # 0 = at lower band, 1 = at upper band
        'near_upper': position > 0.8 if upper and lower else False,
        'near_lower': position < 0.2 if upper and lower else False,
    }


def calculate_volume_trend(df: pd.DataFrame, period: int = 20) -> Dict:
    """Calculate volume analysis"""
    avg_volume = df['Volume'].rolling(window=period).mean()
    current_volume = df['Volume'].iloc[-1]
    relative_volume = current_volume / avg_volume.iloc[-1] if len(avg_volume) > 0 and avg_volume.iloc[-1] > 0 else 1
    
    # Check if volume is increasing or decreasing
    volume_trend = df['Volume'].tail(5).mean() / df['Volume'].tail(10).mean() if len(df) >= 10 else 1
    
    return {
        'avg_volume': avg_volume.iloc[-1] if len(avg_volume) > 0 else None,
        'current_volume': current_volume,
        'relative_volume': relative_volume,
        'high_volume': relative_volume > 1.5,
        'low_volume': relative_volume < 0.5,
        'volume_increasing': volume_trend > 1.1,
    }


def calculate_adx(df: pd.DataFrame, period: int = 14) -> Dict:
    """Calculate ADX (Average Directional Index) for trend strength"""
    high = df['High']
    low = df['Low']
    close = df['Close']
    
    # Calculate True Range
    tr1 = high - low
    tr2 = (high - close.shift()).abs()
    tr3 = (low - close.shift()).abs()
    tr = pd.concat([tr1, tr2, tr3], axis=1).max(axis=1)
    atr = tr.rolling(window=period).mean()
    
    # Calculate directional movements
    plus_dm = high.diff()
    minus_dm = -low.diff()
    plus_dm[plus_dm < 0] = 0
    minus_dm[minus_dm < 0] = 0
    plus_dm[plus_dm < minus_dm] = 0
    minus_dm[minus_dm < plus_dm] = 0
    
    # Calculate smoothed directional movements
    plus_di = 100 * (plus_dm.rolling(window=period).mean() / atr)
    minus_di = 100 * (minus_dm.rolling(window=period).mean() / atr)
    
    # Calculate ADX
    dx = 100 * (plus_di - minus_di).abs() / (plus_di + minus_di)
    adx = dx.rolling(window=period).mean()
    
    return {
        'adx': adx.iloc[-1] if len(adx) > 0 else None,
        'plus_di': plus_di.iloc[-1] if len(plus_di) > 0 else None,
        'minus_di': minus_di.iloc[-1] if len(minus_di) > 0 else None,
        'trend_strength': 'Strong' if adx.iloc[-1] > 40 else ( 'Moderate' if adx.iloc[-1] > 20 else 'Weak') if len(adx) > 0 else 'Weak',
        'bullish_trend': plus_di.iloc[-1] > minus_di.iloc[-1] if len(plus_di) > 0 and len(minus_di) > 0 else False,
    }


def analyze_timeframe(df: pd.DataFrame, timeframe: str) -> Dict:
    """Analyze a specific timeframe (daily, weekly, monthly)"""
    if df is None or len(df) < 50:
        return {'timeframe': timeframe, 'signal': 'insufficient_data'}
    
    # Calculate indicators for this timeframe
    ma_short = df['Close'].rolling(window=20).mean().iloc[-1]
    ma_long = df['Close'].rolling(window=50).mean().iloc[-1]
    current_price = df['Close'].iloc[-1]
    rsi = calculate_rsi(df, 14).iloc[-1]
    
    # Determine trend direction
    if current_price > ma_short > ma_long:
        trend = 'bullish'
    elif current_price < ma_short < ma_long:
        trend = 'bearish'
    else:
        trend = 'neutral'
    
    # Determine signal
    if trend == 'bullish' and rsi < 40:
        signal = 'bullish'
    elif trend == 'bearish' and rsi > 60:
        signal = 'bearish'
    elif trend == 'bullish':
        signal = 'bullish'
    elif trend == 'bearish':
        signal = 'bearish'
    else:
        signal = 'neutral'
    
    return {
        'timeframe': timeframe,
        'trend': trend,
        'signal': signal,
        'current_price': current_price,
        'ma_short': ma_short,
        'ma_long': ma_long,
        'rsi': rsi,
    }


def get_stock_data(ticker: str, period: str = "1y") -> Optional[pd.DataFrame]:
    """Fetch historical stock data from yfinance with retry logic and rate limiting"""
    cache_key = f"stock_history:{ticker}_{period}"
    
    # Check Redis cache first
    if redis_client:
        try:
            cached = redis_client.get(cache_key)
            if cached:
                print(f"Using Redis cached history for {ticker}")
                return pd.read_json(StringIO(cached))
        except Exception as e:
            print(f"Redis cache read failed: {e}")
    
    # Fallback to local cache
    if cache_key in _stock_history_cache:
        print(f"Using local cached history for {ticker}")
        return _stock_history_cache[cache_key]
    
    max_retries = 3
    for attempt in range(max_retries):
        try:
            _yfinance_delay()  # Enforce rate limiting
            stock = yf.Ticker(ticker, session=_yf_session)
            df = stock.history(period=period)
            if df.empty:
                return None
            # Cache the result in Redis (15 min TTL)
            if redis_client:
                try:
                    redis_client.setex(cache_key, 900, df.to_json())
                except Exception as e:
                    print(f"Redis cache write failed: {e}")
            # Also cache locally as fallback
            _stock_history_cache[cache_key] = df
            return df
        except Exception as e:
            print(f"Error fetching data for {ticker}: {e}")
            if attempt < max_retries - 1:
                time.sleep(10 * (attempt + 1))  # 10s, 20s, 30s
            else:
                return None


def calculate_indicators(df: pd.DataFrame) -> Dict:
    """Calculate all technical indicators"""
    if df is None or len(df) < 200:
        return None
    
    # Calculate moving averages
    df['MA50'] = df['Close'].rolling(window=50).mean()
    df['MA200'] = df['Close'].rolling(window=200).mean()
    
    # Calculate RSI
    df['RSI'] = calculate_rsi(df, period=14)
    
    # Calculate new indicators
    macd = calculate_macd(df)
    bollinger = calculate_bollinger_bands(df)
    volume = calculate_volume_trend(df)
    adx = calculate_adx(df)
    
    # Get latest values
    latest = df.iloc[-1]
    
    return {
        'ticker': None,  # Will be set by caller
        'current_price': float(latest['Close']),
        'ma50': float(latest['MA50']) if pd.notna(latest['MA50']) else None,
        'ma200': float(latest['MA200']) if pd.notna(latest['MA200']) else None,
        'rsi': float(latest['RSI']) if pd.notna(latest['RSI']) else None,
        'date': df.index[-1].strftime('%Y-%m-%d'),
        'macd': macd,
        'bollinger': bollinger,
        'volume': volume,
        'adx': adx,
    }


def generate_signal(indicators: Dict) -> str:
    """
    Generate trading signal based on multiple indicators for better accuracy:
    - BUY: Strong upward momentum, oversold conditions, or multiple bullish indicators
    - SELL: Strong downward momentum, overbought conditions, or multiple bearish indicators
    - HOLD: Mixed or unclear signals
    """
    if indicators is None:
        return "NO_DATA"
    
    current_price = indicators['current_price']
    ma50 = indicators['ma50']
    ma200 = indicators['ma200']
    rsi = indicators['rsi']
    macd = indicators.get('macd', {})
    bollinger = indicators.get('bollinger', {})
    volume = indicators.get('volume', {})
    
    if ma50 is None or rsi is None:
        return "INSUFFICIENT_DATA"
    
    # Count bullish and bearish signals
    bullish_signals = 0
    bearish_signals = 0
    
    # Price vs MA signals (momentum-based)
    if current_price > ma50:
        bullish_signals += 1  # Above MA50 shows strength
    elif current_price < ma50:
        bearish_signals += 1  # Below MA50 shows weakness
    
    if ma200 and current_price > ma200:
        bullish_signals += 1  # Above MA200 shows long-term strength
    elif ma200 and current_price < ma200:
        bearish_signals += 1  # Below MA200 shows long-term weakness
    
    # RSI signals
    if rsi < 30:
        bullish_signals += 2  # Oversold is strong bullish signal
    elif rsi < 45:
        bullish_signals += 1  # Slightly oversold
    elif rsi > 70:
        bearish_signals += 2  # Overbought is strong bearish signal
    elif rsi > 55:
        bearish_signals += 1  # Slightly overbought
    
    # MACD signals
    if macd:
        macd_value = macd.get('macd', 0)
        signal_value = macd.get('signal', 0)
        if macd_value > signal_value:
            bullish_signals += 1  # MACD above signal = bullish
        elif macd_value < signal_value:
            bearish_signals += 1  # MACD below signal = bearish
        
        # MACD histogram
        histogram = macd_value - signal_value
        if histogram > 0 and macd_value > 0:
            bullish_signals += 1  # Positive and rising MACD
        elif histogram < 0 and macd_value < 0:
            bearish_signals += 1  # Negative and falling MACD
    
    # Bollinger Bands signals
    if bollinger:
        upper = bollinger.get('upper')
        lower = bollinger.get('lower')
        if lower and current_price < lower:
            bullish_signals += 2  # Below lower band is strong buy
        elif upper and current_price > upper:
            bearish_signals += 2  # Above upper band is strong sell
    
    # Volume trend signals
    if volume:
        trend = volume.get('trend')
        if trend == 'increasing':
            if current_price > ma50:
                bullish_signals += 1  # Volume + price up = strong buy
            else:
                bearish_signals += 1  # Volume + price down = strong sell
    
    # Generate final signal based on weighted signals
    if bullish_signals >= 2:
        return "BUY"
    elif bearish_signals >= 2:
        return "SELL"
    elif bullish_signals > bearish_signals:
        return "HOLD"
    elif bearish_signals > bullish_signals:
        return "HOLD"
    else:
        return "HOLD"


def analyze_stock(ticker: str) -> Optional[Dict]:
    """Analyze a single stock and return indicators with signal"""
    df = get_stock_data(ticker)
    if df is None:
        return None
    
    indicators = calculate_indicators(df)
    if indicators is None:
        return None
    
    indicators['ticker'] = ticker
    indicators['signal'] = generate_signal(indicators)
    
    return indicators


def get_technical_indicators(ticker: str) -> dict:
    """Compute MA50, MA200, and volume ratio from cached history. Returns {} on failure."""
    cache_key = f"technicals:{ticker}"
    if redis_client:
        try:
            cached = redis_client.get(cache_key)
            if cached:
                return json.loads(cached)
        except Exception:
            pass
    try:
        df = get_stock_data(ticker, period="1y")
        if df is None or len(df) < 20:
            return {}
        closes = df['Close']
        volumes = df['Volume']
        result = {}
        if len(closes) >= 50:
            result['ma50'] = float(closes.rolling(50).mean().iloc[-1])
        if len(closes) >= 200:
            result['ma200'] = float(closes.rolling(200).mean().iloc[-1])
        if len(volumes) >= 20:
            avg_vol = float(volumes.iloc[-21:-1].mean())  # 20-day avg excluding today
            today_vol = float(volumes.iloc[-1])
            result['volume_ratio'] = today_vol / avg_vol if avg_vol > 0 else 1.0
        if redis_client:
            try:
                redis_client.setex(cache_key, 3600, json.dumps(result))  # 1h cache
            except Exception:
                pass
        return result
    except Exception as e:
        print(f"Error computing technicals for {ticker}: {e}")
        return {}


def calculate_signal_score(current_price: float, open_price: float,
                           previous_close: float, percent_change: float,
                           high: float = None, low: float = None,
                           ma50: float = None, ma200: float = None,
                           volume_ratio: float = None) -> tuple:
    """
    Calculate signal score based on multiple factors:
    Returns (signal, score, reasoning)
    """
    score = 0
    reasons = []

    # Factor 1: Daily percent change (momentum)
    if percent_change > 3:
        score += 3
        reasons.append("Strong upward momentum (+3%)")
    elif percent_change > 1.5:
        score += 2
        reasons.append("Positive momentum (+1.5%)")
    elif percent_change > 0.5:
        score += 1
        reasons.append("Slight upward trend")
    elif percent_change < -3:
        score -= 3
        reasons.append("Strong downward momentum (-3%)")
    elif percent_change < -1.5:
        score -= 2
        reasons.append("Negative momentum (-1.5%)")
    elif percent_change < -0.5:
        score -= 1
        reasons.append("Slight downward trend")

    # Factor 2: Price vs Open (intraday trend)
    if current_price > open_price * 1.02:
        score += 2
        reasons.append("Strong intraday gain")
    elif current_price > open_price:
        score += 1
        reasons.append("Above opening price")
    elif current_price < open_price * 0.98:
        score -= 2
        reasons.append("Strong intraday loss")
    elif current_price < open_price:
        score -= 1
        reasons.append("Below opening price")

    # Factor 3: Price vs Previous Close (trend continuation)
    if current_price > previous_close * 1.01:
        score += 1
        reasons.append("Above previous close")
    elif current_price < previous_close * 0.99:
        score -= 1
        reasons.append("Below previous close")

    # Factor 4: Position within daily range
    if high and low and high > low:
        range_position = (current_price - low) / (high - low)
        if range_position > 0.8:
            score += 1
            reasons.append("Near daily high")
        elif range_position < 0.2:
            score -= 1
            reasons.append("Near daily low")

    # Factor 5: MA50 (short-term trend)
    if ma50 and current_price:
        if current_price > ma50 * 1.02:
            score += 2
            reasons.append("Price well above MA50 (bullish)")
        elif current_price > ma50:
            score += 1
            reasons.append("Price above MA50")
        elif current_price < ma50 * 0.98:
            score -= 2
            reasons.append("Price well below MA50 (bearish)")
        elif current_price < ma50:
            score -= 1
            reasons.append("Price below MA50")

    # Factor 6: MA200 (long-term trend)
    if ma200 and current_price:
        if current_price > ma200:
            score += 1
            reasons.append("Price above MA200 (long-term uptrend)")
        else:
            score -= 1
            reasons.append("Price below MA200 (long-term downtrend)")

    # Factor 7: MA50 vs MA200 crossover (golden/death cross)
    if ma50 and ma200:
        if ma50 > ma200 * 1.01:
            score += 1
            reasons.append("Golden cross: MA50 above MA200")
        elif ma50 < ma200 * 0.99:
            score -= 1
            reasons.append("Death cross: MA50 below MA200")

    # Factor 8: Volume confirmation
    if volume_ratio is not None:
        if volume_ratio > 2.0 and percent_change > 0:
            score += 2
            reasons.append(f"High volume buying ({volume_ratio:.1f}x avg)")
        elif volume_ratio > 1.5 and percent_change > 0:
            score += 1
            reasons.append(f"Above-average volume on up day ({volume_ratio:.1f}x)")
        elif volume_ratio > 2.0 and percent_change < 0:
            score -= 2
            reasons.append(f"High volume selling ({volume_ratio:.1f}x avg)")
        elif volume_ratio > 1.5 and percent_change < 0:
            score -= 1
            reasons.append(f"Above-average volume on down day ({volume_ratio:.1f}x)")

    # Determine signal
    if score >= 5:
        signal = "Strong Buy"
    elif score >= 2:
        signal = "Buy"
    elif score <= -5:
        signal = "Strong Sell"
    elif score <= -2:
        signal = "Sell"
    else:
        signal = "Hold"

    return signal, score, reasons


def get_all_signals(watchlist: Optional[List[str]] = None) -> List[Dict]:
    """Get signals for all stocks in watchlist using Finnhub (fast, no rate limiting)"""
    signals = []
    target = watchlist if watchlist else WATCHLIST
    
    for ticker in target:
        print(f"Analyzing {ticker}...")
        # Use Finnhub for fast, rate-limit-free data
        stock_info = get_stock_info_finnhub(ticker)
        if stock_info:
            current_price = stock_info.get('current_price')
            percent_change = stock_info.get('percent_change', 0)
            open_price = stock_info.get('open', current_price)
            previous_close = stock_info.get('previous_close', current_price)
            high = stock_info.get('high')
            low = stock_info.get('low')

            # Get technical indicators (MA50, MA200, volume) from cached history
            technicals = get_technical_indicators(ticker)

            # Use shared signal calculation
            signal, score, reasons = calculate_signal_score(
                current_price, open_price, previous_close, percent_change, high, low,
                ma50=technicals.get('ma50'),
                ma200=technicals.get('ma200'),
                volume_ratio=technicals.get('volume_ratio'),
            )
            
            # Convert all values to Python native types for JSON serialization
            def to_native(val):
                if val is None:
                    return None
                if isinstance(val, (np.floating, np.integer)):
                    return float(val)
                if isinstance(val, np.bool_):
                    return bool(val)
                return val
            
            result = {
                'ticker': ticker,
                'name': stock_info.get('name'),  # Company full name
                'current_price': to_native(current_price),
                'signal': signal,
                'change': to_native(stock_info.get('change')),
                'percent_change': to_native(percent_change),
                'high': to_native(stock_info.get('high')),
                'low': to_native(stock_info.get('low')),
                'open': to_native(stock_info.get('open')),
                'previous_close': to_native(stock_info.get('previous_close')),
                'ma50': to_native(technicals.get('ma50')),
                'ma200': to_native(technicals.get('ma200')),
                'volume_ratio': to_native(technicals.get('volume_ratio')),
                'market_cap': to_native(stock_info.get('market_cap')),
                'pe_ratio': to_native(stock_info.get('pe_ratio')),
                'beta': to_native(stock_info.get('beta')),
                'eps': to_native(stock_info.get('eps')),
                'is_premarket': to_native(is_premarket_hours()),
                'premarket_price': to_native(stock_info.get('premarket_price')),
                'premarket_change': to_native(stock_info.get('premarket_change')),
                'premarket_percent_change': to_native(stock_info.get('premarket_percent_change')),
                '52_week_high': to_native(stock_info.get('52_week_high')),
                '52_week_low': to_native(stock_info.get('52_week_low')),
                'industry': stock_info.get('industry'),
                'sector': stock_info.get('sector'),
                'description': stock_info.get('description'),
            }
            signals.append(result)
        # No delay needed for Finnhub
    
    return signals


def get_stock_history(ticker: str, period: str = "3mo") -> Optional[List[Dict]]:
    """Get historical price data for a stock"""
    print(f"Fetching history for {ticker} with period {period}")
    df = get_stock_data(ticker, period)
    if df is None:
        print(f"No data returned for {ticker}")
        return None
    
    print(f"Data shape: {df.shape}")
    history = []
    for date, row in df.iterrows():
        history.append({
            'date': date.strftime('%Y-%m-%d'),
            'open': float(row['Open']),
            'high': float(row['High']),
            'low': float(row['Low']),
            'close': float(row['Close']),
            'volume': int(row['Volume'])
        })
    
    print(f"Returning {len(history)} data points")
    return history


def get_stock_info_finnhub(ticker: str) -> Optional[Dict]:
    """Get stock information from Finnhub API (more reliable for current price and company info)"""
    cache_key = f"stock_info_finnhub_v3:{ticker}"  # v3 includes company name
    
    # Check Redis cache first
    if redis_client:
        try:
            cached = redis_client.get(cache_key)
            if cached:
                print(f"Using Redis cached Finnhub info for {ticker}")
                return json.loads(cached)
        except Exception as e:
            print(f"Redis cache read failed: {e}")
    
    try:
        # Get quote (current price)
        quote = finnhub_client.quote(ticker)
        if not quote or quote.get('c') is None:
            return None
        
        # Get company profile
        profile = finnhub_client.company_profile2(symbol=ticker)
        print(f"Finnhub profile for {ticker}: {profile}")
        
        # Build result with Finnhub data (no yfinance dependency for speed)
        result = {
            'ticker': ticker,
            'current_price': quote.get('c'),  # Current price
            'change': quote.get('d'),  # Change
            'percent_change': quote.get('dp'),  # Percent change
            'high': quote.get('h'),  # High of the day
            'low': quote.get('l'),  # Low of the day
            'open': quote.get('o'),  # Open price
            'previous_close': quote.get('pc'),  # Previous close
            'source': 'finnhub'
        }
        
        # Add profile data if available
        if profile:
            result.update({
                'name': profile.get('name') or ETF_NAMES.get(ticker),  # Company full name or ETF mapping
                'market_cap': profile.get('marketCapitalization'),
                'pe_ratio': profile.get('pe'),
                'dividend_yield': profile.get('dividendYield'),
                'beta': profile.get('beta'),
                'eps': profile.get('eps'),
                '52_week_high': profile.get('52WeekHigh'),
                '52_week_low': profile.get('52WeekLow'),
                'industry': profile.get('industry'),
                'sector': profile.get('sector'),
                'description': profile.get('description'),
                'country': profile.get('country'),
                'exchange': profile.get('exchange'),
                'currency': profile.get('currency'),
            })
        else:
            # No profile data - check if it's an ETF
            if ticker in ETF_NAMES:
                result['name'] = ETF_NAMES[ticker]
        
        # Add premarket data if available
        premarket_data = get_premarket_data(ticker)
        if premarket_data:
            result.update(premarket_data)
        
        # Cache result in Redis (15 min TTL)
        if redis_client:
            try:
                redis_client.setex(cache_key, 900, json.dumps(result))
            except Exception as e:
                print(f"Redis cache write failed: {e}")
        return result
    except Exception as e:
        print(f"Error fetching Finnhub info for {ticker}: {e}")
        return None


def is_premarket_hours() -> bool:
    """Check if current time is in premarket hours (4:00 AM - 9:30 AM ET)"""
    try:
        et = pytz.timezone('US/Eastern')
        now = datetime.now(et)
        current_time = now.time()
        is_premarket = current_time.hour >= 4 and (current_time.hour < 9 or (current_time.hour == 9 and current_time.minute < 30))
        print(f"Current ET time: {now.strftime('%H:%M')}, Is premarket: {is_premarket}")
        return is_premarket
    except Exception as e:
        print(f"Error checking premarket hours: {e}")
        return False


def is_market_open() -> bool:
    """Check if US market is currently open (9:30 AM - 4:00 PM ET, excluding weekends)"""
    try:
        et = pytz.timezone('US/Eastern')
        now = datetime.now(et)
        
        # Check if it's a weekend
        if now.weekday() >= 5:  # Saturday (5) or Sunday (6)
            return False
        
        current_time = now.time()
        # Market hours: 9:30 AM - 4:00 PM ET
        market_open = current_time.hour == 9 and current_time.minute >= 30
        market_midday = current_time.hour > 9 and current_time.hour < 16
        market_close = current_time.hour == 16 and current_time.minute == 0
        
        return market_open or market_midday or market_close
    except Exception as e:
        print(f"Error checking market status: {e}")
        return False


def get_market_hours() -> Dict:
    """Get US market hours in UTC for frontend display"""
    try:
        et = pytz.timezone('US/Eastern')
        now = datetime.now(et)
        
        # Market hours in ET
        market_open_et = "9:30 AM"
        market_close_et = "4:00 PM"
        
        # Convert to UTC
        utc = pytz.UTC
        market_open_utc = et.localize(datetime(now.year, now.month, now.day, 9, 30)).astimezone(utc)
        market_close_utc = et.localize(datetime(now.year, now.month, now.day, 16, 0)).astimezone(utc)
        
        return {
            'is_open': is_market_open(),
            'is_premarket': is_premarket_hours(),
            'market_open_et': market_open_et,
            'market_close_et': market_close_et,
            'market_open_utc': market_open_utc.strftime('%H:%M'),
            'market_close_utc': market_close_utc.strftime('%H:%M'),
            'timezone': 'US/Eastern',
            'current_time_et': now.strftime('%I:%M %p'),
            'current_time_utc': datetime.now(utc).strftime('%H:%M'),
        }
    except Exception as e:
        print(f"Error getting market hours: {e}")
        return {
            'is_open': False,
            'is_premarket': False,
            'error': str(e)
        }


def get_premarket_data(ticker: str) -> Optional[Dict]:
    """Get premarket data from Yahoo Finance"""
    try:
        et = pytz.timezone('US/Eastern')
        now = datetime.now(et)
        
        # Only fetch during premarket hours (4:00 AM - 9:30 AM ET)
        if not is_premarket_hours():
            return None
        
        # Use Yahoo Finance API for premarket data
        import requests
        
        url = f'https://query1.finance.yahoo.com/v7/finance/options/{ticker}'
        headers = {
            'User-Agent': 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36'
        }
        
        response = requests.get(url, headers=headers, timeout=5)
        
        if response.status_code == 200:
            data = response.json()
            result = data['optionChain']['result'][0]['quote']
            
            premarket_price = result.get('preMarketPrice')
            premarket_change_percent = result.get('preMarketChangePercent')
            market_state = result.get('marketState')
            previous_close = result.get('regularMarketPreviousClose')
            
            if premarket_price and previous_close:
                change = premarket_price - previous_close
                percent_change = (change / previous_close) * 100 if previous_close > 0 else 0
                
                print(f"Premarket data for {ticker} (Yahoo): ${premarket_price} ({percent_change:.2f}%) - State: {market_state}")
                
                return {
                    'premarket_price': premarket_price,
                    'premarket_change': change,
                    'premarket_percent_change': percent_change,
                    'is_premarket': True,
                    'market_state': market_state
                }
            else:
                print(f"No premarket price for {ticker} - State: {market_state}")
        else:
            print(f"Yahoo Finance API failed for {ticker}: {response.status_code}")
        
        # Fallback: just return premarket flag without price data
        return {
            'is_premarket': True,
            'premarket_price': None,
            'premarket_change': None,
            'premarket_percent_change': None
        }
    except Exception as e:
        print(f"Error fetching premarket data for {ticker}: {e}")
        return None


def get_stock_info(ticker: str) -> Optional[Dict]:
    """Get detailed stock information with retry logic for rate limiting"""
    cache_key = f"stock_info:{ticker}"
    
    # Check Redis cache first
    if redis_client:
        try:
            cached = redis_client.get(cache_key)
            if cached:
                print(f"Using Redis cached info for {ticker}")
                return json.loads(cached)
        except Exception as e:
            print(f"Redis cache read failed: {e}")
    
    # Fallback to local cache
    if ticker in _stock_info_cache:
        print(f"Using local cached info for {ticker}")
        return _stock_info_cache[ticker]
    
    max_retries = 3
    for attempt in range(max_retries):
        try:
            _yfinance_delay()  # Enforce global rate limiting
            stock = yf.Ticker(ticker, session=_yf_session)
            info = stock.info
            
            if not info:
                return None
            
            # Determine if this is a futures ticker
            is_futures = ticker.endswith('=F')
            
            result = {
                'ticker': ticker,
                'name': info.get('longName') or info.get('shortName'),
                'description': info.get('longBusinessSummary') or info.get('longName') or info.get('shortName'),
                'sector': info.get('sector'),
                'industry': info.get('industry'),
                'currency': info.get('currency', 'USD'),
                'current_price': info.get('currentPrice') or info.get('regularMarketPrice') or info.get('lastPrice') or info.get('price'),
                'percent_change': info.get('regularMarketChangePercent', 0),
                'change': info.get('regularMarketChange', 0),
                'open': info.get('regularMarketOpen') or info.get('open'),
                'previous_close': info.get('previousClose') or info.get('regularMarketPreviousClose'),
                'high': info.get('dayHigh') or info.get('regularMarketDayHigh'),
                'low': info.get('dayLow') or info.get('regularMarketDayLow'),
                'market_cap': info.get('marketCap'),
                'pe_ratio': info.get('trailingPE') or info.get('forwardPE'),
                'dividend_yield': info.get('dividendYield'),
                'dividend_rate': info.get('dividendRate'),
                'beta': info.get('beta'),
                'eps': info.get('trailingEps') or info.get('forwardEps'),
                'avg_volume': info.get('averageVolume') or info.get('averageVolume10days'),
                '52_week_high': info.get('fiftyTwoWeekHigh'),
                '52_week_low': info.get('fiftyTwoWeekLow'),
                'profit_margin': info.get('profitMargins'),
                'revenue': info.get('totalRevenue'),
            }
            
            # Add unit/currency info for futures
            if is_futures:
                _futures_names = {
                    'GC': ('Gold', 'Commodity · per troy oz'),
                    'SI': ('Silver', 'Commodity · per troy oz'),
                    'CL': ('Crude Oil (WTI)', 'Commodity · per barrel'),
                    'BZ': ('Brent Crude Oil', 'Commodity · per barrel'),
                    'NG': ('Natural Gas', 'Commodity · per MMBtu'),
                    'HG': ('Copper', 'Commodity · per lb'),
                    'PL': ('Platinum', 'Commodity · per troy oz'),
                    'PA': ('Palladium', 'Commodity · per troy oz'),
                    'ZC': ('Corn', 'Commodity · per bushel'),
                    'ZW': ('Wheat', 'Commodity · per bushel'),
                    'ZS': ('Soybeans', 'Commodity · per bushel'),
                    'ES': ('S&P 500 Futures', 'Index Future'),
                    'NQ': ('Nasdaq-100 Futures', 'Index Future'),
                    'YM': ('Dow Jones Futures', 'Index Future'),
                    'RTY': ('Russell 2000 Futures', 'Index Future'),
                }
                prefix = ticker.replace('=F', '')
                fname, fdesc = _futures_names.get(prefix, (ticker.replace('=F', ''), 'Futures Contract'))
                result['name'] = fname
                result['description'] = fdesc
                result['unit'] = fdesc
                result['currency'] = 'USD'
                result['is_futures'] = True
                result['grams'] = 31.1035
            # Cache result in Redis (15 min TTL)
            if redis_client:
                try:
                    redis_client.setex(cache_key, 900, json.dumps(result))
                except Exception as e:
                    print(f"Redis cache write failed: {e}")
            # Also cache locally as fallback
            _stock_info_cache[ticker] = result
            return result
        except Exception as e:
            print(f"Error fetching info for {ticker} (attempt {attempt + 1}/{max_retries}): {e}")
            if attempt < max_retries - 1:
                time.sleep(5 * (attempt + 1))  # Exponential backoff: 5s, 10s, 15s
            else:
                return None


def predict_stock(ticker: str) -> Optional[Dict]:
    """Predict stock movement for the next month based on technical indicators"""
    try:
        result = analyze_stock(ticker)
        if not result:
            return None
        
        current_price = result['current_price']
        ma50 = result['ma50']
        ma200 = result['ma200']
        rsi = result['rsi']
        macd = result.get('macd', {})
        bollinger = result.get('bollinger', {})
        volume = result.get('volume', {})
        adx = result.get('adx', {})
        
        # Analyze multiple timeframes
        daily_df = get_stock_data(ticker, "1y")
        weekly_df = get_stock_data(ticker, "2y")
        monthly_df = get_stock_data(ticker, "5y")
        
        # Resample for weekly and monthly
        if weekly_df is not None:
            weekly_df = weekly_df.resample('W').agg({
                'Open': 'first',
                'High': 'max',
                'Low': 'min',
                'Close': 'last',
                'Volume': 'sum'
            }).dropna()
        
        if monthly_df is not None:
            monthly_df = monthly_df.resample('ME').agg({
                'Open': 'first',
                'High': 'max',
                'Low': 'min',
                'Close': 'last',
                'Volume': 'sum'
            }).dropna()
        
        daily_analysis = analyze_timeframe(daily_df, 'daily')
        weekly_analysis = analyze_timeframe(weekly_df, 'weekly')
        monthly_analysis = analyze_timeframe(monthly_df, 'monthly')
        
        # Trend strength filter: Only predict if ADX > 10 (relaxed threshold)
        adx_value = adx.get('adx')
        if adx_value is None or adx_value < 10:
            return {
                'ticker': ticker,
                'prediction': 'Hold',
                'confidence': 40,
                'potential_change': 0,
                'score': 0,
                'factors': ['Weak trend (ADX < 20) - insufficient trend strength for prediction'],
                'current_price': current_price,
                'rsi': rsi,
                'ma50': ma50,
                'ma200': ma200,
                'adx': adx_value,
                'trend_strength': adx.get('trend_strength', 'Weak'),
                'timeframe_analysis': {
                    'daily': daily_analysis,
                    'weekly': weekly_analysis,
                    'monthly': monthly_analysis,
                },
            }
        
        # Calculate weighted prediction score
        score = 0
        factors = []
        
        # Add daily signal score for alignment with main page (weight: 1.0)
        # Fetch daily data from Finnhub for consistent scoring
        try:
            stock_info = get_stock_info_finnhub(ticker)
            if stock_info:
                daily_signal, daily_score, daily_reasons = calculate_signal_score(
                    stock_info.get('current_price', current_price),
                    stock_info.get('open', current_price),
                    stock_info.get('previous_close', current_price),
                    stock_info.get('percent_change', 0),
                    stock_info.get('high'),
                    stock_info.get('low')
                )
                # Add daily score as weighted factor
                score += daily_score * 0.5
                factors.extend([f"Daily: {r}" for r in daily_reasons[:2]])  # Add up to 2 daily reasons
        except Exception as e:
            print(f"Could not add daily signal score: {e}")
        
        # RSI analysis (weight: 1.5)
        if rsi < 30:
            score += 1.5
            factors.append('RSI oversold (<30)')
        elif rsi < 40:
            score += 0.75
            factors.append('RSI approaching oversold')
        elif rsi > 70:
            score -= 1.5
            factors.append('RSI overbought (>70)')
        elif rsi > 60:
            score -= 0.75
            factors.append('RSI approaching overbought')
        
        # MACD analysis (weight: 2.0)
        if macd.get('macd_above_signal'):
            if macd.get('histogram', 0) > 0:
                score += 2.0
                factors.append('MACD bullish crossover with positive histogram')
            else:
                score += 1.0
                factors.append('MACD above signal line')
        else:
            if macd.get('histogram', 0) < 0:
                score -= 2.0
                factors.append('MACD bearish crossover with negative histogram')
            else:
                score -= 1.0
                factors.append('MACD below signal line')
        
        # Bollinger Bands analysis (weight: 1.5)
        if bollinger.get('near_lower'):
            score += 1.5
            factors.append('Price near lower Bollinger Band (oversold)')
        elif bollinger.get('near_upper'):
            score -= 1.5
            factors.append('Price near upper Bollinger Band (overbought)')
        elif bollinger.get('position', 0.5) < 0.3:
            score += 0.75
            factors.append('Price in lower Bollinger Band region')
        elif bollinger.get('position', 0.5) > 0.7:
            score -= 0.75
            factors.append('Price in upper Bollinger Band region')
        
        # Volume analysis (weight: 1.0)
        if volume.get('high_volume') and score > 0:
            score += 1.0
            factors.append('High volume confirming bullish move')
        elif volume.get('high_volume') and score < 0:
            score -= 1.0
            factors.append('High volume confirming bearish move')
        elif volume.get('low_volume'):
            factors.append('Low volume - weak confirmation')
        
        # Moving average analysis (weight: 1.5)
        if ma50 and ma200:
            if current_price > ma50 > ma200:
                score += 1.5
                factors.append('Price above 50-day MA, 50-day above 200-day MA (bullish)')
            elif current_price > ma50:
                score += 0.75
                factors.append('Price above 50-day MA')
            elif current_price < ma50 < ma200:
                score -= 1.5
                factors.append('Price below 50-day MA, 50-day below 200-day MA (bearish)')
            elif current_price < ma50:
                score -= 0.75
                factors.append('Price below 50-day MA')
            
            if ma50 > ma200:
                score += 0.75
                factors.append('50-day MA above 200-day MA (golden cross)')
            else:
                score -= 0.75
                factors.append('50-day MA below 200-day MA (death cross)')
        
        # ADX trend direction (weight: 1.5)
        if adx.get('bullish_trend'):
            score += 0.75
            factors.append('Bullish trend direction (+DI > -DI)')
        else:
            score -= 0.75
            factors.append('Bearish trend direction (+DI < -DI)')
        
        # Multiple timeframe confirmation (weight: 2.0)
        timeframe_signals = []
        if daily_analysis.get('signal') != 'insufficient_data':
            timeframe_signals.append(daily_analysis['signal'])
        if weekly_analysis.get('signal') != 'insufficient_data':
            timeframe_signals.append(weekly_analysis['signal'])
        if monthly_analysis.get('signal') != 'insufficient_data':
            timeframe_signals.append(monthly_analysis['signal'])
        
        bullish_count = timeframe_signals.count('bullish')
        bearish_count = timeframe_signals.count('bearish')
        
        if bullish_count >= 2:
            score += 2.0
            factors.append(f'Timeframe confirmation: {bullish_count}/3 bullish')
        elif bearish_count >= 2:
            score -= 2.0
            factors.append(f'Timeframe confirmation: {bearish_count}/3 bearish')
        elif bullish_count == 1 and bearish_count == 0:
            score += 1.0
            factors.append('Timeframe confirmation: 1 bullish')
        elif bearish_count == 1 and bullish_count == 0:
            score -= 1.0
            factors.append('Timeframe confirmation: 1 bearish')
        else:
            factors.append('Timeframe confirmation: Mixed signals')
        
        # Determine prediction based on weighted score
        if score >= 5:
            prediction = 'Strong Buy'
            confidence = min(95, 60 + score * 5)
        elif score >= 3:
            prediction = 'Buy'
            confidence = min(85, 50 + score * 8)
        elif score <= -5:
            prediction = 'Strong Sell'
            confidence = min(95, 60 + abs(score) * 5)
        elif score <= -3:
            prediction = 'Sell'
            confidence = min(85, 50 + abs(score) * 8)
        else:
            prediction = 'Hold'
            confidence = 50
        
        # Estimate potential change
        potential_change = 0
        if prediction in ['Strong Buy', 'Buy']:
            potential_change = score * 1.2  # Estimate 1.2% per score point
        elif prediction in ['Strong Sell', 'Sell']:
            potential_change = score * 1.2  # Negative for sell
        
        return {
            'ticker': ticker,
            'prediction': prediction,
            'confidence': confidence,
            'potential_change': potential_change,
            'score': score,
            'factors': factors,
            'current_price': current_price,
            'rsi': rsi,
            'ma50': ma50,
            'ma200': ma200,
            'adx': adx_value,
            'trend_strength': adx.get('trend_strength', 'Unknown'),
            'timeframe_analysis': {
                'daily': daily_analysis,
                'weekly': weekly_analysis,
                'monthly': monthly_analysis,
            },
        }
    except Exception as e:
        print(f"Error predicting {ticker}: {e}")
        return None


def get_all_predictions(category: Optional[str] = None, limit: int = 5, watchlist: Optional[List[str]] = None) -> List[Dict]:
    """Get predictions for watchlist stocks using parallel processing"""
    # Use provided watchlist or combine personal with default
    if watchlist is not None:
        target_watchlist = watchlist
        print(f"Using provided watchlist with {len(target_watchlist)} stocks")
    else:
        try:
            import database
            personal_watchlist = database.get_personal_watchlist()
            default_watchlist = CATEGORIES.get(category, WATCHLIST) if category else WATCHLIST
            
            # Combine both watchlists and remove duplicates
            combined_watchlist = list(set(personal_watchlist + default_watchlist))
            target_watchlist = combined_watchlist if combined_watchlist else default_watchlist
            
            print(f"Using combined watchlist with {len(target_watchlist)} stocks (personal: {len(personal_watchlist)}, default: {len(default_watchlist)})")
        except Exception as e:
            print(f"Error fetching personal watchlist, using default: {e}")
            target_watchlist = CATEGORIES.get(category, WATCHLIST) if category else WATCHLIST
    
    predictions = []
    
    print(f"Predicting {len(target_watchlist)} stocks in {category or 'all'} category...")
    
    # Use ThreadPoolExecutor for parallel processing
    with ThreadPoolExecutor(max_workers=10) as executor:
        future_to_ticker = {
            executor.submit(predict_stock, ticker): ticker 
            for ticker in target_watchlist
        }
        
        for future in future_to_ticker:
            ticker = future_to_ticker[future]
            try:
                result = future.result()
                if result:
                    predictions.append(result)
                    print(f"✓ {ticker}")
            except Exception as e:
                print(f"✗ {ticker} failed: {e}")
    
    # Sort by score (highest to lowest)
    predictions.sort(key=lambda x: x['score'], reverse=True)
    
    # Separate gainers and losers by score (top 3 gains, bottom 3 losses)
    gainers = predictions[:3]  # Top 3 highest scores
    losers = predictions[-3:] if len(predictions) >= 3 else predictions  # Bottom 3 lowest scores
    
    # Return combined result
    result = {
        'gainers': gainers,
        'losers': losers,
        'category': category or 'all',
        'total_analyzed': len(predictions)
    }
    
    print(f"Completed {len(predictions)} predictions. Top {len(gainers)} gainers, {len(losers)} losers")
    return result


if __name__ == "__main__":
    signals_list = get_all_signals()
    print("\n=== Trading Signals ===")
    for signal in signals_list:
        print(f"\nTicker: {signal['ticker']}")
        print(f"Name: {signal.get('name', 'N/A')}")
        print(f"Current Price: ${signal['current_price']:.2f}")
        print(f"Change: {signal['percent_change']:.2f}%")
        print(f"Signal: {signal['signal']}")
